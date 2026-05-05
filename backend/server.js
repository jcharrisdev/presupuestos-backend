/**
 * server.js — Backend principal de Salarying
 *
 * Stack: Node.js + Express + MySQL (mysql2) + node-cron
 * Desplegado en: Render (free tier)
 * Base de datos: Clever Cloud MySQL
 *
 * MÓDULOS QUE GESTIONA ESTE ARCHIVO:
 *  1. Períodos — lógica de ciclos de presupuesto (quincenal / mensual)
 *  2. Presupuestos — CRUD de presupuestos del usuario
 *  3. Gastos — plantillas de gasto y meta de ahorro
 *  4. Movimientos — transacciones reales dentro de un período
 *  5. Calendario — eventos de pago/cobro con fecha fija
 *  6. Cobros — producción de insumos, ventas y cobros a clientes
 *  7. Cron job — marcado automático de eventos vencidos cada medianoche
 *
 * AUTENTICACIÓN:
 *  Por ahora se usa firebase_uid = email del usuario.
 *  Cuando se implemente Firebase Auth real, vendrá del JWT en el header.
 *  Todos los endpoints ya reciben y filtran por firebase_uid para estar
 *  preparados para ese cambio sin refactorizaciones mayores.
 */

const express = require('express');
const mysql   = require('mysql2');
const cors    = require('cors');
const cron    = require('node-cron');  // Para el job diario de vencimientos

const app = express();
app.use(cors());          // Permite peticiones desde el app Flutter (cross-origin)
app.use(express.json());  // Parsea el body de las peticiones como JSON

// =============================================================================
// CONEXIÓN A MYSQL — POOL de conexiones
// =============================================================================
// Se usa createPool en lugar de createConnection para evitar que el servidor
// crashee cuando Clever Cloud cierra conexiones inactivas (timeout).
// Con pool, mysql2 reabre la conexión automáticamente cuando se necesita.
// connectionLimit: 10 → máximo 10 conexiones simultáneas (suficiente para free tier)
const pool = mysql.createPool({
  host:     process.env.MYSQLHOST,
  user:     process.env.MYSQLUSER,
  password: process.env.MYSQLPASSWORD,
  database: process.env.MYSQLDATABASE,
  port:     Number(process.env.MYSQLPORT),
  waitForConnections: true,
  connectionLimit: 10,
  queueLimit: 0,
});

// Verifica la conexión al arrancar el servidor
pool.getConnection((err, conn) => {
  if (err) { console.error('❌ Error conectando a MySQL:', err); return; }
  console.log('✅ Conectado a MySQL');
  conn.release(); // Libera la conexión de vuelta al pool
});

// Usamos la versión con Promises (async/await) del pool
const db = pool.promise();


// =============================================================================
// LÓGICA DE PERÍODOS
// Estas funciones son el corazón del sistema. Cada presupuesto opera en ciclos
// de tiempo (períodos). La función principal es getPeriodoActivo(), que siempre
// garantiza que exista un período vigente para trabajar.
// =============================================================================

/**
 * Obtiene el período activo de un presupuesto.
 * Si el período actual ya venció, lo cierra y crea uno nuevo automáticamente.
 * Si no existe ningún período, crea el primero.
 *
 * @param {number} presupuestoId - ID del presupuesto
 * @param {string} firebaseUid - ID del usuario
 * @returns {Object} Período activo (con id, fecha_inicio, fecha_fin, etc.)
 */
async function getPeriodoActivo(presupuestoId, firebaseUid) {
  // Obtenemos la configuración del presupuesto para saber su tipo de período
  const [[presupuesto]] = await db.execute(
    `SELECT tipo_periodo, dia_inicio_periodo FROM presupuestos WHERE id = ? AND firebase_uid = ?`,
    [presupuestoId, firebaseUid]
  );
  if (!presupuesto) throw new Error('Presupuesto no encontrado');

  const { tipo_periodo, dia_inicio_periodo } = presupuesto;

  // Buscamos el único período activo (siempre debe haber máximo 1)
  const [periodos] = await db.execute(
    `SELECT *, DATE(NOW()) fecha_hoy FROM periodos
     WHERE presupuesto_id = ? AND firebase_uid = ? AND estado = 'activo' LIMIT 1`,
    [presupuestoId, firebaseUid]
  );

  if (periodos.length > 0) {
    const periodo = periodos[0];

    // Comparamos fechas como strings "YYYY-MM-DD" para evitar problemas de timezone.
    // MySQL retorna DATE como string, pero a veces como Date object según la versión.
    const hoyStr = periodo.fecha_hoy instanceof Date
      ? periodo.fecha_hoy.toISOString().split('T')[0]
      : String(periodo.fecha_hoy);
    const finStr = periodo.fecha_fin instanceof Date
      ? periodo.fecha_fin.toISOString().split('T')[0]
      : String(periodo.fecha_fin);

    // Si el período aún no venció, lo devolvemos tal cual
    if (hoyStr <= finStr) return periodo;

    // Si ya venció: cerramos el período actual y creamos el siguiente
    await db.execute(
      `UPDATE periodos SET estado = 'cerrado', closed_at = NOW() WHERE id = ?`,
      [periodo.id]
    );
    // El nuevo período comienza el día siguiente al fin del anterior
    return crearNuevoPeriodo(presupuestoId, firebaseUid, tipo_periodo, periodo.fecha_fin);
  }

  // No existe ningún período → crear el primero
  return crearPrimerPeriodo(presupuestoId, firebaseUid, tipo_periodo, dia_inicio_periodo);
}

/**
 * Genera automáticamente los movimientos para un período recién creado.
 * Solo aplica a gastos de tipo 'fijo', 'ahorro' con cuotas restantes, y 'fijo_x_periodo'.
 * Los gastos 'no fijo' NO se generan aquí — el usuario los agrega manualmente.
 *
 * @param {number} presupuestoId
 * @param {number} periodoId - ID del nuevo período
 * @param {string} firebaseUid
 */
async function generarMovimientosPeriodo(presupuestoId, periodoId, firebaseUid) {
  // Solo traemos gastos que deben generar movimiento automático:
  // - fijo: siempre (alquiler, servicios)
  // - ahorro: si no tiene límite (numero_quincena IS NULL) o le quedan cuotas
  // - fijo_x_periodo: si le quedan períodos (numero_quincena > 0)
  const [gastos] = await db.execute(
    `SELECT * FROM gastos WHERE presupuesto_id = ? AND firebase_uid = ?
     AND (
       tipo = 'fijo'
       OR (tipo = 'ahorro' AND (numero_quincena IS NULL OR numero_quincena > 0))
       OR (tipo = 'fijo_x_periodo' AND numero_quincena > 0)
     )`,
    [presupuestoId, firebaseUid]
  );

  for (const gasto of gastos) {
    // Insertamos el movimiento con estado pagado=0 (pendiente de pago)
    await db.execute(
      `INSERT INTO movimientos
       (presupuesto_id, periodo_id, gasto_id, descripcion, monto, tipo, pagado, firebase_uid, created_at)
       VALUES (?, ?, ?, ?, ?, ?, 0, ?, NOW())`,
      [presupuestoId, periodoId, gasto.id, gasto.descripcion, gasto.monto, gasto.tipo, firebaseUid]
    );

    // Para gastos con contador de períodos: decrementamos el contador
    // Cuando llegue a 0, el gasto ya no generará más movimientos
    if (gasto.tipo === 'fijo_x_periodo' ||
        (gasto.tipo === 'ahorro' && gasto.numero_quincena !== null)) {
      await db.execute(
        `UPDATE gastos SET numero_quincena = numero_quincena - 1 WHERE id = ? AND numero_quincena > 0`,
        [gasto.id]
      );
    }
  }
}

/**
 * Crea el primer período de un presupuesto.
 * Calcula la fecha de inicio según el día configurado en el presupuesto.
 * Si el día de inicio ya pasó este mes, el período empieza el mes/quincena siguiente.
 *
 * Ejemplo: dia_inicio=15, hoy=20 mayo → primer período empieza el 15 junio.
 * Ejemplo: dia_inicio=1, hoy=1 mayo a las 8am → primer período empieza el 1 mayo.
 * (Se compara solo la fecha, no la hora, para evitar que el mismo día quede "pasado")
 *
 * @param {number} presupuestoId
 * @param {string} firebaseUid
 * @param {string} tipoPeriodo - 'quincenal' | 'mensual'
 * @param {number} dia_inicio_periodo - Día del mes (1-31)
 */
async function crearPrimerPeriodo(presupuestoId, firebaseUid, tipoPeriodo, dia_inicio_periodo) {
  const hoy = new Date();
  const hoyStr = hoy.toISOString().split('T')[0]; // "YYYY-MM-DD"

  // Construimos la fecha de inicio con UTC para evitar desfases por timezone
  let fechaInicio = new Date(Date.UTC(hoy.getUTCFullYear(), hoy.getUTCMonth(), dia_inicio_periodo));

  // Si el día ya pasó este mes, avanzamos al siguiente ciclo
  if (fechaInicio.toISOString().split('T')[0] < hoyStr) {
    if (tipoPeriodo === 'quincenal') fechaInicio.setUTCDate(fechaInicio.getUTCDate() + 14);
    else fechaInicio.setUTCMonth(fechaInicio.getUTCMonth() + 1);
  }

  return _insertarPeriodo(presupuestoId, firebaseUid, tipoPeriodo, fechaInicio);
}

/**
 * Crea el siguiente período consecutivo después de que el anterior venció.
 * La fecha de inicio es siempre el día siguiente al fin del período anterior.
 *
 * @param {string} fechaFinAnterior - Fecha de fin del período cerrado
 */
async function crearNuevoPeriodo(presupuestoId, firebaseUid, tipoPeriodo, fechaFinAnterior) {
  const fechaInicio = new Date(fechaFinAnterior);
  fechaInicio.setDate(fechaInicio.getDate() + 1); // Día siguiente al fin anterior
  return _insertarPeriodo(presupuestoId, firebaseUid, tipoPeriodo, fechaInicio);
}

/**
 * Función interna que inserta el registro en la tabla periodos y
 * llama a generarMovimientosPeriodo para crear las transacciones del nuevo ciclo.
 * Es el paso final tanto para el primer período como para los subsiguientes.
 */
async function _insertarPeriodo(presupuestoId, firebaseUid, tipoPeriodo, fechaInicio) {
  const fechaFin = calcularFechaFin(fechaInicio, tipoPeriodo);

  // Obtenemos el número del último período para incrementarlo
  const [[{ ultimo }]] = await db.execute(
    `SELECT MAX(numero_periodo) AS ultimo FROM periodos WHERE presupuesto_id = ?`,
    [presupuestoId]
  );
  const numeroPeriodo = (ultimo || 0) + 1;

  const [result] = await db.execute(
    `INSERT INTO periodos (presupuesto_id, firebase_uid, numero_periodo, tipo_periodo, fecha_inicio, fecha_fin, estado)
     VALUES (?, ?, ?, ?, ?, ?, 'activo')`,
    [presupuestoId, firebaseUid, numeroPeriodo, tipoPeriodo,
     fechaInicio.toISOString().split('T')[0], fechaFin]
  );

  // Generamos los movimientos automáticos para este nuevo período
  await generarMovimientosPeriodo(presupuestoId, result.insertId, firebaseUid);

  return {
    id: result.insertId, presupuesto_id: presupuestoId, firebase_uid: firebaseUid,
    numero_periodo: numeroPeriodo, tipo_periodo: tipoPeriodo,
    fecha_inicio: fechaInicio, fecha_fin: fechaFin, estado: 'activo',
  };
}

