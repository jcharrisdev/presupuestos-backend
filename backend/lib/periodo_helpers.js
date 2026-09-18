/**
 * lib/periodo_helpers.js — Lógica de períodos: cada presupuesto opera en ciclos
 * de tiempo (períodos). getPeriodoActivo() es el corazón del sistema: siempre
 * garantiza que exista un período vigente para trabajar. Extraído de server.js
 * porque Presupuestos, Gastos, Movimientos, Jobs y las herramientas de IA lo usan.
 */
const { db } = require('./db');
const { calcularFechaFin } = require('./calculos_financieros');

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
  // Obtener tipo_periodo del presupuesto para calcular el monto por período
  const [[presupuesto]] = await db.execute(
    `SELECT tipo_periodo FROM presupuestos WHERE id = ?`, [presupuestoId]
  );
  const divisor = presupuesto?.tipo_periodo === 'quincenal' ? 2 : 1;

  // 1. Compromisos fijos GLOBALES del usuario (user_gastos_fijos)
  //    Estos son la realidad de su vida: hipoteca, carro, préstamos, etc.
  const [gastosFijos] = await db.execute(
    `SELECT * FROM user_gastos_fijos WHERE firebase_uid = ? AND activo = 1`,
    [firebaseUid]
  );
  for (const gf of gastosFijos) {
    const montoPeriodo = parseFloat((Number(gf.monto_mensual) / divisor).toFixed(2));
    await db.execute(
      `INSERT INTO movimientos
       (presupuesto_id, periodo_id, gasto_id, descripcion, monto, tipo, pagado,
        firebase_uid, clasificacion, created_at)
       VALUES (?, ?, NULL, ?, ?, 'fijo', 0, ?, ?, NOW())`,
      [presupuestoId, periodoId, gf.descripcion, montoPeriodo, firebaseUid, gf.clasificacion]
    );
  }

  // 2. Metas de ahorro activas del presupuesto (gastos tipo 'ahorro' con cuotas)
  const [gastosAhorro] = await db.execute(
    `SELECT * FROM gastos WHERE presupuesto_id = ? AND firebase_uid = ?
     AND tipo = 'ahorro'
     AND (numero_quincena IS NULL OR numero_quincena > 0)`,
    [presupuestoId, firebaseUid]
  );
  for (const gasto of gastosAhorro) {
    if (gasto.numero_quincena !== null) {
      const [[{ ya_aportado }]] = await db.execute(
        `SELECT COALESCE(SUM(monto), 0) AS ya_aportado FROM aportaciones_ahorro WHERE gasto_id = ?`,
        [gasto.id]
      );
      const [[{ ya_pagado }]] = await db.execute(
        `SELECT COALESCE(SUM(monto_pagado_real), 0) AS ya_pagado FROM movimientos WHERE gasto_id = ? AND pagado = 1`,
        [gasto.id]
      );
      const metaTotal = gasto.monto * gasto.numero_quincena;
      if ((parseFloat(ya_aportado) + parseFloat(ya_pagado)) >= metaTotal) {
        await db.execute(`UPDATE gastos SET numero_quincena = 0 WHERE id = ?`, [gasto.id]);
        continue;
      }
    }
    await db.execute(
      `INSERT INTO movimientos
       (presupuesto_id, periodo_id, gasto_id, descripcion, monto, tipo, pagado, firebase_uid, created_at)
       VALUES (?, ?, ?, ?, ?, 'ahorro', 0, ?, NOW())`,
      [presupuestoId, periodoId, gasto.id, gasto.descripcion, gasto.monto, firebaseUid]
    );
    if (gasto.numero_quincena !== null) {
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

module.exports = {
  getPeriodoActivo,
  generarMovimientosPeriodo,
  crearPrimerPeriodo,
  crearNuevoPeriodo,
  _insertarPeriodo,
};