/**
 * Calcula la fecha de fin de un período dado su fecha de inicio.
 * - Quincenal: fecha_inicio + 14 días
 * - Mensual: último día del mes siguiente (para cubrir meses de 28, 30 o 31 días)
 *
 * @param {Date} fechaInicio
 * @param {string} tipoPeriodo - 'quincenal' | 'mensual'
 * @returns {string} Fecha de fin en formato "YYYY-MM-DD"
 */
function calcularFechaFin(fechaInicio, tipoPeriodo) {
  const f = new Date(fechaInicio);
  if (tipoPeriodo === 'quincenal') {
    f.setDate(f.getDate() + 14);
  } else {
    // Para mensual: avanzamos un mes y restamos un día
    // Ej: inicio 01/05 → fin 31/05 (no 01/06)
    f.setMonth(f.getMonth() + 1);
    f.setDate(f.getDate() - 1);
  }
  return f.toISOString().split('T')[0];
}


// =============================================================================
// LÓGICA DE CALENDARIO
// Genera eventos futuros en calendario_eventos cuando el usuario crea
// un gasto con tipo_fecha = 'fija'. Esto permite ver los pagos en el calendario.
// =============================================================================

/**
 * Calcula todas las fechas de pago para los próximos 12 meses según la frecuencia.
 *
 * - 'unico': una sola fecha exacta
 * - 'mensual': una fecha por mes (en el dia_pago del mes)
 * - 'quincenal': dos fechas por mes (dia_pago y dia_pago+14)
 * - 'anual': una fecha por año
 *
 * Se usa Math.min(dia, ultimoDiaMes) para evitar el problema del 31 en meses cortos.
 *
 * @param {string} frecuencia - 'unico' | 'mensual' | 'quincenal' | 'anual'
 * @param {number} diaPago - Día del mes (1-31)
 * @param {Date|string} fechaExacta - Solo para frecuencia='unico'
 * @returns {string[]} Array de fechas "YYYY-MM-DD"
 */
function calcularFechasEvento(frecuencia, diaPago, fechaExacta) {
  const fechas = [];
  const hoy = new Date();

  if (frecuencia === 'unico') {
    if (fechaExacta) {
      const f = fechaExacta instanceof Date
        ? fechaExacta.toISOString().split('T')[0]
        : String(fechaExacta).split('T')[0];
      fechas.push(f);
    }
    return fechas;
  }

  const MESES = 12; // Generamos eventos para los próximos 12 meses
  for (let m = 0; m < MESES; m++) {
    const anio      = hoy.getUTCFullYear() + Math.floor((hoy.getUTCMonth() + m) / 12);
    const mes       = (hoy.getUTCMonth() + m) % 12;
    const ultimoDia = new Date(Date.UTC(anio, mes + 1, 0)).getUTCDate(); // Último día del mes

    // Para anual, solo generamos 1 evento cada 12 meses
    if (frecuencia === 'anual' && m % 12 !== 0) continue;

    // Base: dia_pago del mes (ajustado al último día si el mes es más corto)
    const dias = [Math.min(diaPago, ultimoDia)];
    // Para quincenal: segunda fecha 14 días después (también ajustada)
    if (frecuencia === 'quincenal') dias.push(Math.min(diaPago + 14, ultimoDia));

    for (const dia of dias) {
      fechas.push(`${anio}-${String(mes + 1).padStart(2, '0')}-${String(dia).padStart(2, '0')}`);
    }
  }
  return fechas;
}

/**
 * Genera los eventos de calendario para un gasto con tipo_fecha='fija'.
 * Se llama automáticamente al crear un gasto con fecha fija.
 * También se puede llamar manualmente con POST /calendario/generar.
 *
 * @param {number} gastoId
 * @param {string} firebaseUid
 * @returns {number} Cantidad de eventos insertados
 */
async function generarEventosCalendario(gastoId, firebaseUid) {
  const [[gasto]] = await db.execute(
    `SELECT * FROM gastos WHERE id = ? AND firebase_uid = ?`, [gastoId, firebaseUid]
  );
  // Solo generamos eventos si el gasto tiene fecha fija configurada
  if (!gasto || gasto.tipo_fecha !== 'fija') return 0;

  const fechas = calcularFechasEvento(gasto.frecuencia_pago, gasto.dia_pago, gasto.fecha_pago_exacta);
  let insertados = 0;
  for (const fecha of fechas) {
    try {
      await db.execute(
        `INSERT INTO calendario_eventos
         (firebase_uid, gasto_id, titulo, tipo, fecha_evento, monto_esperado, notificacion_activa, dias_anticipacion)
         VALUES (?, ?, ?, 'pago', ?, ?, ?, ?)`,
        [firebaseUid, gastoId, gasto.descripcion, fecha, gasto.monto,
         gasto.genera_notificacion ? 1 : 0, gasto.dias_anticipacion || 3]
      );
      insertados++;
    } catch (err) { console.error('Error insertando evento:', err.message); }
  }
  return insertados;
}


// =============================================================================
// HEALTHCHECK
// =============================================================================
// Endpoint raíz para verificar que el servidor está activo.
// Render y el app Flutter usan este endpoint para saber si el backend responde.
app.get('/', (req, res) => res.json({
  status: 'Backend funcionando correctamente',
  version: '2.4'  // Incrementar con cada cambio mayor
}));


// =============================================================================
// MÓDULO: PRESUPUESTOS
// CRUD básico de presupuestos de usuario.
// =============================================================================

/**
 * POST /presupuestos
 * Crea un nuevo presupuesto y genera automáticamente su primer período.
 * El primer período se calcula en base al dia_inicio_periodo configurado.
 */
app.post('/presupuestos', async (req, res) => {
  const { nombre, monto_total, firebase_uid, tipo_periodo, dia_inicio_periodo } = req.body;

  if (!nombre || monto_total == null || !firebase_uid || !tipo_periodo || !dia_inicio_periodo)
    return res.status(400).json({ error: 'Datos incompletos' });

  try {
    const [result] = await db.execute(
      `INSERT INTO presupuestos (nombre, monto_total, firebase_uid, tipo_periodo, dia_inicio_periodo)
       VALUES (?, ?, ?, ?, ?)`,
      [nombre, monto_total, firebase_uid, tipo_periodo, dia_inicio_periodo]
    );
    // Crear primer período automáticamente al momento de crear el presupuesto
    await crearPrimerPeriodo(result.insertId, firebase_uid, tipo_periodo, dia_inicio_periodo);
    res.status(201).json({ id: result.insertId, nombre, monto_total, tipo_periodo, dia_inicio_periodo });
  } catch (error) {
    console.error('Error creando presupuesto:', error);
    res.status(500).json({ error: 'Error al crear presupuesto' });
  }
});

/**
 * GET /presupuestos?firebase_uid=
 * Lista todos los presupuestos del usuario, ordenados del más reciente al más antiguo.
 */
app.get('/presupuestos', async (req, res) => {
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid es requerido' });
  try {
    const [results] = await db.execute(
      `SELECT * FROM presupuestos WHERE firebase_uid = ? ORDER BY id DESC`, [firebase_uid]
    );
    res.json(results);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Error al obtener presupuestos' });
  }
});

/**
 * PUT /presupuestos/:id
 * Actualiza el nombre y monto de un presupuesto existente.
 * Requiere firebase_uid para verificar propiedad del recurso (seguridad básica).
 */
app.put('/presupuestos/:id', async (req, res) => {
  const { id } = req.params;
  const { nombre, monto_total, firebase_uid } = req.body;
  if (!nombre || monto_total == null || !firebase_uid)
    return res.status(400).json({ error: 'Datos incompletos' });
  try {
    const [result] = await db.execute(
      `UPDATE presupuestos SET nombre = ?, monto_total = ? WHERE id = ? AND firebase_uid = ?`,
      [nombre, monto_total, id, firebase_uid]
    );
    if (result.affectedRows === 0) return res.status(404).json({ error: 'Presupuesto no encontrado' });
    res.json({ message: 'Presupuesto actualizado' });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Error al actualizar presupuesto' });
  }
});


// =============================================================================
// MÓDULO: GASTOS
// Los gastos son plantillas que definen qué se gasta en cada período.
// No son transacciones directas; generan movimientos automáticamente.
// =============================================================================

/**
 * POST /gastos/ahorroMeta
 * Crea un gasto de tipo 'ahorro' con cuota distribuida por período.
 * Calcula automáticamente la cuota según el tipo de período del presupuesto:
 *   - Mensual:   cuota = monto_total / tiempo_meses
 *   - Quincenal: cuota = monto_total / (tiempo_meses × 2)  ← 2 períodos por mes
 *
 * numero_quincena = cantidad total de períodos de pago (contador regresivo).
 */
app.post('/gastos/ahorroMeta', async (req, res) => {
  const { presupuesto_id, descripcion, monto, fecha, firebase_uid, tiempo_meses = 12 } = req.body;
  if (!presupuesto_id || !descripcion || monto == null || !firebase_uid)
    return res.status(400).json({ error: 'Datos incompletos' });

  const fechaStr = fecha ? fecha.split('T')[0] : new Date().toISOString().split('T')[0];

  try {
    // Necesitamos el tipo_periodo para saber cuántos períodos caben en los meses indicados
    const [[presupuesto]] = await db.execute(
      `SELECT tipo_periodo FROM presupuestos WHERE id = ? AND firebase_uid = ?`,
      [presupuesto_id, firebase_uid]
    );
    if (!presupuesto) return res.status(404).json({ error: 'Presupuesto no encontrado' });

    // Calculamos cuántos períodos en total tiene el plan de ahorro
    const periodos_total = presupuesto.tipo_periodo === 'quincenal'
      ? Number(tiempo_meses) * 2   // Quincenal: 2 períodos por mes
      : Number(tiempo_meses);       // Mensual: 1 período por mes

    // Cuota por período (redondeando hacia arriba para no perder centavos)
    const monto_periodo = Math.ceil((monto / periodos_total) * 100) / 100;

    // Guardamos el gasto con el monto de la CUOTA (no el total)
    // numero_quincena actúa como contador regresivo de períodos restantes
    const [result] = await db.execute(
      `INSERT INTO gastos (presupuesto_id, descripcion, monto, tipo, fecha, pagado, firebase_uid, numero_quincena)
       VALUES (?, ?, ?, 'ahorro', ?, 0, ?, ?)`,
      [presupuesto_id, descripcion, monto_periodo, fechaStr, firebase_uid, periodos_total]
    );
    const gastoId = result.insertId;

    // Crear el movimiento para el período actual inmediatamente
    try {
      const periodo = await getPeriodoActivo(presupuesto_id, firebase_uid);
      await db.execute(
        `INSERT INTO movimientos
         (presupuesto_id, periodo_id, gasto_id, descripcion, monto, tipo, pagado, firebase_uid, created_at)
         VALUES (?, ?, ?, ?, ?, 'ahorro', 0, ?, NOW())`,
        [presupuesto_id, periodo.id, gastoId, descripcion, monto_periodo, firebase_uid]
      );
      // Decrementamos porque el primer período ya fue consumido
      await db.execute(
        `UPDATE gastos SET numero_quincena = numero_quincena - 1 WHERE id = ? AND numero_quincena > 0`,
        [gastoId]
      );
    } catch (err) { console.error('⚠️ No se pudo auto-crear movimiento para ahorro:', err.message); }

    res.status(201).json({ id: gastoId, monto_periodo, periodos_total, tipo_periodo: presupuesto.tipo_periodo, message: 'Ahorro/Meta creado' });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Error al crear ahorro/meta' });
  }
});

/**
 * POST /gastos
 * Crea un gasto estándar (fijo, no fijo, fijo_x_periodo).
 * Para tipos 'fijo', 'fijo_x_periodo' y 'ahorro': auto-crea movimiento en período activo.
 * Si tipo_fecha='fija': genera eventos en el calendario para los próximos 12 meses.
 */
app.post('/gastos', async (req, res) => {
  const {
    presupuesto_id, descripcion, monto, tipo, fecha, firebase_uid,
    tipo_fecha = 'flexible',    // 'flexible' | 'fija'
    dia_pago = null,            // Día del mes para gastos con fecha fija
    frecuencia_pago = null,     // 'unico' | 'mensual' | 'quincenal' | 'anual'
    fecha_pago_exacta = null,   // Solo para frecuencia='unico'
    genera_notificacion = false,
    dias_anticipacion = 3
  } = req.body;

  if (!presupuesto_id || !descripcion || monto == null || !tipo || !fecha || !firebase_uid)
    return res.status(400).json({ error: 'Datos incompletos' });

  // Normalizamos las fechas a formato YYYY-MM-DD (quitamos la parte de tiempo)
  const fechaStr = fecha.split('T')[0];
  const fechaPagoStr = fecha_pago_exacta ? fecha_pago_exacta.split('T')[0] : null;

  try {
    const [result] = await db.execute(
      `INSERT INTO gastos
       (presupuesto_id, descripcion, monto, tipo, fecha, pagado, firebase_uid,
        tipo_fecha, dia_pago, frecuencia_pago, fecha_pago_exacta, genera_notificacion, dias_anticipacion)
       VALUES (?, ?, ?, ?, ?, 0, ?, ?, ?, ?, ?, ?, ?)`,
      [presupuesto_id, descripcion, monto, tipo, fechaStr, firebase_uid,
       tipo_fecha, dia_pago, frecuencia_pago, fechaPagoStr,
       genera_notificacion ? 1 : 0, dias_anticipacion]
    );
    const gastoId = result.insertId;

    // Auto-crear movimiento para gastos que aparecen automáticamente cada período
    if (tipo === 'fijo' || tipo === 'fijo_x_periodo' || tipo === 'ahorro') {
      try {
        const periodo = await getPeriodoActivo(presupuesto_id, firebase_uid);
        await db.execute(
          `INSERT INTO movimientos
           (presupuesto_id, periodo_id, gasto_id, descripcion, monto, tipo, pagado, firebase_uid, created_at)
           VALUES (?, ?, ?, ?, ?, ?, 0, ?, NOW())`,
          [presupuesto_id, periodo.id, gastoId, descripcion, monto, tipo, firebase_uid]
        );
        console.log(`✅ Movimiento auto-creado para gasto ${gastoId} en periodo ${periodo.id}`);
      } catch (err) { console.error('⚠️ No se pudo auto-crear movimiento:', err.message); }
    }

    // Si tiene fecha fija, generar eventos en el calendario
    if (tipo_fecha === 'fija') {
      const count = await generarEventosCalendario(gastoId, firebase_uid);
      console.log(`📅 ${count} eventos de calendario generados para gasto ${gastoId}`);
    }

    res.status(201).json({ id: gastoId, presupuesto_id, descripcion, monto, tipo, fecha: fechaStr, pagado: 0, firebase_uid });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Error al agregar gasto' });
  }
});

/**
 * GET /presupuestos/:id/gastos?firebase_uid=
 * Devuelve todos los gastos de un presupuesto.
 * También verifica/crea el período activo (efecto secundario intencional).
 */
app.get('/presupuestos/:id/gastos', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid es requerido' });
  try {
    await getPeriodoActivo(id, firebase_uid); // Asegura que exista un período activo
    const [results] = await db.execute(
      `SELECT * FROM gastos WHERE presupuesto_id = ? AND firebase_uid = ? ORDER BY id DESC`,
      [id, firebase_uid]
    );
    res.json(results);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: error.message });
  }
});

/** PUT /gastos/:id — Actualiza el campo 'pagado' de un gasto (uso legacy) */
app.put('/gastos/:id', async (req, res) => {
  const { id } = req.params;
  const { pagado, firebase_uid } = req.body;
  if (pagado === undefined) return res.status(400).json({ error: 'Campo pagado es obligatorio' });
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid es requerido' });
  const pagadoValue = pagado === true || pagado === 1 ? 1 : 0;
  try {
    const [result] = await db.execute(
      `UPDATE gastos SET pagado = ? WHERE id = ? AND firebase_uid = ?`,
      [pagadoValue, id, firebase_uid]
    );
    if (result.affectedRows === 0) return res.status(404).json({ error: 'Gasto no encontrado' });
    res.json({ message: 'Estado actualizado', id, pagado: pagadoValue });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Error al actualizar gasto' });
  }
});

/**
 * PUT /presupuestos/:id/gastos/reanudar-fijos
 * Resetea el estado de pago de todos los movimientos FIJOS del período activo.
 * Se usa cuando el usuario quiere "limpiar" los pagos del período para
 * gestionar quién pagó qué en presupuestos compartidos.
 * IMPORTANTE: opera sobre movimientos (no sobre gastos) para no perder el historial.
 */
app.put('/presupuestos/:id/gastos/reanudar-fijos', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.body;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid es requerido' });
  try {
    const periodo = await getPeriodoActivo(id, firebase_uid);
    // Reseteamos pagado, monto_real y fecha_pago de los movimientos fijos del período
    const [result] = await db.execute(
      `UPDATE movimientos
       SET pagado = 0, monto_pagado_real = NULL, pagado_por_uid = NULL, fecha_pagado = NULL
       WHERE presupuesto_id = ? AND periodo_id = ? AND firebase_uid = ? AND tipo IN ('fijo','fijo_x_periodo')`,
      [id, periodo.id, firebase_uid]
    );
    res.json({ message: 'Gastos fijos reanudados', afectados: result.affectedRows });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Error al reanudar gastos fijos' });
  }
});

/**
 * DELETE /gastos/:id?firebase_uid=
 * Elimina un gasto y sus movimientos asociados (CASCADE).
 * FIX: se agregó validación de firebase_uid para evitar que un usuario
 * elimine gastos de otro usuario si conoce el ID.
 */
app.delete('/gastos/:id', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.query;
  // FIX: firebase_uid es requerido para verificar propiedad del recurso
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid es requerido' });
  try {
    const [result] = await db.execute(
      `DELETE FROM gastos WHERE id = ? AND firebase_uid = ?`,
      [id, firebase_uid]
    );
    if (result.affectedRows === 0) return res.status(404).json({ error: 'Gasto no encontrado' });
    res.json({ message: 'Gasto eliminado' });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Error al eliminar gasto' });
  }
});


// =============================================================================
// MÓDULO: AHORROS
// Vista agregada de los gastos de tipo 'ahorro' con su progreso.
// El monto_ahorrado se calcula sumando monto_pagado_real de los movimientos pagados.
// =============================================================================

/**
 * GET /ahorros?firebase_uid=
 * Lista todas las metas de ahorro del usuario con su progreso actual.
 * monto_meta = monto del gasto (cuota por período)
 * monto_ahorrado = suma de lo realmente pagado en todos los movimientos de esa meta
 */
app.get('/ahorros', async (req, res) => {
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid es requerido' });
  try {
    const [ahorros] = await db.execute(
      `SELECT g.id, g.descripcion AS nombre, g.monto AS monto_meta,
              COALESCE(SUM(m.monto_pagado_real), 0) AS monto_ahorrado
       FROM gastos g
       LEFT JOIN movimientos m ON m.gasto_id = g.id AND m.pagado = 1
       WHERE g.firebase_uid = ? AND g.tipo = 'ahorro'
       GROUP BY g.id`,
      [firebase_uid]
    );
    res.json(ahorros);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Error al obtener ahorros' });
  }
});

/**
 * DELETE /ahorros/:id?firebase_uid=
 * Elimina una meta de ahorro.
 * FIX: se agregó validación de firebase_uid para verificar propiedad del recurso.
 */
app.delete('/ahorros/:id', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid es requerido' });
  try {
    const [result] = await db.execute(
      `DELETE FROM gastos WHERE id = ? AND tipo = 'ahorro' AND firebase_uid = ?`,
      [id, firebase_uid]
    );
    if (result.affectedRows === 0) return res.status(404).json({ error: 'Ahorro no encontrado' });
    res.json({ message: 'Ahorro eliminado' });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Error al eliminar ahorro' });
  }
});


// =============================================================================
// MÓDULO: MOVIMIENTOS
// Los movimientos son las transacciones reales dentro de un período.
// La pantalla de detalle del presupuesto trabaja exclusivamente con movimientos.
// =============================================================================

/**
 * GET /presupuestos/:id/detalle?firebase_uid=
 * Endpoint principal de la pantalla de detalle del presupuesto.
 * Devuelve:
 *   - periodo: el período activo (o crea uno si no existe)
 *   - movimientos: todas las transacciones del período activo
 *   - resumen: totales por tipo + porcentaje de pagados
 */
app.get('/presupuestos/:id/detalle', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid es requerido' });
  try {
    const periodo = await getPeriodoActivo(id, firebase_uid);

    const [movimientos] = await db.execute(
      `SELECT * FROM movimientos
       WHERE presupuesto_id = ? AND periodo_id = ? AND firebase_uid = ?
       ORDER BY id DESC`,
      [id, periodo.id, firebase_uid]
    );

    // Calculamos totales por tipo de gasto
    let totalFijo = 0, totalNoFijo = 0, totalAhorro = 0;
    movimientos.forEach(m => {
      if (m.tipo === 'fijo' || m.tipo === 'fijo_x_periodo') totalFijo   += Number(m.monto);
      if (m.tipo === 'no fijo')                              totalNoFijo += Number(m.monto);
      if (m.tipo === 'ahorro')                               totalAhorro += Number(m.monto);
    });

    const pagados = movimientos.filter(m => m.pagado === 1).length;

    res.json({
      periodo,
      movimientos,
      resumen: {
        totalFijo, totalNoFijo, totalAhorro,
        totalGastado: totalFijo + totalNoFijo + totalAhorro,
        // Porcentaje de movimientos marcados como pagados (0.0 a 1.0)
        porcentajePagados: movimientos.length > 0 ? pagados / movimientos.length : 0,
      },
    });
  } catch (error) {
    console.error('Error detalle:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * GET /presupuestos/:id/historico?firebase_uid=
 * Resumen de los últimos 6 períodos del presupuesto para la tab Historial.
 * Retorna totales por tipo de gasto y avance de pagos por período.
 */
app.get('/presupuestos/:id/historico', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid es requerido' });
  try {
    const [[presupuesto]] = await db.execute(
      `SELECT id, nombre, monto_total FROM presupuestos WHERE id = ? AND firebase_uid = ?`,
      [id, firebase_uid]
    );
    if (!presupuesto) return res.status(404).json({ error: 'Presupuesto no encontrado' });

    const [periodos] = await db.execute(
      `SELECT
         p.id, p.numero_periodo, p.fecha_inicio, p.fecha_fin, p.estado,
         COALESCE(SUM(CASE WHEN m.tipo='fijo' OR m.tipo='fijo_x_periodo' THEN m.monto_pagado_real ELSE 0 END), 0) AS total_fijo,
         COALESCE(SUM(CASE WHEN m.tipo='no fijo' THEN m.monto_pagado_real ELSE 0 END), 0) AS total_no_fijo,
         COALESCE(SUM(CASE WHEN m.tipo='ahorro' THEN m.monto_pagado_real ELSE 0 END), 0) AS total_ahorro,
         COALESCE(SUM(m.monto_pagado_real), 0) AS total_gastado,
         COUNT(CASE WHEN m.pagado=1 THEN 1 END) AS movimientos_pagados,
         COUNT(m.id) AS movimientos_total
       FROM periodos p
       LEFT JOIN movimientos m ON m.periodo_id = p.id AND m.firebase_uid = p.firebase_uid
       WHERE p.presupuesto_id = ? AND p.firebase_uid = ?
       GROUP BY p.id
       ORDER BY p.numero_periodo DESC
       LIMIT 6`,
      [id, firebase_uid]
    );
    res.json({ monto_total: presupuesto.monto_total, periodos });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

/**
 * POST /presupuestos/:id/movimientos
 * Crea movimientos manualmente desde una selección de gastos.
 * Para gastos 'no fijo': permite múltiples movimientos por período
 *   (ej: varias compras en el supermercado en el mismo mes).
 * Para gastos 'fijo' / 'ahorro': evita duplicados (ya se crean automáticamente).
 */
app.post('/presupuestos/:id/movimientos', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid, items } = req.body; // items: [{gasto_id, monto}]

  if (!firebase_uid || !Array.isArray(items) || items.length === 0)
    return res.status(400).json({ error: 'Datos incompletos' });

  try {
    const periodo = await getPeriodoActivo(id, firebase_uid);

    for (const item of items) {
      const { gasto_id, monto } = item;
      if (!gasto_id || monto == null || monto <= 0) continue;

      // Verificamos que el gasto existe y pertenece al usuario
      const [[gasto]] = await db.execute(
        `SELECT * FROM gastos WHERE id = ? AND presupuesto_id = ? AND firebase_uid = ?`,
        [gasto_id, id, firebase_uid]
      );
      if (!gasto) continue;

      // Para gastos no-fijo: permitimos múltiples movimientos en el mismo período
      // Para fijo/ahorro: saltamos si ya existe para no duplicar
      if (gasto.tipo !== 'no fijo') {
        const [[existing]] = await db.execute(
          `SELECT id FROM movimientos WHERE gasto_id = ? AND periodo_id = ? AND firebase_uid = ?`,
          [gasto_id, periodo.id, firebase_uid]
        );
        if (existing) continue; // Ya existe, no duplicar
      }

      await db.execute(
        `INSERT INTO movimientos
         (presupuesto_id, periodo_id, gasto_id, descripcion, monto, tipo, pagado, firebase_uid, created_at)
         VALUES (?, ?, ?, ?, ?, ?, 0, ?, NOW())`,
        [id, periodo.id, gasto.id, gasto.descripcion, monto, gasto.tipo, firebase_uid]
      );
    }

    res.status(201).json({ message: 'Movimientos creados correctamente', periodo_id: periodo.id });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * GET /presupuestos/:id/gastos-seleccionables?firebase_uid=
 * Devuelve todos los gastos del presupuesto para el modal de "Agregar".
 * Incluye gastos de todos los tipos (no solo 'no fijo').
 * El Flutter decide cómo manejar duplicados según el tipo del gasto.
 */
app.get('/presupuestos/:id/gastos-seleccionables', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid es requerido' });
  try {
    const periodo = await getPeriodoActivo(id, firebase_uid);
    const [gastos] = await db.execute(
      `SELECT g.* FROM gastos g
       WHERE g.presupuesto_id = ? AND g.firebase_uid = ? AND g.tipo = 'no fijo'
       AND NOT EXISTS (
         SELECT 1 FROM movimientos m
         WHERE m.gasto_id = g.id AND m.periodo_id = ?
       )
       ORDER BY g.descripcion`,
      [id, firebase_uid, periodo.id]
    );
    res.json({ periodo_id: periodo.id, gastos });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * PUT /movimientos/:id/pagar
 * Marca un movimiento como pagado con su monto real.
 * monto_pagado_real puede diferir del monto presupuestado.
 * Esta diferencia es visible en la pantalla de detalle para análisis financiero.
 */
app.put('/movimientos/:id/pagar', async (req, res) => {
  const { id } = req.params;
  const { pagado, monto_pagado_real, firebase_uid } = req.body;

  if (pagado === undefined || !firebase_uid)
    return res.status(400).json({ error: 'Datos incompletos' });
  if (pagado === 1 && (!monto_pagado_real || monto_pagado_real <= 0))
    return res.status(400).json({ error: 'Monto pagado real inválido' });

  try {
    const [[movimiento]] = await db.execute(`SELECT id FROM movimientos WHERE id = ? AND firebase_uid = ?`, [id, firebase_uid]);
    if (!movimiento) return res.status(404).json({ error: 'Movimiento no encontrado' });

    await db.execute(
      `UPDATE movimientos
       SET pagado = ?,
           monto_pagado_real = ?,
           pagado_por_uid = ?,
           fecha_pagado = CASE WHEN ? = 1 THEN NOW() ELSE NULL END
       WHERE id = ? AND firebase_uid = ?`,
      [pagado, pagado ? monto_pagado_real : null,
       pagado ? firebase_uid : null, pagado, id, firebase_uid]
    );
    res.json({ message: 'Movimiento actualizado correctamente' });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: error.message });
  }
});


// =============================================================================
// MÓDULO: CALENDARIO
// Agenda de eventos de pago y cobro con fecha fija.
// Los eventos de pago se generan al crear gastos con tipo_fecha='fija'.
// Los eventos de cobro se generan al agregar clientes con condicion='plazo'.
// =============================================================================

/**
 * GET /calendario/eventos?firebase_uid=&mes=&anio=
 * Devuelve todos los eventos del mes/año indicado para el usuario.
 * Si no se pasa mes/anio, devuelve todos los eventos del usuario.
 */
app.get('/calendario/eventos', async (req, res) => {
  const { firebase_uid, mes, anio } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid es requerido' });
  try {
    let sql = `SELECT ce.*, g.tipo AS gasto_tipo
               FROM calendario_eventos ce
               LEFT JOIN gastos g ON ce.gasto_id = g.id
               WHERE ce.firebase_uid = ?`;
    const params = [firebase_uid];
    if (mes && anio) {
      sql += ` AND YEAR(ce.fecha_evento) = ? AND MONTH(ce.fecha_evento) = ?`;
      params.push(anio, mes);
    }
    sql += ` ORDER BY ce.fecha_evento ASC`;
    const [eventos] = await db.execute(sql, params);
    res.json(eventos);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * POST /calendario/generar
 * Genera manualmente los eventos de calendario para un gasto ya existente.
 * Útil si el usuario cambia un gasto a tipo_fecha='fija' después de crearlo.
 */
app.post('/calendario/generar', async (req, res) => {
  const { gasto_id, firebase_uid } = req.body;
  if (!gasto_id || !firebase_uid) return res.status(400).json({ error: 'Datos incompletos' });
  try {
    const [[gasto]] = await db.execute(
      `SELECT id FROM gastos WHERE id = ? AND firebase_uid = ?`,
      [gasto_id, firebase_uid]
    );
    if (!gasto) return res.status(404).json({ error: 'Gasto no encontrado' });
    const count = await generarEventosCalendario(gasto_id, firebase_uid);
    res.json({ message: `${count} eventos generados`, count });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * PUT /calendario/eventos/:id/estado
 * Actualiza el estado de un evento: 'pendiente' | 'pagado' | 'vencido'.
 * Se llama cuando el usuario marca un pago desde la pantalla del calendario.
 */
app.put('/calendario/eventos/:id/estado', async (req, res) => {
  const { id } = req.params;
  let { estado, firebase_uid } = req.body;
  if (!estado || !firebase_uid) return res.status(400).json({ error: 'Datos incompletos' });
  if (!['pendiente', 'pagado', 'vencido', 'cobrado'].includes(estado))
    return res.status(400).json({ error: 'Estado inválido' });
  // El ENUM de calendario_eventos solo acepta ('pendiente','pagado','vencido').
  // Versiones anteriores del app enviaban 'cobrado' → mapear a 'pagado' para
  // evitar WARN_DATA_TRUNCATED de MySQL sin requerir migración de schema.
  if (estado === 'cobrado') estado = 'pagado';
  try {
    const [result] = await db.execute(
      `UPDATE calendario_eventos SET estado = ? WHERE id = ? AND firebase_uid = ?`,
      [estado, id, firebase_uid]
    );
    if (result.affectedRows === 0) return res.status(404).json({ error: 'Evento no encontrado' });
    res.json({ message: 'Estado actualizado', estado });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * DELETE /calendario/eventos/:id?firebase_uid=&solo_este=true|false
 * Elimina un evento del calendario.
 * solo_este=true  → solo elimina este evento específico
 * solo_este=false → elimina este y todos los futuros del mismo gasto
 *   (útil cuando el usuario cancela un gasto recurrente)
 */
app.delete('/calendario/eventos/:id', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid, solo_este } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid es requerido' });
  try {
    let sql, params;
    if (solo_este === 'false') {
      // Eliminar este y todos los eventos futuros del mismo gasto
      const [[ev]] = await db.execute(
        `SELECT gasto_id, fecha_evento FROM calendario_eventos WHERE id = ?`, [id]
      );
      if (!ev) return res.status(404).json({ error: 'Evento no encontrado' });
      const fechaStr = ev.fecha_evento instanceof Date
        ? ev.fecha_evento.toISOString().split('T')[0]
        : String(ev.fecha_evento).split('T')[0];
      sql    = `DELETE FROM calendario_eventos WHERE gasto_id = ? AND firebase_uid = ? AND fecha_evento >= ?`;
      params = [ev.gasto_id, firebase_uid, fechaStr];
    } else {
      sql    = `DELETE FROM calendario_eventos WHERE id = ? AND firebase_uid = ?`;
      params = [id, firebase_uid];
    }
    const [result] = await db.execute(sql, params);
    res.json({ message: `${result.affectedRows} evento(s) eliminado(s)` });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: error.message });
  }
});


// =============================================================================
// MÓDULO: PRODUCCIÓN DE INSUMOS
// Presupuestos de costo de producción (ej: ingredientes para hacer cheesecakes).
// El costo total se calcula como SUM(cantidad × precio_unitario) de los ítems.
// =============================================================================

/** GET /produccion?firebase_uid= — Lista los presupuestos de producción con su total */
app.get('/produccion', async (req, res) => {
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [rows] = await db.execute(
      `SELECT p.*, COALESCE(SUM(i.cantidad * i.precio_unitario), 0) AS total_invertido
       FROM presupuestos_produccion p
       LEFT JOIN items_produccion i ON i.presupuesto_produccion_id = p.id
       WHERE p.firebase_uid = ?
       GROUP BY p.id ORDER BY p.id DESC`,
      [firebase_uid]
    );
    res.json(rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

/** POST /produccion — Crea un nuevo presupuesto de producción */
app.post('/produccion', async (req, res) => {
  const { nombre, descripcion, firebase_uid } = req.body;
  if (!nombre || !firebase_uid) return res.status(400).json({ error: 'Datos incompletos' });
  try {
    const [result] = await db.execute(
      `INSERT INTO presupuestos_produccion (firebase_uid, nombre, descripcion) VALUES (?, ?, ?)`,
      [firebase_uid, nombre, descripcion || null]
    );
    res.status(201).json({ id: result.insertId, nombre });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

/** GET /produccion/:id — Detalle de un presupuesto de producción con todos sus ítems */
app.get('/produccion/:id', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [[presupuesto]] = await db.execute(
      `SELECT p.*, COALESCE(SUM(i.cantidad * i.precio_unitario), 0) AS total_invertido
       FROM presupuestos_produccion p
       LEFT JOIN items_produccion i ON i.presupuesto_produccion_id = p.id
       WHERE p.id = ? AND p.firebase_uid = ? GROUP BY p.id`,
      [id, firebase_uid]
    );
    if (!presupuesto) return res.status(404).json({ error: 'No encontrado' });

    const [items] = await db.execute(
      `SELECT * FROM items_produccion WHERE presupuesto_produccion_id = ? ORDER BY id ASC`, [id]
    );
    res.json({ ...presupuesto, items });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

/** POST /produccion/:id/items — Agrega un ítem de insumo al presupuesto */
app.post('/produccion/:id/items', async (req, res) => {
  const { id } = req.params;
  const { nombre, cantidad, precio_unitario, firebase_uid } = req.body;
  if (!nombre || !cantidad || !precio_unitario || !firebase_uid)
    return res.status(400).json({ error: 'Datos incompletos' });
  try {
    const [result] = await db.execute(
      `INSERT INTO items_produccion (presupuesto_produccion_id, firebase_uid, nombre, cantidad, precio_unitario)
       VALUES (?, ?, ?, ?, ?)`,
      [id, firebase_uid, nombre, cantidad, precio_unitario]
    );
    res.status(201).json({ id: result.insertId, nombre, cantidad, precio_unitario });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

/** DELETE /produccion/items/:id — Elimina un ítem de producción */
app.delete('/produccion/items/:id', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    await db.execute(
      `DELETE FROM items_produccion WHERE id = ? AND firebase_uid = ?`, [id, firebase_uid]
    );
    res.json({ message: 'Item eliminado' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

/** DELETE /produccion/:id — Elimina un presupuesto de producción y sus ítems (CASCADE) */
app.delete('/produccion/:id', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    await db.execute(
      `DELETE FROM presupuestos_produccion WHERE id = ? AND firebase_uid = ?`, [id, firebase_uid]
    );
    res.json({ message: 'Presupuesto eliminado' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});


// =============================================================================
// MÓDULO: VENTAS Y COBROS A CLIENTES
// Gestión de ventas con su rentabilidad y cobros por cliente.
// La rentabilidad = total_cobrado − total_invertido_en_produccion.
// =============================================================================

/** GET /ventas?firebase_uid= — Lista ventas con totales cobrados y pendientes */
app.get('/ventas', async (req, res) => {
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [rows] = await db.execute(
      `SELECT v.*,
              COALESCE(SUM(CASE WHEN c.estado='cobrado' THEN c.monto_cobrado ELSE 0 END), 0) AS total_cobrado,
              COALESCE(SUM(c.monto), 0) AS total_esperado,
              SUM(CASE WHEN c.estado='pendiente' THEN 1 ELSE 0 END) AS cobros_pendientes
       FROM ventas v
       LEFT JOIN cobros_clientes c ON c.venta_id = v.id
       WHERE v.firebase_uid = ?
       GROUP BY v.id ORDER BY v.id DESC`,
      [firebase_uid]
    );
    res.json(rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

/**
 * POST /ventas — Crea una nueva venta.
 *
 * Body:
 *   nombre       string          — requerido
 *   firebase_uid string          — requerido
 *   inversion    number          — opcional (Bug 2): inversión manual en pesos
 *   presupuesto_ids int[]        — opcional (Fase 2): IDs de presupuestos de producción
 *   presupuesto_produccion_id int — opcional LEGACY
 */
app.post('/ventas', async (req, res) => {
  const { nombre, presupuesto_produccion_id, presupuesto_ids, inversion, firebase_uid } = req.body;
  if (!nombre || !firebase_uid) return res.status(400).json({ error: 'Datos incompletos' });

  const conn = await db.getConnection();
  await conn.beginTransaction();
  try {
    const ids = presupuesto_ids
      ? (Array.isArray(presupuesto_ids) ? presupuesto_ids : [presupuesto_ids])
      : (presupuesto_produccion_id ? [presupuesto_produccion_id] : []);

    const legacyId = ids.length > 0 ? ids[0] : null;
    // Solo guardar inversion si es > 0; 0 y null se tratan igual (sin inversión)
    const inversionVal = (inversion != null && Number(inversion) > 0) ? Number(inversion) : null;

    const [result] = await conn.execute(
      `INSERT INTO ventas (firebase_uid, nombre, presupuesto_produccion_id, inversion) VALUES (?, ?, ?, ?)`,
      [firebase_uid, nombre, legacyId, inversionVal]
    );
    const ventaId = result.insertId;

    for (const pid of ids) {
      await conn.execute(
        `INSERT IGNORE INTO venta_presupuestos (venta_id, presupuesto_produccion_id) VALUES (?, ?)`,
        [ventaId, pid]
      );
    }

    await conn.commit();
    conn.release();
    res.status(201).json({ id: ventaId, nombre });
  } catch (err) {
    await conn.rollback();
    conn.release();
    res.status(500).json({ error: err.message });
  }
});

/**
 * PUT /ventas/:id — Edita nombre e inversión de una venta existente.
 * Body: { nombre?, inversion?, firebase_uid }
 */
app.put('/ventas/:id', async (req, res) => {
  const { id } = req.params;
  const { nombre, firebase_uid } = req.body;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });

  // inversion: undefined = no viene en el body (no tocar), null = borrar, número = guardar
  // hasInversion flag evita la lógica confusa de undefined vs null en JS
  const hasInversion = Object.prototype.hasOwnProperty.call(req.body, 'inversion');
  const inversionVal = hasInversion
    ? (req.body.inversion === null || Number(req.body.inversion) <= 0 ? null : Number(req.body.inversion))
    : undefined;

  try {
    const [result] = await db.execute(
      `UPDATE ventas
       SET nombre    = COALESCE(?, nombre)
           ${inversionVal !== undefined ? ', inversion = ?' : ''}
       WHERE id = ? AND firebase_uid = ?`,
      inversionVal !== undefined
        ? [nombre || null, inversionVal, id, firebase_uid]
        : [nombre || null, id, firebase_uid]
    );
    if (result.affectedRows === 0) return res.status(404).json({ error: 'Venta no encontrada' });
    res.json({ message: 'Venta actualizada' });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

/**
 * GET /ventas/:id?firebase_uid=
 * Devuelve el detalle completo de una venta incluyendo:
 *   - Información de la venta
 *   - presupuestos[] — lista de presupuestos de producción vinculados (Fase 2)
 *   - Lista de cobros/clientes con sus items
 *   - Resumen financiero ampliado (Fase 7):
 *       total_invertido, total_cobrado, total_esperado, total_pendiente,
 *       ganancia, margen, margen_esperado, porcentaje_cobrado,
 *       cobros_realizados, cobros_pendientes
 *
 * total_invertido = SUM de todos los presupuestos en venta_presupuestos (Fase 2).
 * Si la venta no tiene entradas en venta_presupuestos (datos legacy), cae al
 * campo presupuesto_produccion_id de la tabla ventas como fallback.
 */
app.get('/ventas/:id', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    // Bug 2: si la venta tiene inversión manual (campo `inversion`), se usa directamente.
    // Si no, se calcula desde los presupuestos de producción vinculados (Fase 2) con fallback legacy.
    const [[venta]] = await db.execute(
      `SELECT v.*,
              COALESCE(
                v.inversion,
                (SELECT SUM(i.cantidad * i.precio_unitario)
                 FROM venta_presupuestos vp2
                 JOIN items_produccion i ON i.presupuesto_produccion_id = vp2.presupuesto_produccion_id
                 WHERE vp2.venta_id = v.id),
                COALESCE(
                  (SELECT SUM(i2.cantidad * i2.precio_unitario)
                   FROM items_produccion i2
                   WHERE i2.presupuesto_produccion_id = v.presupuesto_produccion_id),
                  0
                )
              ) AS total_invertido
       FROM ventas v
       WHERE v.id = ? AND v.firebase_uid = ?`,
      [id, firebase_uid]
    );
    if (!venta) return res.status(404).json({ error: 'Venta no encontrada' });

    // Fase 2: lista de presupuestos vinculados con su costo individual
    const [presupuestos] = await db.execute(
      `SELECT pp.id, pp.nombre, pp.descripcion,
              COALESCE(SUM(ip.cantidad * ip.precio_unitario), 0) AS total_invertido
       FROM venta_presupuestos vp
       JOIN presupuestos_produccion pp ON pp.id = vp.presupuesto_produccion_id
       LEFT JOIN items_produccion ip ON ip.presupuesto_produccion_id = pp.id
       WHERE vp.venta_id = ?
       GROUP BY pp.id ORDER BY pp.id ASC`,
      [id]
    );

    const [cobros] = await db.execute(
      `SELECT * FROM cobros_clientes WHERE venta_id = ? AND firebase_uid = ? ORDER BY id ASC`,
      [id, firebase_uid]
    );

    // Adjuntar ítems de pedido a cada cobro (Fase 1)
    if (cobros.length > 0) {
      const cobroIds = cobros.map(c => c.id);
      const placeholders = cobroIds.map(() => '?').join(',');
      const [items] = await db.execute(
        `SELECT pi.*, vp.nombre AS variante_nombre, pr.nombre AS producto_nombre
         FROM pedido_items pi
         LEFT JOIN variantes_producto vp ON vp.id = pi.variante_id
         LEFT JOIN productos pr ON pr.id = vp.producto_id
         WHERE pi.cobro_cliente_id IN (${placeholders})
         ORDER BY pi.id ASC`,
        cobroIds
      );
      const itemsMap = {};
      items.forEach(item => {
        if (!itemsMap[item.cobro_cliente_id]) itemsMap[item.cobro_cliente_id] = [];
        itemsMap[item.cobro_cliente_id].push(item);
      });
      cobros.forEach(c => { c.items = itemsMap[c.id] || []; });
    } else {
      cobros.forEach(c => { c.items = []; });
    }

    // Fase 7: cálculo de todas las métricas financieras
    const cobradosList   = cobros.filter(c => c.estado === 'cobrado');
    const pendientesList = cobros.filter(c => c.estado === 'pendiente');

    const totalCobrado   = cobradosList.reduce((s, c) => s + Number(c.monto_cobrado || c.monto), 0);
    const totalEsperado  = cobros.reduce((s, c) => s + Number(c.monto), 0);
    const totalPendiente = pendientesList.reduce((s, c) => s + Number(c.monto), 0);
    const invertido      = Number(venta.total_invertido);

    const ganancia          = totalCobrado - invertido;
    // Bug 2: margen = (ganancia / total_cobrado) × 100 (antes dividía entre invertido)
    const margen            = totalCobrado > 0 ? (ganancia / totalCobrado * 100) : 0;
    const margenEsperado    = totalEsperado > 0 ? ((totalEsperado - invertido) / totalEsperado * 100) : 0;
    const porcentajeCobrado = totalEsperado > 0 ? (totalCobrado / totalEsperado * 100) : 0;

    // Fase 6: costo estimado desde recetas × precios de insumos
    // Solo se calcula si algún insumo tiene precio_unitario definido.
    let costoEstimado = null;
    if (cobros.length > 0) {
      const cobroIds     = cobros.map(c => c.id);
      const placeholders = cobroIds.map(() => '?').join(',');
      const [[ceRow]] = await db.execute(
        `SELECT SUM(ri.precio_unitario * ri.cantidad * pi.cantidad / r.rendimiento) AS costo_estimado
         FROM cobros_clientes cc
         JOIN pedido_items pi  ON pi.cobro_cliente_id = cc.id
         JOIN recetas r        ON r.variante_id = pi.variante_id
         JOIN receta_insumos ri ON ri.receta_id = r.id
         WHERE cc.id IN (${placeholders})
           AND pi.variante_id IS NOT NULL
           AND ri.precio_unitario IS NOT NULL AND ri.precio_unitario > 0`,
        cobroIds
      );
      if (ceRow?.costo_estimado != null)
        costoEstimado = parseFloat(Number(ceRow.costo_estimado).toFixed(2));
    }

    res.json({
      venta,
      presupuestos,   // Fase 2
      cobros,
      resumen: {
        total_invertido:     invertido,
        total_cobrado:       totalCobrado,
        total_esperado:      totalEsperado,
        total_pendiente:     totalPendiente,       // Fase 7
        ganancia,
        margen,
        margen_esperado:     margenEsperado,       // Fase 7
        porcentaje_cobrado:  porcentajeCobrado,    // Fase 7
        costo_estimado:      costoEstimado,        // Fase 6: null si no hay precios en recetas
        diferencia_costo:    costoEstimado != null ? parseFloat((invertido - costoEstimado).toFixed(2)) : null,
        cobros_realizados:   cobradosList.length,
        cobros_pendientes:   pendientesList.length,
      }
    });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

/**
 * POST /ventas/:id/cobros
 * Agrega un cliente a una venta con su monto y condición de pago.
 *
 * condicion_pago puede ser:
 *   'contra_entrega'  → sin fecha, sin evento en calendario
 *   'plazo'           → fecha = hoy + dias_plazo → crea evento en calendario
 *   'fecha_especifica'→ fecha exacta del body (fecha_pago_especifica) → crea evento en calendario
 *
 * Cuando se crea evento en calendario:
 *   - tipo = 'cobro'
 *   - cobro_id vinculado para sincronizar estado al cobrar
 *   - recordatorio implícito (el cron de vencidos lo detectará)
 */
app.post('/ventas/:id/cobros', async (req, res) => {
  const { id } = req.params;
  const { nombre_cliente, monto, condicion_pago, dias_plazo,
          fecha_pago_especifica, firebase_uid } = req.body;
  if (!nombre_cliente || monto == null || !condicion_pago || !firebase_uid)
    return res.status(400).json({ error: 'Datos incompletos' });

  const conn = await db.getConnection();
  await conn.beginTransaction();
  try {
    // Calcular la fecha de cobro según el tipo de condición
    let fechaCobro = null;
    if (condicion_pago === 'plazo' && dias_plazo) {
      const f = new Date();
      f.setDate(f.getDate() + Number(dias_plazo));
      fechaCobro = f.toISOString().split('T')[0];
    } else if (condicion_pago === 'fecha_especifica' && fecha_pago_especifica) {
      fechaCobro = fecha_pago_especifica; // ya viene en formato YYYY-MM-DD
    }

    const [result] = await conn.execute(
      `INSERT INTO cobros_clientes
       (venta_id, firebase_uid, nombre_cliente, monto, condicion_pago, dias_plazo, fecha_cobro)
       VALUES (?, ?, ?, ?, ?, ?, ?)`,
      [id, firebase_uid, nombre_cliente, monto, condicion_pago, dias_plazo || null, fechaCobro]
    );
    const cobroId = result.insertId;

    // Crear evento en calendario cuando hay fecha definida (plazo O fecha_especifica)
    const necesitaEvento = (condicion_pago === 'plazo' || condicion_pago === 'fecha_especifica') && fechaCobro;
    if (necesitaEvento) {
      const [[venta]] = await conn.execute(`SELECT nombre FROM ventas WHERE id = ?`, [id]);
      const titulo = `Cobro: ${nombre_cliente} (${venta?.nombre || 'Venta'})`;

      const [evResult] = await conn.execute(
        `INSERT INTO calendario_eventos (firebase_uid, titulo, tipo, fecha_evento, monto_esperado, estado, cobro_id)
         VALUES (?, ?, 'cobro', ?, ?, 'pendiente', ?)`,
        [firebase_uid, titulo, fechaCobro, monto, cobroId]
      );
      await conn.execute(
        `UPDATE cobros_clientes SET calendario_evento_id = ? WHERE id = ?`,
        [evResult.insertId, cobroId]
      );
    }

    await conn.commit();
    conn.release();
    res.status(201).json({ id: cobroId, message: 'Cliente agregado' });
  } catch (err) {
    await conn.rollback();
    conn.release();
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

/**
 * PUT /cobros/:id/cobrar
 * Marca un cobro como realizado con el monto real cobrado.
 * También actualiza el evento del calendario a 'pagado' (si existe).
 */
app.put('/cobros/:id/cobrar', async (req, res) => {
  const { id } = req.params;
  const { monto_cobrado, firebase_uid } = req.body;
  if (!monto_cobrado || !firebase_uid) return res.status(400).json({ error: 'Datos incompletos' });
  try {
    await db.execute(
      `UPDATE cobros_clientes
       SET estado = 'cobrado', monto_cobrado = ?, fecha_cobrado = NOW()
       WHERE id = ? AND firebase_uid = ?`,
      [monto_cobrado, id, firebase_uid]
    );

    // Actualizamos el evento del calendario si existe
    const [[cobro]] = await db.execute(
      `SELECT calendario_evento_id FROM cobros_clientes WHERE id = ?`, [id]
    );
    if (cobro?.calendario_evento_id) {
      await db.execute(
        `UPDATE calendario_eventos SET estado = 'pagado' WHERE id = ?`,
        [cobro.calendario_evento_id]
      );
    }

    res.json({ message: 'Cobro registrado' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

/**
 * DELETE /cobros/:id?firebase_uid=
 * Elimina un cobro/cliente de una venta.
 * Si tenía un evento en el calendario, también lo elimina.
 */
app.delete('/cobros/:id', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [[cobro]] = await db.execute(
      `SELECT calendario_evento_id FROM cobros_clientes WHERE id = ?`, [id]
    );
    await db.execute(
      `DELETE FROM cobros_clientes WHERE id = ? AND firebase_uid = ?`, [id, firebase_uid]
    );
    // Limpiamos el evento del calendario vinculado
    if (cobro?.calendario_evento_id) {
      await db.execute(
        `DELETE FROM calendario_eventos WHERE id = ?`, [cobro.calendario_evento_id]
      );
    }
    res.json({ message: 'Cobro eliminado' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});


// =============================================================================
// MÓDULO: MULTI-PRESUPUESTO POR VENTA (Fase 2)
// Endpoints para vincular / desvincular presupuestos de producción en una venta.
// =============================================================================

/**
 * POST /ventas/:id/presupuestos
 * Vincula un presupuesto de producción adicional a una venta existente.
 * Útil cuando el usuario quiere agregar más insumos sin recrear la venta.
 *
 * Body: { presupuesto_produccion_id: int, firebase_uid: string }
 */
app.post('/ventas/:id/presupuestos', async (req, res) => {
  const { id } = req.params;
  const { presupuesto_produccion_id, firebase_uid } = req.body;
  if (!presupuesto_produccion_id || !firebase_uid)
    return res.status(400).json({ error: 'Datos incompletos' });
  try {
    // Verificar que la venta pertenece al usuario
    const [[venta]] = await db.execute(
      `SELECT id FROM ventas WHERE id = ? AND firebase_uid = ?`, [id, firebase_uid]
    );
    if (!venta) return res.status(404).json({ error: 'Venta no encontrada' });

    // Verificar que el presupuesto pertenece al usuario
    const [[pp]] = await db.execute(
      `SELECT id FROM presupuestos_produccion WHERE id = ? AND firebase_uid = ?`,
      [presupuesto_produccion_id, firebase_uid]
    );
    if (!pp) return res.status(404).json({ error: 'Presupuesto de producción no encontrado' });

    await db.execute(
      `INSERT IGNORE INTO venta_presupuestos (venta_id, presupuesto_produccion_id) VALUES (?, ?)`,
      [id, presupuesto_produccion_id]
    );
    res.status(201).json({ message: 'Presupuesto vinculado' });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

/**
 * DELETE /ventas/:id/presupuestos/:pid?firebase_uid=
 * Desvincula un presupuesto de producción de una venta.
 */
app.delete('/ventas/:id/presupuestos/:pid', async (req, res) => {
  const { id, pid } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    // Verificar propiedad de la venta
    const [[venta]] = await db.execute(
      `SELECT id FROM ventas WHERE id = ? AND firebase_uid = ?`, [id, firebase_uid]
    );
    if (!venta) return res.status(404).json({ error: 'Venta no encontrada' });

    const [result] = await db.execute(
      `DELETE FROM venta_presupuestos WHERE venta_id = ? AND presupuesto_produccion_id = ?`,
      [id, pid]
    );
    if (result.affectedRows === 0) return res.status(404).json({ error: 'Vínculo no encontrado' });
    res.json({ message: 'Presupuesto desvinculado' });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});


// =============================================================================
// MÓDULO: LISTA DE COMPRAS (Fase 5)
// Calcula automáticamente cuánto insumo comprar para cubrir los pedidos de
// una venta, usando las recetas de cada variante vendida.
// Fórmula: cantidad_necesaria = cantidad_base_receta × unidades_vendidas / rendimiento
// =============================================================================

/**
 * GET /ventas/:id/lista-compras?firebase_uid=
 * Retorna la lista de compras agrupada por insumo para todos los pedidos de la venta.
 *
 * Respuesta:
 *   insumos[]       — insumos con receta: { nombre, unidad, cantidad_total, fuentes, precio_estimado }
 *   sin_receta[]    — variantes vendidas sin receta definida: { descripcion, cantidad_total }
 *   resumen         — { total_insumos, variantes_sin_receta, costo_estimado_total }
 *
 * Solo considera pedido_items con variante_id (ignora ítems manuales sin variante).
 * Si los insumos no tienen precio_unitario, precio_estimado es null.
 */
app.get('/ventas/:id/lista-compras', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    // Verificar propiedad de la venta
    const [[venta]] = await db.execute(
      `SELECT id, nombre FROM ventas WHERE id = ? AND firebase_uid = ?`, [id, firebase_uid]
    );
    if (!venta) return res.status(404).json({ error: 'Venta no encontrada' });

    // Insumos con receta: agrupados por nombre+unidad
    // fuentes: lista de "variante (N uds)" separadas por coma
    const [insumos] = await db.execute(
      `SELECT
         ri.nombre,
         ri.unidad,
         ROUND(SUM(ri.cantidad * pi.cantidad / r.rendimiento), 3) AS cantidad_total,
         ri.precio_unitario,
         GROUP_CONCAT(
           DISTINCT CONCAT(vp.nombre, ' × ', CAST(pi.cantidad AS CHAR))
           ORDER BY vp.nombre SEPARATOR ', '
         ) AS fuentes
       FROM cobros_clientes cc
       JOIN pedido_items pi    ON pi.cobro_cliente_id = cc.id
       JOIN variantes_producto vp ON vp.id = pi.variante_id
       JOIN recetas r           ON r.variante_id = pi.variante_id
       JOIN receta_insumos ri   ON ri.receta_id = r.id
       WHERE cc.venta_id = ? AND cc.firebase_uid = ?
         AND pi.variante_id IS NOT NULL
       GROUP BY ri.nombre, ri.unidad, ri.precio_unitario
       ORDER BY ri.nombre`,
      [id, firebase_uid]
    );

    // Combinar filas del mismo insumo (mismo nombre+unidad, distinto precio_unitario no debería ocurrir,
    // pero si lo hace los agrupamos sumando cantidades y tomando el primer precio disponible)
    const insumosMap = {};
    insumos.forEach(row => {
      const key = `${row.nombre}||${row.unidad}`;
      if (!insumosMap[key]) {
        insumosMap[key] = {
          nombre: row.nombre,
          unidad: row.unidad,
          cantidad_total: 0,
          precio_unitario: row.precio_unitario,
          fuentes: new Set(),
        };
      }
      insumosMap[key].cantidad_total = parseFloat(
        (insumosMap[key].cantidad_total + Number(row.cantidad_total)).toFixed(3)
      );
      if (row.precio_unitario != null && insumosMap[key].precio_unitario == null)
        insumosMap[key].precio_unitario = row.precio_unitario;
      row.fuentes.split(', ').forEach(f => insumosMap[key].fuentes.add(f));
    });

    const insumosResult = Object.values(insumosMap).map(i => ({
      nombre:          i.nombre,
      unidad:          i.unidad,
      cantidad_total:  i.cantidad_total,
      precio_unitario: i.precio_unitario,
      costo_estimado:  i.precio_unitario != null
        ? parseFloat((Number(i.precio_unitario) * i.cantidad_total).toFixed(2))
        : null,
      fuentes: [...i.fuentes].join(', '),
    }));

    // Variantes vendidas sin receta definida
    const [sinReceta] = await db.execute(
      `SELECT pi.descripcion, SUM(pi.cantidad) AS cantidad_total
       FROM cobros_clientes cc
       JOIN pedido_items pi ON pi.cobro_cliente_id = cc.id
       WHERE cc.venta_id = ? AND cc.firebase_uid = ?
         AND pi.variante_id IS NOT NULL
         AND pi.variante_id NOT IN (SELECT variante_id FROM recetas)
       GROUP BY pi.descripcion
       ORDER BY pi.descripcion`,
      [id, firebase_uid]
    );

    const costoTotal = insumosResult.reduce(
      (s, i) => s + (i.costo_estimado != null ? i.costo_estimado : 0), 0
    );
    const tieneCostos = insumosResult.some(i => i.costo_estimado != null);

    res.json({
      insumos: insumosResult,
      sin_receta: sinReceta,
      resumen: {
        total_insumos:        insumosResult.length,
        variantes_sin_receta: sinReceta.length,
        costo_estimado_total: tieneCostos ? parseFloat(costoTotal.toFixed(2)) : null,
      },
    });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});


// =============================================================================
// MÓDULO: CATÁLOGO DE PRODUCTOS Y VARIANTES (Fase 1)
// Permite al usuario mantener un catálogo reutilizable de lo que vende.
// Flujo: producto → variante → pedido_item → cobro_cliente → venta
// =============================================================================

/**
 * GET /productos?firebase_uid=
 * Lista todos los productos del usuario con el conteo de variantes activas.
 */
app.get('/productos', async (req, res) => {
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [rows] = await db.execute(
      `SELECT p.*,
              COUNT(CASE WHEN v.activo = 1 THEN 1 END) AS variantes_activas
       FROM productos p
       LEFT JOIN variantes_producto v ON v.producto_id = p.id
       WHERE p.firebase_uid = ?
       GROUP BY p.id
       ORDER BY p.nombre ASC`,
      [firebase_uid]
    );
    res.json(rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

/**
 * POST /productos
 * Crea un producto en el catálogo.
 */
app.post('/productos', async (req, res) => {
  const { nombre, descripcion, firebase_uid } = req.body;
  if (!nombre || !firebase_uid) return res.status(400).json({ error: 'Datos incompletos' });
  try {
    const [result] = await db.execute(
      `INSERT INTO productos (firebase_uid, nombre, descripcion) VALUES (?, ?, ?)`,
      [firebase_uid, nombre, descripcion || null]
    );
    res.status(201).json({ id: result.insertId, nombre });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

/**
 * PUT /productos/:id
 * Edita nombre, descripción o estado activo de un producto.
 */
app.put('/productos/:id', async (req, res) => {
  const { id } = req.params;
  const { nombre, descripcion, activo, firebase_uid } = req.body;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    await db.execute(
      `UPDATE productos SET nombre = COALESCE(?, nombre),
                            descripcion = COALESCE(?, descripcion),
                            activo = COALESCE(?, activo)
       WHERE id = ? AND firebase_uid = ?`,
      [nombre || null, descripcion !== undefined ? descripcion : null, activo !== undefined ? activo : null, id, firebase_uid]
    );
    res.json({ message: 'Producto actualizado' });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

/**
 * DELETE /productos/:id?firebase_uid=
 * Elimina un producto y sus variantes (CASCADE).
 */
app.delete('/productos/:id', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [result] = await db.execute(
      `DELETE FROM productos WHERE id = ? AND firebase_uid = ?`, [id, firebase_uid]
    );
    if (result.affectedRows === 0) return res.status(404).json({ error: 'Producto no encontrado' });
    res.json({ message: 'Producto eliminado' });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

/**
 * GET /productos/:id/variantes?firebase_uid=
 * Lista las variantes de un producto (incluye inactivas para gestión).
 */
app.get('/productos/:id/variantes', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [rows] = await db.execute(
      `SELECT v.* FROM variantes_producto v
       JOIN productos p ON p.id = v.producto_id
       WHERE v.producto_id = ? AND p.firebase_uid = ?
       ORDER BY v.nombre ASC`,
      [id, firebase_uid]
    );
    res.json(rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

/**
 * POST /productos/:id/variantes
 * Crea una variante (sabor, tamaño, presentación) para un producto.
 */
app.post('/productos/:id/variantes', async (req, res) => {
  const { id } = req.params;
  const { nombre, tamano, precio, unidad, firebase_uid } = req.body;
  if (!nombre || precio == null || !firebase_uid) return res.status(400).json({ error: 'Datos incompletos' });
  try {
    const [[producto]] = await db.execute(
      `SELECT id FROM productos WHERE id = ? AND firebase_uid = ?`, [id, firebase_uid]
    );
    if (!producto) return res.status(404).json({ error: 'Producto no encontrado' });
    const [result] = await db.execute(
      `INSERT INTO variantes_producto (producto_id, nombre, tamano, precio, unidad) VALUES (?, ?, ?, ?, ?)`,
      [id, nombre, tamano || null, precio, unidad || 'unidad']
    );
    res.status(201).json({ id: result.insertId, nombre, tamano: tamano || null, precio, unidad: unidad || 'unidad' });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

/**
 * PUT /variantes/:id
 * Edita nombre, precio, unidad o estado activo de una variante.
 */
app.put('/variantes/:id', async (req, res) => {
  const { id } = req.params;
  const { nombre, tamano, precio, unidad, activo, firebase_uid } = req.body;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    await db.execute(
      `UPDATE variantes_producto v
       JOIN productos p ON p.id = v.producto_id
       SET v.nombre  = COALESCE(?, v.nombre),
           v.tamano  = COALESCE(?, v.tamano),
           v.precio  = COALESCE(?, v.precio),
           v.unidad  = COALESCE(?, v.unidad),
           v.activo  = COALESCE(?, v.activo)
       WHERE v.id = ? AND p.firebase_uid = ?`,
      [nombre || null, tamano !== undefined ? (tamano || null) : null,
       precio !== undefined ? precio : null,
       unidad || null, activo !== undefined ? activo : null,
       id, firebase_uid]
    );
    res.json({ message: 'Variante actualizada' });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

/**
 * DELETE /variantes/:id?firebase_uid=
 * Elimina una variante. Si tiene pedido_items, los desvincula (SET NULL en variante_id).
 */
app.delete('/variantes/:id', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [result] = await db.execute(
      `DELETE v FROM variantes_producto v
       JOIN productos p ON p.id = v.producto_id
       WHERE v.id = ? AND p.firebase_uid = ?`,
      [id, firebase_uid]
    );
    if (result.affectedRows === 0) return res.status(404).json({ error: 'Variante no encontrada' });
    res.json({ message: 'Variante eliminada' });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});


// =============================================================================
// MÓDULO: RECETAS DE PRODUCTOS (Fase 4)
// Define qué insumos necesita cada variante para producirse.
// Fórmula: cantidad_necesaria = cantidad_base_receta * total_vendido / rendimiento
// =============================================================================

/**
 * GET /variantes/:id/receta?firebase_uid=
 * Retorna la receta de una variante con todos sus insumos.
 * Si la variante no tiene receta, retorna 404.
 */
app.get('/variantes/:id/receta', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    // Verificar propiedad vía join con productos
    const [[receta]] = await db.execute(
      `SELECT r.* FROM recetas r
       JOIN variantes_producto vp ON vp.id = r.variante_id
       JOIN productos p ON p.id = vp.producto_id
       WHERE r.variante_id = ? AND p.firebase_uid = ?`,
      [id, firebase_uid]
    );
    if (!receta) return res.status(404).json({ error: 'Receta no encontrada' });

    const [insumos] = await db.execute(
      `SELECT * FROM receta_insumos WHERE receta_id = ? ORDER BY id ASC`,
      [receta.id]
    );
    res.json({ ...receta, insumos });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

/**
 * POST /variantes/:id/receta
 * Crea o reemplaza la receta de una variante.
 * Si ya existe una receta para esta variante, la actualiza (upsert).
 *
 * Body: { rendimiento, unidad, notas, firebase_uid }
 */
app.post('/variantes/:id/receta', async (req, res) => {
  const { id } = req.params;
  const { rendimiento, unidad, notas, firebase_uid } = req.body;
  if (rendimiento == null || !firebase_uid)
    return res.status(400).json({ error: 'Datos incompletos' });
  try {
    // Verificar propiedad
    const [[vp]] = await db.execute(
      `SELECT vp.id FROM variantes_producto vp
       JOIN productos p ON p.id = vp.producto_id
       WHERE vp.id = ? AND p.firebase_uid = ?`,
      [id, firebase_uid]
    );
    if (!vp) return res.status(404).json({ error: 'Variante no encontrada' });

    const [result] = await db.execute(
      `INSERT INTO recetas (variante_id, rendimiento, unidad, notas)
       VALUES (?, ?, ?, ?)
       ON DUPLICATE KEY UPDATE
         rendimiento = VALUES(rendimiento),
         unidad = VALUES(unidad),
         notas = VALUES(notas)`,
      [id, Number(rendimiento), unidad || 'tanda', notas || null]
    );

    // Si fue INSERT, insertId tiene el nuevo id; si fue UPDATE, obtenerlo
    const recetaId = result.insertId || (await db.execute(
      `SELECT id FROM recetas WHERE variante_id = ?`, [id]
    ))[0][0]?.id;

    res.status(201).json({ id: recetaId, message: 'Receta guardada' });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

/**
 * PUT /recetas/:id
 * Actualiza rendimiento, unidad o notas de una receta existente.
 */
app.put('/recetas/:id', async (req, res) => {
  const { id } = req.params;
  const { rendimiento, unidad, notas, firebase_uid } = req.body;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    await db.execute(
      `UPDATE recetas r
       JOIN variantes_producto vp ON vp.id = r.variante_id
       JOIN productos p ON p.id = vp.producto_id
       SET r.rendimiento = COALESCE(?, r.rendimiento),
           r.unidad = COALESCE(?, r.unidad),
           r.notas = ?
       WHERE r.id = ? AND p.firebase_uid = ?`,
      [rendimiento != null ? Number(rendimiento) : null,
       unidad || null, notas !== undefined ? notas : null, id, firebase_uid]
    );
    res.json({ message: 'Receta actualizada' });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

/**
 * DELETE /recetas/:id?firebase_uid=
 * Elimina una receta y todos sus insumos (CASCADE).
 */
app.delete('/recetas/:id', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [result] = await db.execute(
      `DELETE r FROM recetas r
       JOIN variantes_producto vp ON vp.id = r.variante_id
       JOIN productos p ON p.id = vp.producto_id
       WHERE r.id = ? AND p.firebase_uid = ?`,
      [id, firebase_uid]
    );
    if (result.affectedRows === 0) return res.status(404).json({ error: 'Receta no encontrada' });
    res.json({ message: 'Receta eliminada' });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

/**
 * POST /recetas/:id/insumos
 * Agrega un insumo (ingrediente) a una receta.
 * Body: { nombre, cantidad, unidad, precio_unitario?, firebase_uid }
 * precio_unitario es opcional (Fase 6: permite calcular costo estimado).
 */
app.post('/recetas/:id/insumos', async (req, res) => {
  const { id } = req.params;
  const { nombre, cantidad, unidad, precio_unitario, firebase_uid } = req.body;
  if (!nombre || cantidad == null || !firebase_uid)
    return res.status(400).json({ error: 'Datos incompletos' });
  try {
    const [[receta]] = await db.execute(
      `SELECT r.id FROM recetas r
       JOIN variantes_producto vp ON vp.id = r.variante_id
       JOIN productos p ON p.id = vp.producto_id
       WHERE r.id = ? AND p.firebase_uid = ?`,
      [id, firebase_uid]
    );
    if (!receta) return res.status(404).json({ error: 'Receta no encontrada' });

    const precio = precio_unitario != null && Number(precio_unitario) > 0
      ? Number(precio_unitario) : null;

    const [result] = await db.execute(
      `INSERT INTO receta_insumos (receta_id, nombre, cantidad, unidad, precio_unitario)
       VALUES (?, ?, ?, ?, ?)`,
      [id, nombre, Number(cantidad), unidad || 'g', precio]
    );
    res.status(201).json({
      id: result.insertId, nombre,
      cantidad: Number(cantidad), unidad: unidad || 'g', precio_unitario: precio,
    });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

/**
 * PUT /receta-insumos/:id
 * Edita nombre, cantidad, unidad o precio_unitario de un insumo.
 * precio_unitario: enviar null para borrar el precio (sin estimado para este insumo).
 */
app.put('/receta-insumos/:id', async (req, res) => {
  const { id } = req.params;
  const { nombre, cantidad, unidad, precio_unitario, firebase_uid } = req.body;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    // precio_unitario puede ser null explícito (borrar) o un número
    const precio = precio_unitario === null ? null
      : (precio_unitario != null && Number(precio_unitario) > 0 ? Number(precio_unitario) : undefined);

    await db.execute(
      `UPDATE receta_insumos ri
       JOIN recetas r ON r.id = ri.receta_id
       JOIN variantes_producto vp ON vp.id = r.variante_id
       JOIN productos p ON p.id = vp.producto_id
       SET ri.nombre          = COALESCE(?, ri.nombre),
           ri.cantidad        = COALESCE(?, ri.cantidad),
           ri.unidad          = COALESCE(?, ri.unidad),
           ri.precio_unitario = ${precio !== undefined ? '?' : 'ri.precio_unitario'}
       WHERE ri.id = ? AND p.firebase_uid = ?`,
      precio !== undefined
        ? [nombre || null, cantidad != null ? Number(cantidad) : null, unidad || null, precio, id, firebase_uid]
        : [nombre || null, cantidad != null ? Number(cantidad) : null, unidad || null, id, firebase_uid]
    );
    res.json({ message: 'Insumo actualizado' });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

/**
 * DELETE /receta-insumos/:id?firebase_uid=
 * Elimina un insumo de una receta.
 */
app.delete('/receta-insumos/:id', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [result] = await db.execute(
      `DELETE ri FROM receta_insumos ri
       JOIN recetas r ON r.id = ri.receta_id
       JOIN variantes_producto vp ON vp.id = r.variante_id
       JOIN productos p ON p.id = vp.producto_id
       WHERE ri.id = ? AND p.firebase_uid = ?`,
      [id, firebase_uid]
    );
    if (result.affectedRows === 0) return res.status(404).json({ error: 'Insumo no encontrado' });
    res.json({ message: 'Insumo eliminado' });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});


// =============================================================================
// MÓDULO: PEDIDO ITEMS (Fase 1)
// Detalle de productos por cliente. Permite calcular el total del cliente
// automáticamente desde los productos pedidos.
// =============================================================================

/**
 * GET /cobros/:id/items
 * Lista los ítems del pedido de un cliente con subtotales.
 */
app.get('/cobros/:id/items', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    // Verificar que el cobro pertenece al usuario antes de retornar sus ítems
    const [[cobro]] = await db.execute(
      `SELECT id FROM cobros_clientes WHERE id = ? AND firebase_uid = ?`, [id, firebase_uid]
    );
    if (!cobro) return res.status(404).json({ error: 'Cobro no encontrado' });

    const [rows] = await db.execute(
      `SELECT pi.*, vp.nombre AS variante_nombre, pr.nombre AS producto_nombre
       FROM pedido_items pi
       LEFT JOIN variantes_producto vp ON vp.id = pi.variante_id
       LEFT JOIN productos pr ON pr.id = vp.producto_id
       WHERE pi.cobro_cliente_id = ?
       ORDER BY pi.id ASC`,
      [id]
    );
    res.json(rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

/**
 * POST /cobros/:id/items
 * Agrega un ítem al pedido de un cliente y actualiza el monto total del cobro.
 * Si variante_id viene, copia nombre y precio de la variante (snapshot del precio).
 * Si no viene (ítem libre), usa descripcion y precio_unitario del body.
 *
 * Después de insertar, recalcula cobros_clientes.monto como SUM(pedido_items.subtotal)
 * y pone monto_manual=0 para indicar que el total es calculado.
 */
app.post('/cobros/:id/items', async (req, res) => {
  const { id } = req.params;
  const { variante_id, descripcion, cantidad, precio_unitario, firebase_uid } = req.body;
  if (!firebase_uid || (!variante_id && !descripcion) || !cantidad || precio_unitario == null)
    return res.status(400).json({ error: 'Datos incompletos' });

  const conn = await db.getConnection();
  await conn.beginTransaction();
  try {
    let desc = descripcion;
    let precio = Number(precio_unitario);

    // Si viene variante_id, usar su nombre y precio actual como snapshot
    if (variante_id) {
      const [[variante]] = await conn.execute(
        `SELECT nombre, precio FROM variantes_producto WHERE id = ?`, [variante_id]
      );
      if (!variante) {
        await conn.rollback();
        conn.release();
        return res.status(404).json({ error: 'Variante no encontrada' });
      }
      desc = desc || variante.nombre;
      precio = precio || Number(variante.precio);
    }

    const cant = Number(cantidad);
    const subtotal = parseFloat((cant * precio).toFixed(2));

    const [result] = await conn.execute(
      `INSERT INTO pedido_items (cobro_cliente_id, variante_id, descripcion, cantidad, precio_unitario, subtotal)
       VALUES (?, ?, ?, ?, ?, ?)`,
      [id, variante_id || null, desc, cant, precio, subtotal]
    );

    // Recalcular el monto del cobro desde los ítems y marcar como calculado
    await conn.execute(
      `UPDATE cobros_clientes
       SET monto = (SELECT COALESCE(SUM(subtotal), 0) FROM pedido_items WHERE cobro_cliente_id = ?),
           monto_manual = 0
       WHERE id = ?`,
      [id, id]
    );

    // Sincronizar monto_esperado en el evento de calendario vinculado.
    // Cuando se agrega el primer ítem, el cobro tenía monto=0 (creado con catálogo),
    // por lo que el evento quedó con monto_esperado=0. Aquí se corrige.
    const [[cobroActualizado]] = await conn.execute(
      `SELECT monto, calendario_evento_id FROM cobros_clientes WHERE id = ?`, [id]
    );
    if (cobroActualizado?.calendario_evento_id) {
      await conn.execute(
        `UPDATE calendario_eventos SET monto_esperado = ? WHERE id = ?`,
        [cobroActualizado.monto, cobroActualizado.calendario_evento_id]
      );
    }

    await conn.commit();
    conn.release();
    res.status(201).json({ id: result.insertId, descripcion: desc, cantidad: cant, precio_unitario: precio, subtotal });
  } catch (err) {
    await conn.rollback();
    conn.release();
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

/**
 * DELETE /pedido-items/:id?firebase_uid=
 * Elimina un ítem del pedido y recalcula el monto del cobro.
 */
app.delete('/pedido-items/:id', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    // Obtener el cobro_cliente_id y verificar ownership en un solo JOIN
    const [[item]] = await db.execute(
      `SELECT pi.cobro_cliente_id
       FROM pedido_items pi
       JOIN cobros_clientes cc ON cc.id = pi.cobro_cliente_id
       WHERE pi.id = ? AND cc.firebase_uid = ?`,
      [id, firebase_uid]
    );
    if (!item) return res.status(404).json({ error: 'Ítem no encontrado' });

    await db.execute(`DELETE FROM pedido_items WHERE id = ?`, [id]);

    // Recalcular monto del cobro
    await db.execute(
      `UPDATE cobros_clientes
       SET monto = (SELECT COALESCE(SUM(subtotal), 0) FROM pedido_items WHERE cobro_cliente_id = ?)
       WHERE id = ?`,
      [item.cobro_cliente_id, item.cobro_cliente_id]
    );

    res.json({ message: 'Ítem eliminado' });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

// =============================================================================
// CRON JOB — DETECCIÓN DE EVENTOS VENCIDOS
// Corre cada día a medianoche (hora de Panamá UTC-5).
// Busca eventos del calendario que hayan vencido sin ser pagados y los marca.
// Esto permite al usuario ver claramente cuáles pagos se le pasaron.
// =============================================================================
cron.schedule('0 0 * * *', async () => {
  try {
    const [result] = await db.execute(
      `UPDATE calendario_eventos
       SET estado = 'vencido'
       WHERE estado = 'pendiente' AND fecha_evento < CURDATE()`
    );
    console.log(`⏰ Cron vencidos: ${result.affectedRows} eventos actualizados`);
  } catch (err) {
    console.error('Error en cron vencimientos:', err);
  }
}, { timezone: 'America/Panama' }); // Zona horaria de Panamá (donde opera el usuario)


// =============================================================================
// MÓDULO: ESTADO DE CUENTA POR CLIENTE (Prompt 6)
// =============================================================================

/**
 * GET /clientes/:nombre/estado-cuenta?firebase_uid=
 * Historial completo de cobros de un cliente a través de TODAS sus ventas.
 * Retorna totales de cobrado, pendiente y cantidad de ventas distintas.
 */
app.get('/clientes/:nombre/estado-cuenta', async (req, res) => {
  const { nombre } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid es requerido' });
  try {
    const [cobros] = await db.execute(
      `SELECT
         cc.id, cc.nombre_cliente, cc.monto, cc.estado, cc.fecha_cobro,
         cc.monto_cobrado, cc.fecha_cobrado, cc.condicion_pago,
         v.nombre AS venta_nombre, v.id AS venta_id
       FROM cobros_clientes cc
       JOIN ventas v ON v.id = cc.venta_id
       WHERE cc.firebase_uid = ? AND LOWER(cc.nombre_cliente) = LOWER(?)
       ORDER BY cc.created_at DESC`,
      [firebase_uid, nombre]
    );

    if (cobros.length === 0) return res.status(404).json({ error: 'Cliente no encontrado' });

    const totalCobrado  = cobros
      .filter(c => c.estado === 'cobrado')
      .reduce((s, c) => s + Number(c.monto_cobrado || 0), 0);
    const totalPendiente = cobros
      .filter(c => c.estado === 'pendiente')
      .reduce((s, c) => s + Number(c.monto || 0), 0);
    const ventasIds = [...new Set(cobros.map(c => c.venta_id))];

    res.json({
      nombre_cliente: cobros[0].nombre_cliente,
      cobros,
      total_cobrado: totalCobrado,
      total_pendiente: totalPendiente,
      cantidad_ventas: ventasIds.length,
    });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});


// =============================================================================
// INICIO DEL SERVIDOR
// =============================================================================
const PORT = process.env.PORT || 3002;
app.listen(PORT, () => console.log(`🚀 Servidor activo en puerto ${PORT}`));
