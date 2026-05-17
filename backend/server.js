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
const cron    = require('node-cron');
const fetch   = (...args) => import('node-fetch').then(({default: f}) => f(...args));

const app = express();
app.use(cors());          // Permite peticiones desde el app Flutter (cross-origin)
app.use(express.json());  // Parsea el body de las peticiones como JSON

// =============================================================================
// CONEXIÓN A MYSQL — POOL de conexiones
// =============================================================================
// Se usa createPool en lugar de createConnection para evitar que el servidor
// crashee cuando Clever Cloud cierra conexiones inactivas (timeout).
// Con pool, mysql2 reabre la conexión automáticamente cuando se necesita.
// connectionLimit: 3 → Clever Cloud free tier permite máximo 5 conexiones por usuario
const pool = mysql.createPool({
  host:     process.env.MYSQLHOST,
  user:     process.env.MYSQLUSER,
  password: process.env.MYSQLPASSWORD,
  database: process.env.MYSQLDATABASE,
  port:     Number(process.env.MYSQLPORT),
  waitForConnections: true,
  connectionLimit: 3,
  queueLimit: 0,
});

// Verifica la conexión y ejecuta migraciones al arrancar
pool.getConnection(async (err, conn) => {
  if (err) { console.error('❌ Error conectando a MySQL:', err); return; }
  console.log('✅ Conectado a MySQL');
  conn.release();

  // Migración: tablas de perfil financiero global del usuario
  try {
    await db.execute(`CREATE TABLE IF NOT EXISTS user_income (
      id INT AUTO_INCREMENT PRIMARY KEY,
      firebase_uid VARCHAR(255) NOT NULL,
      tipo_ingreso ENUM('salario','informal','ocasional','otro') DEFAULT 'salario',
      ingreso_bruto_mensual DECIMAL(10,2) DEFAULT 0,
      desc_seguro DECIMAL(10,2) DEFAULT 0,
      desc_pension DECIMAL(10,2) DEFAULT 0,
      desc_impuesto DECIMAL(10,2) DEFAULT 0,
      desc_otros DECIMAL(10,2) DEFAULT 0,
      ingreso_neto_mensual DECIMAL(10,2) NOT NULL,
      calcular_automatico TINYINT DEFAULT 0,
      frecuencia_cobro ENUM('mensual','quincenal') DEFAULT 'quincenal',
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      UNIQUE KEY uq_user_income (firebase_uid)
    )`);
    await db.execute(`CREATE TABLE IF NOT EXISTS user_gastos_fijos (
      id INT AUTO_INCREMENT PRIMARY KEY,
      firebase_uid VARCHAR(255) NOT NULL,
      descripcion VARCHAR(255) NOT NULL,
      monto_mensual DECIMAL(10,2) NOT NULL,
      tipo ENUM('vivienda','transporte','deuda','servicios','educacion','salud','alimentacion','otro') DEFAULT 'otro',
      clasificacion ENUM('esencial','importante','flexible') DEFAULT 'importante',
      es_deuda TINYINT DEFAULT 0,
      activo TINYINT DEFAULT 1,
      subcategoria VARCHAR(100),
      notas TEXT,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      KEY idx_ugf_user (firebase_uid)
    )`);
    console.log('✅ Migración user_income / user_gastos_fijos OK');
  } catch (e) {
    console.error('⚠️ Migración parcial:', e.message);
  }

  // Migración: sobres de presupuesto y gastos rápidos
  try {
    await db.execute(`CREATE TABLE IF NOT EXISTS presupuesto_categorias (
      id INT AUTO_INCREMENT PRIMARY KEY,
      presupuesto_id INT NOT NULL,
      firebase_uid VARCHAR(255) NOT NULL,
      nombre VARCHAR(100) NOT NULL,
      icono VARCHAR(50) DEFAULT 'category',
      color VARCHAR(10) DEFAULT '#6B7280',
      monto_asignado DECIMAL(10,2) NOT NULL DEFAULT 0,
      orden INT DEFAULT 0,
      activa TINYINT DEFAULT 1,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      KEY idx_pc_presupuesto (presupuesto_id),
      KEY idx_pc_user (firebase_uid)
    )`);
    await db.execute(`CREATE TABLE IF NOT EXISTS presupuesto_gastos (
      id INT AUTO_INCREMENT PRIMARY KEY,
      presupuesto_id INT NOT NULL,
      periodo_id INT,
      categoria_id INT,
      firebase_uid VARCHAR(255) NOT NULL,
      descripcion VARCHAR(255),
      monto DECIMAL(10,2) NOT NULL,
      fecha DATE NOT NULL,
      es_hormiga TINYINT DEFAULT 0,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      KEY idx_pg_presupuesto (presupuesto_id),
      KEY idx_pg_categoria (categoria_id),
      KEY idx_pg_user (firebase_uid)
    )`);
    // Columna aporte_periodo en shared_budget_members (ya existe en prod — skip silencioso)
    try {
      await db.execute(`ALTER TABLE shared_budget_members
        ADD COLUMN aporte_periodo DECIMAL(10,2) DEFAULT 0`);
    } catch (_) { /* ya existe, ignorar */ }
    console.log('✅ Migración presupuesto_categorias / presupuesto_gastos OK');
  } catch (e) {
    console.error('⚠️ Migración sobres parcial:', e.message);
  }

  // ── NUEVO MODELO FINANCIERO ANUAL ──────────────────────────────────────────
  try {
    await db.execute(`CREATE TABLE IF NOT EXISTS subcategorias (
      id           INT AUTO_INCREMENT PRIMARY KEY,
      firebase_uid VARCHAR(255) NOT NULL,
      categoria    VARCHAR(100) NOT NULL,
      nombre       VARCHAR(100) NOT NULL,
      es_global    TINYINT DEFAULT 0,
      activa       TINYINT DEFAULT 1,
      created_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      KEY idx_sub_user (firebase_uid)
    )`);

    await db.execute(`CREATE TABLE IF NOT EXISTS gastos_variables_base (
      id             INT AUTO_INCREMENT PRIMARY KEY,
      firebase_uid   VARCHAR(255) NOT NULL,
      nombre         VARCHAR(255) NOT NULL,
      categoria      VARCHAR(100) NOT NULL,
      subcategoria_id INT DEFAULT NULL,
      monto_estimado DECIMAL(12,2) NOT NULL,
      frecuencia     ENUM('mensual','quincenal','semanal','anual') DEFAULT 'mensual',
      aplica_meses   LONGTEXT DEFAULT NULL,
      activo         TINYINT DEFAULT 1,
      en_calendario  TINYINT DEFAULT 0,
      notas          TEXT,
      created_at     TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      updated_at     TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      KEY idx_gvb_user (firebase_uid)
    )`);

    await db.execute(`CREATE TABLE IF NOT EXISTS estado_financiero_anual (
      id                       INT AUTO_INCREMENT PRIMARY KEY,
      firebase_uid             VARCHAR(255) NOT NULL,
      anio                     YEAR NOT NULL,
      ingreso_anual_estimado   DECIMAL(14,2) DEFAULT 0,
      gastos_fijos_anuales     DECIMAL(14,2) DEFAULT 0,
      gastos_variables_anuales DECIMAL(14,2) DEFAULT 0,
      remanente_anual_estimado DECIMAL(14,2) DEFAULT 0,
      ingreso_anual_real       DECIMAL(14,2) DEFAULT 0,
      gastos_fijos_reales      DECIMAL(14,2) DEFAULT 0,
      gastos_variables_reales  DECIMAL(14,2) DEFAULT 0,
      compras_no_presup_reales DECIMAL(14,2) DEFAULT 0,
      remanente_anual_real     DECIMAL(14,2) DEFAULT 0,
      cerrado                  TINYINT DEFAULT 0,
      created_at               TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      updated_at               TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      UNIQUE KEY uq_efa_user_anio (firebase_uid, anio)
    )`);

    await db.execute(`CREATE TABLE IF NOT EXISTS meses_financieros (
      id                       INT AUTO_INCREMENT PRIMARY KEY,
      firebase_uid             VARCHAR(255) NOT NULL,
      estado_anual_id          INT NOT NULL,
      anio                     YEAR NOT NULL,
      mes                      TINYINT NOT NULL,
      ingreso_estimado         DECIMAL(12,2) DEFAULT 0,
      fijos_estimados          DECIMAL(12,2) DEFAULT 0,
      variables_estimados      DECIMAL(12,2) DEFAULT 0,
      remanente_estimado       DECIMAL(12,2) DEFAULT 0,
      ingreso_real             DECIMAL(12,2) DEFAULT 0,
      fijos_reales             DECIMAL(12,2) DEFAULT 0,
      variables_reales         DECIMAL(12,2) DEFAULT 0,
      no_presupuestados_reales DECIMAL(12,2) DEFAULT 0,
      remanente_real           DECIMAL(12,2) DEFAULT 0,
      estado                   ENUM('futuro','activo','cerrado') DEFAULT 'futuro',
      cerrado_at               TIMESTAMP NULL,
      KEY idx_mf_user (firebase_uid),
      KEY idx_mf_anual (estado_anual_id),
      UNIQUE KEY uq_mf_user_mes (firebase_uid, anio, mes)
    )`);

    await db.execute(`CREATE TABLE IF NOT EXISTS registros_gasto (
      id                 INT AUTO_INCREMENT PRIMARY KEY,
      firebase_uid       VARCHAR(255) NOT NULL,
      mes_id             INT NOT NULL,
      anio               YEAR NOT NULL,
      mes                TINYINT NOT NULL,
      tipo               ENUM('fijo','variable','no_presupuestado') NOT NULL,
      categoria          VARCHAR(100) NOT NULL,
      subcategoria_id    INT DEFAULT NULL,
      nombre             VARCHAR(255) NOT NULL,
      monto              DECIMAL(12,2) NOT NULL,
      fecha              DATE NOT NULL,
      pagado             TINYINT DEFAULT 0,
      origen_fijo_id     INT DEFAULT NULL,
      origen_variable_id INT DEFAULT NULL,
      notas              TEXT,
      en_calendario      TINYINT DEFAULT 0,
      created_at         TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      KEY idx_rg_user (firebase_uid),
      KEY idx_rg_mes (mes_id),
      KEY idx_rg_cat (categoria)
    )`);

    await db.execute(`CREATE TABLE IF NOT EXISTS analisis_categorias (
      id                INT AUTO_INCREMENT PRIMARY KEY,
      firebase_uid      VARCHAR(255) NOT NULL,
      mes_id            INT NOT NULL,
      anio              YEAR NOT NULL,
      mes               TINYINT NOT NULL,
      categoria         VARCHAR(100) NOT NULL,
      presupuestado     DECIMAL(12,2) DEFAULT 0,
      gastado_variable  DECIMAL(12,2) DEFAULT 0,
      gastado_no_presup DECIMAL(12,2) DEFAULT 0,
      total_gastado     DECIMAL(12,2) DEFAULT 0,
      desviacion        DECIMAL(12,2) DEFAULT 0,
      pct_desviacion    DECIMAL(7,2)  DEFAULT 0,
      KEY idx_ac_user (firebase_uid),
      UNIQUE KEY uq_ac_mes_cat (mes_id, categoria)
    )`);

    await db.execute(`CREATE TABLE IF NOT EXISTS alertas_financieras (
      id              INT AUTO_INCREMENT PRIMARY KEY,
      firebase_uid    VARCHAR(255) NOT NULL,
      anio            YEAR,
      mes             TINYINT,
      tipo            VARCHAR(100) NOT NULL,
      categoria       VARCHAR(100),
      nivel           ENUM('info','warning','danger') DEFAULT 'info',
      titulo          VARCHAR(255) NOT NULL,
      mensaje         TEXT NOT NULL,
      accion_sugerida TEXT,
      leida           TINYINT DEFAULT 0,
      created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      KEY idx_al_user (firebase_uid),
      UNIQUE KEY uq_alerta (firebase_uid, anio, mes, tipo, categoria)
    )`);

    await db.execute(`CREATE TABLE IF NOT EXISTS cierres_mensuales (
      id                        INT AUTO_INCREMENT PRIMARY KEY,
      firebase_uid              VARCHAR(255) NOT NULL,
      mes_id                    INT NOT NULL,
      anio                      YEAR NOT NULL,
      mes                       TINYINT NOT NULL,
      ingreso_real              DECIMAL(12,2),
      fijos_pagados             DECIMAL(12,2),
      variables_reales          DECIMAL(12,2),
      no_presupuestados         DECIMAL(12,2),
      remanente_real            DECIMAL(12,2),
      categorias_con_desviacion LONGTEXT,
      recomendaciones           LONGTEXT,
      cerrado_at                TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      UNIQUE KEY uq_cm_mes (mes_id)
    )`);

    await db.execute(`CREATE TABLE IF NOT EXISTS cierres_anuales (
      id                      INT AUTO_INCREMENT PRIMARY KEY,
      firebase_uid            VARCHAR(255) NOT NULL,
      anio                    YEAR NOT NULL,
      ingreso_total           DECIMAL(14,2),
      fijos_total             DECIMAL(14,2),
      variables_total         DECIMAL(14,2),
      no_presupuestados_total DECIMAL(14,2),
      remanente_real          DECIMAL(14,2),
      analisis_categorias     LONGTEXT,
      recomendaciones_sig     LONGTEXT,
      cerrado_at              TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      UNIQUE KEY uq_ca_user_anio (firebase_uid, anio)
    )`);

    console.log('✅ Migración nuevo modelo financiero anual OK');
  } catch (e) {
    console.error('⚠️ Migración modelo anual:', e.message);
  }

  // Migración: tabla de eventos del calendario (pagos, recordatorios)
  try {
    await db.execute(`CREATE TABLE IF NOT EXISTS calendario_eventos (
      id                  INT AUTO_INCREMENT PRIMARY KEY,
      firebase_uid        VARCHAR(255) NOT NULL,
      gasto_id            INT DEFAULT NULL,
      user_gasto_fijo_id  INT DEFAULT NULL,
      presupuesto_id      INT DEFAULT NULL,
      titulo              VARCHAR(255) NOT NULL,
      tipo                ENUM('pago','ingreso','recordatorio') DEFAULT 'pago',
      fecha_evento        DATE NOT NULL,
      monto_esperado      DECIMAL(12,2) DEFAULT NULL,
      estado              ENUM('pendiente','pagado','vencido') DEFAULT 'pendiente',
      notificacion_activa TINYINT DEFAULT 1,
      dias_anticipacion   INT DEFAULT 3,
      created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      KEY idx_ce_user      (firebase_uid),
      KEY idx_ce_fecha     (firebase_uid, fecha_evento),
      KEY idx_ce_ugf       (user_gasto_fijo_id)
    )`);
    console.log('✅ Migración calendario_eventos OK');
  } catch (e) {
    console.error('⚠️ Migración calendario_eventos:', e.message);
  }

  // Migración: gastos globales reutilizables (independientes de presupuesto)
  try {
    await db.execute(`CREATE TABLE IF NOT EXISTS gastos_globales (
      id INT AUTO_INCREMENT PRIMARY KEY,
      firebase_uid VARCHAR(255) NOT NULL,
      nombre VARCHAR(255) NOT NULL,
      descripcion TEXT,
      monto DECIMAL(12,2) NOT NULL,
      categoria ENUM('vivienda','transporte','alimentacion','servicios','salud',
                     'educacion','entretenimiento','deuda','ahorro','otro') DEFAULT 'otro',
      tipo ENUM('fijo','variable') DEFAULT 'variable',
      modalidad ENUM('individual','compartido') DEFAULT 'individual',
      frecuencia ENUM('unico','mensual','quincenal','anual') DEFAULT 'mensual',
      dia_pago INT DEFAULT NULL,
      activo TINYINT DEFAULT 1,
      notas TEXT,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      KEY idx_gg_user (firebase_uid)
    )`);
    console.log('✅ Migración gastos_globales OK');
  } catch (e) {
    console.error('⚠️ Migración gastos_globales parcial:', e.message);
  }

  // Migración: link entre gastos de presupuesto y gastos_globales
  try {
    await db.execute(`ALTER TABLE gastos ADD COLUMN gasto_global_id INT DEFAULT NULL`);
  } catch (_) { /* columna ya existe */ }

  // Migración: período de vigencia en gastos_variables_base (qué meses aplica)
  const alterGVB = [
    `ALTER TABLE gastos_variables_base ADD COLUMN mes_inicio TINYINT DEFAULT 1`,
    `ALTER TABLE gastos_variables_base ADD COLUMN mes_fin TINYINT DEFAULT 12`,
  ];
  for (const sql of alterGVB) {
    try { await db.execute(sql); } catch (_) {}
  }

  // Migración: segundo día de pago para gastos quincenales
  try {
    await db.execute(`ALTER TABLE user_gastos_fijos ADD COLUMN dia_pago_2 INT DEFAULT NULL`);
  } catch (_) {}

  // Migración: campos de período y acreedor para deudas
  const alterDeudasPeriodo = [
    `ALTER TABLE deudas ADD COLUMN mes_inicio_pago TINYINT DEFAULT 1`,
    `ALTER TABLE deudas ADD COLUMN num_pagos_realizados INT DEFAULT 0`,
  ];
  for (const sql of alterDeudasPeriodo) {
    try { await db.execute(sql); } catch (_) {}
  }

  // Migración: campos de letras/cuotas en tabla deudas (silent si ya existen)
  const alterDeudas = [
    `ALTER TABLE deudas ADD COLUMN es_letra TINYINT DEFAULT 0`,
    `ALTER TABLE deudas ADD COLUMN num_cuotas_total INT DEFAULT NULL`,
    `ALTER TABLE deudas ADD COLUMN num_cuotas_pagadas INT DEFAULT 0`,
    `ALTER TABLE deudas ADD COLUMN cuota_fija DECIMAL(12,2) DEFAULT NULL`,
    `ALTER TABLE deudas ADD COLUMN nombre_acreedor VARCHAR(255) DEFAULT NULL`,
    `ALTER TABLE deudas ADD COLUMN fecha_inicio DATE DEFAULT NULL`,
  ];
  for (const sql of alterDeudas) {
    try { await db.execute(sql); } catch (_) { /* columna ya existe */ }
  }

  // Migración: columnas faltantes en user_gastos_fijos (silent si ya existen)
  const alterUGF = [
    `ALTER TABLE user_gastos_fijos ADD COLUMN frecuencia ENUM('fijo','variable') DEFAULT 'fijo'`,
    `ALTER TABLE user_gastos_fijos ADD COLUMN dia_pago INT DEFAULT NULL`,
    `ALTER TABLE user_gastos_fijos ADD COLUMN recordatorio TINYINT DEFAULT 0`,
    `ALTER TABLE user_gastos_fijos ADD COLUMN deuda_id INT DEFAULT NULL`,
  ];
  for (const sql of alterUGF) {
    try { await db.execute(sql); } catch (_) { /* columna ya existe */ }
  }
  console.log('✅ Migración ALTER deudas / user_gastos_fijos OK');

  // Migración: tabla de logs del servidor para diagnóstico de errores
  try {
    await db.execute(`CREATE TABLE IF NOT EXISTS server_logs (
      id           INT AUTO_INCREMENT PRIMARY KEY,
      nivel        ENUM('error','warn','info') DEFAULT 'error',
      ruta         VARCHAR(255),
      firebase_uid VARCHAR(255),
      mensaje      TEXT,
      stack        LONGTEXT,
      req_body     LONGTEXT,
      created_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      KEY idx_sl_time (created_at),
      KEY idx_sl_uid  (firebase_uid),
      KEY idx_sl_nivel (nivel)
    )`);
    console.log('✅ Migración server_logs OK');
  } catch (e) {
    console.error('⚠️ Migración server_logs:', e.message);
  }
});

// Usamos la versión con Promises (async/await) del pool
const db = pool.promise();

// =============================================================================
// SISTEMA DE LOGGING — guarda errores en server_logs para diagnóstico remoto
// =============================================================================
const LOG_SECRET = 'salarying_logs_2025';

async function _logError(ruta, error, uid = '-', reqBody = null) {
  try {
    const bodyStr = reqBody ? JSON.stringify(reqBody).substring(0, 1000) : null;
    await db.execute(
      `INSERT INTO server_logs (nivel, ruta, firebase_uid, mensaje, stack, req_body)
       VALUES ('error', ?, ?, ?, ?, ?)`,
      [ruta, uid, error?.message || String(error),
       error?.stack?.substring(0, 2000) || null, bodyStr]
    );
  } catch (_) {}
}

async function _logInfo(ruta, mensaje, uid = '-') {
  try {
    await db.execute(
      `INSERT INTO server_logs (nivel, ruta, firebase_uid, mensaje) VALUES ('info', ?, ?, ?)`,
      [ruta, uid, mensaje]
    );
  } catch (_) {}
}

// Auto-limpieza cada hora — borra todos los logs de más de 60 minutos
setInterval(async () => {
  try {
    await db.execute(`DELETE FROM server_logs WHERE created_at < DATE_SUB(NOW(), INTERVAL 60 MINUTE)`);
  } catch (_) {}
}, 60 * 60 * 1000);

// Middleware que intercepta automáticamente todas las respuestas 5xx
// y las guarda en server_logs sin modificar ningún endpoint existente.
app.use((req, res, next) => {
  const originalJson = res.json.bind(res);
  res.json = function(data) {
    if (res.statusCode >= 500 && data?.error) {
      const uid = req.body?.firebase_uid || req.query?.firebase_uid || '-';
      const safeBody = { ...req.body };
      delete safeBody.firebase_uid; // no loguear uid completa en body
      _logError(req.path, { message: data.error, stack: null }, uid, safeBody);
    }
    return originalJson(data);
  };
  next();
});

// GET /logs — devuelve los últimos errores del servidor (protegido por secret)
app.get('/logs', async (req, res) => {
  const { secret, limit = 50, nivel, uid, desde } = req.query;
  if (secret !== LOG_SECRET)
    return res.status(401).json({ error: 'Acceso denegado' });
  try {
    let sql = `SELECT id, nivel, ruta, firebase_uid, mensaje, stack, req_body, created_at
               FROM server_logs WHERE 1=1`;
    const params = [];
    if (nivel) { sql += ` AND nivel = ?`; params.push(nivel); }
    if (uid)   { sql += ` AND firebase_uid LIKE ?`; params.push(`%${uid}%`); }
    if (desde) { sql += ` AND created_at >= ?`; params.push(desde); }
    // LIMIT inlined — MySQL 5.6 + mysql2 no acepta BigInt/Number en prepared LIMIT
    const limitInt = Math.min(Math.max(parseInt(limit, 10) || 50, 1), 200);
    sql += ` ORDER BY created_at DESC LIMIT ${limitInt}`;
    const [rows] = await db.execute(sql, params);
    const [[countRow]] = await db.execute(`SELECT COUNT(*) AS total FROM server_logs`);
    const total = Number(countRow.total);
    res.json({ total, mostrados: rows.length, logs: rows });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// DELETE /logs — limpia los logs (protegido por secret)
app.delete('/logs', async (req, res) => {
  const { secret } = req.query;
  if (secret !== LOG_SECRET) return res.status(401).json({ error: 'Acceso denegado' });
  try {
    await db.execute(`DELETE FROM server_logs WHERE created_at < DATE_SUB(NOW(), INTERVAL 7 DAY)`);
    res.json({ ok: true, mensaje: 'Logs de más de 7 días eliminados' });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

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
    // Períodos reales: 1-15 y 16-último día del mes
    if (f.getDate() <= 15) {
      f.setDate(15);
    } else {
      // Avanzar al mes siguiente y retroceder 1 día = último día del mes actual
      f.setMonth(f.getMonth() + 1);
      f.setDate(0);
    }
  } else {
    // Mensual: inicio 01/05 → fin 31/05
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
  version: '4.0'  // Nuevo modelo financiero anual
}));


// =============================================================================
// MÓDULO: PERFIL FINANCIERO DEL USUARIO
// Ingreso global y compromisos fijos — existen una vez, persisten entre presupuestos.
// El presupuesto se CALCULA a partir de estos datos, no se inventa.
// =============================================================================

// GET /user/income?firebase_uid=
app.get('/user/income', async (req, res) => {
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [[row]] = await db.execute(
      `SELECT * FROM user_income WHERE firebase_uid = ?`, [firebase_uid]
    );
    if (!row) return res.json({ tiene_income: false });
    res.json({ tiene_income: true, ...row });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// POST /user/income — upsert del ingreso global
app.post('/user/income', async (req, res) => {
  const { firebase_uid, tipo_ingreso = 'salario', ingreso_bruto_mensual = 0,
    desc_seguro = 0, desc_pension = 0, desc_impuesto = 0, desc_otros = 0,
    ingreso_neto_mensual, calcular_automatico = 0, frecuencia_cobro = 'quincenal' } = req.body;
  if (!firebase_uid || ingreso_neto_mensual == null)
    return res.status(400).json({ error: 'firebase_uid e ingreso_neto_mensual requeridos' });
  if (Number(ingreso_neto_mensual) <= 0)
    return res.status(400).json({ error: 'ingreso_neto_mensual debe ser mayor a 0' });
  try {
    await db.execute(
      `INSERT INTO user_income
         (firebase_uid, tipo_ingreso, ingreso_bruto_mensual, desc_seguro, desc_pension,
          desc_impuesto, desc_otros, ingreso_neto_mensual, calcular_automatico, frecuencia_cobro)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
       ON DUPLICATE KEY UPDATE
         tipo_ingreso = VALUES(tipo_ingreso),
         ingreso_bruto_mensual = VALUES(ingreso_bruto_mensual),
         desc_seguro = VALUES(desc_seguro),
         desc_pension = VALUES(desc_pension),
         desc_impuesto = VALUES(desc_impuesto),
         desc_otros = VALUES(desc_otros),
         ingreso_neto_mensual = VALUES(ingreso_neto_mensual),
         calcular_automatico = VALUES(calcular_automatico),
         frecuencia_cobro = VALUES(frecuencia_cobro),
         updated_at = NOW()`,
      [firebase_uid, tipo_ingreso, ingreso_bruto_mensual, desc_seguro, desc_pension,
       desc_impuesto, desc_otros, ingreso_neto_mensual, calcular_automatico, frecuencia_cobro]
    );
    const [[saved]] = await db.execute(`SELECT * FROM user_income WHERE firebase_uid = ?`, [firebase_uid]);
    res.json({ tiene_income: true, ...saved });
    _logInfo('/user/income', `Ingreso configurado: $${Number(ingreso_neto_mensual).toFixed(2)}/mes (${tipo_ingreso})`, firebase_uid);
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// DELETE /user/income — elimina el ingreso global (para reconfigurar)
app.delete('/user/income', async (req, res) => {
  const { firebase_uid } = req.body;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    await db.execute(`DELETE FROM user_income WHERE firebase_uid = ?`, [firebase_uid]);
    res.json({ success: true });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// Helper: mapea tipo de gasto del perfil al tipo ENUM de deudas
function _mapTipoGastoToDeuda(tipo) {
  const map = { vivienda: 'hipoteca', transporte: 'auto', deuda: 'personal' };
  return map[tipo] || 'otro';
}

// GET /user/gastos-fijos?firebase_uid=
// Incluye info_completa para deudas (saben si les falta tasa/saldo en la tabla deudas)
app.get('/user/gastos-fijos', async (req, res) => {
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [rows] = await db.execute(
      `SELECT ugf.*,
              CASE WHEN ugf.deuda_id IS NOT NULL
                        AND d.monto_pendiente IS NOT NULL
                        AND d.tasa_interes IS NOT NULL
                   THEN 1 ELSE 0 END AS deuda_info_completa
       FROM user_gastos_fijos ugf
       LEFT JOIN deudas d ON d.id = ugf.deuda_id
       WHERE ugf.firebase_uid = ?
       ORDER BY ugf.es_deuda DESC, ugf.monto_mensual DESC`,
      [firebase_uid]
    );
    const total = rows.filter(r => r.activo).reduce((s, r) => s + Number(r.monto_mensual), 0);
    res.json({ gastos: rows, total_mensual: parseFloat(total.toFixed(2)) });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// Helper: genera eventos de calendario para un gasto del perfil con recordatorio.
// Si diaPago2 está definido, genera un segundo evento por mes (quincenas).
async function _generarEventosPerfilGasto(firebase_uid, ugfId, titulo, monto, diaPago, diaPago2) {
  const today = new Date();
  let generados = 0;
  const dias = [diaPago, diaPago2].filter(Boolean);
  for (const diaNum of dias) {
    for (let i = 0; i < 12; i++) {
      const d = new Date(today.getFullYear(), today.getMonth() + i, 1);
      const diasEnMes = new Date(d.getFullYear(), d.getMonth() + 1, 0).getDate();
      const dia = Math.min(diaNum, diasEnMes);
      const fecha = new Date(d.getFullYear(), d.getMonth(), dia);
      const fechaStr = fecha.toISOString().split('T')[0];
      const estado = fecha < today ? 'vencido' : 'pendiente';
      await db.execute(
        `INSERT INTO calendario_eventos
           (firebase_uid, user_gasto_fijo_id, titulo, tipo, fecha_evento,
            monto_esperado, estado, notificacion_activa, dias_anticipacion)
         VALUES (?, ?, ?, 'pago', ?, ?, ?, 1, 2)`,
        [firebase_uid, ugfId, titulo, fechaStr, monto, estado]
      );
      generados++;
    }
  }
  return generados;
}

// POST /user/gastos-fijos
// Si es_deuda=1, crea automáticamente un registro en tabla deudas con los datos disponibles
app.post('/user/gastos-fijos', async (req, res) => {
  const { firebase_uid, descripcion, monto_mensual, tipo = 'otro',
    clasificacion = 'importante', es_deuda = 0, subcategoria, notas,
    frecuencia = 'fijo', dia_pago = null, dia_pago_2 = null, recordatorio = 0 } = req.body;
  if (!firebase_uid || !descripcion || monto_mensual == null)
    return res.status(400).json({ error: 'firebase_uid, descripcion y monto_mensual requeridos' });
  try {
    const [result] = await db.execute(
      `INSERT INTO user_gastos_fijos
         (firebase_uid, descripcion, monto_mensual, tipo, clasificacion, es_deuda,
          subcategoria, notas, frecuencia, dia_pago, dia_pago_2, recordatorio)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [firebase_uid, descripcion, monto_mensual, tipo, clasificacion, es_deuda,
       subcategoria || null, notas || null, frecuencia, dia_pago || null, dia_pago_2 || null, recordatorio]
    );
    const ugfId = result.insertId;

    // Si es deuda, auto-crear en tabla deudas con datos disponibles
    if (Number(es_deuda) === 1) {
      const tipoDeuda = _mapTipoGastoToDeuda(tipo);
      const [deudaResult] = await db.execute(
        `INSERT INTO deudas (firebase_uid, nombre, tipo, monto_total, monto_pendiente,
           tasa_interes, pago_minimo, activa)
         VALUES (?, ?, ?, NULL, NULL, NULL, ?, 1)`,
        [firebase_uid, descripcion, tipoDeuda, monto_mensual]
      );
      await db.execute(
        `UPDATE user_gastos_fijos SET deuda_id = ? WHERE id = ?`,
        [deudaResult.insertId, ugfId]
      );
    }

    if (dia_pago) {
      await _generarEventosPerfilGasto(firebase_uid, ugfId, descripcion, monto_mensual, dia_pago, dia_pago_2 || null);
    }
    const [[created]] = await db.execute(
      `SELECT ugf.*, CASE WHEN ugf.deuda_id IS NOT NULL AND d.monto_pendiente IS NOT NULL
                               AND d.tasa_interes IS NOT NULL THEN 1 ELSE 0 END AS deuda_info_completa
       FROM user_gastos_fijos ugf LEFT JOIN deudas d ON d.id = ugf.deuda_id
       WHERE ugf.id = ?`, [ugfId]
    );
    res.status(201).json(created);
    _recalcularEstimadosAnio(firebase_uid, new Date().getFullYear()).catch(() => {});
    _logInfo('/user/gastos-fijos', `Gasto fijo creado: "${descripcion}" $${Number(monto_mensual).toFixed(2)}/mes`, firebase_uid);
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// PUT /user/gastos-fijos/:id
// Sincroniza cambios con la tabla deudas si existe deuda_id
app.put('/user/gastos-fijos/:id', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid, descripcion, monto_mensual, tipo, clasificacion, es_deuda,
    activo, subcategoria, notas, frecuencia, dia_pago, dia_pago_2, recordatorio } = req.body;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [[existing]] = await db.execute(
      `SELECT * FROM user_gastos_fijos WHERE id = ? AND firebase_uid = ?`, [id, firebase_uid]
    );
    if (!existing) return res.status(404).json({ error: 'No encontrado' });

    const nuevoEsDeuda = es_deuda !== undefined ? Number(es_deuda) : Number(existing.es_deuda);
    const anteriorEsDeuda = Number(existing.es_deuda);

    await db.execute(
      `UPDATE user_gastos_fijos SET
         descripcion   = COALESCE(?, descripcion),
         monto_mensual = COALESCE(?, monto_mensual),
         tipo          = COALESCE(?, tipo),
         clasificacion = COALESCE(?, clasificacion),
         es_deuda      = COALESCE(?, es_deuda),
         activo        = COALESCE(?, activo),
         subcategoria  = COALESCE(?, subcategoria),
         notas         = COALESCE(?, notas),
         frecuencia    = COALESCE(?, frecuencia),
         dia_pago      = ?,
         dia_pago_2    = ?,
         recordatorio  = COALESCE(?, recordatorio),
         updated_at    = NOW()
       WHERE id = ?`,
      [descripcion ?? null, monto_mensual ?? null, tipo ?? null, clasificacion ?? null,
       es_deuda ?? null, activo ?? null, subcategoria ?? null, notas ?? null,
       frecuencia ?? null, dia_pago ?? existing.dia_pago ?? null,
       dia_pago_2 !== undefined ? (dia_pago_2 ?? null) : (existing.dia_pago_2 ?? null),
       recordatorio ?? null, id]
    );

    const nuevoTitulo = descripcion ?? existing.descripcion;
    const nuevoMonto  = monto_mensual ?? existing.monto_mensual;

    // Sincronizar con tabla deudas
    if (nuevoEsDeuda === 1 && anteriorEsDeuda === 0) {
      // Recién marcada como deuda → crear en tabla deudas
      const tipoDeuda = _mapTipoGastoToDeuda(tipo ?? existing.tipo);
      const [dr] = await db.execute(
        `INSERT INTO deudas (firebase_uid, nombre, tipo, monto_total, monto_pendiente,
           tasa_interes, pago_minimo, activa)
         VALUES (?, ?, ?, NULL, NULL, NULL, ?, 1)`,
        [firebase_uid, nuevoTitulo, tipoDeuda, nuevoMonto]
      );
      await db.execute(`UPDATE user_gastos_fijos SET deuda_id = ? WHERE id = ?`, [dr.insertId, id]);
    } else if (nuevoEsDeuda === 0 && anteriorEsDeuda === 1 && existing.deuda_id) {
      // Dejó de ser deuda → archivar en tabla deudas
      await db.execute(`UPDATE deudas SET activa = 0 WHERE id = ?`, [existing.deuda_id]);
      await db.execute(`UPDATE user_gastos_fijos SET deuda_id = NULL WHERE id = ?`, [id]);
    } else if (nuevoEsDeuda === 1 && existing.deuda_id) {
      // Sigue siendo deuda → sincronizar nombre y pago_minimo
      await db.execute(
        `UPDATE deudas SET nombre = ?, pago_minimo = ? WHERE id = ?`,
        [nuevoTitulo, nuevoMonto, existing.deuda_id]
      );
    }

    // Regenerar eventos de calendario
    const nuevoDiaPago  = dia_pago   ?? existing.dia_pago;
    const nuevoDiaPago2 = dia_pago_2 !== undefined ? (dia_pago_2 ?? null) : (existing.dia_pago_2 ?? null);
    await db.execute(
      `DELETE FROM calendario_eventos WHERE user_gasto_fijo_id = ? AND estado IN ('pendiente', 'vencido')`, [id]
    );
    if (nuevoDiaPago) {
      await _generarEventosPerfilGasto(firebase_uid, id, nuevoTitulo, nuevoMonto, nuevoDiaPago, nuevoDiaPago2);
    }

    const [[updated]] = await db.execute(
      `SELECT ugf.*, CASE WHEN ugf.deuda_id IS NOT NULL AND d.monto_pendiente IS NOT NULL
                               AND d.tasa_interes IS NOT NULL THEN 1 ELSE 0 END AS deuda_info_completa
       FROM user_gastos_fijos ugf LEFT JOIN deudas d ON d.id = ugf.deuda_id
       WHERE ugf.id = ?`, [id]
    );
    res.json(updated);
    _recalcularEstimadosAnio(firebase_uid, new Date().getFullYear()).catch(() => {});
    _logInfo(`/user/gastos-fijos/${id}`, `Gasto fijo editado: "${updated.descripcion}" $${Number(updated.monto_mensual).toFixed(2)}/mes`, firebase_uid);
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// DELETE /user/gastos-fijos/:id
// Archiva la deuda vinculada (si existe) y elimina eventos pendientes del calendario
app.delete('/user/gastos-fijos/:id', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [[ugf]] = await db.execute(
      `SELECT deuda_id FROM user_gastos_fijos WHERE id = ? AND firebase_uid = ?`,
      [id, firebase_uid]
    );
    if (ugf?.deuda_id) {
      await db.execute(`UPDATE deudas SET activa = 0 WHERE id = ?`, [ugf.deuda_id]);
    }
    await db.execute(
      `DELETE FROM calendario_eventos WHERE user_gasto_fijo_id = ? AND estado IN ('pendiente', 'vencido')`, [id]
    );
    await db.execute(
      `DELETE FROM user_gastos_fijos WHERE id = ? AND firebase_uid = ?`, [id, firebase_uid]
    );
    res.json({ success: true });
    _recalcularEstimadosAnio(firebase_uid, new Date().getFullYear()).catch(() => {});
    _logInfo(`/user/gastos-fijos/${id}`, `Gasto fijo eliminado (id=${id})`, firebase_uid);
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// POST /user/sync-deudas — crea registros en tabla deudas para todos los gastos
// del perfil con es_deuda=1 que no tienen deuda_id (retrocompatibilidad)
app.post('/user/sync-deudas', async (req, res) => {
  const { firebase_uid } = req.body;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [pendientes] = await db.execute(
      `SELECT * FROM user_gastos_fijos WHERE firebase_uid = ? AND es_deuda = 1 AND deuda_id IS NULL`,
      [firebase_uid]
    );
    let creadas = 0;
    for (const ugf of pendientes) {
      const tipoDeuda = _mapTipoGastoToDeuda(ugf.tipo);
      const [dr] = await db.execute(
        `INSERT INTO deudas (firebase_uid, nombre, tipo, monto_total, monto_pendiente,
           tasa_interes, pago_minimo, activa)
         VALUES (?, ?, ?, NULL, NULL, NULL, ?, 1)`,
        [firebase_uid, ugf.descripcion, tipoDeuda, ugf.monto_mensual]
      );
      await db.execute(
        `UPDATE user_gastos_fijos SET deuda_id = ? WHERE id = ?`, [dr.insertId, ugf.id]
      );
      creadas++;
    }
    res.json({ creadas, message: `${creadas} deuda(s) sincronizada(s)` });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// DELETE /user/data — elimina TODOS los datos del usuario (para empezar de cero)
app.delete('/user/data', async (req, res) => {
  const { firebase_uid } = req.body;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    // Obtener todos los presupuesto IDs del usuario
    const [presupuestos] = await db.execute(
      `SELECT id FROM presupuestos WHERE firebase_uid = ?`, [firebase_uid]
    );
    for (const p of presupuestos) {
      await db.execute(`DELETE FROM movimientos WHERE presupuesto_id = ?`, [p.id]);
      await db.execute(`DELETE FROM periodos WHERE presupuesto_id = ?`, [p.id]);
      await db.execute(`DELETE FROM gastos WHERE presupuesto_id = ?`, [p.id]);
      await db.execute(`DELETE FROM calendario_eventos WHERE firebase_uid = ? AND presupuesto_id = ?`, [firebase_uid, p.id]);
    }
    await db.execute(`DELETE FROM presupuestos WHERE firebase_uid = ?`, [firebase_uid]);
    await db.execute(`DELETE FROM budget_income WHERE firebase_uid = ?`, [firebase_uid]);
    await db.execute(`DELETE FROM user_income WHERE firebase_uid = ?`, [firebase_uid]);
    await db.execute(`DELETE FROM user_gastos_fijos WHERE firebase_uid = ?`, [firebase_uid]);
    await db.execute(`DELETE FROM deudas WHERE firebase_uid = ?`, [firebase_uid]);
    await db.execute(`DELETE FROM aportaciones_ahorro WHERE firebase_uid = ?`, [firebase_uid]);
    await db.execute(`DELETE FROM gustitos WHERE user_id = ?`, [firebase_uid]);
    // Nuevo modelo financiero anual
    const [efas] = await db.execute(`SELECT id FROM estado_financiero_anual WHERE firebase_uid = ?`, [firebase_uid]);
    for (const efa of efas) {
      const [mfRows] = await db.execute(`SELECT id FROM meses_financieros WHERE estado_anual_id = ?`, [efa.id]);
      for (const mf of mfRows) {
        await db.execute(`DELETE FROM registros_gasto WHERE mes_id = ?`, [mf.id]);
        await db.execute(`DELETE FROM analisis_categorias WHERE mes_id = ?`, [mf.id]);
        await db.execute(`DELETE FROM cierres_mensuales WHERE mes_id = ?`, [mf.id]);
      }
      await db.execute(`DELETE FROM meses_financieros WHERE estado_anual_id = ?`, [efa.id]);
      await db.execute(`DELETE FROM cierres_anuales WHERE firebase_uid = ? AND anio = (SELECT anio FROM estado_financiero_anual WHERE id = ?)`, [firebase_uid, efa.id]);
    }
    await db.execute(`DELETE FROM estado_financiero_anual WHERE firebase_uid = ?`, [firebase_uid]);
    await db.execute(`DELETE FROM gastos_variables_base WHERE firebase_uid = ?`, [firebase_uid]);
    await db.execute(`DELETE FROM subcategorias WHERE firebase_uid = ?`, [firebase_uid]);
    await db.execute(`DELETE FROM alertas_financieras WHERE firebase_uid = ?`, [firebase_uid]);
    await db.execute(`DELETE FROM gastos_globales WHERE firebase_uid = ?`, [firebase_uid]);
    res.json({ success: true, message: 'Todos los datos del usuario eliminados' });
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: e.message });
  }
});

// =============================================================================
// MÓDULO: DASHBOARD Y REPORTES
// Dashboard consolidado, score de salud financiera y resumen mensual por correo.
// =============================================================================

/**
 * Calcula el score de salud financiera (0-100).
 * No es punitivo: un usuario nuevo empieza en 50, no en 0.
 * Factores: ratio deuda/ingreso, ratio gastos fijos/ingreso, ahorro, pagos al día.
 */
function _calcularScore({ ingresoNeto, totalGastosFijos, totalCuotasDeudas, totalAhorros, pagosCumplidos, pagosTotales }) {
  if (!ingresoNeto || ingresoNeto <= 0) return 50; // Sin datos = neutral

  let score = 50; // Base neutral para usuarios nuevos

  // Factor 1: ratio deuda/ingreso (40% de la puntuación)
  // Ideal: cuotas < 30% del ingreso
  const ratioDeuda = totalCuotasDeudas / ingresoNeto;
  if (ratioDeuda === 0)           score += 20; // Sin deudas: excelente
  else if (ratioDeuda <= 0.15)    score += 15;
  else if (ratioDeuda <= 0.30)    score += 8;
  else if (ratioDeuda <= 0.50)    score -= 5;
  else                            score -= 15; // Más del 50% a deudas: crítico

  // Factor 2: ratio gastos fijos/ingreso (30% de la puntuación)
  const ratioGastos = totalGastosFijos / ingresoNeto;
  if (ratioGastos <= 0.40)        score += 15;
  else if (ratioGastos <= 0.60)   score += 5;
  else if (ratioGastos <= 0.80)   score -= 5;
  else                            score -= 15;

  // Factor 3: ahorro mensual (20% de la puntuación)
  const ratioAhorro = totalAhorros / ingresoNeto;
  if (ratioAhorro >= 0.20)        score += 10;
  else if (ratioAhorro >= 0.10)   score += 5;
  else if (ratioAhorro >= 0.05)   score += 2;

  // Factor 4: cumplimiento de pagos (10% de la puntuación)
  if (pagosTotales > 0) {
    const pct = pagosCumplidos / pagosTotales;
    if (pct >= 0.90) score += 5;
    else if (pct >= 0.70) score += 2;
    else score -= 5;
  }

  return Math.min(100, Math.max(0, Math.round(score)));
}

function _scoreLegible(score) {
  if (score >= 80) return { etiqueta: 'Excelente', color: '#22c55e' };
  if (score >= 60) return { etiqueta: 'Buena',     color: '#84cc16' };
  if (score >= 40) return { etiqueta: 'Regular',   color: '#f59e0b' };
  if (score >= 20) return { etiqueta: 'Ajustada',  color: '#f97316' };
  return              { etiqueta: 'Crítica',   color: '#ef4444' };
}

// GET /user/dashboard?firebase_uid=
// Dashboard financiero consolidado. Combina perfil, deudas, presupuesto activo
// y proyección en una sola respuesta para la pantalla principal del app.
app.get('/user/dashboard', async (req, res) => {
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    // Perfil financiero base
    const [[income]] = await db.execute(`SELECT * FROM user_income WHERE firebase_uid = ?`, [firebase_uid]);
    const [gastosFijos] = await db.execute(
      `SELECT * FROM user_gastos_fijos WHERE firebase_uid = ? AND activo = 1`, [firebase_uid]
    );
    const [deudas] = await db.execute(
      `SELECT * FROM deudas WHERE firebase_uid = ? AND activa = 1`, [firebase_uid]
    );

    const ingresoNeto       = income ? Number(income.ingreso_neto_mensual) : 0;
    const totalGastosFijos  = gastosFijos.reduce((s, g) => s + Number(g.monto_mensual), 0);
    const totalCuotasDeudas = deudas.reduce((s, d) => {
      return s + (d.es_letra ? Number(d.cuota_fija || 0) : Number(d.pago_minimo || 0));
    }, 0);
    const disponible = ingresoNeto - totalGastosFijos - totalCuotasDeudas;

    // Presupuesto activo más reciente
    const [[presActivo]] = await db.execute(
      `SELECT p.id, p.nombre, p.monto_total, p.tipo_periodo
       FROM presupuestos p
       WHERE p.firebase_uid = ? ORDER BY p.id DESC LIMIT 1`,
      [firebase_uid]
    );

    // Pagos del período activo para el score
    let pagosCumplidos = 0, pagosTotales = 0;
    let resumenPeriodo = null;
    if (presActivo) {
      const [periodo] = await db.execute(
        `SELECT * FROM periodos WHERE presupuesto_id = ? AND firebase_uid = ? AND estado = 'activo' LIMIT 1`,
        [presActivo.id, firebase_uid]
      );
      if (periodo.length > 0) {
        const [movs] = await db.execute(
          `SELECT pagado, monto, monto_pagado_real, tipo FROM movimientos
           WHERE periodo_id = ? AND firebase_uid = ?`, [periodo[0].id, firebase_uid]
        );
        pagosTotales   = movs.filter(m => m.tipo === 'fijo' || m.tipo === 'fijo_x_periodo').length;
        pagosCumplidos = movs.filter(m => m.pagado && (m.tipo === 'fijo' || m.tipo === 'fijo_x_periodo')).length;
        const totalPagado = movs.filter(m => m.pagado).reduce((s, m) => s + Number(m.monto_pagado_real || 0), 0);
        resumenPeriodo = {
          periodo_id:   periodo[0].id,
          fecha_inicio: periodo[0].fecha_inicio,
          fecha_fin:    periodo[0].fecha_fin,
          tipo:         periodo[0].tipo_periodo,
          pagos_fijos:  `${pagosCumplidos}/${pagosTotales}`,
          total_pagado: parseFloat(totalPagado.toFixed(2)),
          monto_total:  Number(presActivo.monto_total),
        };
      }
    }

    // Score de salud (no punitivo)
    const totalAhorros = 0; // TODO: integrar metas de ahorro cuando existan
    const score = _calcularScore({ ingresoNeto, totalGastosFijos, totalCuotasDeudas, totalAhorros, pagosCumplidos, pagosTotales });
    const scoreLegible = _scoreLegible(score);

    // Próximos 3 meses del timeline (resumen rápido)
    const timeline3 = _construirTimeline(income, gastosFijos, deudas, 3);

    res.json({
      tiene_perfil: !!income,
      salud: {
        score,
        ...scoreLegible,
        descripcion: !income
          ? 'Completa tu perfil financiero para ver tu score real'
          : score >= 60
            ? 'Tus finanzas están en buen camino'
            : 'Hay compromisos que presionan tu disponible',
      },
      resumen_mensual: {
        ingreso_neto:        parseFloat(ingresoNeto.toFixed(2)),
        gastos_fijos:        parseFloat(totalGastosFijos.toFixed(2)),
        cuotas_deudas:       parseFloat(totalCuotasDeudas.toFixed(2)),
        disponible:          parseFloat(disponible.toFixed(2)),
        ratio_comprometido:  ingresoNeto > 0
          ? parseFloat(((totalGastosFijos + totalCuotasDeudas) / ingresoNeto * 100).toFixed(1))
          : 0,
      },
      deudas: {
        total:           deudas.length,
        monto_pendiente: parseFloat(deudas.reduce((s, d) => s + Number(d.monto_pendiente || 0), 0).toFixed(2)),
        cuota_mensual:   parseFloat(totalCuotasDeudas.toFixed(2)),
      },
      presupuesto_activo: presActivo || null,
      periodo_activo:     resumenPeriodo,
      proximos_3_meses:   timeline3.map(m => ({
        label:      m.label,
        disponible: m.disponible,
        salud:      m.salud,
        eventos:    m.eventos,
      })),
    });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// GET /user/metricas?firebase_uid=&meses=6
// Comparativa histórica entre períodos: evolución de gastos, pagos y ahorro.
app.get('/user/metricas', async (req, res) => {
  const { firebase_uid, meses = 6 } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    // Últimos N períodos cerrados con sus totales
    const [periodos] = await db.execute(
      `SELECT
         p.id, p.numero_periodo, p.fecha_inicio, p.fecha_fin, p.tipo_periodo,
         pr.nombre AS presupuesto_nombre, pr.monto_total,
         COALESCE(SUM(CASE WHEN m.tipo IN ('fijo','fijo_x_periodo') AND m.pagado=1
                          THEN COALESCE(m.monto_pagado_real, m.monto) ELSE 0 END), 0) AS fijos_pagados,
         COALESCE(SUM(CASE WHEN m.tipo IN ('no fijo','variable') AND m.pagado=1
                          THEN COALESCE(m.monto_pagado_real, m.monto) ELSE 0 END), 0) AS variables_pagados,
         COALESCE(SUM(CASE WHEN m.tipo='ahorro' AND m.pagado=1
                          THEN COALESCE(m.monto_pagado_real, m.monto) ELSE 0 END), 0) AS ahorro_pagado,
         COUNT(CASE WHEN m.tipo IN ('fijo','fijo_x_periodo') THEN 1 END)          AS fijos_total,
         COUNT(CASE WHEN m.tipo IN ('fijo','fijo_x_periodo') AND m.pagado=1 THEN 1 END) AS fijos_pagados_count
       FROM periodos p
       JOIN presupuestos pr ON pr.id = p.presupuesto_id
       LEFT JOIN movimientos m ON m.periodo_id = p.id AND m.firebase_uid = p.firebase_uid
       WHERE p.firebase_uid = ? AND p.estado = 'cerrado'
       GROUP BY p.id ORDER BY p.fecha_inicio DESC LIMIT ?`,
      [firebase_uid, Number(meses)]
    );

    const periodosOrdenados = periodos.reverse(); // Cronológico

    // Progreso de deudas
    const [deudas] = await db.execute(
      `SELECT id, nombre, monto_total, monto_pendiente, es_letra, cuota_fija, pago_minimo, activa
       FROM deudas WHERE firebase_uid = ? ORDER BY created_at ASC`, [firebase_uid]
    );

    const progresoPorDeuda = deudas.map(d => {
      const original  = Number(d.monto_total || 0);
      const pendiente = Number(d.monto_pendiente || 0);
      const pagado    = Math.max(0, original - pendiente);
      return {
        id:          d.id,
        nombre:      d.nombre,
        monto_total: original,
        pagado,
        pendiente,
        pct_pagado:  original > 0 ? parseFloat((pagado / original * 100).toFixed(1)) : 0,
        activa:      Boolean(d.activa),
      };
    });

    // Tendencia: último período vs penúltimo
    let tendencia = null;
    if (periodosOrdenados.length >= 2) {
      const ultimo    = periodosOrdenados[periodosOrdenados.length - 1];
      const penultimo = periodosOrdenados[periodosOrdenados.length - 2];
      const gastUlt   = parseFloat(ultimo.fijos_pagados) + parseFloat(ultimo.variables_pagados);
      const gastPen   = parseFloat(penultimo.fijos_pagados) + parseFloat(penultimo.variables_pagados);
      const delta     = gastUlt - gastPen;
      tendencia = {
        delta_gasto:      parseFloat(delta.toFixed(2)),
        direccion:        delta < 0 ? 'mejoro' : delta > 0 ? 'empeoro' : 'igual',
        mensaje:          delta < 0
          ? `Gastaste $${Math.abs(delta).toFixed(2)} menos que el período anterior`
          : delta > 0
            ? `Gastaste $${delta.toFixed(2)} más que el período anterior`
            : 'Igual que el período anterior',
      };
    }

    res.json({
      periodos: periodosOrdenados.map(p => ({
        id:              p.id,
        numero:          p.numero_periodo,
        label:           p.presupuesto_nombre,
        fecha_inicio:    p.fecha_inicio,
        fecha_fin:       p.fecha_fin,
        monto_total:     Number(p.monto_total),
        fijos_pagados:   parseFloat(p.fijos_pagados),
        variables_pagados: parseFloat(p.variables_pagados),
        ahorro_pagado:   parseFloat(p.ahorro_pagado),
        total_gastado:   parseFloat((Number(p.fijos_pagados) + Number(p.variables_pagados) + Number(p.ahorro_pagado)).toFixed(2)),
        cumplimiento_fijos: p.fijos_total > 0
          ? parseFloat((p.fijos_pagados_count / p.fijos_total * 100).toFixed(1)) : 100,
        sobrante:        parseFloat((Number(p.monto_total) - Number(p.fijos_pagados) - Number(p.variables_pagados)).toFixed(2)),
      })),
      deudas: progresoPorDeuda,
      tendencia,
    });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// POST /user/enviar-resumen-mensual
// Envía el estado de cuenta del mes al correo del usuario vía Brevo.
// Puede llamarse manualmente o desde el cron mensual.
async function _enviarResumenMensual(firebase_uid, email) {
  const [[income]] = await db.execute(`SELECT * FROM user_income WHERE firebase_uid = ?`, [firebase_uid]);
  const [gastosFijos] = await db.execute(
    `SELECT * FROM user_gastos_fijos WHERE firebase_uid = ? AND activo = 1`, [firebase_uid]
  );
  const [deudas] = await db.execute(
    `SELECT * FROM deudas WHERE firebase_uid = ? AND activa = 1`, [firebase_uid]
  );

  // Último período cerrado
  const [[ultimoPeriodo]] = await db.execute(
    `SELECT p.*, pr.monto_total, pr.nombre AS presupuesto_nombre
     FROM periodos p JOIN presupuestos pr ON pr.id = p.presupuesto_id
     WHERE p.firebase_uid = ? AND p.estado = 'cerrado'
     ORDER BY p.fecha_fin DESC LIMIT 1`,
    [firebase_uid]
  );

  let filasPagos = '';
  let totalPagado = 0, totalFijos = 0, totalAhorros = 0;

  if (ultimoPeriodo) {
    const [movs] = await db.execute(
      `SELECT * FROM movimientos WHERE periodo_id = ? AND pagado = 1`, [ultimoPeriodo.id]
    );
    for (const m of movs) {
      const monto = Number(m.monto_pagado_real || m.monto);
      totalPagado += monto;
      if (m.tipo === 'fijo' || m.tipo === 'fijo_x_periodo') totalFijos += monto;
      if (m.tipo === 'ahorro') totalAhorros += monto;
      filasPagos += `<tr><td style="padding:6px 0;border-bottom:1px solid #2B3139">${m.descripcion}</td><td style="text-align:right;padding:6px 0;border-bottom:1px solid #2B3139">$${monto.toFixed(2)}</td></tr>`;
    }
  }

  const ingresoNeto    = income ? Number(income.ingreso_neto_mensual) : 0;
  const totalCuotas    = deudas.reduce((s, d) => s + Number(d.pago_minimo || 0), 0);
  const totalGastosFijosN = gastosFijos.reduce((s, g) => s + Number(g.monto_mensual), 0);
  const disponible     = ingresoNeto - totalGastosFijosN - totalCuotas;
  const score          = _calcularScore({ ingresoNeto, totalGastosFijos: totalGastosFijosN, totalCuotasDeudas: totalCuotas, totalAhorros, pagosCumplidos: 1, pagosTotales: 1 });
  const scoreLegible   = _scoreLegible(score);

  const timeline1 = _construirTimeline(income, gastosFijos, deudas, 1);
  const proxMes    = timeline1[0];

  if (!process.env.BREVO_API_KEY) return { enviado: false, razon: 'BREVO_API_KEY no configurada' };

  await fetch('https://api.brevo.com/v3/smtp/email', {
    method: 'POST',
    headers: { 'api-key': process.env.BREVO_API_KEY, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      sender: { email: process.env.BREVO_SENDER_EMAIL, name: 'Salarying' },
      to: [{ email }],
      subject: `Tu resumen financiero de ${new Date().toLocaleDateString('es', { month: 'long', year: 'numeric' })}`,
      htmlContent: `
        <div style="font-family:sans-serif;max-width:520px;margin:auto;background:#1E2026;color:#EAECEF;padding:28px;border-radius:14px">
          <h2 style="color:#F0B90B;margin:0 0 4px">Salarying</h2>
          <p style="color:#848E9C;margin:0 0 24px">Tu estado financiero del mes</p>

          <div style="background:#2B3139;border-radius:10px;padding:16px;margin-bottom:16px;text-align:center">
            <div style="font-size:13px;color:#848E9C">Salud financiera</div>
            <div style="font-size:42px;font-weight:bold;color:${scoreLegible.color}">${score}</div>
            <div style="color:${scoreLegible.color};font-weight:600">${scoreLegible.etiqueta}</div>
          </div>

          <div style="display:flex;gap:12px;margin-bottom:16px">
            <div style="flex:1;background:#2B3139;border-radius:8px;padding:14px;text-align:center">
              <div style="font-size:11px;color:#848E9C;margin-bottom:4px">Ingreso neto</div>
              <div style="font-size:18px;font-weight:bold;color:#22c55e">$${ingresoNeto.toFixed(2)}</div>
            </div>
            <div style="flex:1;background:#2B3139;border-radius:8px;padding:14px;text-align:center">
              <div style="font-size:11px;color:#848E9C;margin-bottom:4px">Total gastado</div>
              <div style="font-size:18px;font-weight:bold;color:#f97316">$${totalPagado.toFixed(2)}</div>
            </div>
            <div style="flex:1;background:#2B3139;border-radius:8px;padding:14px;text-align:center">
              <div style="font-size:11px;color:#848E9C;margin-bottom:4px">Disponible</div>
              <div style="font-size:18px;font-weight:bold;color:${disponible >= 0 ? '#22c55e' : '#ef4444'}">$${(ingresoNeto - totalPagado).toFixed(2)}</div>
            </div>
          </div>

          ${filasPagos ? `
          <div style="background:#2B3139;border-radius:8px;padding:16px;margin-bottom:16px">
            <div style="font-size:13px;font-weight:600;margin-bottom:12px;color:#EAECEF">Pagos realizados</div>
            <table style="width:100%;border-collapse:collapse;font-size:13px">${filasPagos}</table>
          </div>` : ''}

          <div style="background:#2B3139;border-radius:8px;padding:16px;margin-bottom:24px">
            <div style="font-size:13px;font-weight:600;margin-bottom:8px;color:#EAECEF">Próximo mes estimado</div>
            <div style="font-size:13px;color:#848E9C">Disponible proyectado: <span style="color:${proxMes.disponible >= 0 ? '#22c55e' : '#ef4444'};font-weight:bold">$${proxMes.disponible.toFixed(2)}</span></div>
            ${proxMes.eventos.length > 0 ? `<div style="font-size:12px;color:#F0B90B;margin-top:6px">⚡ ${proxMes.eventos[0].mensaje}</div>` : ''}
          </div>

          <p style="font-size:12px;color:#848E9C;text-align:center">Abre la app Salarying para ver tu análisis completo.</p>
        </div>`,
    }),
  });
  return { enviado: true };
}

app.post('/user/enviar-resumen-mensual', async (req, res) => {
  const { firebase_uid, email } = req.body;
  if (!firebase_uid || !email) return res.status(400).json({ error: 'firebase_uid y email requeridos' });
  try {
    const resultado = await _enviarResumenMensual(firebase_uid, email);
    res.json(resultado);
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// GET /user/ahorros-activos?firebase_uid=
// Devuelve metas de ahorro activas del usuario con su cuota y progreso.
// Usadas por el perfil financiero para incluirlas en el cálculo del disponible.
app.get('/user/ahorros-activos', async (req, res) => {
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [ahorros] = await db.execute(
      `SELECT g.id, g.descripcion AS nombre, g.monto AS cuota_periodo,
              p.tipo_periodo,
              g.numero_quincena AS periodos_restantes,
              COALESCE(SUM(m.monto_pagado_real), 0) AS monto_ahorrado,
              COALESCE((SELECT SUM(a.monto) FROM aportaciones_ahorro a WHERE a.gasto_id = g.id), 0) AS total_aportaciones
       FROM gastos g
       JOIN presupuestos p ON p.id = g.presupuesto_id
       LEFT JOIN movimientos m ON m.gasto_id = g.id AND m.pagado = 1
       WHERE g.firebase_uid = ? AND g.tipo = 'ahorro'
         AND (g.numero_quincena IS NULL OR g.numero_quincena > 0)
       GROUP BY g.id, g.descripcion, g.monto, p.tipo_periodo, g.numero_quincena`,
      [firebase_uid]
    );
    const result = ahorros.map(a => {
      // Normalizar cuota a mensual: si el presupuesto es quincenal, multiplicar ×2
      const cuotaMensual = a.tipo_periodo === 'quincenal'
        ? parseFloat((Number(a.cuota_periodo) * 2).toFixed(2))
        : parseFloat(Number(a.cuota_periodo).toFixed(2));
      const totalAhorrado = parseFloat((Number(a.monto_ahorrado) + Number(a.total_aportaciones)).toFixed(2));
      return { ...a, cuota_mensual: cuotaMensual, total_ahorrado: totalAhorrado };
    });
    const totalCuotaMensual = result.reduce((s, a) => s + a.cuota_mensual, 0);
    res.json({ ahorros: result, total_cuota_mensual: parseFloat(totalCuotaMensual.toFixed(2)) });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// GET /user/perfil-financiero?firebase_uid= — resumen completo del perfil financiero
// Incluye: income, gastos_fijos, ahorros activos, aporte shared → disponible real
app.get('/user/perfil-financiero', async (req, res) => {
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [[income]] = await db.execute(
      `SELECT * FROM user_income WHERE firebase_uid = ?`, [firebase_uid]
    );
    const [gastos] = await db.execute(
      `SELECT ugf.*, CASE WHEN ugf.deuda_id IS NOT NULL AND d.monto_pendiente IS NOT NULL
                               AND d.tasa_interes IS NOT NULL THEN 1 ELSE 0 END AS deuda_info_completa
       FROM user_gastos_fijos ugf
       LEFT JOIN deudas d ON d.id = ugf.deuda_id
       WHERE ugf.firebase_uid = ? AND ugf.activo = 1
       ORDER BY ugf.es_deuda DESC, ugf.monto_mensual DESC`, [firebase_uid]
    );
    // Ahorros activos con cuota mensual normalizada
    const [ahorrosRows] = await db.execute(
      `SELECT g.id, g.descripcion AS nombre, g.monto AS cuota_periodo,
              p.tipo_periodo, g.numero_quincena AS periodos_restantes
       FROM gastos g
       JOIN presupuestos p ON p.id = g.presupuesto_id
       WHERE g.firebase_uid = ? AND g.tipo = 'ahorro'
         AND (g.numero_quincena IS NULL OR g.numero_quincena > 0)`,
      [firebase_uid]
    );
    const ahorros = ahorrosRows.map(a => ({
      ...a,
      cuota_mensual: a.tipo_periodo === 'quincenal'
        ? parseFloat((Number(a.cuota_periodo) * 2).toFixed(2))
        : parseFloat(Number(a.cuota_periodo).toFixed(2)),
    }));
    const totalCuotaAhorroMensual = ahorros.reduce((s, a) => s + a.cuota_mensual, 0);

    // Aportes a presupuestos compartidos activos donde el usuario es miembro
    const [[sharedRow]] = await db.execute(
      `SELECT COALESCE(SUM(sbm.aporte_periodo), 0) AS total_aporte_shared
       FROM shared_budget_members sbm
       JOIN shared_budgets sb ON sb.id = sbm.shared_budget_id
       WHERE sbm.firebase_uid = ? AND sb.estado = 'active'`,
      [firebase_uid]
    );

    // Deudas activas NO vinculadas a user_gastos_fijos (creadas directamente en /deudas)
    // Su pago_minimo debe contarse como compromiso mensual para que el disponible sea real
    const [deudasIndep] = await db.execute(
      `SELECT d.id, d.nombre, d.pago_minimo, d.es_letra, d.cuota_fija,
              d.num_cuotas_total, d.num_cuotas_pagadas, d.tasa_interes
       FROM deudas d
       LEFT JOIN user_gastos_fijos ugf ON ugf.deuda_id = d.id
       WHERE d.firebase_uid = ? AND d.activa = 1 AND ugf.id IS NULL`,
      [firebase_uid]
    );
    const totalCuotasDeudas = deudasIndep.reduce((s, d) => {
      const cuota = d.es_letra ? Number(d.cuota_fija || 0) : Number(d.pago_minimo || 0);
      return s + cuota;
    }, 0);

    const ingresoNeto        = income ? Number(income.ingreso_neto_mensual) : 0;
    const totalGastos        = gastos.reduce((s, g) => s + Number(g.monto_mensual), 0);
    const totalAporteShared  = Number(sharedRow?.total_aporte_shared || 0);
    const totalAhorros       = parseFloat(totalCuotaAhorroMensual.toFixed(2));
    const totalDeudas        = parseFloat(totalCuotasDeudas.toFixed(2));
    const disponibleMensual  = ingresoNeto - totalGastos - totalAporteShared - totalAhorros - totalDeudas;
    const divisor            = (income?.frecuencia_cobro === 'quincenal') ? 2 : 1;

    res.json({
      tiene_income: !!income,
      income: income || null,
      gastos_fijos: gastos,
      ahorros_activos: ahorros,
      deudas_independientes: deudasIndep,
      resumen: {
        ingreso_neto_mensual:          parseFloat(ingresoNeto.toFixed(2)),
        ingreso_neto_periodo:          parseFloat((ingresoNeto / divisor).toFixed(2)),
        total_gastos_mensual:          parseFloat(totalGastos.toFixed(2)),
        total_gastos_periodo:          parseFloat((totalGastos / divisor).toFixed(2)),
        total_ahorros_mensual:         totalAhorros,
        total_ahorros_periodo:         parseFloat((totalAhorros / divisor).toFixed(2)),
        total_cuotas_deudas_mensual:   totalDeudas,
        total_cuotas_deudas_periodo:   parseFloat((totalDeudas / divisor).toFixed(2)),
        total_aporte_shared_mensual:   parseFloat(totalAporteShared.toFixed(2)),
        disponible_mensual:            parseFloat(disponibleMensual.toFixed(2)),
        disponible_periodo:            parseFloat((disponibleMensual / divisor).toFixed(2)),
        frecuencia_cobro:              income?.frecuencia_cobro || 'quincenal',
        compromisos_son_sostenibles:   disponibleMensual >= 0,
      }
    });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// POST /user/generar-presupuesto
// Crea automáticamente un presupuesto desde el perfil financiero del usuario.
// Incluye como gastos base: todos los user_gastos_fijos activos + cuotas de deudas independientes.
// El usuario solo necesita tener income registrado.
app.post('/user/generar-presupuesto', async (req, res) => {
  const { firebase_uid, tipo_periodo = 'mensual', dia_inicio_periodo = 1, nombre } = req.body;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [[income]] = await db.execute(
      `SELECT * FROM user_income WHERE firebase_uid = ?`, [firebase_uid]
    );
    if (!income) return res.status(400).json({ error: 'Registra tu ingreso antes de generar un presupuesto' });

    const divisor = tipo_periodo === 'quincenal' ? 2 : 1;
    const monto_total = parseFloat((Number(income.ingreso_neto_mensual) / divisor).toFixed(2));
    const nombreFinal = nombre || `Presupuesto ${tipo_periodo === 'quincenal' ? 'quincenal' : 'mensual'}`;

    // Crear el presupuesto
    const [presResult] = await db.execute(
      `INSERT INTO presupuestos (nombre, monto_total, firebase_uid, tipo_periodo, dia_inicio_periodo)
       VALUES (?, ?, ?, ?, ?)`,
      [nombreFinal, monto_total, firebase_uid, tipo_periodo, dia_inicio_periodo]
    );
    const presupuestoId = presResult.insertId;

    // Obtener gastos fijos activos del perfil
    const [gastosFijos] = await db.execute(
      `SELECT * FROM user_gastos_fijos WHERE firebase_uid = ? AND activo = 1`, [firebase_uid]
    );

    // Obtener deudas independientes (no vinculadas a gastos fijos)
    const [deudasIndep] = await db.execute(
      `SELECT d.* FROM deudas d
       LEFT JOIN user_gastos_fijos ugf ON ugf.deuda_id = d.id
       WHERE d.firebase_uid = ? AND d.activa = 1 AND ugf.id IS NULL`, [firebase_uid]
    );

    // Insertar gastos fijos como gastos del presupuesto
    for (const g of gastosFijos) {
      const montoPeriodo = parseFloat((Number(g.monto_mensual) / divisor).toFixed(2));
      await db.execute(
        `INSERT INTO gastos (presupuesto_id, firebase_uid, descripcion, monto, tipo, tipo_fecha, dia_pago, frecuencia_pago)
         VALUES (?, ?, ?, ?, 'fijo', ?, ?, 'mensual')`,
        [presupuestoId, firebase_uid, g.descripcion, montoPeriodo,
         g.dia_pago ? 'fija' : 'variable', g.dia_pago || null]
      );
    }

    // Insertar cuotas de deudas independientes como gastos fijos del presupuesto
    for (const d of deudasIndep) {
      const cuota = d.es_letra ? Number(d.cuota_fija || 0) : Number(d.pago_minimo || 0);
      if (cuota <= 0) continue;
      const montoPeriodo = parseFloat((cuota / divisor).toFixed(2));
      await db.execute(
        `INSERT INTO gastos (presupuesto_id, firebase_uid, descripcion, monto, tipo, tipo_fecha, dia_pago, frecuencia_pago)
         VALUES (?, ?, ?, ?, 'fijo', ?, ?, 'mensual')`,
        [presupuestoId, firebase_uid,
         d.es_letra ? `Letra: ${d.nombre}` : `Cuota: ${d.nombre}`,
         montoPeriodo, d.fecha_proximo_pago ? 'fija' : 'variable',
         d.fecha_proximo_pago ? new Date(d.fecha_proximo_pago).getDate() : null]
      );
    }

    // Crear el primer período y sus movimientos automáticos
    const periodo = await crearPrimerPeriodo(presupuestoId, firebase_uid, tipo_periodo, dia_inicio_periodo);

    const [[presupuestoCreado]] = await db.execute(
      `SELECT * FROM presupuestos WHERE id = ?`, [presupuestoId]
    );
    res.status(201).json({
      message: 'Presupuesto generado desde tu perfil financiero',
      presupuesto: presupuestoCreado,
      periodo,
      gastos_incluidos: gastosFijos.length + deudasIndep.filter(d => {
        const c = d.es_letra ? Number(d.cuota_fija || 0) : Number(d.pago_minimo || 0);
        return c > 0;
      }).length,
    });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

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
  const { nombre, firebase_uid, tipo_periodo, dia_inicio_periodo,
    monto_total: monto_manual } = req.body;

  if (!nombre || !firebase_uid || !tipo_periodo || !dia_inicio_periodo)
    return res.status(400).json({ error: 'Datos incompletos' });

  try {
    // Calcular monto_total desde user_income si existe (presupuesto = ingreso neto por período)
    let monto_total = monto_manual;
    const [[incomeRow]] = await db.execute(
      `SELECT ingreso_neto_mensual, frecuencia_cobro FROM user_income WHERE firebase_uid = ?`,
      [firebase_uid]
    );
    if (incomeRow) {
      const divisor = tipo_periodo === 'quincenal' ? 2 : 1;
      monto_total = parseFloat((Number(incomeRow.ingreso_neto_mensual) / divisor).toFixed(2));
    } else if (!monto_total) {
      return res.status(400).json({ error: 'Configura tu ingreso antes de crear un presupuesto' });
    }

    const [result] = await db.execute(
      `INSERT INTO presupuestos (nombre, monto_total, firebase_uid, tipo_periodo, dia_inicio_periodo)
       VALUES (?, ?, ?, ?, ?)`,
      [nombre, monto_total, firebase_uid, tipo_periodo, dia_inicio_periodo]
    );
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


// PATCH /presupuestos/:id/tipo-periodo
// Cambia el tipo de período de mensual a quincenal o viceversa.
// Si mensual → quincenal: divide el monto_total entre 2 y ajusta gastos fijos del presupuesto.
// Si quincenal → mensual: multiplica por 2.
// El período activo actual se cierra y se crea uno nuevo con el nuevo tipo.
app.patch('/presupuestos/:id/tipo-periodo', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid, tipo_periodo, dia_inicio_periodo } = req.body;
  if (!firebase_uid || !tipo_periodo)
    return res.status(400).json({ error: 'firebase_uid y tipo_periodo son requeridos' });
  if (!['mensual', 'quincenal'].includes(tipo_periodo))
    return res.status(400).json({ error: 'tipo_periodo debe ser mensual o quincenal' });
  try {
    const [[pres]] = await db.execute(
      `SELECT * FROM presupuestos WHERE id = ? AND firebase_uid = ?`, [id, firebase_uid]
    );
    if (!pres) return res.status(404).json({ error: 'Presupuesto no encontrado' });
    if (pres.tipo_periodo === tipo_periodo)
      return res.status(400).json({ error: 'El presupuesto ya usa ese tipo de período' });

    // Factor de conversión: mensual→quincenal = ÷2, quincenal→mensual = ×2
    const factor = tipo_periodo === 'quincenal' ? 0.5 : 2;
    const nuevoMonto = parseFloat((Number(pres.monto_total) * factor).toFixed(2));
    const nuevoDia   = dia_inicio_periodo ?? pres.dia_inicio_periodo;

    // Actualizar el presupuesto
    await db.execute(
      `UPDATE presupuestos SET tipo_periodo = ?, monto_total = ?, dia_inicio_periodo = ? WHERE id = ?`,
      [tipo_periodo, nuevoMonto, nuevoDia, id]
    );

    // Ajustar los gastos fijos del presupuesto (tabla gastos) al nuevo tipo
    const [gastosFijos] = await db.execute(
      `SELECT id, monto FROM gastos WHERE presupuesto_id = ? AND firebase_uid = ? AND tipo = 'fijo'`,
      [id, firebase_uid]
    );
    for (const g of gastosFijos) {
      const nuevoMontoGasto = parseFloat((Number(g.monto) * factor).toFixed(2));
      await db.execute(`UPDATE gastos SET monto = ? WHERE id = ?`, [nuevoMontoGasto, g.id]);
    }

    // Cerrar período activo y abrir uno nuevo con el nuevo tipo
    await db.execute(
      `UPDATE periodos SET estado = 'cerrado', closed_at = NOW()
       WHERE presupuesto_id = ? AND firebase_uid = ? AND estado = 'activo'`,
      [id, firebase_uid]
    );
    const nuevoPeriodo = await crearPrimerPeriodo(id, firebase_uid, tipo_periodo, nuevoDia);

    res.json({
      mensaje:         `Presupuesto cambiado a ${tipo_periodo}`,
      monto_anterior:  Number(pres.monto_total),
      monto_nuevo:     nuevoMonto,
      gastos_ajustados: gastosFijos.length,
      nuevo_periodo:   nuevoPeriodo,
    });
  } catch (e) { res.status(500).json({ error: e.message }); }
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
    tipo_fecha = 'flexible',
    dia_pago = null,
    frecuencia_pago = null,
    fecha_pago_exacta = null,
    genera_notificacion = false,
    dias_anticipacion = 3,
    subcategoria = null,
    clasificacion = null,
    gasto_global_id = null,      // Si viene de gastos_globales, enlaza aquí
    guardar_como_global = false, // Si true, auto-guarda en gastos_globales para reuso
  } = req.body;

  if (!presupuesto_id || !descripcion || monto == null || !tipo || !fecha || !firebase_uid)
    return res.status(400).json({ error: 'Datos incompletos' });

  const clasificacionValida = ['esencial', 'importante', 'flexible'];
  const clasificacionFinal = clasificacionValida.includes(clasificacion) ? clasificacion : null;
  const fechaStr     = fecha.split('T')[0];
  const fechaPagoStr = fecha_pago_exacta ? fecha_pago_exacta.split('T')[0] : null;

  try {
    // Si viene de gastos_globales, copiar datos de ahí (descripcion/monto del global tienen prioridad)
    let globalId = gasto_global_id ? Number(gasto_global_id) : null;
    if (globalId) {
      const [[global]] = await db.execute(
        `SELECT * FROM gastos_globales WHERE id = ? AND firebase_uid = ?`, [globalId, firebase_uid]
      );
      if (!global) return res.status(404).json({ error: 'Gasto global no encontrado' });
    }

    const [result] = await db.execute(
      `INSERT INTO gastos
         (presupuesto_id, descripcion, monto, tipo, fecha, pagado, firebase_uid,
          tipo_fecha, dia_pago, frecuencia_pago, fecha_pago_exacta,
          genera_notificacion, dias_anticipacion, subcategoria, clasificacion, gasto_global_id)
       VALUES (?, ?, ?, ?, ?, 0, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [presupuesto_id, descripcion, monto, tipo, fechaStr, firebase_uid,
       tipo_fecha, dia_pago, frecuencia_pago, fechaPagoStr,
       genera_notificacion ? 1 : 0, dias_anticipacion, subcategoria || null, clasificacionFinal, globalId]
    );
    const gastoId = result.insertId;

    // Auto-guardar en gastos_globales si es variable nuevo y el usuario lo indica
    if (guardar_como_global && !globalId) {
      const [gr] = await db.execute(
        `INSERT INTO gastos_globales (firebase_uid, nombre, monto, tipo, modalidad, frecuencia, dia_pago)
         VALUES (?, ?, ?, 'variable', 'individual', ?, ?)`,
        [firebase_uid, descripcion, monto, frecuencia_pago || 'unico', dia_pago]
      );
      await db.execute(`UPDATE gastos SET gasto_global_id = ? WHERE id = ?`, [gr.insertId, gastoId]);
      globalId = gr.insertId;
    }

    // Auto-crear movimiento para gastos fijos/periódicos
    if (tipo === 'fijo' || tipo === 'fijo_x_periodo' || tipo === 'ahorro') {
      try {
        const periodo = await getPeriodoActivo(presupuesto_id, firebase_uid);
        await db.execute(
          `INSERT INTO movimientos
             (presupuesto_id, periodo_id, gasto_id, descripcion, monto, tipo, pagado, firebase_uid, subcategoria, clasificacion, created_at)
           VALUES (?, ?, ?, ?, ?, ?, 0, ?, ?, ?, NOW())`,
          [presupuesto_id, periodo.id, gastoId, descripcion, monto, tipo, firebase_uid, subcategoria || null, clasificacionFinal]
        );
      } catch (err) { console.error('⚠️ No se pudo auto-crear movimiento:', err.message); }
    }

    // Si tiene fecha fija, generar eventos de calendario
    if (tipo_fecha === 'fija') {
      await generarEventosCalendario(gastoId, firebase_uid);
    }

    const [[created]] = await db.execute(`SELECT * FROM gastos WHERE id = ?`, [gastoId]);
    res.status(201).json(created);
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

// PUT /gastos/:id — edición completa del gasto
// Permite cambiar descripción, monto, tipo_fecha, dia_pago, subcategoria, clasificacion.
// Si cambia tipo_fecha o dia_pago, regenera los eventos de calendario.
app.put('/gastos/:id', async (req, res) => {
  const { id } = req.params;
  const {
    firebase_uid, pagado, descripcion, monto, tipo, subcategoria, clasificacion,
    tipo_fecha, dia_pago, frecuencia_pago, fecha_pago_exacta, genera_notificacion, dias_anticipacion,
  } = req.body;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid es requerido' });
  try {
    const [[existing]] = await db.execute(
      `SELECT * FROM gastos WHERE id = ? AND firebase_uid = ?`, [id, firebase_uid]
    );
    if (!existing) return res.status(404).json({ error: 'Gasto no encontrado' });

    const fields = [], vals = [];
    if (pagado !== undefined)              { fields.push('pagado = ?');              vals.push(pagado === true || pagado === 1 ? 1 : 0); }
    if (descripcion !== undefined)         { fields.push('descripcion = ?');         vals.push(descripcion); }
    if (monto !== undefined)               { fields.push('monto = ?');               vals.push(monto); }
    if (tipo !== undefined)                { fields.push('tipo = ?');                vals.push(tipo); }
    if (subcategoria !== undefined)        { fields.push('subcategoria = ?');        vals.push(subcategoria); }
    if (clasificacion !== undefined)       { fields.push('clasificacion = ?');       vals.push(clasificacion); }
    if (tipo_fecha !== undefined)          { fields.push('tipo_fecha = ?');          vals.push(tipo_fecha); }
    if (dia_pago !== undefined)            { fields.push('dia_pago = ?');            vals.push(dia_pago); }
    if (frecuencia_pago !== undefined)     { fields.push('frecuencia_pago = ?');     vals.push(frecuencia_pago); }
    if (fecha_pago_exacta !== undefined)   { fields.push('fecha_pago_exacta = ?');   vals.push(fecha_pago_exacta ? fecha_pago_exacta.split('T')[0] : null); }
    if (genera_notificacion !== undefined) { fields.push('genera_notificacion = ?'); vals.push(genera_notificacion ? 1 : 0); }
    if (dias_anticipacion !== undefined)   { fields.push('dias_anticipacion = ?');   vals.push(dias_anticipacion); }

    if (fields.length === 0) return res.status(400).json({ error: 'Nada que actualizar' });
    vals.push(id, firebase_uid);
    await db.execute(`UPDATE gastos SET ${fields.join(', ')} WHERE id = ? AND firebase_uid = ?`, vals);

    // Regenerar eventos de calendario si cambió tipo_fecha o dia_pago
    const nuevaTipoFecha   = tipo_fecha   ?? existing.tipo_fecha;
    const nuevoDiaPago     = dia_pago     ?? existing.dia_pago;
    const necesitaCalend   = tipo_fecha !== undefined || dia_pago !== undefined;
    if (necesitaCalend) {
      await db.execute(
        `DELETE FROM calendario_eventos WHERE gasto_id = ? AND estado = 'pendiente'`, [id]
      );
      if (nuevaTipoFecha === 'fija') {
        await generarEventosCalendario(id, firebase_uid);
      }
    }

    const [[updated]] = await db.execute(`SELECT * FROM gastos WHERE id = ?`, [id]);
    res.json(updated);
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
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid es requerido' });
  try {
    const [result] = await db.execute(
      `DELETE FROM gastos WHERE id = ? AND firebase_uid = ?`, [id, firebase_uid]
    );
    if (result.affectedRows === 0) return res.status(404).json({ error: 'Gasto no encontrado' });
    // Limpiar eventos de calendario pendientes asociados a este gasto
    await db.execute(
      `DELETE FROM calendario_eventos WHERE gasto_id = ? AND estado = 'pendiente'`, [id]
    );
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
      `SELECT g.id, g.descripcion AS nombre,
              g.monto AS cuota_periodo,
              g.numero_quincena AS periodos_restantes,
              COALESCE(SUM(m.monto_pagado_real), 0) AS monto_ahorrado,
              COUNT(m.id) AS cuotas_pagadas,
              COALESCE((SELECT SUM(a.monto) FROM aportaciones_ahorro a WHERE a.gasto_id = g.id), 0) AS total_aportaciones,
              (SELECT COUNT(*) FROM movimientos m2 WHERE m2.gasto_id = g.id) AS cuotas_generadas
       FROM gastos g
       LEFT JOIN movimientos m ON m.gasto_id = g.id AND m.pagado = 1
       WHERE g.firebase_uid = ? AND g.tipo = 'ahorro'
       GROUP BY g.id`,
      [firebase_uid]
    );

    // monto_meta_total = cuota × (cuotas ya generadas + períodos restantes) = total original
    // Para ahorros sin límite (periodos_restantes IS NULL) usamos solo cuotas generadas como referencia
    const result = ahorros.map(a => {
      const totalAhorrado    = parseFloat(a.monto_ahorrado) + parseFloat(a.total_aportaciones);
      const completado       = a.periodos_restantes === 0;
      const cuotasGeneradas  = parseInt(a.cuotas_generadas) || 0;
      const periodosRestantes = a.periodos_restantes !== null ? parseInt(a.periodos_restantes) : null;
      const totalCuotas      = periodosRestantes !== null ? cuotasGeneradas + periodosRestantes : null;
      const metaTotal        = totalCuotas !== null && totalCuotas > 0
        ? parseFloat((parseFloat(a.cuota_periodo) * totalCuotas).toFixed(2))
        : null;
      return {
        ...a,
        monto_meta: a.cuota_periodo, // cuota por período (compatibilidad hacia atrás)
        monto_meta_total: metaTotal, // meta total real — usar este para barras de progreso
        total_ahorrado: parseFloat(totalAhorrado.toFixed(2)),
        completado,
      };
    });
    res.json(result);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Error al obtener ahorros' });
  }
});

/**
 * POST /ahorros/:id/aportaciones
 * Registra una aportación manual a una meta de ahorro.
 */
app.post('/ahorros/:id/aportaciones', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid, monto, nota, fecha } = req.body;
  if (!firebase_uid || !monto || !fecha) return res.status(400).json({ error: 'Datos incompletos' });
  if (Number(monto) <= 0) return res.status(400).json({ error: 'Monto debe ser mayor a 0' });
  try {
    const [[gasto]] = await db.execute(
      `SELECT id FROM gastos WHERE id = ? AND firebase_uid = ? AND tipo = 'ahorro'`,
      [id, firebase_uid]
    );
    if (!gasto) return res.status(404).json({ error: 'Meta de ahorro no encontrada' });
    const [result] = await db.execute(
      `INSERT INTO aportaciones_ahorro (gasto_id, firebase_uid, monto, nota, fecha) VALUES (?, ?, ?, ?, ?)`,
      [id, firebase_uid, monto, nota || null, fecha]
    );
    res.status(201).json({ id: result.insertId, gasto_id: Number(id), monto, nota, fecha });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

/**
 * GET /ahorros/:id/aportaciones?firebase_uid=
 * Lista las aportaciones manuales de una meta de ahorro.
 */
app.get('/ahorros/:id/aportaciones', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid es requerido' });
  try {
    const [aportaciones] = await db.execute(
      `SELECT * FROM aportaciones_ahorro WHERE gasto_id = ? AND firebase_uid = ? ORDER BY fecha DESC`,
      [id, firebase_uid]
    );
    const total = aportaciones.reduce((s, a) => s + Number(a.monto), 0);
    res.json({ aportaciones, total_aportado: total });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

/**
 * DELETE /aportaciones/:id?firebase_uid=
 * Elimina una aportación manual.
 */
app.delete('/aportaciones/:id', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid es requerido' });
  try {
    const [[ap]] = await db.execute(
      `SELECT a.id FROM aportaciones_ahorro a
       JOIN gastos g ON g.id = a.gasto_id
       WHERE a.id = ? AND a.firebase_uid = ?`,
      [id, firebase_uid]
    );
    if (!ap) return res.status(404).json({ error: 'Aportación no encontrada' });
    await db.execute(`DELETE FROM aportaciones_ahorro WHERE id = ?`, [id]);
    res.json({ deleted: true });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
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
    const [[presupuesto]] = await db.execute(
      `SELECT id, nombre, monto_total FROM presupuestos WHERE id = ? AND firebase_uid = ?`,
      [id, firebase_uid]
    );
    if (!presupuesto) return res.status(404).json({ error: 'Presupuesto no encontrado' });

    const periodo = await getPeriodoActivo(id, firebase_uid);

    const [movimientos] = await db.execute(
      `SELECT * FROM movimientos
       WHERE presupuesto_id = ? AND periodo_id = ? AND firebase_uid = ?
       ORDER BY id DESC`,
      [id, periodo.id, firebase_uid]
    );

    // Totales por tipo — fijos = compromisos, variables = gastos del período, ahorro = metas
    let totalFijos = 0, totalVariables = 0, totalAhorro = 0;
    let fijosPagados = 0, variablesPagados = 0;
    movimientos.forEach(m => {
      const esF = m.tipo === 'fijo' || m.tipo === 'fijo_x_periodo';
      const esV = m.tipo === 'no fijo' || m.tipo === 'variable';
      const esA = m.tipo === 'ahorro';
      if (esF) { totalFijos     += Number(m.monto); if (m.pagado) fijosPagados     += Number(m.monto_pagado_real || m.monto); }
      if (esV) { totalVariables += Number(m.monto); if (m.pagado) variablesPagados += Number(m.monto_pagado_real || m.monto); }
      if (esA) { totalAhorro    += Number(m.monto); }
    });

    // Gustitos (módulo independiente de micro-gastos)
    let totalGustitos = 0;
    try {
      const [[gustitosRow]] = await db.execute(
        `SELECT COALESCE(SUM(amount), 0) AS totalGustitos
         FROM gustitos WHERE budget_id = ? AND user_id = ? AND deleted_at IS NULL`,
        [id, firebase_uid]
      );
      totalGustitos = Math.round(Number(gustitosRow.totalGustitos) * 100) / 100;
    } catch (_) { /* tabla gustitos puede no existir */ }

    const pagados       = movimientos.filter(m => m.pagado === 1).length;
    const totalGastado  = totalFijos + totalVariables + totalAhorro;
    const montoTotal    = Number(presupuesto.monto_total);
    const comprometido  = parseFloat((totalFijos + totalAhorro).toFixed(2));          // gastos fijos del período
    const gastadoLibre  = parseFloat((totalVariables + totalGustitos).toFixed(2));    // gastos variables reales
    const disponible    = parseFloat((montoTotal - comprometido - gastadoLibre).toFixed(2));
    const porcentajeUtilizado = montoTotal > 0
      ? parseFloat(((totalGastado + totalGustitos) / montoTotal * 100).toFixed(1)) : 0;

    res.json({
      periodo,
      movimientos,
      presupuesto: { monto_total: montoTotal, nombre: presupuesto.nombre },
      resumen: {
        // Compromisos fijos del período (gastos del perfil trasladados al presupuesto)
        total_fijos:            parseFloat(totalFijos.toFixed(2)),
        total_fijos_pagados:    parseFloat(fijosPagados.toFixed(2)),
        // Gastos variables que el usuario fue añadiendo
        total_variables:        parseFloat(totalVariables.toFixed(2)),
        total_variables_pagados: parseFloat(variablesPagados.toFixed(2)),
        // Ahorros del período
        total_ahorro:           parseFloat(totalAhorro.toFixed(2)),
        // Micro-gastos (gustitos)
        total_gustitos:         totalGustitos,
        // Resumen ejecutivo
        comprometido,
        gastado_libre:          gastadoLibre,
        total_gastado:          parseFloat((comprometido + gastadoLibre).toFixed(2)),
        disponible_real:        disponible,
        porcentaje_utilizado:   porcentajeUtilizado,
        porcentaje_pagados:     movimientos.length > 0
          ? parseFloat((pagados / movimientos.length * 100).toFixed(1)) : 0,
        presupuesto_sano:       disponible >= 0,
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

// GET /periodos/:id/resumen-cierre?firebase_uid=
// Devuelve el resumen completo del período antes de cerrarlo.
// El Flutter lo muestra como pantalla de confirmación: "Así te fue este período".
app.get('/periodos/:id/resumen-cierre', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [[periodo]] = await db.execute(
      `SELECT p.*, pr.nombre AS presupuesto_nombre, pr.monto_total, pr.tipo_periodo
       FROM periodos p
       JOIN presupuestos pr ON pr.id = p.presupuesto_id
       WHERE p.id = ? AND p.firebase_uid = ?`,
      [id, firebase_uid]
    );
    if (!periodo) return res.status(404).json({ error: 'Período no encontrado' });

    const [movimientos] = await db.execute(
      `SELECT * FROM movimientos WHERE periodo_id = ? AND firebase_uid = ?`, [id, firebase_uid]
    );

    let fijosPagado = 0, fijosTotal = 0;
    let variablesPagado = 0, variablesTotal = 0;
    let ahorroPagado = 0, ahorroTotal = 0;
    const sinPagar = [];

    for (const m of movimientos) {
      const esF = m.tipo === 'fijo' || m.tipo === 'fijo_x_periodo';
      const esV = m.tipo === 'no fijo' || m.tipo === 'variable';
      const esA = m.tipo === 'ahorro';
      const monto     = Number(m.monto);
      const montoPag  = Number(m.monto_pagado_real || 0);

      if (esF) { fijosTotal += monto; if (m.pagado) fijosPagado += montoPag; else sinPagar.push({ descripcion: m.descripcion, monto, tipo: 'fijo' }); }
      if (esV) { variablesTotal += monto; if (m.pagado) variablesPagado += montoPag; }
      if (esA) { ahorroTotal += monto; if (m.pagado) ahorroPagado += montoPag; }
    }

    const montoTotal    = Number(periodo.monto_total);
    const totalGastado  = fijosPagado + variablesPagado + ahorroPagado;
    const sobrante      = parseFloat((montoTotal - totalGastado).toFixed(2));

    // Gastos fijos del perfil que se incluirán en el siguiente período
    const [gastosFijosActivos] = await db.execute(
      `SELECT id, descripcion, monto_mensual, clasificacion FROM user_gastos_fijos
       WHERE firebase_uid = ? AND activo = 1 ORDER BY monto_mensual DESC`,
      [firebase_uid]
    );

    res.json({
      periodo: {
        id: periodo.id,
        numero:        periodo.numero_periodo,
        fecha_inicio:  periodo.fecha_inicio,
        fecha_fin:     periodo.fecha_fin,
        tipo_periodo:  periodo.tipo_periodo,
        presupuesto:   periodo.presupuesto_nombre,
      },
      balance: {
        ingreso_periodo:     montoTotal,
        total_fijos:         parseFloat(fijosTotal.toFixed(2)),
        total_fijos_pagado:  parseFloat(fijosPagado.toFixed(2)),
        total_variables:     parseFloat(variablesTotal.toFixed(2)),
        total_variables_pagado: parseFloat(variablesPagado.toFixed(2)),
        total_ahorro:        parseFloat(ahorroTotal.toFixed(2)),
        total_ahorro_pagado: parseFloat(ahorroPagado.toFixed(2)),
        total_gastado:       parseFloat(totalGastado.toFixed(2)),
        sobrante,
        cerro_positivo:      sobrante >= 0,
      },
      pagos_pendientes: sinPagar,
      siguiente_periodo: {
        gastos_fijos_base: gastosFijosActivos,
        total_fijos_base:  parseFloat(gastosFijosActivos.reduce((s, g) => s + Number(g.monto_mensual), 0).toFixed(2)),
        mensaje: '¿Deseas continuar con los mismos compromisos para el siguiente período?',
      },
    });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// POST /periodos/:id/cerrar
// Cierra manualmente el período activo y abre el siguiente.
// El body permite modificar la configuración para el próximo período.
//
// Opciones en body:
//   continuar_igual: true   → cierra y abre el siguiente sin cambios
//   modificaciones: [       → lista de cambios a aplicar antes de abrir el siguiente
//     { tipo: 'eliminar_gasto_fijo', gasto_fijo_id: X },
//     { tipo: 'agregar_gasto_fijo',  descripcion, monto_mensual, tipo? },
//     { tipo: 'editar_gasto_fijo',   gasto_fijo_id, monto_mensual },
//   ]
app.post('/periodos/:id/cerrar', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid, continuar_igual = true, modificaciones = [] } = req.body;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [[periodo]] = await db.execute(
      `SELECT p.*, pr.tipo_periodo FROM periodos p
       JOIN presupuestos pr ON pr.id = p.presupuesto_id
       WHERE p.id = ? AND p.firebase_uid = ? AND p.estado = 'activo'`,
      [id, firebase_uid]
    );
    if (!periodo) return res.status(404).json({ error: 'Período activo no encontrado' });

    // Cerrar el período actual
    await db.execute(
      `UPDATE periodos SET estado = 'cerrado', closed_at = NOW() WHERE id = ?`, [id]
    );

    // Aplicar modificaciones al perfil antes de abrir el siguiente período
    for (const mod of modificaciones) {
      if (mod.tipo === 'eliminar_gasto_fijo' && mod.gasto_fijo_id) {
        await db.execute(
          `UPDATE user_gastos_fijos SET activo = 0 WHERE id = ? AND firebase_uid = ?`,
          [mod.gasto_fijo_id, firebase_uid]
        );
      } else if (mod.tipo === 'agregar_gasto_fijo' && mod.descripcion && mod.monto_mensual) {
        await db.execute(
          `INSERT INTO user_gastos_fijos (firebase_uid, descripcion, monto_mensual, tipo, clasificacion, activo)
           VALUES (?, ?, ?, ?, 'importante', 1)`,
          [firebase_uid, mod.descripcion, mod.monto_mensual, mod.tipo || 'otro']
        );
      } else if (mod.tipo === 'editar_gasto_fijo' && mod.gasto_fijo_id && mod.monto_mensual) {
        await db.execute(
          `UPDATE user_gastos_fijos SET monto_mensual = ? WHERE id = ? AND firebase_uid = ?`,
          [mod.monto_mensual, mod.gasto_fijo_id, firebase_uid]
        );
      }
    }

    // Abrir el siguiente período
    const siguientePeriodo = await crearNuevoPeriodo(
      periodo.presupuesto_id, firebase_uid, periodo.tipo_periodo, periodo.fecha_fin
    );

    res.json({
      mensaje:           'Período cerrado correctamente',
      periodo_cerrado:   { id: Number(id), numero: periodo.numero_periodo },
      siguiente_periodo: siguientePeriodo,
      modificaciones_aplicadas: modificaciones.length,
    });
  } catch (e) { res.status(500).json({ error: e.message }); }
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
  const { firebase_uid, items } = req.body; // items: [{gasto_id, monto, subcategoria?}]

  if (!firebase_uid || !Array.isArray(items) || items.length === 0)
    return res.status(400).json({ error: 'Datos incompletos' });

  try {
    const periodo = await getPeriodoActivo(id, firebase_uid);

    for (const item of items) {
      const { gasto_id, monto, subcategoria } = item;
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

      // subcategoria: usa la del item si viene, si no hereda la del gasto
      const subcategoriaFinal = subcategoria || gasto.subcategoria || null;

      await db.execute(
        `INSERT INTO movimientos
         (presupuesto_id, periodo_id, gasto_id, descripcion, monto, tipo, pagado, firebase_uid, subcategoria, created_at)
         VALUES (?, ?, ?, ?, ?, ?, 0, ?, ?, NOW())`,
        [id, periodo.id, gasto.id, gasto.descripcion, monto, gasto.tipo, firebase_uid, subcategoriaFinal]
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
      `SELECT p.*, COALESCE(SUM(
         CASE
           WHEN i.cantidad_usada IS NOT NULL AND i.precio_total_paquete IS NOT NULL
             THEN i.precio_total_paquete * (i.cantidad_usada / i.cantidad)
           ELSE i.cantidad * i.precio_unitario
         END
       ), 0) AS total_invertido
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
      `SELECT p.*, COALESCE(SUM(
         CASE
           WHEN i.cantidad_usada IS NOT NULL AND i.precio_total_paquete IS NOT NULL
             THEN i.precio_total_paquete * (i.cantidad_usada / i.cantidad)
           ELSE i.cantidad * i.precio_unitario
         END
       ), 0) AS total_invertido
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
  const { nombre, cantidad, precio_unitario, firebase_uid, precio_total_paquete, cantidad_usada } = req.body;
  if (!nombre || !cantidad || !firebase_uid)
    return res.status(400).json({ error: 'Datos incompletos' });
  // precio_unitario puede derivarse de precio_total_paquete / cantidad
  const precioUnitario = precio_unitario
    ? Number(precio_unitario)
    : (precio_total_paquete ? Number(precio_total_paquete) / Number(cantidad) : null);
  if (!precioUnitario || precioUnitario <= 0)
    return res.status(400).json({ error: 'Se requiere precio_unitario o precio_total_paquete' });
  try {
    const [result] = await db.execute(
      `INSERT INTO items_produccion (presupuesto_produccion_id, firebase_uid, nombre, cantidad, precio_unitario, precio_total_paquete, cantidad_usada)
       VALUES (?, ?, ?, ?, ?, ?, ?)`,
      [id, firebase_uid, nombre, cantidad, precioUnitario,
       precio_total_paquete ? Number(precio_total_paquete) : null,
       cantidad_usada ? Number(cantidad_usada) : null]
    );
    res.status(201).json({ id: result.insertId, nombre, cantidad, precio_unitario: precioUnitario, precio_total_paquete, cantidad_usada });
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
    // Markup: ganancia sobre lo invertido (ganancia/costo × 100). Ej: $12 costo, $18 venta → 50% markup.
    const margen            = invertido > 0 ? (ganancia / invertido * 100) : 0;
    const margenEsperado    = invertido > 0 ? ((totalEsperado - invertido) / invertido * 100) : 0;
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
    // Si viene precio nuevo, registrar historial si cambió
    if (precio !== undefined && precio !== null) {
      const [[varActual]] = await db.execute(
        `SELECT v.precio FROM variantes_producto v
         JOIN productos p ON p.id = v.producto_id
         WHERE v.id = ? AND p.firebase_uid = ?`,
        [id, firebase_uid]
      );
      if (varActual && Number(varActual.precio) !== Number(precio)) {
        await db.execute(
          `INSERT INTO historial_precios_variante (variante_id, firebase_uid, precio_anterior, precio_nuevo)
           VALUES (?, ?, ?, ?)`,
          [id, firebase_uid, varActual.precio, precio]
        );
      }
    }

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
 * GET /variantes/:id/historial-precios?firebase_uid=
 * Retorna el historial de cambios de precio de una variante.
 */
app.get('/variantes/:id/historial-precios', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid es requerido' });
  try {
    // Verificar propiedad via JOIN con productos
    const [[variante]] = await db.execute(
      `SELECT v.id, v.nombre, v.precio FROM variantes_producto v
       JOIN productos p ON p.id = v.producto_id
       WHERE v.id = ? AND p.firebase_uid = ?`,
      [id, firebase_uid]
    );
    if (!variante) return res.status(404).json({ error: 'Variante no encontrada' });

    const [historial] = await db.execute(
      `SELECT * FROM historial_precios_variante
       WHERE variante_id = ? AND firebase_uid = ?
       ORDER BY changed_at DESC
       LIMIT 20`,
      [id, firebase_uid]
    );
    res.json({ variante, historial });
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
  if (Number(rendimiento) <= 0)
    return res.status(400).json({ error: 'El rendimiento debe ser mayor a 0' });
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
  if (rendimiento != null && Number(rendimiento) <= 0)
    return res.status(400).json({ error: 'El rendimiento debe ser mayor a 0' });
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
// Cron diario: marcar eventos de calendario vencidos
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
}, { timezone: 'America/Panama' });

// Cron mensual: enviar resumen financiero el último día de cada mes a las 8 AM
// Solo envía si el usuario tiene income y email registrado (firebase_uid = email en esta versión)
cron.schedule('0 8 28-31 * *', async () => {
  // Verificar que hoy sea realmente el último día del mes
  const hoy = new Date();
  const manana = new Date(hoy); manana.setDate(hoy.getDate() + 1);
  if (manana.getDate() !== 1) return; // No es último día del mes

  try {
    const [usuarios] = await db.execute(
      `SELECT DISTINCT firebase_uid FROM user_income`
    );
    let enviados = 0;
    for (const u of usuarios) {
      try {
        // En esta versión firebase_uid = email del usuario
        await _enviarResumenMensual(u.firebase_uid, u.firebase_uid);
        enviados++;
      } catch (err) {
        console.error(`Error enviando resumen a ${u.firebase_uid}:`, err.message);
      }
    }
    console.log(`📧 Cron resumen mensual: ${enviados}/${usuarios.length} enviados`);
  } catch (err) {
    console.error('Error en cron resumen mensual:', err);
  }
}, { timezone: 'America/Panama' });


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
// MÓDULO: PRESUPUESTOS COMPARTIDOS
// =============================================================================

async function sendInvitationEmail({ emailInvitado, ownerUid, presupuestoNombre }) {
  if (!process.env.BREVO_API_KEY) return;
  try {
    await fetch('https://api.brevo.com/v3/smtp/email', {
      method: 'POST',
      headers: {
        'api-key': process.env.BREVO_API_KEY,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        sender: { email: process.env.BREVO_SENDER_EMAIL, name: 'Salarying' },
        to: [{ email: emailInvitado }],
        subject: 'Te invitaron a un presupuesto compartido en Salarying',
        htmlContent: `
          <div style="font-family:sans-serif;max-width:480px;margin:auto;padding:24px;background:#1E2026;color:#EAECEF;border-radius:12px;">
            <h2 style="color:#F0B90B;margin-bottom:8px;">Salarying</h2>
            <p style="font-size:16px;"><b>${ownerUid}</b> te invitó a gestionar el presupuesto compartido:</p>
            <div style="background:#2B3139;border-radius:8px;padding:16px;margin:16px 0;text-align:center;">
              <span style="font-size:20px;font-weight:bold;color:#F0B90B;">${presupuestoNombre}</span>
            </div>
            <p>Para aceptar o rechazar la invitación, abre la app <b>Salarying</b> y ve a:</p>
            <p style="background:#2B3139;border-radius:8px;padding:12px;text-align:center;font-weight:bold;">
              Menú principal → Compartido → ícono de sobre ✉️
            </p>
            <p style="color:#848E9C;font-size:13px;margin-top:16px;">La invitación expira en 7 días.</p>
          </div>
        `,
      }),
    });
  } catch (err) {
    console.error('Error enviando email de invitación:', err.message);
  }
}

function calcularSplits(monto, regla, miembros) {
  // miembros: [{ firebase_uid, porcentaje, ingreso_declarado }]
  if (regla === 'equitativo') {
    const parte = Math.round((monto / miembros.length) * 100) / 100;
    return miembros.map(m => ({ firebase_uid: m.firebase_uid, monto_responsabilidad: parte }));
  }
  if (regla === 'porcentual') {
    // Normalizar porcentajes por si no suman exactamente 100
    const totalPct = miembros.reduce((s, m) => s + (parseFloat(m.porcentaje) || 0), 0);
    const factor = totalPct > 0 ? 100 / totalPct : 1;
    return miembros.map(m => ({
      firebase_uid: m.firebase_uid,
      monto_responsabilidad: Math.round(monto * ((parseFloat(m.porcentaje) || 0) * factor / 100) * 100) / 100,
    }));
  }
  if (regla === 'proporcional') {
    const totalIngresos = miembros.reduce((s, m) => s + (parseFloat(m.ingreso_declarado) || 0), 0);
    if (totalIngresos === 0) {
      const parte = Math.round((monto / miembros.length) * 100) / 100;
      return miembros.map(m => ({ firebase_uid: m.firebase_uid, monto_responsabilidad: parte }));
    }
    return miembros.map(m => ({
      firebase_uid: m.firebase_uid,
      monto_responsabilidad: Math.round(monto * ((parseFloat(m.ingreso_declarado) || 0) / totalIngresos) * 100) / 100,
    }));
  }
  // pool_contribucion: sin splits individuales, el gasto se registra pero sin deuda entre personas
  if (regla === 'pool_contribucion') return [];
  return [];
}

// POST /shared-budgets
app.post('/shared-budgets', async (req, res) => {
  const { nombre, tipo_periodo, dia_inicio_periodo, regla_reparto, porcentaje_owner, ingreso_owner, contribucion_owner, aporte_periodo_owner = 0, firebase_uid } = req.body;
  if (!nombre || !firebase_uid) return res.status(400).json({ error: 'Datos incompletos' });
  const conn = await db.getConnection();
  await conn.beginTransaction();
  try {
    const [r] = await conn.execute(
      `INSERT INTO shared_budgets (nombre, tipo_periodo, dia_inicio_periodo, regla_reparto, estado, owner_uid)
       VALUES (?, ?, ?, ?, 'waiting_for_members', ?)`,
      [nombre, tipo_periodo || 'mensual', dia_inicio_periodo || 1, regla_reparto || 'equitativo', firebase_uid]
    );
    const budgetId = r.insertId;
    const pct = regla_reparto === 'porcentual' ? (porcentaje_owner || 50) : 50;
    const ingreso = regla_reparto === 'proporcional' ? (ingreso_owner || null) : null;
    const contribucion = regla_reparto === 'pool_contribucion' ? (contribucion_owner || null) : null;
    await conn.execute(
      `INSERT INTO shared_budget_members (shared_budget_id, firebase_uid, rol, porcentaje, ingreso_declarado, contribucion_mensual, aporte_periodo)
       VALUES (?, ?, 'owner', ?, ?, ?, ?)`,
      [budgetId, firebase_uid, pct, ingreso, contribucion, Number(aporte_periodo_owner) || 0]
    );
    await conn.execute(
      `INSERT INTO shared_budget_activity_logs (shared_budget_id, actor_uid, accion, detalle)
       VALUES (?, ?, 'crear_presupuesto', ?)`,
      [budgetId, firebase_uid, JSON.stringify({ nombre })]
    );
    await conn.commit();
    conn.release();
    res.status(201).json({ id: budgetId, nombre, estado: 'waiting_for_members' });
  } catch (err) {
    await conn.rollback();
    conn.release();
    res.status(500).json({ error: err.message });
  }
});

// GET /shared-budgets
app.get('/shared-budgets', async (req, res) => {
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [rows] = await db.execute(
      `SELECT sb.id, sb.nombre, sb.tipo_periodo, sb.regla_reparto, sb.estado, sb.owner_uid, sb.created_at,
              m.rol, m.porcentaje
       FROM shared_budgets sb
       JOIN shared_budget_members m ON m.shared_budget_id = sb.id AND m.firebase_uid = ?
       ORDER BY sb.created_at DESC`,
      [firebase_uid]
    );
    res.json(rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// GET /shared-budgets/:id
app.get('/shared-budgets/:id', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [[budget]] = await db.execute(
      `SELECT sb.* FROM shared_budgets sb
       JOIN shared_budget_members m ON m.shared_budget_id = sb.id AND m.firebase_uid = ?
       WHERE sb.id = ?`,
      [firebase_uid, id]
    );
    if (!budget) return res.status(404).json({ error: 'No encontrado' });
    const [members] = await db.execute(
      `SELECT firebase_uid, rol, porcentaje, ingreso_declarado, contribucion_mensual, joined_at FROM shared_budget_members WHERE shared_budget_id = ?`,
      [id]
    );

    // Modo pool_contribucion: calcular balance del fondo común sin deudas individuales
    if (budget.regla_reparto === 'pool_contribucion') {
      const totalContribucion = members.reduce((s, m) => s + (parseFloat(m.contribucion_mensual) || 0), 0);
      const [[{ total_gastos_pool }]] = await db.execute(
        `SELECT COALESCE(SUM(monto), 0) AS total_gastos_pool FROM shared_expenses WHERE shared_budget_id = ? AND es_personal = 0`,
        [id]
      );
      const balancePool = Math.round((totalContribucion - parseFloat(total_gastos_pool)) * 100) / 100;
      return res.json({
        ...budget,
        members,
        modo_pool: true,
        total_contribucion: totalContribucion,
        total_gastos: parseFloat(total_gastos_pool),
        balance_disponible: balancePool,
        balance_neto: null,
      });
    }

    // Calcular balance: lo que cada miembro debe al otro menos lo que ya pagó via settlements
    const [splits] = await db.execute(
      `SELECT ses.firebase_uid, ses.monto_responsabilidad, se.pagado_por
       FROM shared_expense_splits ses
       JOIN shared_expenses se ON se.id = ses.expense_id
       WHERE se.shared_budget_id = ? AND se.es_personal = 0`,
      [id]
    );
    const [settlements] = await db.execute(
      `SELECT pagador_uid, receptor_uid, monto FROM shared_settlements WHERE shared_budget_id = ?`,
      [id]
    );
    // balance neto: positivo = firebase_uid le debe a otro, negativo = otro le debe a firebase_uid
    let debeAOtro = 0;
    let otroLeDebe = 0;
    for (const s of splits) {
      if (s.firebase_uid === firebase_uid && s.pagado_por !== firebase_uid) {
        debeAOtro += parseFloat(s.monto_responsabilidad);
      }
      if (s.firebase_uid !== firebase_uid && s.pagado_por === firebase_uid) {
        otroLeDebe += parseFloat(s.monto_responsabilidad);
      }
    }
    for (const st of settlements) {
      if (st.pagador_uid === firebase_uid) debeAOtro -= parseFloat(st.monto);
      if (st.receptor_uid === firebase_uid) otroLeDebe -= parseFloat(st.monto);
    }
    const balanceNeto = Math.round((debeAOtro - otroLeDebe) * 100) / 100;
    res.json({ ...budget, members, balance_neto: balanceNeto, modo_pool: false });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// PATCH /shared-budgets/:id
app.patch('/shared-budgets/:id', async (req, res) => {
  const { id } = req.params;
  const { nombre, regla_reparto, tipo_periodo, dia_inicio_periodo, firebase_uid } = req.body;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [[budget]] = await db.execute(
      `SELECT id FROM shared_budgets WHERE id = ? AND owner_uid = ?`, [id, firebase_uid]
    );
    if (!budget) return res.status(403).json({ error: 'No autorizado' });
    await db.execute(
      `UPDATE shared_budgets SET
        nombre = COALESCE(?, nombre),
        regla_reparto = COALESCE(?, regla_reparto),
        tipo_periodo = COALESCE(?, tipo_periodo),
        dia_inicio_periodo = COALESCE(?, dia_inicio_periodo)
       WHERE id = ?`,
      [nombre || null, regla_reparto || null, tipo_periodo || null, dia_inicio_periodo || null, id]
    );
    res.json({ message: 'Actualizado' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// DELETE /shared-budgets/:id
app.delete('/shared-budgets/:id', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [[budget]] = await db.execute(
      `SELECT id FROM shared_budgets WHERE id = ? AND owner_uid = ?`, [id, firebase_uid]
    );
    if (!budget) return res.status(403).json({ error: 'No autorizado' });
    await db.execute(`DELETE FROM shared_budgets WHERE id = ?`, [id]);
    res.json({ message: 'Eliminado' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// POST /shared-budgets/:id/invitations
app.post('/shared-budgets/:id/invitations', async (req, res) => {
  const { id } = req.params;
  const { email_invitado, firebase_uid } = req.body;
  if (!email_invitado || !firebase_uid) return res.status(400).json({ error: 'Datos incompletos' });
  try {
    const [[budget]] = await db.execute(
      `SELECT id FROM shared_budgets WHERE id = ? AND owner_uid = ?`, [id, firebase_uid]
    );
    if (!budget) return res.status(403).json({ error: 'No autorizado' });
    // Cancelar invitaciones previas pendientes al mismo email
    await db.execute(
      `UPDATE shared_budget_invitations SET estado = 'cancelled'
       WHERE shared_budget_id = ? AND email_invitado = ? AND estado = 'pending'`,
      [id, email_invitado]
    );
    const token = require('crypto').randomBytes(32).toString('hex');
    const expiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000);
    await db.execute(
      `INSERT INTO shared_budget_invitations (shared_budget_id, email_invitado, token, expires_at)
       VALUES (?, ?, ?, ?)`,
      [id, email_invitado, token, expiresAt]
    );
    await db.execute(
      `INSERT INTO shared_budget_activity_logs (shared_budget_id, actor_uid, accion, detalle)
       VALUES (?, ?, 'invitar_usuario', ?)`,
      [id, firebase_uid, JSON.stringify({ email_invitado })]
    );
    const [[budgetInfo]] = await db.execute(`SELECT nombre FROM shared_budgets WHERE id = ?`, [id]);
    sendInvitationEmail({ emailInvitado: email_invitado, ownerUid: firebase_uid, presupuestoNombre: budgetInfo.nombre });
    res.status(201).json({ token, email_invitado, expires_at: expiresAt });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// GET /shared-budget-invitations
app.get('/shared-budget-invitations', async (req, res) => {
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [rows] = await db.execute(
      `SELECT sbi.id, sbi.token, sbi.expires_at, sbi.created_at,
              sb.nombre AS presupuesto_nombre, sb.owner_uid, sb.regla_reparto, sb.tipo_periodo
       FROM shared_budget_invitations sbi
       JOIN shared_budgets sb ON sb.id = sbi.shared_budget_id
       WHERE sbi.email_invitado = ? AND sbi.estado = 'pending' AND sbi.expires_at > NOW()
       ORDER BY sbi.created_at DESC`,
      [firebase_uid]
    );
    res.json(rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// POST /shared-budget-invitations/:token/accept
app.post('/shared-budget-invitations/:token/accept', async (req, res) => {
  const { token } = req.params;
  const { firebase_uid, ingreso_declarado } = req.body;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  const conn = await db.getConnection();
  await conn.beginTransaction();
  try {
    const [[inv]] = await conn.execute(
      `SELECT * FROM shared_budget_invitations WHERE token = ? AND estado = 'pending' AND expires_at > NOW()`,
      [token]
    );
    if (!inv) { await conn.rollback(); conn.release(); return res.status(404).json({ error: 'Invitación no válida o expirada' }); }
    if (inv.email_invitado !== firebase_uid) { await conn.rollback(); conn.release(); return res.status(403).json({ error: 'No autorizado' }); }
    await conn.execute(
      `UPDATE shared_budget_invitations SET estado = 'accepted' WHERE id = ?`, [inv.id]
    );
    const [[budget]] = await conn.execute(`SELECT regla_reparto FROM shared_budgets WHERE id = ?`, [inv.shared_budget_id]);
    // Nuevo miembro entra con porcentaje 0 y contribucion_mensual del body si aplica.
    // El owner debe rebalancear porcentajes usando PATCH /shared-budgets/:id/members/:uid.
    const contribucionNuevo = budget.regla_reparto === 'pool_contribucion' ? (ingreso_declarado || null) : null;
    await conn.execute(
      `INSERT IGNORE INTO shared_budget_members (shared_budget_id, firebase_uid, rol, porcentaje, ingreso_declarado, contribucion_mensual)
       VALUES (?, ?, 'member', 0, ?, ?)`,
      [inv.shared_budget_id, firebase_uid, ingreso_declarado || null, contribucionNuevo]
    );
    await conn.execute(
      `UPDATE shared_budgets SET estado = 'active' WHERE id = ?`, [inv.shared_budget_id]
    );
    await conn.execute(
      `INSERT INTO shared_budget_activity_logs (shared_budget_id, actor_uid, accion, detalle)
       VALUES (?, ?, 'aceptar_invitacion', NULL)`,
      [inv.shared_budget_id, firebase_uid]
    );
    await conn.commit();
    conn.release();
    res.json({ message: 'Invitación aceptada', shared_budget_id: inv.shared_budget_id });
  } catch (err) {
    await conn.rollback();
    conn.release();
    res.status(500).json({ error: err.message });
  }
});

// POST /shared-budget-invitations/:token/reject
app.post('/shared-budget-invitations/:token/reject', async (req, res) => {
  const { token } = req.params;
  const { firebase_uid } = req.body;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [[inv]] = await db.execute(
      `SELECT * FROM shared_budget_invitations WHERE token = ? AND estado = 'pending'`, [token]
    );
    if (!inv) return res.status(404).json({ error: 'Invitación no encontrada' });
    if (inv.email_invitado !== firebase_uid) return res.status(403).json({ error: 'No autorizado' });
    await db.execute(`UPDATE shared_budget_invitations SET estado = 'rejected' WHERE id = ?`, [inv.id]);
    res.json({ message: 'Invitación rechazada' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// PATCH /shared-budgets/:id/members/:uid — Editar porcentaje/contribución de un miembro (solo el owner)
app.patch('/shared-budgets/:id/members/:uid', async (req, res) => {
  const { id, uid } = req.params;
  const { porcentaje, ingreso_declarado, contribucion_mensual, firebase_uid } = req.body;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    // Verificar que el que hace el cambio es el owner
    const [[budget]] = await db.execute(
      `SELECT owner_uid, regla_reparto FROM shared_budgets WHERE id = ?`, [id]
    );
    if (!budget) return res.status(404).json({ error: 'Presupuesto no encontrado' });
    if (budget.owner_uid !== firebase_uid) return res.status(403).json({ error: 'Solo el owner puede editar miembros' });

    // Validar que los porcentajes no superen 100% si regla es porcentual
    if (budget.regla_reparto === 'porcentual' && porcentaje != null) {
      const [[{ total_pct }]] = await db.execute(
        `SELECT COALESCE(SUM(porcentaje), 0) AS total_pct FROM shared_budget_members WHERE shared_budget_id = ? AND firebase_uid != ?`,
        [id, uid]
      );
      if (parseFloat(total_pct) + parseFloat(porcentaje) > 100.01) {
        return res.status(400).json({
          error: `Los porcentajes sumarían ${(parseFloat(total_pct) + parseFloat(porcentaje)).toFixed(1)}%. Máximo 100%.`
        });
      }
    }

    await db.execute(
      `UPDATE shared_budget_members SET
         porcentaje          = COALESCE(?, porcentaje),
         ingreso_declarado   = CASE WHEN ? IS NOT NULL THEN ? ELSE ingreso_declarado END,
         contribucion_mensual = CASE WHEN ? IS NOT NULL THEN ? ELSE contribucion_mensual END
       WHERE shared_budget_id = ? AND firebase_uid = ?`,
      [porcentaje != null ? parseFloat(porcentaje) : null,
       ingreso_declarado, ingreso_declarado,
       contribucion_mensual, contribucion_mensual,
       id, uid]
    );
    await db.execute(
      `INSERT INTO shared_budget_activity_logs (shared_budget_id, actor_uid, accion, detalle)
       VALUES (?, ?, 'editar_miembro', ?)`,
      [id, firebase_uid, JSON.stringify({ uid, porcentaje, ingreso_declarado, contribucion_mensual })]
    );
    res.json({ message: 'Miembro actualizado' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// POST /shared-budgets/:id/expenses
app.post('/shared-budgets/:id/expenses', async (req, res) => {
  const { id } = req.params;
  const { descripcion, monto, pagado_por, regla_override, es_personal, firebase_uid_personal, fecha, firebase_uid } = req.body;
  if (!descripcion || monto == null || !pagado_por || !fecha || !firebase_uid) return res.status(400).json({ error: 'Datos incompletos' });
  const conn = await db.getConnection();
  await conn.beginTransaction();
  try {
    const [[budget]] = await conn.execute(
      `SELECT sb.regla_reparto FROM shared_budgets sb
       JOIN shared_budget_members m ON m.shared_budget_id = sb.id AND m.firebase_uid = ?
       WHERE sb.id = ? AND sb.estado = 'active'`,
      [firebase_uid, id]
    );
    if (!budget) { await conn.rollback(); conn.release(); return res.status(403).json({ error: 'No autorizado o presupuesto inactivo' }); }
    const [r] = await conn.execute(
      `INSERT INTO shared_expenses (shared_budget_id, descripcion, monto, pagado_por, regla_override, es_personal, firebase_uid_personal, fecha)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
      [id, descripcion, monto, pagado_por, regla_override || null, es_personal ? 1 : 0, firebase_uid_personal || null, fecha]
    );
    const expenseId = r.insertId;
    if (!es_personal) {
      const [members] = await conn.execute(
        `SELECT firebase_uid, porcentaje, ingreso_declarado FROM shared_budget_members WHERE shared_budget_id = ?`, [id]
      );
      const regla = regla_override || budget.regla_reparto;
      const splits = calcularSplits(parseFloat(monto), regla, members);
      for (const sp of splits) {
        await conn.execute(
          `INSERT INTO shared_expense_splits (expense_id, firebase_uid, monto_responsabilidad) VALUES (?, ?, ?)`,
          [expenseId, sp.firebase_uid, sp.monto_responsabilidad]
        );
      }
    }
    await conn.execute(
      `INSERT INTO shared_budget_activity_logs (shared_budget_id, actor_uid, accion, detalle)
       VALUES (?, ?, 'crear_gasto', ?)`,
      [id, firebase_uid, JSON.stringify({ descripcion, monto })]
    );
    await conn.commit();
    conn.release();
    res.status(201).json({ id: expenseId, message: 'Gasto creado' });
  } catch (err) {
    await conn.rollback();
    conn.release();
    res.status(500).json({ error: err.message });
  }
});

// GET /shared-budgets/:id/expenses
app.get('/shared-budgets/:id/expenses', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [[member]] = await db.execute(
      `SELECT id FROM shared_budget_members WHERE shared_budget_id = ? AND firebase_uid = ?`, [id, firebase_uid]
    );
    if (!member) return res.status(403).json({ error: 'No autorizado' });
    const [expenses] = await db.execute(
      `SELECT se.id, se.descripcion, se.monto, se.pagado_por, se.regla_override,
              se.es_personal, se.firebase_uid_personal, se.fecha, se.created_at,
              my_split.monto_responsabilidad AS mi_responsabilidad,
              CASE
                WHEN se.pagado_por = ? OR my_split.pagado = 1 THEN 1
                ELSE 0
              END AS mi_parte_pagada,
              CASE
                WHEN (se.es_personal = 0 AND se.pagado_por IS NOT NULL AND se.pagado_por != ? AND se.pagado_por != '')
                     OR other_split.pagado = 1
                THEN 1
                ELSE 0
              END AS su_parte_pagada
       FROM shared_expenses se
       LEFT JOIN shared_expense_splits my_split
         ON my_split.expense_id = se.id AND my_split.firebase_uid = ?
       LEFT JOIN shared_expense_splits other_split
         ON other_split.expense_id = se.id AND other_split.firebase_uid != ?
       WHERE se.shared_budget_id = ?
       ORDER BY se.fecha DESC, se.created_at DESC`,
      [firebase_uid, firebase_uid, firebase_uid, firebase_uid, id]
    );
    res.json(expenses);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// PATCH /shared-expenses/:expenseId
app.patch('/shared-expenses/:expenseId', async (req, res) => {
  const { expenseId } = req.params;
  const { descripcion, monto, firebase_uid } = req.body;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  const conn = await db.getConnection();
  await conn.beginTransaction();
  try {
    const [[expense]] = await conn.execute(
      `SELECT se.*, sb.regla_reparto FROM shared_expenses se
       JOIN shared_budgets sb ON sb.id = se.shared_budget_id
       JOIN shared_budget_members m ON m.shared_budget_id = sb.id AND m.firebase_uid = ?
       WHERE se.id = ?`,
      [firebase_uid, expenseId]
    );
    if (!expense) { await conn.rollback(); conn.release(); return res.status(403).json({ error: 'No autorizado' }); }
    await conn.execute(
      `UPDATE shared_expenses SET
        descripcion = COALESCE(?, descripcion),
        monto = COALESCE(?, monto)
       WHERE id = ?`,
      [descripcion || null, monto || null, expenseId]
    );
    if (monto != null && !expense.es_personal) {
      await conn.execute(`DELETE FROM shared_expense_splits WHERE expense_id = ?`, [expenseId]);
      const [members] = await conn.execute(
        `SELECT firebase_uid, porcentaje, ingreso_declarado FROM shared_budget_members WHERE shared_budget_id = ?`,
        [expense.shared_budget_id]
      );
      const regla = expense.regla_override || expense.regla_reparto;
      const splits = calcularSplits(parseFloat(monto), regla, members);
      for (const sp of splits) {
        await conn.execute(
          `INSERT INTO shared_expense_splits (expense_id, firebase_uid, monto_responsabilidad) VALUES (?, ?, ?)`,
          [expenseId, sp.firebase_uid, sp.monto_responsabilidad]
        );
      }
    }
    await conn.commit();
    conn.release();
    res.json({ message: 'Actualizado' });
  } catch (err) {
    await conn.rollback();
    conn.release();
    res.status(500).json({ error: err.message });
  }
});

// DELETE /shared-expenses/:expenseId
app.delete('/shared-expenses/:expenseId', async (req, res) => {
  const { expenseId } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [[expense]] = await db.execute(
      `SELECT se.id FROM shared_expenses se
       JOIN shared_budget_members m ON m.shared_budget_id = se.shared_budget_id AND m.firebase_uid = ?
       WHERE se.id = ?`,
      [firebase_uid, expenseId]
    );
    if (!expense) return res.status(403).json({ error: 'No autorizado' });
    await db.execute(`DELETE FROM shared_expenses WHERE id = ?`, [expenseId]);
    res.json({ message: 'Eliminado' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// POST /shared-expenses/:expenseId/confirm-payment
app.post('/shared-expenses/:expenseId/confirm-payment', async (req, res) => {
  const { expenseId } = req.params;
  const { firebase_uid } = req.body;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [[split]] = await db.execute(
      `SELECT ses.id FROM shared_expense_splits ses
       JOIN shared_expenses se ON se.id = ses.expense_id
       JOIN shared_budget_members m ON m.shared_budget_id = se.shared_budget_id AND m.firebase_uid = ?
       WHERE ses.expense_id = ? AND ses.firebase_uid = ?`,
      [firebase_uid, expenseId, firebase_uid]
    );
    if (!split) return res.status(403).json({ error: 'No autorizado o split no encontrado' });
    await db.execute(
      `UPDATE shared_expense_splits SET pagado = 1 WHERE expense_id = ? AND firebase_uid = ?`,
      [expenseId, firebase_uid]
    );
    res.json({ message: 'Pago confirmado' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// POST /shared-budgets/:id/request-delete
app.post('/shared-budgets/:id/request-delete', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.body;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [[member]] = await db.execute(
      `SELECT id FROM shared_budget_members WHERE shared_budget_id = ? AND firebase_uid = ?`,
      [id, firebase_uid]
    );
    if (!member) return res.status(403).json({ error: 'No autorizado' });
    await db.execute(
      `UPDATE shared_budgets SET delete_requested_by = ? WHERE id = ?`,
      [firebase_uid, id]
    );
    res.json({ message: 'Solicitud de eliminación enviada al co-dueño' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// POST /shared-budgets/:id/confirm-delete
// El co-dueño aprueba la eliminación del presupuesto compartido.
// Solo puede confirmarlo quien NO hizo la solicitud original.
app.post('/shared-budgets/:id/confirm-delete', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.body;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [[budget]] = await db.execute(
      `SELECT id, delete_requested_by FROM shared_budgets WHERE id = ?`,
      [id]
    );
    if (!budget) return res.status(404).json({ error: 'Presupuesto compartido no encontrado' });
    if (!budget.delete_requested_by) return res.status(400).json({ error: 'No hay solicitud de eliminación activa' });
    if (budget.delete_requested_by === firebase_uid) return res.status(403).json({ error: 'No puedes aprobar tu propia solicitud de eliminación' });

    const [[member]] = await db.execute(
      `SELECT id FROM shared_budget_members WHERE shared_budget_id = ? AND firebase_uid = ?`,
      [id, firebase_uid]
    );
    if (!member) return res.status(403).json({ error: 'No eres miembro de este presupuesto' });

    // Eliminar en cascada: miembros, movimientos, settlements, luego el presupuesto
    await db.execute(`DELETE FROM shared_budget_members WHERE shared_budget_id = ?`, [id]);
    await db.execute(`DELETE FROM shared_settlements WHERE shared_budget_id = ?`, [id]);
    await db.execute(`DELETE FROM shared_budgets WHERE id = ?`, [id]);

    res.json({ message: 'Presupuesto compartido eliminado correctamente' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// POST /shared-budgets/:id/settlements
app.post('/shared-budgets/:id/settlements', async (req, res) => {
  const { id } = req.params;
  const { receptor_uid, monto, nota, fecha, firebase_uid } = req.body;
  if (!receptor_uid || monto == null || !fecha || !firebase_uid) return res.status(400).json({ error: 'Datos incompletos' });
  try {
    const [[member]] = await db.execute(
      `SELECT id FROM shared_budget_members WHERE shared_budget_id = ? AND firebase_uid = ?`, [id, firebase_uid]
    );
    if (!member) return res.status(403).json({ error: 'No autorizado' });
    const [r] = await db.execute(
      `INSERT INTO shared_settlements (shared_budget_id, pagador_uid, receptor_uid, monto, nota, fecha)
       VALUES (?, ?, ?, ?, ?, ?)`,
      [id, firebase_uid, receptor_uid, monto, nota || null, fecha]
    );
    await db.execute(
      `INSERT INTO shared_budget_activity_logs (shared_budget_id, actor_uid, accion, detalle)
       VALUES (?, ?, 'registrar_pago', ?)`,
      [id, firebase_uid, JSON.stringify({ receptor_uid, monto })]
    );
    res.status(201).json({ id: r.insertId, message: 'Pago registrado' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// GET /shared-budgets/:id/settlements
app.get('/shared-budgets/:id/settlements', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [[member]] = await db.execute(
      `SELECT id FROM shared_budget_members WHERE shared_budget_id = ? AND firebase_uid = ?`, [id, firebase_uid]
    );
    if (!member) return res.status(403).json({ error: 'No autorizado' });
    const [rows] = await db.execute(
      `SELECT id, pagador_uid, receptor_uid, monto, nota, fecha, created_at
       FROM shared_settlements WHERE shared_budget_id = ? ORDER BY fecha DESC`,
      [id]
    );
    res.json(rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// =============================================================================
// MÓDULO: OFRECIMIENTO DE SERVICIOS (JOBS)
// =============================================================================

// GET /jobs — lista de trabajos con resumen financiero
app.get('/jobs', async (req, res) => {
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [jobs] = await db.execute(
      `SELECT j.*,
        COALESCE(SUM(cp.monto), 0) AS total_recibido,
        COALESCE(SUM(oe.monto), 0) AS total_gastos,
        COALESCE(SUM(tmp.monto), 0) AS total_pagos_colaboradores
       FROM jobs j
       LEFT JOIN customer_payments cp ON cp.job_id = j.id
       LEFT JOIN operational_expenses oe ON oe.job_id = j.id
       LEFT JOIN team_member_payments tmp ON tmp.job_id = j.id
       WHERE j.firebase_uid = ?
       GROUP BY j.id
       ORDER BY j.created_at DESC`,
      [firebase_uid]
    );
    res.json(jobs);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// POST /jobs — crear trabajo
app.post('/jobs', async (req, res) => {
  const { firebase_uid, nombre, descripcion, nombre_cliente, telefono_cliente, monto_total, estado, fecha_inicio, fecha_fin } = req.body;
  if (!firebase_uid || !nombre || monto_total === undefined) {
    return res.status(400).json({ error: 'firebase_uid, nombre y monto_total son requeridos' });
  }
  try {
    const [result] = await db.execute(
      `INSERT INTO jobs (firebase_uid, nombre, descripcion, nombre_cliente, telefono_cliente, monto_total, estado, fecha_inicio, fecha_fin)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [firebase_uid, nombre, descripcion || null, nombre_cliente || null, telefono_cliente || null,
       monto_total, estado || 'draft', fecha_inicio || null, fecha_fin || null]
    );
    await db.execute(
      `INSERT INTO job_activity_logs (job_id, firebase_uid, accion, detalle) VALUES (?, ?, ?, ?)`,
      [result.insertId, firebase_uid, 'created', `Trabajo "${nombre}" creado`]
    );
    const [[job]] = await db.execute('SELECT * FROM jobs WHERE id = ?', [result.insertId]);
    res.status(201).json(job);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// GET /jobs/:id — detalle completo
app.get('/jobs/:id', async (req, res) => {
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [[job]] = await db.execute('SELECT * FROM jobs WHERE id = ? AND firebase_uid = ?', [req.params.id, firebase_uid]);
    if (!job) return res.status(404).json({ error: 'Trabajo no encontrado' });

    const [teamMembers] = await db.execute(
      'SELECT * FROM job_team_members WHERE job_id = ? ORDER BY created_at ASC', [req.params.id]
    );
    const [customerPayments] = await db.execute(
      'SELECT * FROM customer_payments WHERE job_id = ? ORDER BY fecha_pago DESC', [req.params.id]
    );
    const [expenses] = await db.execute(
      'SELECT * FROM operational_expenses WHERE job_id = ? ORDER BY fecha_gasto DESC', [req.params.id]
    );
    const [teamPayments] = await db.execute(
      'SELECT tmp.*, jtm.nombre AS nombre_colaborador FROM team_member_payments tmp JOIN job_team_members jtm ON jtm.id = tmp.team_member_id WHERE tmp.job_id = ? ORDER BY tmp.fecha_pago DESC',
      [req.params.id]
    );

    const totalRecibido = customerPayments.reduce((s, p) => s + parseFloat(p.monto), 0);
    const totalGastos = expenses.reduce((s, e) => s + parseFloat(e.monto), 0);
    const totalPagosColab = teamPayments.reduce((s, p) => s + parseFloat(p.monto), 0);
    const utilidadNeta = totalRecibido - totalGastos - totalPagosColab;
    const margen = totalRecibido > 0 ? (utilidadNeta / totalRecibido) * 100 : 0;

    res.json({
      job,
      teamMembers,
      customerPayments,
      expenses,
      teamPayments,
      resumen: {
        monto_total: parseFloat(job.monto_total),
        total_recibido: totalRecibido,
        saldo_pendiente: parseFloat(job.monto_total) - totalRecibido,
        total_gastos: totalGastos,
        total_pagos_colaboradores: totalPagosColab,
        utilidad_neta: utilidadNeta,
        margen: parseFloat(margen.toFixed(2)),
      }
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// PUT /jobs/:id — editar trabajo
app.put('/jobs/:id', async (req, res) => {
  const { firebase_uid, nombre, descripcion, nombre_cliente, telefono_cliente, monto_total, estado, payment_status, fecha_inicio, fecha_fin } = req.body;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [[job]] = await db.execute('SELECT id FROM jobs WHERE id = ? AND firebase_uid = ?', [req.params.id, firebase_uid]);
    if (!job) return res.status(404).json({ error: 'Trabajo no encontrado' });

    await db.execute(
      `UPDATE jobs SET nombre=COALESCE(?,nombre), descripcion=COALESCE(?,descripcion),
       nombre_cliente=COALESCE(?,nombre_cliente), telefono_cliente=COALESCE(?,telefono_cliente),
       monto_total=COALESCE(?,monto_total), estado=COALESCE(?,estado),
       payment_status=COALESCE(?,payment_status), fecha_inicio=COALESCE(?,fecha_inicio),
       fecha_fin=COALESCE(?,fecha_fin) WHERE id = ?`,
      [nombre||null, descripcion||null, nombre_cliente||null, telefono_cliente||null,
       monto_total||null, estado||null, payment_status||null, fecha_inicio||null, fecha_fin||null, req.params.id]
    );
    if (estado) {
      await db.execute(
        `INSERT INTO job_activity_logs (job_id, firebase_uid, accion, detalle) VALUES (?, ?, ?, ?)`,
        [req.params.id, firebase_uid, 'status_change', `Estado cambiado a "${estado}"`]
      );
    }
    const [[updated]] = await db.execute('SELECT * FROM jobs WHERE id = ?', [req.params.id]);
    res.json(updated);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// DELETE /jobs/:id — eliminar trabajo
app.delete('/jobs/:id', async (req, res) => {
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [[job]] = await db.execute('SELECT id FROM jobs WHERE id = ? AND firebase_uid = ?', [req.params.id, firebase_uid]);
    if (!job) return res.status(404).json({ error: 'Trabajo no encontrado' });
    await db.execute('DELETE FROM jobs WHERE id = ?', [req.params.id]);
    res.json({ ok: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// POST /jobs/:id/team-members — agregar colaborador
app.post('/jobs/:id/team-members', async (req, res) => {
  const { firebase_uid, nombre, tipo_compensacion, monto_acordado, porcentaje, horas_trabajadas, tarifa_hora } = req.body;
  if (!firebase_uid || !nombre || !tipo_compensacion) {
    return res.status(400).json({ error: 'firebase_uid, nombre y tipo_compensacion son requeridos' });
  }
  try {
    // Validar que la suma de porcentajes de colaboradores no supere el 100%
    if (tipo_compensacion === 'porcentual') {
      const pct = parseFloat(porcentaje) || 0;
      if (pct <= 0) return res.status(400).json({ error: 'El porcentaje debe ser mayor a 0' });
      const [[{ total_pct }]] = await db.execute(
        `SELECT COALESCE(SUM(porcentaje), 0) AS total_pct FROM job_team_members WHERE job_id = ? AND tipo_compensacion = 'porcentual'`,
        [req.params.id]
      );
      if (parseFloat(total_pct) + pct > 100) {
        return res.status(400).json({
          error: `Los porcentajes sumarían ${(parseFloat(total_pct) + pct).toFixed(1)}%. El total no puede superar 100%.`
        });
      }
    }

    let calculado = 0;
    if (tipo_compensacion === 'fijo') calculado = parseFloat(monto_acordado) || 0;
    else if (tipo_compensacion === 'por_horas') calculado = (parseFloat(horas_trabajadas) || 0) * (parseFloat(tarifa_hora) || 0);

    const [result] = await db.execute(
      `INSERT INTO job_team_members (job_id, firebase_uid, nombre, tipo_compensacion, monto_acordado, porcentaje, horas_trabajadas, tarifa_hora, monto_calculado)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [req.params.id, firebase_uid, nombre, tipo_compensacion,
       monto_acordado || 0, porcentaje || 0, horas_trabajadas || 0, tarifa_hora || 0, calculado]
    );
    const [[member]] = await db.execute('SELECT * FROM job_team_members WHERE id = ?', [result.insertId]);
    res.status(201).json(member);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// DELETE /jobs/:id/team-members/:mid — eliminar colaborador
app.delete('/jobs/:id/team-members/:mid', async (req, res) => {
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    await db.execute('DELETE FROM job_team_members WHERE id = ? AND job_id = ?', [req.params.mid, req.params.id]);
    res.json({ ok: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// POST /jobs/:id/customer-payments — registrar pago del cliente
app.post('/jobs/:id/customer-payments', async (req, res) => {
  const { firebase_uid, monto, tipo, nota } = req.body;
  if (!firebase_uid || !monto) return res.status(400).json({ error: 'firebase_uid y monto son requeridos' });
  try {
    const [result] = await db.execute(
      `INSERT INTO customer_payments (job_id, firebase_uid, monto, tipo, nota) VALUES (?, ?, ?, ?, ?)`,
      [req.params.id, firebase_uid, monto, tipo || 'pago_parcial', nota || null]
    );
    // Recalcular payment_status
    const [[{ total_recibido }]] = await db.execute(
      'SELECT COALESCE(SUM(monto),0) AS total_recibido FROM customer_payments WHERE job_id = ?', [req.params.id]
    );
    const [[job]] = await db.execute('SELECT monto_total FROM jobs WHERE id = ?', [req.params.id]);
    const newStatus = parseFloat(total_recibido) >= parseFloat(job.monto_total) ? 'paid'
      : parseFloat(total_recibido) > 0 ? 'partially_paid' : 'pending';
    await db.execute('UPDATE jobs SET payment_status = ? WHERE id = ?', [newStatus, req.params.id]);
    await db.execute(
      `INSERT INTO job_activity_logs (job_id, firebase_uid, accion, detalle) VALUES (?, ?, ?, ?)`,
      [req.params.id, firebase_uid, 'customer_payment', `Pago cliente: $${monto} (${tipo || 'pago_parcial'})`]
    );
    const [[payment]] = await db.execute('SELECT * FROM customer_payments WHERE id = ?', [result.insertId]);
    res.status(201).json(payment);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// DELETE /jobs/:id/customer-payments/:pid — eliminar pago del cliente
app.delete('/jobs/:id/customer-payments/:pid', async (req, res) => {
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    await db.execute('DELETE FROM customer_payments WHERE id = ? AND job_id = ?', [req.params.pid, req.params.id]);
    res.json({ ok: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// POST /jobs/:id/expenses — registrar gasto operativo
app.post('/jobs/:id/expenses', async (req, res) => {
  const { firebase_uid, descripcion, monto, categoria } = req.body;
  if (!firebase_uid || !descripcion || !monto) {
    return res.status(400).json({ error: 'firebase_uid, descripcion y monto son requeridos' });
  }
  try {
    const [result] = await db.execute(
      `INSERT INTO operational_expenses (job_id, firebase_uid, descripcion, monto, categoria) VALUES (?, ?, ?, ?, ?)`,
      [req.params.id, firebase_uid, descripcion, monto, categoria || null]
    );
    await db.execute(
      `INSERT INTO job_activity_logs (job_id, firebase_uid, accion, detalle) VALUES (?, ?, ?, ?)`,
      [req.params.id, firebase_uid, 'expense', `Gasto: ${descripcion} $${monto}`]
    );
    const [[expense]] = await db.execute('SELECT * FROM operational_expenses WHERE id = ?', [result.insertId]);
    res.status(201).json(expense);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// DELETE /jobs/:id/expenses/:eid — eliminar gasto
app.delete('/jobs/:id/expenses/:eid', async (req, res) => {
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    await db.execute('DELETE FROM operational_expenses WHERE id = ? AND job_id = ?', [req.params.eid, req.params.id]);
    res.json({ ok: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// POST /jobs/:id/team-member-payments — registrar pago a colaborador
app.post('/jobs/:id/team-member-payments', async (req, res) => {
  const { firebase_uid, team_member_id, monto, nota } = req.body;
  if (!firebase_uid || !team_member_id || !monto) {
    return res.status(400).json({ error: 'firebase_uid, team_member_id y monto son requeridos' });
  }
  try {
    // Calcular advertencia si el colaborador es porcentual y se supera lo acordado
    let advertencia = null;
    const [[miembro]] = await db.execute(
      `SELECT jtm.tipo_compensacion, jtm.porcentaje,
              COALESCE(SUM(tmp.monto), 0) AS ya_pagado
       FROM job_team_members jtm
       LEFT JOIN team_member_payments tmp ON tmp.team_member_id = jtm.id
       WHERE jtm.id = ? GROUP BY jtm.id`,
      [team_member_id]
    );
    if (miembro && miembro.tipo_compensacion === 'porcentual' && miembro.porcentaje > 0) {
      const [[{ rec }]] = await db.execute(
        `SELECT COALESCE(SUM(monto),0) AS rec FROM customer_payments WHERE job_id = ?`, [req.params.id]
      );
      const [[{ gas }]] = await db.execute(
        `SELECT COALESCE(SUM(monto),0) AS gas FROM operational_expenses WHERE job_id = ?`, [req.params.id]
      );
      const utilidad = parseFloat(rec) - parseFloat(gas);
      const sugerido = parseFloat((utilidad * miembro.porcentaje / 100).toFixed(2));
      const totalConNuevo = parseFloat(miembro.ya_pagado) + parseFloat(monto);
      if (totalConNuevo > sugerido && sugerido > 0) {
        advertencia = `El total pagado ($${totalConNuevo.toFixed(2)}) supera el ${miembro.porcentaje}% acordado ($${sugerido.toFixed(2)}).`;
      }
    }

    const [result] = await db.execute(
      `INSERT INTO team_member_payments (job_id, team_member_id, firebase_uid, monto, nota) VALUES (?, ?, ?, ?, ?)`,
      [req.params.id, team_member_id, firebase_uid, monto, nota || null]
    );
    await db.execute(
      `INSERT INTO job_activity_logs (job_id, firebase_uid, accion, detalle) VALUES (?, ?, ?, ?)`,
      [req.params.id, firebase_uid, 'team_payment', `Pago colaborador: $${monto}`]
    );
    const [[payment]] = await db.execute(
      `SELECT tmp.*, jtm.nombre AS nombre_colaborador FROM team_member_payments tmp
       JOIN job_team_members jtm ON jtm.id = tmp.team_member_id WHERE tmp.id = ?`,
      [result.insertId]
    );
    res.status(201).json({ ...payment, advertencia });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// DELETE /jobs/:id/team-member-payments/:pid — eliminar pago a colaborador
app.delete('/jobs/:id/team-member-payments/:pid', async (req, res) => {
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [[payment]] = await db.execute(
      'SELECT tmp.* FROM team_member_payments tmp JOIN jobs j ON j.id = tmp.job_id WHERE tmp.id = ? AND j.firebase_uid = ?',
      [req.params.pid, firebase_uid]
    );
    if (!payment) return res.status(404).json({ error: 'Pago no encontrado' });
    await db.execute('DELETE FROM team_member_payments WHERE id = ?', [req.params.pid]);
    res.json({ message: 'Pago eliminado' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// GET /jobs/:id/financial-summary — resumen financiero
app.get('/jobs/:id/financial-summary', async (req, res) => {
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [[job]] = await db.execute('SELECT * FROM jobs WHERE id = ? AND firebase_uid = ?', [req.params.id, firebase_uid]);
    if (!job) return res.status(404).json({ error: 'Trabajo no encontrado' });

    const [[{ total_recibido }]] = await db.execute(
      'SELECT COALESCE(SUM(monto),0) AS total_recibido FROM customer_payments WHERE job_id = ?', [req.params.id]
    );
    const [[{ total_gastos }]] = await db.execute(
      'SELECT COALESCE(SUM(monto),0) AS total_gastos FROM operational_expenses WHERE job_id = ?', [req.params.id]
    );
    const [[{ total_pagos_colab }]] = await db.execute(
      'SELECT COALESCE(SUM(monto),0) AS total_pagos_colab FROM team_member_payments WHERE job_id = ?', [req.params.id]
    );

    const rec = parseFloat(total_recibido);
    const gas = parseFloat(total_gastos);
    const cob = parseFloat(total_pagos_colab);
    const utilidad = rec - gas - cob;
    const margen = rec > 0 ? (utilidad / rec) * 100 : 0;

    // Sugerencia de pagos para colaboradores con compensación porcentual
    const [teamMembers] = await db.execute(
      `SELECT jtm.id, jtm.nombre, jtm.tipo_compensacion, jtm.porcentaje,
              COALESCE(SUM(tmp.monto), 0) AS ya_pagado
       FROM job_team_members jtm
       LEFT JOIN team_member_payments tmp ON tmp.team_member_id = jtm.id
       WHERE jtm.job_id = ?
       GROUP BY jtm.id`,
      [req.params.id]
    );
    const utilidadBruta = rec - gas; // antes de pagar colaboradores
    const pagosSugeridos = teamMembers
      .filter(m => m.tipo_compensacion === 'porcentual' && m.porcentaje > 0)
      .map(m => ({
        id: m.id,
        nombre: m.nombre,
        porcentaje: m.porcentaje,
        pago_sugerido: parseFloat((utilidadBruta * m.porcentaje / 100).toFixed(2)),
        ya_pagado: parseFloat(m.ya_pagado),
        pendiente: parseFloat((utilidadBruta * m.porcentaje / 100 - parseFloat(m.ya_pagado)).toFixed(2)),
      }));

    res.json({
      monto_total: parseFloat(job.monto_total),
      total_recibido: rec,
      saldo_pendiente: parseFloat(job.monto_total) - rec,
      total_gastos: gas,
      total_pagos_colaboradores: cob,
      utilidad_neta: utilidad,
      margen: parseFloat(margen.toFixed(2)),
      pagos_sugeridos_colaboradores: pagosSugeridos,
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// =============================================================================
// MÓDULO: GUSTITOS
// Un Gustito es una compra pequeña, espontánea o personal, registrada para
// dar conciencia financiera sin generar culpa psicológica.
// Afecta el disponible del presupuesto (ver GET /presupuestos/:id/detalle).
// Preparado para integración futura con facturas QR (scanned_invoice_id).
// =============================================================================

/**
 * POST /gustitos
 * Registra un nuevo Gustito asociado a un presupuesto.
 */
app.post('/gustitos', async (req, res) => {
  const {
    user_id, budget_id, name, amount, spent_at,
    description = null, merchant = null, category = null,
    emotion_tag = null, source = 'manual', scanned_invoice_id = null
  } = req.body;

  if (!user_id || !budget_id || !name || amount == null || !spent_at)
    return res.status(400).json({ error: 'Datos incompletos: user_id, budget_id, name, amount y spent_at son requeridos' });

  if (Number(amount) <= 0)
    return res.status(400).json({ error: 'El monto debe ser mayor a 0' });

  try {
    // Verificar que el presupuesto pertenece al usuario
    const [[presupuesto]] = await db.execute(
      `SELECT id FROM presupuestos WHERE id = ? AND firebase_uid = ?`,
      [budget_id, user_id]
    );
    if (!presupuesto) return res.status(404).json({ error: 'Presupuesto no encontrado' });

    const spentAtStr = spent_at.split('T')[0];

    const [result] = await db.execute(
      `INSERT INTO gustitos
       (user_id, budget_id, scanned_invoice_id, name, description, merchant, amount, category, emotion_tag, source, spent_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [user_id, budget_id, scanned_invoice_id, name, description, merchant,
       Number(amount), category, emotion_tag, source, spentAtStr]
    );

    const [[gustito]] = await db.execute(
      `SELECT * FROM gustitos WHERE id = ?`, [result.insertId]
    );
    res.status(201).json(gustito);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * GET /gustitos?firebase_uid=
 * Lista todos los Gustitos del usuario, más recientes primero.
 */
app.get('/gustitos', async (req, res) => {
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid es requerido' });
  try {
    const [gustitos] = await db.execute(
      `SELECT * FROM gustitos WHERE user_id = ? AND deleted_at IS NULL ORDER BY spent_at DESC, id DESC`,
      [firebase_uid]
    );
    res.json(gustitos);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * GET /gustitos/:id?firebase_uid=
 * Detalle de un Gustito específico.
 */
app.get('/gustitos/:id', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid es requerido' });
  try {
    const [[gustito]] = await db.execute(
      `SELECT * FROM gustitos WHERE id = ? AND user_id = ? AND deleted_at IS NULL`,
      [id, firebase_uid]
    );
    if (!gustito) return res.status(404).json({ error: 'Gustito no encontrado' });
    res.json(gustito);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * PATCH /gustitos/:id
 * Actualiza campos de un Gustito. Solo se actualizan los campos enviados.
 */
app.patch('/gustitos/:id', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid, name, amount, description, merchant, category, emotion_tag, spent_at } = req.body;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid es requerido' });

  try {
    const [[gustito]] = await db.execute(
      `SELECT id FROM gustitos WHERE id = ? AND user_id = ? AND deleted_at IS NULL`,
      [id, firebase_uid]
    );
    if (!gustito) return res.status(404).json({ error: 'Gustito no encontrado' });

    if (amount != null && Number(amount) <= 0)
      return res.status(400).json({ error: 'El monto debe ser mayor a 0' });

    const campos = [];
    const valores = [];

    if (name       != null) { campos.push('name = ?');        valores.push(name); }
    if (amount     != null) { campos.push('amount = ?');      valores.push(Number(amount)); }
    if (description != null){ campos.push('description = ?'); valores.push(description); }
    if (merchant   != null) { campos.push('merchant = ?');    valores.push(merchant); }
    if (category   != null) { campos.push('category = ?');    valores.push(category); }
    if (emotion_tag != null){ campos.push('emotion_tag = ?'); valores.push(emotion_tag); }
    if (spent_at   != null) { campos.push('spent_at = ?');    valores.push(spent_at.split('T')[0]); }

    if (campos.length === 0) return res.status(400).json({ error: 'No hay campos para actualizar' });

    campos.push('updated_at = NOW()');
    valores.push(id, firebase_uid);

    await db.execute(
      `UPDATE gustitos SET ${campos.join(', ')} WHERE id = ? AND user_id = ?`,
      valores
    );

    const [[updated]] = await db.execute(
      `SELECT * FROM gustitos WHERE id = ?`, [id]
    );
    res.json(updated);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * DELETE /gustitos/:id?firebase_uid=
 * Soft delete de un Gustito (deleted_at = NOW()).
 */
app.delete('/gustitos/:id', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid es requerido' });
  try {
    const [[gustito]] = await db.execute(
      `SELECT id FROM gustitos WHERE id = ? AND user_id = ? AND deleted_at IS NULL`,
      [id, firebase_uid]
    );
    if (!gustito) return res.status(404).json({ error: 'Gustito no encontrado' });

    await db.execute(
      `UPDATE gustitos SET deleted_at = NOW() WHERE id = ? AND user_id = ?`,
      [id, firebase_uid]
    );
    res.json({ message: 'Gustito eliminado correctamente' });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * GET /presupuestos/:budgetId/gustitos?firebase_uid=
 * Lista los Gustitos de un presupuesto específico.
 */
app.get('/presupuestos/:budgetId/gustitos', async (req, res) => {
  const { budgetId } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid es requerido' });
  try {
    const [[presupuesto]] = await db.execute(
      `SELECT id FROM presupuestos WHERE id = ? AND firebase_uid = ?`,
      [budgetId, firebase_uid]
    );
    if (!presupuesto) return res.status(404).json({ error: 'Presupuesto no encontrado' });

    const [gustitos] = await db.execute(
      `SELECT * FROM gustitos
       WHERE budget_id = ? AND user_id = ? AND deleted_at IS NULL
       ORDER BY spent_at DESC, id DESC`,
      [budgetId, firebase_uid]
    );
    res.json(gustitos);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * GET /presupuestos/:budgetId/gustitos/summary?firebase_uid=
 * Resumen estadístico de Gustitos para mostrar en el detalle del presupuesto.
 */
app.get('/presupuestos/:budgetId/gustitos/summary', async (req, res) => {
  const { budgetId } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid es requerido' });
  try {
    const [[presupuesto]] = await db.execute(
      `SELECT id FROM presupuestos WHERE id = ? AND firebase_uid = ?`,
      [budgetId, firebase_uid]
    );
    if (!presupuesto) return res.status(404).json({ error: 'Presupuesto no encontrado' });

    const [[stats]] = await db.execute(
      `SELECT
         COALESCE(SUM(amount), 0)   AS total,
         COUNT(*)                   AS count,
         COALESCE(AVG(amount), 0)   AS promedio
       FROM gustitos
       WHERE budget_id = ? AND user_id = ? AND deleted_at IS NULL`,
      [budgetId, firebase_uid]
    );

    // Categoría más frecuente
    const [[catRow]] = await db.execute(
      `SELECT category AS categoria_frecuente, COUNT(*) AS freq
       FROM gustitos
       WHERE budget_id = ? AND user_id = ? AND deleted_at IS NULL AND category IS NOT NULL
       GROUP BY category
       ORDER BY freq DESC
       LIMIT 1`,
      [budgetId, firebase_uid]
    );

    // Día con más Gustitos
    const [[diaRow]] = await db.execute(
      `SELECT DATE(spent_at) AS dia_con_mas, COUNT(*) AS freq
       FROM gustitos
       WHERE budget_id = ? AND user_id = ? AND deleted_at IS NULL
       GROUP BY DATE(spent_at)
       ORDER BY freq DESC
       LIMIT 1`,
      [budgetId, firebase_uid]
    );

    // Últimos 3 registros
    const [ultimos] = await db.execute(
      `SELECT id, name, merchant, amount, category, emotion_tag, spent_at
       FROM gustitos
       WHERE budget_id = ? AND user_id = ? AND deleted_at IS NULL
       ORDER BY spent_at DESC, id DESC
       LIMIT 3`,
      [budgetId, firebase_uid]
    );

    res.json({
      total:               Math.round(Number(stats.total) * 100) / 100,
      count:               Number(stats.count),
      promedio:            Math.round(Number(stats.promedio) * 100) / 100,
      categoria_frecuente: catRow ? catRow.categoria_frecuente : null,
      dia_con_mas:         diaRow ? diaRow.dia_con_mas : null,
      ultimos,
    });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: error.message });
  }
});

// =============================================================================
// INVOICE SCANNER — FACTURAS ESCANEADAS QR DGI PANAMA
// =============================================================================

// Helper: recalcula y actualiza el status de una factura según lo asignado
async function recalcularStatusFactura(invoiceId) {
  const [[invoice]] = await db.query(
    'SELECT total_amount FROM scanned_invoices WHERE id = ?',
    [invoiceId]
  );
  if (!invoice) return;
  const [[agg]] = await db.query(
    'SELECT COALESCE(SUM(amount_assigned),0) AS total_assigned FROM scanned_invoice_assignments WHERE invoice_id = ?',
    [invoiceId]
  );
  const total = parseFloat(invoice.total_amount) || 0;
  const assigned = parseFloat(agg.total_assigned) || 0;
  let status = 'unassigned';
  if (assigned >= total && total > 0) status = 'assigned';
  else if (assigned > 0) status = 'partially_assigned';
  await db.query('UPDATE scanned_invoices SET status = ?, updated_at = NOW() WHERE id = ?', [status, invoiceId]);
}

// Helper: parsea el QR string DGI Panama para extraer CUFE limpio y URL de consulta
// QR DGI formato: https://dgi-fep.mef.gob.pa/Consultas/FacturasPorCUFE/FE01200001...
// CUFE Panama: 66 chars alfanuméricos + guiones + T (NO es hex puro)
function parsearQrFactura(qrContent) {
  const q = qrContent.trim();

  // Extraer CUFE del path /FacturasPorCUFE/{CUFE}
  const pathMatch = q.match(/FacturasPorCUFE\/([A-Z0-9][A-Z0-9\-]{40,70})/i);
  if (pathMatch) {
    const cufe = pathMatch[1];
    const url_fiscal = `https://dgi-fep.mef.gob.pa/Consultas/FacturasPorCUFE/${cufe}`;
    return { url_fiscal, cufe };
  }

  // CUFE suelto (sin URL): FE + dígitos + RUC + T + ...
  const cufeMatch = q.match(/\b(FE[0-9]{2}[12][A-Z0-9\-]{20,60}T[A-Z0-9]{20,50})\b/i);
  if (cufeMatch) {
    const cufe = cufeMatch[1];
    const url_fiscal = `https://dgi-fep.mef.gob.pa/Consultas/FacturasPorCUFE/${cufe}`;
    return { url_fiscal, cufe };
  }

  // Fallback: usar contenido completo como identificador
  const urlMatch = q.match(/https?:\/\/[^\s]+/i);
  return {
    url_fiscal: urlMatch ? urlMatch[0] : null,
    cufe: q.substring(0, 500),
  };
}

// Helper: obtiene datos de la DGI usando el HTML real de /Consultas/FacturasPorCUFE/{CUFE}
// Estructura HTML verificada con factura real DGI Panama (ACE INTERNAT, 2026-05-06)
async function consultarDgi(urlFiscal) {
  if (!urlFiscal) return null;
  try {
    const resp = await fetch(urlFiscal, {
      headers: { 'User-Agent': 'Mozilla/5.0' },
      timeout: 12000,
    });
    if (!resp.ok) return null;
    const html = await resp.text();

    // Extrae valor de un par <dt class="small">LABEL</dt><dd>VALOR</dd>
    const dtdd = (label) => {
      const r = html.match(new RegExp(
        '<dt[^>]*>\\s*' + label.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '\\s*<\\/dt><dd>([^<]*)<\\/dd>', 'i'
      ));
      return r ? r[1].trim() : null;
    };

    // Campos del EMISOR
    const merchantName = dtdd('NOMBRE');
    const ruc          = dtdd('RUC');

    // Número de factura: <h5>\n No. 0000108630</h5>
    const numMatch = html.match(/No\.\s+(\d{7,12})/);

    // Fecha de emisión: primera <h5> con dd/mm/yyyy (ej: <h5>06/05/2026 18:06:25</h5>)
    const fechaMatch = html.match(/<h5>(\d{2}\/\d{2}\/\d{4})/);

    // Totales del tfoot DGI:
    //   Valor Total: <div style="width: 100px;display: inline-block;">4.00</div>
    //   ITBMS Total: <div style="width: 100px;display: inline-block;">0.26</div>
    const totalMatch = html.match(/Valor Total:\s*<div[^>]*>([\d\.]+)<\/div>/i);
    const taxMatch   = html.match(/ITBMS Total:\s*<div[^>]*>([\d\.]+)<\/div>/i);

    // Ítems del detalle: filas de la tabla
    const itemsRaw = [];
    const rowRegex = /<tr>[\s\S]*?<td[^>]*data-title="Descripci[oó]n"[^>]*>([\s\S]*?)<\/td>[\s\S]*?<td[^>]*data-title="Cantidad"[^>]*>([\d\.]+)<\/td>[\s\S]*?<td[^>]*data-title="Precio"[^>]*>([\d\.]+)<\/td>[\s\S]*?<td[^>]*data-title="Descuento"[^>]*>([\d\.]+)<\/td>[\s\S]*?<td[^>]*data-title="Monto"[^>]*>([\d\.]+)<\/td>[\s\S]*?<td[^>]*data-title="Impuesto"[^>]*>([\d\.]+)<\/td>[\s\S]*?<td[^>]*data-title="Total"[^>]*>([\d\.]+)<\/td>/gi;
    let rowMatch;
    while ((rowMatch = rowRegex.exec(html)) !== null) {
      itemsRaw.push({
        descripcion:     rowMatch[1].trim(),
        cantidad:        parseFloat(rowMatch[2]),
        precio_unitario: parseFloat(rowMatch[3]),
        subtotal:        parseFloat(rowMatch[5]),
        impuesto:        parseFloat(rowMatch[6]),
      });
    }

    const parseFechaDDMMYYYY = (s) => {
      if (!s) return null;
      const [d, m, y] = s.split('/');
      return `${y}-${m.padStart(2,'0')}-${d.padStart(2,'0')}`;
    };

    const total = totalMatch ? parseFloat(totalMatch[1]) : null;
    const tax   = taxMatch   ? parseFloat(taxMatch[1])   : null;

    return {
      merchant_name:    merchantName || null,
      merchant_ruc:     ruc || null,
      numero_factura:   numMatch ? numMatch[1] : null,
      total_amount:     total,
      tax_amount:       tax,
      subtotal_amount:  (total != null && tax != null) ? Math.round((total - tax) * 100) / 100 : null,
      invoice_date:     parseFechaDDMMYYYY(fechaMatch ? fechaMatch[1] : null),
      dgi_validated:    1,
      dgi_raw_response: html.substring(0, 4000),
      items:            itemsRaw,
    };
  } catch (_) {
    return null;
  }
}

// POST /invoice-scanner/process
app.post('/invoice-scanner/process', async (req, res) => {
  const { firebase_uid, qr_content } = req.body;
  if (!firebase_uid || !qr_content) {
    return res.status(400).json({ error: 'firebase_uid y qr_content son requeridos' });
  }
  try {
    const { url_fiscal, cufe } = parsearQrFactura(qr_content);

    // Verificar duplicado
    const [[existing]] = await db.query(
      `SELECT si.*,
        (SELECT COALESCE(SUM(amount_assigned),0) FROM scanned_invoice_assignments WHERE invoice_id = si.id) AS total_assigned
       FROM scanned_invoices si WHERE si.firebase_uid = ? AND si.cufe = ?`,
      [firebase_uid, cufe]
    );
    if (existing) {
      const items = await db.query('SELECT * FROM scanned_invoice_items WHERE invoice_id = ?', [existing.id]);
      return res.json({ duplicate: true, invoice: { ...existing, items: items[0] } });
    }

    // Consultar DGI
    const dgiData = await consultarDgi(url_fiscal);

    // Insertar factura
    const [result] = await db.query(
      `INSERT INTO scanned_invoices
        (firebase_uid, cufe, qr_raw, url_fiscal, numero_factura, merchant_name, merchant_ruc,
         total_amount, tax_amount, subtotal_amount, invoice_date, status, dgi_validated, dgi_raw_response)
       VALUES (?,?,?,?,?,?,?,?,?,?,?,'pending',?,?)`,
      [
        firebase_uid, cufe, qr_content, url_fiscal,
        dgiData?.numero_factura  || null,
        dgiData?.merchant_name   || null,
        dgiData?.merchant_ruc    || null,
        dgiData?.total_amount    || null,
        dgiData?.tax_amount      || null,
        dgiData?.subtotal_amount || null,
        dgiData?.invoice_date    || null,
        dgiData?.dgi_validated   || 0,
        dgiData?.dgi_raw_response|| null,
      ]
    );
    const invoiceId = result.insertId;

    // Insertar ítems obtenidos de DGI
    const dgiItems = dgiData?.items || [];
    if (dgiItems.length > 0) {
      const itemVals = dgiItems.map(it =>
        [invoiceId, it.descripcion, it.cantidad, it.precio_unitario, it.subtotal, it.impuesto]
      );
      await db.query(
        `INSERT INTO scanned_invoice_items (invoice_id, descripcion, cantidad, precio_unitario, subtotal, impuesto) VALUES ?`,
        [itemVals]
      );
    }

    await db.query(
      `INSERT INTO invoice_activity_logs (invoice_id, firebase_uid, action, details) VALUES (?,?,?,?)`,
      [invoiceId, firebase_uid, 'scanned', JSON.stringify({ url_fiscal, cufe, dgi_validated: dgiData?.dgi_validated || 0 })]
    );

    const [[invoice]] = await db.query('SELECT * FROM scanned_invoices WHERE id = ?', [invoiceId]);
    const [items]     = await db.query('SELECT * FROM scanned_invoice_items WHERE invoice_id = ?', [invoiceId]);
    res.status(201).json({ duplicate: false, invoice: { ...invoice, items } });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: error.message });
  }
});

// GET /invoice-scanner/invoices
app.get('/invoice-scanner/invoices', async (req, res) => {
  const { firebase_uid, status, date_from, date_to, merchant } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    let where = 'WHERE si.firebase_uid = ?';
    const params = [firebase_uid];
    if (status)    { where += ' AND si.status = ?';         params.push(status); }
    if (date_from) { where += ' AND si.invoice_date >= ?';  params.push(date_from); }
    if (date_to)   { where += ' AND si.invoice_date <= ?';  params.push(date_to); }
    if (merchant)  { where += ' AND si.merchant_name LIKE ?'; params.push(`%${merchant}%`); }

    const [rows] = await db.query(
      `SELECT si.*,
        COALESCE(SUM(sia.amount_assigned),0) AS total_assigned,
        COUNT(sia.id) AS num_assignments
       FROM scanned_invoices si
       LEFT JOIN scanned_invoice_assignments sia ON sia.invoice_id = si.id
       ${where}
       GROUP BY si.id
       ORDER BY si.created_at DESC`,
      params
    );
    res.json(rows.map(r => ({
      ...r,
      total_assigned:    Math.round(Number(r.total_assigned) * 100) / 100,
      remaining:         Math.round((Number(r.total_amount || 0) - Number(r.total_assigned)) * 100) / 100,
      num_assignments:   Number(r.num_assignments),
    })));
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: error.message });
  }
});

// GET /invoice-scanner/invoices/:id
app.get('/invoice-scanner/invoices/:id', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [[invoice]] = await db.query(
      'SELECT * FROM scanned_invoices WHERE id = ? AND firebase_uid = ?',
      [id, firebase_uid]
    );
    if (!invoice) return res.status(404).json({ error: 'Factura no encontrada' });

    const [items]       = await db.query('SELECT * FROM scanned_invoice_items WHERE invoice_id = ?', [id]);
    const [assignments] = await db.query(
      'SELECT * FROM scanned_invoice_assignments WHERE invoice_id = ? ORDER BY created_at DESC',
      [id]
    );
    const [[agg]] = await db.query(
      'SELECT COALESCE(SUM(amount_assigned),0) AS total_assigned FROM scanned_invoice_assignments WHERE invoice_id = ?',
      [id]
    );
    const total_assigned = Math.round(Number(agg.total_assigned) * 100) / 100;
    const remaining      = Math.round((Number(invoice.total_amount || 0) - total_assigned) * 100) / 100;

    res.json({
      ...invoice,
      items,
      assignments,
      total_assigned,
      remaining,
      is_overpaid: remaining < 0,
    });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: error.message });
  }
});

// POST /invoice-scanner/invoices/:id/assign
app.post('/invoice-scanner/invoices/:id/assign', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid, assignment_type, target_id, amount_assigned, notes, periodo_id, presupuesto_id } = req.body;
  if (!firebase_uid || !assignment_type || !amount_assigned) {
    return res.status(400).json({ error: 'firebase_uid, assignment_type y amount_assigned son requeridos' });
  }
  if (amount_assigned <= 0) return res.status(400).json({ error: 'amount_assigned debe ser mayor a 0' });

  const conn = await db.getConnection();
  try {
    await conn.beginTransaction();

    const [[invoice]] = await conn.query(
      'SELECT * FROM scanned_invoices WHERE id = ? AND firebase_uid = ?',
      [id, firebase_uid]
    );
    if (!invoice) { await conn.rollback(); conn.release(); return res.status(404).json({ error: 'Factura no encontrada' }); }

    const [[agg]] = await conn.query(
      'SELECT COALESCE(SUM(amount_assigned),0) AS total_assigned FROM scanned_invoice_assignments WHERE invoice_id = ?',
      [id]
    );
    const remaining  = Number(invoice.total_amount || 0) - Number(agg.total_assigned);
    const overpaid   = amount_assigned > remaining;

    let createdTargetId = target_id || null;

    // Acciones por tipo de asignación
    if (assignment_type === 'gasto_existente' && target_id) {
      await conn.query(
        `UPDATE movimientos SET monto_pagado_real = COALESCE(monto_pagado_real,0) + ?, pagado = 1, fecha_pagado = NOW() WHERE id = ? AND firebase_uid = ?`,
        [amount_assigned, target_id, firebase_uid]
      );
    } else if (assignment_type === 'gasto_nuevo' && presupuesto_id) {
      const periodoResult = await getPeriodoActivo(presupuesto_id, firebase_uid);
      const usePeriodoId  = periodo_id || periodoResult?.id;
      const [mvResult] = await conn.query(
        `INSERT INTO movimientos (presupuesto_id, periodo_id, descripcion, monto, tipo, pagado, monto_pagado_real, pagado_por_uid, fecha_pagado, firebase_uid)
         VALUES (?,?,'Gasto factura QR',?,?,1,?,?,NOW(),?)`,
        [presupuesto_id, usePeriodoId, amount_assigned, 'no fijo', amount_assigned, firebase_uid, firebase_uid]
      );
      createdTargetId = mvResult.insertId;
    } else if (assignment_type === 'gustito' && presupuesto_id) {
      const [gtResult] = await conn.query(
        `INSERT INTO gustitos (user_id, budget_id, name, amount, merchant, category, source, scanned_invoice_id, spent_at, created_at)
         VALUES (?,?,?,?,?,'otro','scanned_invoice',?,NOW(),NOW())`,
        [firebase_uid, presupuesto_id, invoice.merchant_name || 'Factura QR', amount_assigned, invoice.merchant_name || null, id]
      );
      createdTargetId = gtResult.insertId;
    } else if (assignment_type === 'presupuesto_compartido' && target_id) {
      const [seResult] = await conn.query(
        `INSERT INTO shared_expenses (budget_id, paid_by_uid, description, amount, paid_at, created_at)
         VALUES (?,?,'Factura QR',?,NOW(),NOW())`,
        [target_id, firebase_uid, amount_assigned]
      );
      createdTargetId = seResult.insertId;
    } else if (['gasto_operativo_servicio','gasto_empresarial','compra_inventario'].includes(assignment_type) && target_id) {
      const categoria = assignment_type === 'compra_inventario' ? 'inventario' :
                        assignment_type === 'gasto_empresarial' ? 'empresarial' : 'operativo';
      const [opResult] = await conn.query(
        `INSERT INTO operational_expenses (job_id, firebase_uid, description, amount, categoria, scanned_invoice_id, expense_date)
         VALUES (?,?,?,?,?,?,NOW())`,
        [target_id, firebase_uid, invoice.merchant_name || 'Factura QR', amount_assigned, categoria, id]
      );
      createdTargetId = opResult.insertId;
    }
    // sin_asignar: no acción adicional

    const [asgnResult] = await conn.query(
      `INSERT INTO scanned_invoice_assignments (invoice_id, firebase_uid, assignment_type, target_id, amount_assigned, notes)
       VALUES (?,?,?,?,?,?)`,
      [id, firebase_uid, assignment_type, createdTargetId, amount_assigned, notes || null]
    );

    await conn.query(
      `INSERT INTO invoice_activity_logs (invoice_id, firebase_uid, action, details) VALUES (?,?,?,?)`,
      [id, firebase_uid, 'assigned', JSON.stringify({ assignment_type, target_id: createdTargetId, amount_assigned, overpaid })]
    );

    await conn.commit();
    conn.release();

    await recalcularStatusFactura(id);

    const [[updatedInvoice]] = await db.query('SELECT * FROM scanned_invoices WHERE id = ?', [id]);
    res.status(201).json({
      assignment_id:  asgnResult.insertId,
      target_id:      createdTargetId,
      overpaid,
      excess:         overpaid ? Math.round((amount_assigned - remaining) * 100) / 100 : 0,
      invoice_status: updatedInvoice.status,
    });
  } catch (error) {
    await conn.rollback();
    conn.release();
    console.error(error);
    res.status(500).json({ error: error.message });
  }
});

// DELETE /invoice-scanner/invoices/:id/assignments/:assignmentId
app.delete('/invoice-scanner/invoices/:id/assignments/:assignmentId', async (req, res) => {
  const { id, assignmentId } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [[asgn]] = await db.query(
      'SELECT * FROM scanned_invoice_assignments WHERE id = ? AND invoice_id = ? AND firebase_uid = ?',
      [assignmentId, id, firebase_uid]
    );
    if (!asgn) return res.status(404).json({ error: 'Asignación no encontrada' });

    await db.query('DELETE FROM scanned_invoice_assignments WHERE id = ?', [assignmentId]);
    await db.query(
      `INSERT INTO invoice_activity_logs (invoice_id, firebase_uid, action, details) VALUES (?,?,?,?)`,
      [id, firebase_uid, 'assignment_removed', JSON.stringify({ assignment_id: assignmentId, assignment_type: asgn.assignment_type })]
    );
    await recalcularStatusFactura(id);
    res.json({ ok: true });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: error.message });
  }
});

// DELETE /invoice-scanner/invoices/:id
app.delete('/invoice-scanner/invoices/:id', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [[invoice]] = await db.query(
      'SELECT * FROM scanned_invoices WHERE id = ? AND firebase_uid = ?',
      [id, firebase_uid]
    );
    if (!invoice) return res.status(404).json({ error: 'Factura no encontrada' });
    if (!['unassigned','pending'].includes(invoice.status)) {
      return res.status(400).json({ error: 'Solo se pueden eliminar facturas sin asignar o pendientes' });
    }
    await db.query('DELETE FROM scanned_invoices WHERE id = ?', [id]);
    res.json({ ok: true });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: error.message });
  }
});

// GET /invoice-scanner/invoices/:id/logs
app.get('/invoice-scanner/invoices/:id/logs', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [[invoice]] = await db.query(
      'SELECT id FROM scanned_invoices WHERE id = ? AND firebase_uid = ?',
      [id, firebase_uid]
    );
    if (!invoice) return res.status(404).json({ error: 'Factura no encontrada' });
    const [logs] = await db.query(
      'SELECT * FROM invoice_activity_logs WHERE invoice_id = ? ORDER BY created_at DESC',
      [id]
    );
    res.json(logs);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: error.message });
  }
});

// PATCH /invoice-scanner/invoices/:id — actualizar campos manuales (cuando DGI no responde)
app.patch('/invoice-scanner/invoices/:id', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid, merchant_name, merchant_ruc, numero_factura, total_amount, tax_amount, invoice_date } = req.body;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [[invoice]] = await db.query(
      'SELECT id FROM scanned_invoices WHERE id = ? AND firebase_uid = ?',
      [id, firebase_uid]
    );
    if (!invoice) return res.status(404).json({ error: 'Factura no encontrada' });

    const fields = [];
    const vals   = [];
    if (merchant_name  != null) { fields.push('merchant_name = ?');  vals.push(merchant_name); }
    if (merchant_ruc   != null) { fields.push('merchant_ruc = ?');   vals.push(merchant_ruc); }
    if (numero_factura != null) { fields.push('numero_factura = ?'); vals.push(numero_factura); }
    if (total_amount   != null) {
      fields.push('total_amount = ?');    vals.push(total_amount);
      const tax = tax_amount != null ? tax_amount : 0;
      fields.push('tax_amount = ?');      vals.push(tax);
      fields.push('subtotal_amount = ?'); vals.push(Math.round((total_amount - tax) * 100) / 100);
    }
    if (invoice_date   != null) { fields.push('invoice_date = ?');   vals.push(invoice_date); }
    if (fields.length === 0) return res.status(400).json({ error: 'Sin campos para actualizar' });

    fields.push('updated_at = NOW()');
    vals.push(id);
    await db.query(`UPDATE scanned_invoices SET ${fields.join(', ')} WHERE id = ?`, vals);
    await recalcularStatusFactura(id);
    const [[updated]] = await db.query('SELECT * FROM scanned_invoices WHERE id = ?', [id]);
    res.json(updated);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: error.message });
  }
});

// =============================================================================
// HELPER: CIERRE MANUAL DE PERÍODO (reutilizable por endpoint y por auto-cierre)
// =============================================================================
async function cerrarPeriodoManual(periodoId, presupuestoId, firebaseUid) {
  await db.execute(
    `UPDATE periodos SET estado = 'cerrado', closed_at = NOW() WHERE id = ? AND presupuesto_id = ? AND firebase_uid = ?`,
    [periodoId, presupuestoId, firebaseUid]
  );
  const [[cerrado]] = await db.execute(
    `SELECT fecha_fin, tipo_periodo FROM periodos WHERE id = ?`,
    [periodoId]
  );
  return crearNuevoPeriodo(presupuestoId, firebaseUid, cerrado.tipo_periodo, cerrado.fecha_fin);
}

// =============================================================================
// P1 — INGRESO NETO REAL
// =============================================================================

// GET /presupuestos/:id/income — obtener income configurado (204 si no existe)
app.get('/presupuestos/:id/income', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid es requerido' });
  try {
    const [[row]] = await db.execute(
      `SELECT * FROM budget_income WHERE presupuesto_id = ? AND firebase_uid = ? LIMIT 1`,
      [id, firebase_uid]
    );
    if (!row) return res.status(204).send();
    res.json(row);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: error.message });
  }
});

// POST /presupuestos/:id/income — crear o actualizar income (upsert)
app.post('/presupuestos/:id/income', async (req, res) => {
  const { id } = req.params;
  const {
    firebase_uid, tipo_ingreso,
    ingreso_bruto, desc_seguro, desc_pension, desc_impuesto, desc_otros,
    ingreso_neto: ingreso_neto_raw, nota,
    calcular_automatico, ingreso_bruto_mensual
  } = req.body;
  if (!firebase_uid || !tipo_ingreso) {
    return res.status(400).json({ error: 'firebase_uid y tipo_ingreso son requeridos' });
  }
  try {
    const [[presupuesto]] = await db.execute(
      `SELECT id FROM presupuestos WHERE id = ? AND firebase_uid = ?`,
      [id, firebase_uid]
    );
    if (!presupuesto) return res.status(404).json({ error: 'Presupuesto no encontrado' });

    let ingreso_neto;
    let bruto = null, seguro = 0, pension = 0, impuesto = 0, otros = 0;

    if (tipo_ingreso === 'salario') {
      bruto     = parseFloat(ingreso_bruto)   || 0;
      seguro    = parseFloat(desc_seguro)     || 0;
      pension   = parseFloat(desc_pension)    || 0;
      impuesto  = parseFloat(desc_impuesto)   || 0;
      otros     = parseFloat(desc_otros)      || 0;
      ingreso_neto = Math.round((bruto - seguro - pension - impuesto - otros) * 100) / 100;
    } else {
      ingreso_neto = parseFloat(ingreso_neto_raw) || 0;
    }

    if (ingreso_neto <= 0) return res.status(400).json({ error: 'ingreso_neto debe ser mayor a 0' });

    const calcAuto = calcular_automatico != null ? (calcular_automatico ? 1 : 0) : null;
    const brutMensual = ingreso_bruto_mensual != null ? parseFloat(ingreso_bruto_mensual) : null;

    await db.execute(
      `INSERT INTO budget_income
         (presupuesto_id, firebase_uid, tipo_ingreso, ingreso_bruto,
          desc_seguro, desc_pension, desc_impuesto, desc_otros, ingreso_neto, nota,
          calcular_automatico, ingreso_bruto_mensual)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
       ON DUPLICATE KEY UPDATE
         tipo_ingreso          = VALUES(tipo_ingreso),
         ingreso_bruto         = VALUES(ingreso_bruto),
         desc_seguro           = VALUES(desc_seguro),
         desc_pension          = VALUES(desc_pension),
         desc_impuesto         = VALUES(desc_impuesto),
         desc_otros            = VALUES(desc_otros),
         ingreso_neto          = VALUES(ingreso_neto),
         nota                  = VALUES(nota),
         calcular_automatico   = COALESCE(VALUES(calcular_automatico), calcular_automatico),
         ingreso_bruto_mensual = COALESCE(VALUES(ingreso_bruto_mensual), ingreso_bruto_mensual),
         updated_at            = NOW()`,
      [id, firebase_uid, tipo_ingreso, bruto, seguro, pension, impuesto, otros, ingreso_neto, nota || null, calcAuto, brutMensual]
    );

    const [[saved]] = await db.execute(
      `SELECT * FROM budget_income WHERE presupuesto_id = ? AND firebase_uid = ?`,
      [id, firebase_uid]
    );
    res.json(saved);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: error.message });
  }
});

// =============================================================================
// P2 — CAPACIDAD REAL DE PAGO
// =============================================================================

// GET /presupuestos/:id/capacidad
app.get('/presupuestos/:id/capacidad', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid es requerido' });
  try {
    // 1. Ingreso global del usuario (user_income — escala mensual)
    const [[incomeRow]] = await db.execute(
      `SELECT ui.ingreso_neto_mensual, ui.frecuencia_cobro, p.tipo_periodo
       FROM user_income ui
       JOIN presupuestos p ON p.firebase_uid = ui.firebase_uid AND p.id = ?
       WHERE ui.firebase_uid = ?`,
      [id, firebase_uid]
    );
    // Fallback: leer income del presupuesto (retrocompatibilidad)
    let ingreso_neto_periodo = null;
    let tiene_income = false;
    if (incomeRow) {
      const divisorIncome = incomeRow.tipo_periodo === 'quincenal' ? 2 : 1;
      ingreso_neto_periodo = parseFloat((Number(incomeRow.ingreso_neto_mensual) / divisorIncome).toFixed(2));
      tiene_income = true;
    }

    // 2. Compromisos fijos REALES del usuario (user_gastos_fijos — escala mensual)
    const [[presupRow]] = await db.execute(
      `SELECT tipo_periodo FROM presupuestos WHERE id = ? AND firebase_uid = ?`, [id, firebase_uid]
    );
    const divisor = presupRow?.tipo_periodo === 'quincenal' ? 2 : 1;
    const [[gfRow]] = await db.execute(
      `SELECT COALESCE(SUM(monto_mensual), 0) AS total_mensual
       FROM user_gastos_fijos WHERE firebase_uid = ? AND activo = 1`, [firebase_uid]
    );
    const gastos_fijos_mensual = parseFloat(gfRow.total_mensual);
    const gastos_fijos_periodo = parseFloat((gastos_fijos_mensual / divisor).toFixed(2));

    // 3. Promedio de gastos variables en últimos 3 períodos cerrados
    const [periodosCerrados] = await db.execute(
      `SELECT p.id,
              COALESCE(SUM(CASE WHEN m.tipo = 'no fijo' AND m.pagado = 1 THEN m.monto_pagado_real ELSE 0 END), 0) AS total_variable
       FROM periodos p
       LEFT JOIN movimientos m ON m.periodo_id = p.id AND m.firebase_uid = p.firebase_uid
       WHERE p.presupuesto_id = ? AND p.firebase_uid = ? AND p.estado = 'cerrado'
       GROUP BY p.id
       ORDER BY p.numero_periodo DESC LIMIT 3`,
      [id, firebase_uid]
    );
    const promedio_variable = periodosCerrados.length > 0
      ? parseFloat((periodosCerrados.reduce((s, r) => s + parseFloat(r.total_variable), 0) / periodosCerrados.length).toFixed(2))
      : 0;

    const capacidad_real = ingreso_neto_periodo !== null
      ? parseFloat((ingreso_neto_periodo - gastos_fijos_periodo - promedio_variable).toFixed(2))
      : null;

    res.json({
      ingreso_neto: ingreso_neto_periodo,
      gastos_fijos_totales: gastos_fijos_periodo,
      gastos_fijos_mensual,
      gastos_variables_presupuestados: promedio_variable,
      promedio_variable_historico: promedio_variable,
      usa_historico: periodosCerrados.length > 0,
      capacidad_real,
      tiene_income,
      periodos_historico: periodosCerrados.length,
    });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: error.message });
  }
});

// =============================================================================
// P3 — FONDO DE SEGURIDAD
// =============================================================================

// GET /presupuestos/:id/fondo-seguridad
app.get('/presupuestos/:id/fondo-seguridad', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid es requerido' });
  try {
    // 1. Gastos fijos del período activo (proxy de esenciales)
    const [[fijoRow]] = await db.execute(
      `SELECT COALESCE(SUM(m.monto), 0) AS gastos_fijos
       FROM movimientos m
       JOIN periodos p ON p.id = m.periodo_id
       WHERE m.presupuesto_id = ? AND m.firebase_uid = ?
         AND p.estado = 'activo'
         AND m.tipo IN ('fijo', 'fijo_x_periodo')`,
      [id, firebase_uid]
    );

    // 2. Total ahorrado del usuario en todas sus metas de ahorro
    const [[ahorroRow]] = await db.execute(
      `SELECT COALESCE(SUM(sub.total), 0) AS total_ahorrado
       FROM (
         SELECT g.id,
           COALESCE(SUM(CASE WHEN m.pagado = 1 THEN m.monto_pagado_real ELSE 0 END), 0)
           + COALESCE((SELECT SUM(a.monto) FROM aportaciones_ahorro a WHERE a.gasto_id = g.id), 0) AS total
         FROM gastos g
         LEFT JOIN movimientos m ON m.gasto_id = g.id
         WHERE g.firebase_uid = ? AND g.tipo = 'ahorro'
         GROUP BY g.id
       ) sub`,
      [firebase_uid]
    );

    const gastos_fijos = parseFloat(fijoRow.gastos_fijos);
    const total_ahorrado = parseFloat(ahorroRow.total_ahorrado);
    const objetivo_nivel1 = Math.round(gastos_fijos * 100) / 100;
    const objetivo_nivel2 = Math.round(gastos_fijos * 2 * 100) / 100;
    const objetivo_nivel3 = Math.round(gastos_fijos * 6 * 100) / 100;

    let nivel_actual = 0;
    if (total_ahorrado >= objetivo_nivel3) nivel_actual = 3;
    else if (total_ahorrado >= objetivo_nivel2) nivel_actual = 2;
    else if (total_ahorrado >= objetivo_nivel1) nivel_actual = 1;

    const pct_nivel1 = objetivo_nivel1 > 0
      ? Math.min(Math.round((total_ahorrado / objetivo_nivel1) * 1000) / 1000, 1.0)
      : 0;

    res.json({
      total_ahorrado_actual: total_ahorrado,
      gastos_fijos_un_periodo: gastos_fijos,
      objetivo_nivel1,
      objetivo_nivel2,
      objetivo_nivel3,
      nivel_actual,
      pct_nivel1
    });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: error.message });
  }
});

// =============================================================================
// P5 — PATRONES DE GUSTITOS (aprendizaje)
// =============================================================================

// GET /presupuestos/:id/gustitos/patrones
app.get('/presupuestos/:id/gustitos/patrones', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid es requerido' });
  try {
    const [patrones] = await db.execute(
      `SELECT
         g.category,
         COUNT(DISTINCT p.id)              AS periodos_con_gasto,
         COUNT(*)                          AS total_registros,
         ROUND(SUM(g.amount), 2)           AS monto_total,
         ROUND(AVG(g.amount), 2)           AS monto_promedio
       FROM gustitos g
       JOIN periodos p ON (
         g.spent_at >= p.fecha_inicio AND g.spent_at <= p.fecha_fin
         AND p.presupuesto_id = ? AND p.firebase_uid = ?
       )
       WHERE g.budget_id = ? AND g.user_id = ?
         AND g.deleted_at IS NULL
         AND g.category IS NOT NULL AND g.category != ''
       GROUP BY g.category
       HAVING periodos_con_gasto >= 2
       ORDER BY periodos_con_gasto DESC, monto_total DESC`,
      [id, firebase_uid, id, firebase_uid]
    );
    res.json({ tiene_patrones: patrones.length > 0, patrones });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: error.message });
  }
});

// =============================================================================
// P4 — CIERRE DE PERÍODO (resumen + cierre manual)
// =============================================================================

// GET /presupuestos/:id/periodo/:periodoId/resumen-cierre
app.get('/presupuestos/:id/periodo/:periodoId/resumen-cierre', async (req, res) => {
  const { id, periodoId } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid es requerido' });
  try {
    // Datos del período
    const [[periodo]] = await db.execute(
      `SELECT * FROM periodos WHERE id = ? AND presupuesto_id = ? AND firebase_uid = ?`,
      [periodoId, id, firebase_uid]
    );
    if (!periodo) return res.status(404).json({ error: 'Período no encontrado' });

    // Presupuesto (monto_total)
    const [[presupuesto]] = await db.execute(
      `SELECT monto_total FROM presupuestos WHERE id = ? AND firebase_uid = ?`,
      [id, firebase_uid]
    );

    // Gastado real, ahorro y compromisos pendientes del período
    const [[gastadoRow]] = await db.execute(
      `SELECT
         COALESCE(SUM(CASE WHEN pagado = 1 THEN monto_pagado_real ELSE 0 END), 0) AS total_gastado_real,
         COALESCE(SUM(CASE WHEN tipo = 'ahorro' AND pagado = 1 THEN monto_pagado_real ELSE 0 END), 0) AS total_ahorro,
         COALESCE(SUM(CASE WHEN pagado = 0 THEN monto ELSE 0 END), 0) AS total_comprometido_pendiente,
         COUNT(*) AS total_movimientos,
         SUM(CASE WHEN pagado = 0 THEN 1 ELSE 0 END) AS movimientos_pendientes
       FROM movimientos WHERE periodo_id = ? AND firebase_uid = ?`,
      [periodoId, firebase_uid]
    );

    // Ingreso neto configurado
    const [[incomeRow]] = await db.execute(
      `SELECT ingreso_neto FROM budget_income WHERE presupuesto_id = ? AND firebase_uid = ?`,
      [id, firebase_uid]
    );

    // Gustitos del período
    const fechaIni = periodo.fecha_inicio instanceof Date
      ? periodo.fecha_inicio.toISOString().split('T')[0]
      : String(periodo.fecha_inicio);
    const fechaFin = periodo.fecha_fin instanceof Date
      ? periodo.fecha_fin.toISOString().split('T')[0]
      : String(periodo.fecha_fin);

    const [[gustitosRow]] = await db.execute(
      `SELECT COALESCE(SUM(amount), 0) AS total_gustitos, COUNT(*) AS count_gustitos
       FROM gustitos
       WHERE budget_id = ? AND user_id = ? AND deleted_at IS NULL
         AND spent_at BETWEEN ? AND ?`,
      [id, firebase_uid, fechaIni, fechaFin]
    );

    const ingreso_neto               = incomeRow ? parseFloat(incomeRow.ingreso_neto) : null;
    const monto_total                = parseFloat(presupuesto.monto_total);
    const total_gastado              = parseFloat(gastadoRow.total_gastado_real);
    const total_ahorro               = parseFloat(gastadoRow.total_ahorro);
    const total_comprometido_pendiente = parseFloat(gastadoRow.total_comprometido_pendiente);
    const movimientos_pendientes     = parseInt(gastadoRow.movimientos_pendientes || 0);
    const total_movimientos          = parseInt(gastadoRow.total_movimientos || 0);
    const total_gustitos             = parseFloat(gustitosRow.total_gustitos);
    const base_calculo               = ingreso_neto ?? monto_total;
    const disponible_real            = Math.round((base_calculo - total_gastado - total_gustitos) * 100) / 100;
    const hubo_actividad             = total_gastado > 0 || total_gustitos > 0;

    // Calcular si puede cerrar manualmente (hasta 2 días antes del fin)
    const hoy = new Date();
    const finDate = new Date(fechaFin + 'T23:59:59');
    const diffDias = Math.ceil((finDate - hoy) / (1000 * 60 * 60 * 24));
    const puede_cerrar_manualmente = periodo.estado === 'activo' && diffDias <= 2;
    const razon_no_puede_cerrar = !puede_cerrar_manualmente
      ? (periodo.estado !== 'activo' ? 'El período ya está cerrado.' : `Aún quedan ${diffDias} días para que termine el período.`)
      : null;

    // Aprendizajes automáticos — honestos y accionables
    const aprendizajes = [];

    // Sin actividad registrada: avisar sobre compromisos pendientes
    if (!hubo_actividad && movimientos_pendientes > 0) {
      aprendizajes.push(`Tienes ${movimientos_pendientes} compromiso${movimientos_pendientes > 1 ? 's' : ''} por un total de $${total_comprometido_pendiente.toFixed(2)} que no marcaste como pagados. Revísalos antes de cerrar.`);
    }

    if (total_gustitos > 0) {
      const pctGustitos = total_gustitos / base_calculo;
      if (pctGustitos >= 0.10) {
        aprendizajes.push(`Gastaste $${total_gustitos.toFixed(2)} en Gustitos (${Math.round(pctGustitos * 100)}% de tu ingreso). Si se repite, considera presupuestarlo.`);
      } else {
        aprendizajes.push(`Tuviste $${total_gustitos.toFixed(2)} en Gustitos este período. ¡Buen control!`);
      }
    }

    if (ingreso_neto && total_ahorro > 0) {
      const tasaAhorro = total_ahorro / ingreso_neto;
      if (tasaAhorro >= 0.20) {
        aprendizajes.push(`¡Ahorraste ${Math.round(tasaAhorro * 100)}% de tu ingreso! Eso es excelente.`);
      } else if (tasaAhorro >= 0.10) {
        aprendizajes.push(`Ahorraste ${Math.round(tasaAhorro * 100)}% de tu ingreso. La meta ideal es 20% — vas por buen camino.`);
      } else {
        aprendizajes.push(`Ahorraste ${Math.round(tasaAhorro * 100)}% de tu ingreso este período. Intenta incrementarlo poco a poco.`);
      }
    }

    if (hubo_actividad) {
      if (total_gastado > base_calculo) {
        aprendizajes.push(`Te pasaste del presupuesto en $${(total_gastado - base_calculo).toFixed(2)}. El próximo período revisa tus gastos variables.`);
      } else if (disponible_real > 0) {
        aprendizajes.push(`Cerraste con $${disponible_real.toFixed(2)} disponibles. ¡Bien manejado!`);
      }
    }

    res.json({
      periodo: {
        id: periodo.id,
        numero_periodo: periodo.numero_periodo,
        fecha_inicio: fechaIni,
        fecha_fin: fechaFin,
        estado: periodo.estado
      },
      monto_total,
      ingreso_neto,
      total_gastado_real: total_gastado,
      total_ahorro,
      total_gustitos,
      total_comprometido_pendiente,
      movimientos_pendientes,
      disponible_real,
      tiene_income: incomeRow != null,
      puede_cerrar_manualmente,
      razon_no_puede_cerrar,
      aprendizajes
    });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: error.message });
  }
});

// POST /presupuestos/:id/periodo/:periodoId/cerrar — cierre manual
app.post('/presupuestos/:id/periodo/:periodoId/cerrar', async (req, res) => {
  const { id, periodoId } = req.params;
  const { firebase_uid } = req.body;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid es requerido' });
  try {
    const [[periodo]] = await db.execute(
      `SELECT id FROM periodos WHERE id = ? AND presupuesto_id = ? AND firebase_uid = ? AND estado = 'activo'`,
      [periodoId, id, firebase_uid]
    );
    if (!periodo) return res.status(409).json({ error: 'El período ya fue cerrado' });

    const nuevoPeriodo = await cerrarPeriodoManual(periodoId, id, firebase_uid);
    res.json({ message: 'Período cerrado', nuevo_periodo: nuevoPeriodo });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: error.message });
  }
});

// =============================================================================
// #4 CLASIFICACIÓN FINANCIERA DE GASTOS
// =============================================================================

// GET /presupuestos/:id/distribucion-clasificacion?firebase_uid=
// Distribución del gasto del período activo por clasificación financiera.
app.get('/presupuestos/:id/distribucion-clasificacion', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid es requerido' });
  try {
    const periodo = await getPeriodoActivo(id, firebase_uid);
    const [[presupuesto]] = await db.execute(
      `SELECT monto_total FROM presupuestos WHERE id = ? AND firebase_uid = ?`,
      [id, firebase_uid]
    );
    if (!presupuesto) return res.status(404).json({ error: 'Presupuesto no encontrado' });

    const [rows] = await db.execute(
      `SELECT
         COALESCE(clasificacion, 'sin_clasificar') AS clasificacion,
         COUNT(*) AS cantidad,
         SUM(monto) AS total
       FROM movimientos
       WHERE presupuesto_id = ? AND periodo_id = ? AND firebase_uid = ?
       GROUP BY clasificacion`,
      [id, periodo.id, firebase_uid]
    );

    const montoTotal = Number(presupuesto.monto_total);
    const distribucion = {};
    let totalClasificado = 0;
    rows.forEach(r => {
      const t = Number(r.total);
      distribucion[r.clasificacion] = { total: t, cantidad: Number(r.cantidad), pct: montoTotal > 0 ? t / montoTotal : 0 };
      if (r.clasificacion !== 'sin_clasificar') totalClasificado += t;
    });

    // Garantizar que sin_clasificar siempre esté presente en el objeto
    if (!distribucion['sin_clasificar']) {
      distribucion['sin_clasificar'] = { total: 0, cantidad: 0, pct: 0 };
    }

    res.json({
      distribucion,
      monto_total: montoTotal,
      total_clasificado: totalClasificado,
      pct_clasificado: montoTotal > 0 ? totalClasificado / montoTotal : 0,
    });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: error.message });
  }
});

// =============================================================================
// #6 ALERTAS INTELIGENTES PREVENTIVAS
// =============================================================================

// GET /presupuestos/:id/alertas?firebase_uid=
// Retorna alertas financieras basadas en el estado del período activo.
app.get('/presupuestos/:id/alertas', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid es requerido' });
  try {
    const periodo = await getPeriodoActivo(id, firebase_uid);
    const [[presupuesto]] = await db.execute(
      `SELECT monto_total FROM presupuestos WHERE id = ? AND firebase_uid = ?`,
      [id, firebase_uid]
    );
    if (!presupuesto) return res.status(404).json({ error: 'Presupuesto no encontrado' });

    const montoTotal = Number(presupuesto.monto_total);

    // Gasto actual del período
    const [[gastoRow]] = await db.execute(
      `SELECT
         COALESCE(SUM(monto), 0) AS total_gastado,
         COALESCE(SUM(CASE WHEN tipo='no fijo' THEN monto ELSE 0 END), 0) AS total_variable,
         COALESCE(SUM(CASE WHEN (tipo='fijo' OR tipo='fijo_x_periodo') THEN monto ELSE 0 END), 0) AS total_fijo,
         COUNT(*) AS total_movimientos,
         SUM(CASE WHEN pagado=1 THEN 1 ELSE 0 END) AS pagados
       FROM movimientos
       WHERE presupuesto_id = ? AND periodo_id = ? AND firebase_uid = ?`,
      [id, periodo.id, firebase_uid]
    );

    // Gustitos del período
    const [[gustitosRow]] = await db.execute(
      `SELECT COALESCE(SUM(amount), 0) AS total
       FROM gustitos WHERE budget_id = ? AND user_id = ? AND deleted_at IS NULL
       AND spent_at BETWEEN ? AND ?`,
      [id, firebase_uid, periodo.fecha_inicio, periodo.fecha_fin]
    );

    // Promedio de variable de los últimos 3 períodos cerrados
    const [histVariables] = await db.execute(
      `SELECT SUM(CASE WHEN m.tipo='no fijo' THEN m.monto ELSE 0 END) AS var_periodo
       FROM periodos p
       JOIN movimientos m ON m.periodo_id = p.id AND m.firebase_uid = p.firebase_uid
       WHERE p.presupuesto_id = ? AND p.firebase_uid = ? AND p.estado = 'cerrado'
       GROUP BY p.id
       ORDER BY p.fecha_fin DESC LIMIT 3`,
      [id, firebase_uid]
    );
    const promedioVar = histVariables.length > 0
      ? histVariables.reduce((s, r) => s + Number(r.var_periodo), 0) / histVariables.length
      : 0;

    // Avance del período en días (0.0 – 1.0), nunca negativo
    const hoy = new Date();
    const inicio = new Date(periodo.fecha_inicio);
    const fin    = new Date(periodo.fecha_fin);
    const duracion = Math.max(1, (fin - inicio) / 86400000);
    const avance   = Math.max(0, Math.min(1, (hoy - inicio) / 86400000 / duracion));
    const periodoNoIniciado = hoy < inicio;

    const totalGastado = Number(gastoRow.total_gastado);
    const totalVariable = Number(gastoRow.total_variable);
    const totalFijo = Number(gastoRow.total_fijo);
    const totalGustitos = Number(gustitosRow.total);
    const totalConGustitos = totalGastado + totalGustitos;
    const pctGasto = montoTotal > 0 ? totalConGustitos / montoTotal : 0;

    // Ingreso neto por período desde user_income (escala correcta)
    const [[incomeAlertRow]] = await db.execute(
      `SELECT ui.ingreso_neto_mensual, p.tipo_periodo
       FROM user_income ui JOIN presupuestos p ON p.firebase_uid = ui.firebase_uid AND p.id = ?
       WHERE ui.firebase_uid = ?`,
      [id, firebase_uid]
    );
    let ingresoNetoAlert = null;
    if (incomeAlertRow) {
      const div = incomeAlertRow.tipo_periodo === 'quincenal' ? 2 : 1;
      ingresoNetoAlert = parseFloat((Number(incomeAlertRow.ingreso_neto_mensual) / div).toFixed(2));
    }

    const alertas = [];

    // Alerta 0: compromisos fijos superan el ingreso neto del período
    if (ingresoNetoAlert !== null && totalFijo > ingresoNetoAlert) {
      alertas.push({
        tipo: 'gastos_exceden_ingreso',
        nivel: 'danger',
        titulo: 'Tus compromisos superan tu ingreso',
        mensaje: `Tienes $${totalFijo.toFixed(2)} comprometidos en gastos fijos pero tu ingreso es $${ingresoNetoAlert.toFixed(2)}. Hay un déficit de $${(totalFijo - ingresoNetoAlert).toFixed(2)}.`,
      });
    }

    // Alerta 1: ritmo alto de gasto (solo si el período ya inició)
    if (!periodoNoIniciado && avance > 0 && avance < 0.5 && pctGasto > 0.7) {
      alertas.push({
        tipo: 'ritmo_alto',
        nivel: 'danger',
        titulo: 'Ritmo de gasto elevado',
        mensaje: `Llevas ${Math.round(pctGasto * 100)}% del presupuesto consumido en solo ${Math.round(avance * 100)}% del período.`,
      });
    }

    // Alerta 2: cerca del límite
    if (pctGasto >= 0.85 && pctGasto < 1.0) {
      alertas.push({
        tipo: 'cerca_limite',
        nivel: 'warning',
        titulo: 'Cerca del límite',
        mensaje: `Solo te queda $${(montoTotal - totalConGustitos).toFixed(2)} disponible (${Math.round((1 - pctGasto) * 100)}% del presupuesto).`,
      });
    }

    // Alerta 3: presupuesto excedido
    if (pctGasto >= 1.0) {
      alertas.push({
        tipo: 'excedido',
        nivel: 'danger',
        titulo: 'Presupuesto excedido',
        mensaje: `Superaste el presupuesto en $${(totalConGustitos - montoTotal).toFixed(2)}.`,
      });
    }

    // Alerta 4: variables históricamente altas
    if (promedioVar > 0 && totalVariable > promedioVar * 1.3) {
      alertas.push({
        tipo: 'variables_altas',
        nivel: 'warning',
        titulo: 'Gastos variables altos',
        mensaje: `Tus variables ($${totalVariable.toFixed(2)}) superan 30% tu promedio histórico ($${promedioVar.toFixed(2)}).`,
      });
    }

    // Alerta 5: muchos movimientos sin pagar y el período termina pronto
    const diasRestantes = Math.max(0, (fin - hoy) / 86400000);
    const sinPagar = Number(gastoRow.total_movimientos) - Number(gastoRow.pagados);
    if (diasRestantes <= 3 && sinPagar > 0) {
      alertas.push({
        tipo: 'pagos_pendientes',
        nivel: 'info',
        titulo: 'Pagos pendientes al cierre',
        mensaje: `Tienes ${sinPagar} movimiento${sinPagar > 1 ? 's' : ''} sin pagar y el período termina en ${Math.round(diasRestantes)} día${diasRestantes !== 1 ? 's' : ''}.`,
      });
    }

    res.json({ alertas, tiene_alertas: alertas.length > 0 });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: error.message });
  }
});

// =============================================================================
// #7 PRESUPUESTO RECOMENDADO POR PORCENTAJES (Regla 50/30/20 adaptada)
// =============================================================================

// GET /presupuestos/:id/recomendacion-porcentajes?firebase_uid=
// Compara la distribución real del gasto vs la regla 50/30/20:
//   esencial (necesidades) → 50% del ingreso neto
//   importante (quiero)    → 30%
//   flexible (ahorro)      → 20%
app.get('/presupuestos/:id/recomendacion-porcentajes', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid es requerido' });
  try {
    // Usar user_income (global, mensual) dividido por frecuencia del presupuesto
    const [[incomeRow]] = await db.execute(
      `SELECT ui.ingreso_neto_mensual, p.tipo_periodo, p.monto_total
       FROM presupuestos p
       LEFT JOIN user_income ui ON ui.firebase_uid = p.firebase_uid
       WHERE p.id = ? AND p.firebase_uid = ?`,
      [id, firebase_uid]
    );
    if (!incomeRow) return res.status(404).json({ error: 'Presupuesto no encontrado' });

    const divisor = incomeRow.tipo_periodo === 'quincenal' ? 2 : 1;
    const ingresoNetoPeriodo = incomeRow.ingreso_neto_mensual
      ? parseFloat((Number(incomeRow.ingreso_neto_mensual) / divisor).toFixed(2))
      : null;
    // base = ingreso neto por período (correcto) o monto_total como fallback
    const base = ingresoNetoPeriodo ?? Number(incomeRow.monto_total);
    const tiene_income = !!incomeRow.ingreso_neto_mensual;

    const periodo = await getPeriodoActivo(id, firebase_uid);
    const [clasifRows] = await db.execute(
      `SELECT
         COALESCE(clasificacion, 'sin_clasificar') AS clasificacion,
         SUM(monto) AS total
       FROM movimientos
       WHERE presupuesto_id = ? AND periodo_id = ? AND firebase_uid = ?
       GROUP BY clasificacion`,
      [id, periodo.id, firebase_uid]
    );

    const realPorClasif = {};
    clasifRows.forEach(r => { realPorClasif[r.clasificacion] = Number(r.total); });

    const totalGastado = Object.values(realPorClasif).reduce((a, b) => Number(a) + Number(b), 0);
    const margenDisponible = base - totalGastado;
    const margenPct = base > 0 ? margenDisponible / base : 0;

    const recomendacion = {
      tiene_income,
      base_calculo: base,
      regla: '50-30-20',
      margen_disponible: parseFloat(margenDisponible.toFixed(2)),
      margen_ajustado: margenPct < 0.15, // true cuando hay < 15% de margen
      categorias: [
        {
          clasificacion: 'esencial',
          label: 'Necesidades esenciales',
          pct_recomendado: 0.50,
          monto_recomendado: parseFloat((base * 0.50).toFixed(2)),
          monto_real: realPorClasif['esencial'] || 0,
          diferencia: parseFloat(((realPorClasif['esencial'] || 0) - base * 0.50).toFixed(2)),
        },
        {
          clasificacion: 'importante',
          label: 'Gastos importantes',
          pct_recomendado: 0.30,
          monto_recomendado: parseFloat((base * 0.30).toFixed(2)),
          monto_real: realPorClasif['importante'] || 0,
          diferencia: parseFloat(((realPorClasif['importante'] || 0) - base * 0.30).toFixed(2)),
        },
        {
          clasificacion: 'flexible',
          label: 'Gastos flexibles / ahorro',
          pct_recomendado: 0.20,
          monto_recomendado: parseFloat((base * 0.20).toFixed(2)),
          monto_real: realPorClasif['flexible'] || 0,
          diferencia: parseFloat(((realPorClasif['flexible'] || 0) - base * 0.20).toFixed(2)),
        },
      ],
      sin_clasificar: realPorClasif['sin_clasificar'] || 0,
    };

    res.json(recomendacion);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: error.message });
  }
});

// =============================================================================
// #9 DEUDAS COMO ENTIDAD PROPIA
// =============================================================================

// Enriquece una deuda con campos calculados útiles para el frontend
function _enriquecerDeuda(d) {
  const cuotas_restantes = d.es_letra && d.num_cuotas_total
    ? Math.max(0, Number(d.num_cuotas_total) - Number(d.num_cuotas_pagadas || 0))
    : null;
  let fecha_fin_estimada = null;
  if (d.es_letra && cuotas_restantes !== null && d.fecha_proximo_pago) {
    const base = new Date(d.fecha_proximo_pago);
    base.setMonth(base.getMonth() + cuotas_restantes - 1);
    fecha_fin_estimada = base.toISOString().slice(0, 10);
  }
  return { ...d, cuotas_restantes, fecha_fin_estimada };
}

// GET /deudas?firebase_uid=   — lista deudas activas del usuario
app.get('/deudas', async (req, res) => {
  const { firebase_uid, incluir_saldadas } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid es requerido' });
  try {
    const soloActivas = incluir_saldadas === '1' ? '' : "AND activa = 1";
    const [rows] = await db.execute(
      `SELECT * FROM deudas WHERE firebase_uid = ? ${soloActivas} ORDER BY fecha_proximo_pago ASC, created_at DESC`,
      [firebase_uid]
    );
    const enriquecidas = rows.map(_enriquecerDeuda);
    const totalPendiente  = enriquecidas.reduce((s, d) => s + Number(d.monto_pendiente), 0);
    const totalPagoMinimo = enriquecidas.reduce((s, d) => s + Number(d.pago_minimo || 0), 0);
    res.json({ deudas: enriquecidas, total_pendiente: totalPendiente, total_pago_minimo: totalPagoMinimo });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: error.message });
  }
});

// POST /deudas — crear nueva deuda o letra (compra a plazo)
// Para letras: es_letra=1, cuota_fija=X, num_cuotas_total=N, nombre_acreedor=Y, fecha_inicio=YYYY-MM-DD
// tasa_interes=0 en letras sin interés. monto_pendiente = cuota_fija * (num_cuotas_total - num_cuotas_pagadas)
app.post('/deudas', async (req, res) => {
  const {
    firebase_uid, nombre, tipo = 'personal',
    monto_total, monto_pendiente,
    tasa_interes = null, pago_minimo = null,
    fecha_proximo_pago = null, notas = null,
    // Campos de letra/cuota
    es_letra = 0, num_cuotas_total = null, num_cuotas_pagadas = 0,
    cuota_fija = null, nombre_acreedor = null, fecha_inicio = null,
  } = req.body;
  if (!firebase_uid || !nombre || monto_total == null || monto_pendiente == null)
    return res.status(400).json({ error: 'firebase_uid, nombre, monto_total y monto_pendiente son requeridos' });
  try {
    const tiposValidos = ['tarjeta_credito','prestamo','hipoteca','auto','personal','letra','otro'];
    const tipoFinal = tiposValidos.includes(tipo) ? tipo : 'personal';
    // Para letras: pago_minimo = cuota_fija si no se especifica
    const pagoMinFinal = pago_minimo ?? (es_letra && cuota_fija ? cuota_fija : null);
    const [result] = await db.execute(
      `INSERT INTO deudas
         (firebase_uid, nombre, tipo, monto_total, monto_pendiente, tasa_interes,
          pago_minimo, fecha_proximo_pago, notas,
          es_letra, num_cuotas_total, num_cuotas_pagadas, cuota_fija, nombre_acreedor, fecha_inicio)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [firebase_uid, nombre, tipoFinal, monto_total, monto_pendiente, tasa_interes,
       pagoMinFinal, fecha_proximo_pago, notas,
       Number(es_letra), num_cuotas_total, Number(num_cuotas_pagadas), cuota_fija, nombre_acreedor, fecha_inicio]
    );
    const [[created]] = await db.execute(`SELECT * FROM deudas WHERE id = ?`, [result.insertId]);
    res.status(201).json(_enriquecerDeuda(created));
    _logInfo('/deudas', `Deuda creada: "${nombre}" ${es_letra ? 'letra' : tipo} - pendiente $${Number(monto_pendiente).toFixed(2)}`, firebase_uid);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: error.message });
  }
});

// PUT /deudas/:id — editar deuda o letra
app.put('/deudas/:id', async (req, res) => {
  const { id } = req.params;
  const {
    firebase_uid, nombre, tipo, monto_total, monto_pendiente,
    tasa_interes, pago_minimo, fecha_proximo_pago, notas,
    es_letra, num_cuotas_total, num_cuotas_pagadas, cuota_fija, nombre_acreedor, fecha_inicio,
  } = req.body;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid es requerido' });
  try {
    const fields = [], vals = [];
    if (nombre !== undefined)             { fields.push('nombre = ?');             vals.push(nombre); }
    if (tipo !== undefined)               { fields.push('tipo = ?');               vals.push(tipo); }
    if (monto_total !== undefined)        { fields.push('monto_total = ?');        vals.push(monto_total); }
    if (monto_pendiente !== undefined)    { fields.push('monto_pendiente = ?');    vals.push(monto_pendiente); }
    if (tasa_interes !== undefined)       { fields.push('tasa_interes = ?');       vals.push(tasa_interes); }
    if (pago_minimo !== undefined)        { fields.push('pago_minimo = ?');        vals.push(pago_minimo); }
    if (fecha_proximo_pago !== undefined) { fields.push('fecha_proximo_pago = ?'); vals.push(fecha_proximo_pago); }
    if (notas !== undefined)              { fields.push('notas = ?');              vals.push(notas); }
    if (es_letra !== undefined)           { fields.push('es_letra = ?');           vals.push(Number(es_letra)); }
    if (num_cuotas_total !== undefined)   { fields.push('num_cuotas_total = ?');   vals.push(num_cuotas_total); }
    if (num_cuotas_pagadas !== undefined) { fields.push('num_cuotas_pagadas = ?'); vals.push(num_cuotas_pagadas); }
    if (cuota_fija !== undefined)         { fields.push('cuota_fija = ?');         vals.push(cuota_fija); }
    if (nombre_acreedor !== undefined)    { fields.push('nombre_acreedor = ?');    vals.push(nombre_acreedor); }
    if (fecha_inicio !== undefined)       { fields.push('fecha_inicio = ?');       vals.push(fecha_inicio); }
    if (fields.length === 0) return res.status(400).json({ error: 'Nada que actualizar' });
    vals.push(id, firebase_uid);
    const [result] = await db.execute(
      `UPDATE deudas SET ${fields.join(', ')} WHERE id = ? AND firebase_uid = ?`, vals
    );
    if (result.affectedRows === 0) return res.status(404).json({ error: 'Deuda no encontrada' });
    const [[updated]] = await db.execute(`SELECT * FROM deudas WHERE id = ?`, [id]);
    res.json(_enriquecerDeuda(updated));
    _logInfo(`/deudas/${id}`, `Deuda editada: "${updated.nombre}" - pendiente $${Number(updated.monto_pendiente).toFixed(2)}`, firebase_uid);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: error.message });
  }
});

// PATCH /deudas/:id/abono — registrar un abono (reduce monto_pendiente)
app.patch('/deudas/:id/abono', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid, monto_abono, fecha_proximo_pago } = req.body;
  if (!firebase_uid || monto_abono == null) return res.status(400).json({ error: 'firebase_uid y monto_abono son requeridos' });
  if (Number(monto_abono) <= 0) return res.status(400).json({ error: 'monto_abono debe ser mayor a 0' });
  try {
    const [[deuda]] = await db.execute(
      `SELECT * FROM deudas WHERE id = ? AND firebase_uid = ? AND activa = 1`, [id, firebase_uid]
    );
    if (!deuda) return res.status(404).json({ error: 'Deuda no encontrada o ya saldada' });
    const nuevoPendiente = Math.max(0, Number(deuda.monto_pendiente) - Number(monto_abono));
    const nuevaActiva = nuevoPendiente > 0 ? 1 : 0;
    const updateFields = ['monto_pendiente = ?', 'activa = ?'];
    const updateVals   = [nuevoPendiente, nuevaActiva];
    if (fecha_proximo_pago) { updateFields.push('fecha_proximo_pago = ?'); updateVals.push(fecha_proximo_pago); }
    updateVals.push(id, firebase_uid);
    await db.execute(`UPDATE deudas SET ${updateFields.join(', ')} WHERE id = ? AND firebase_uid = ?`, updateVals);
    const [[updated]] = await db.execute(`SELECT * FROM deudas WHERE id = ?`, [id]);
    res.json({ ...updated, saldada: nuevaActiva === 0 });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: error.message });
  }
});

// DELETE /deudas/:id?firebase_uid= — archivar deuda (activa=0)
app.delete('/deudas/:id', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid es requerido' });
  try {
    const [result] = await db.execute(
      `UPDATE deudas SET activa = 0 WHERE id = ? AND firebase_uid = ?`, [id, firebase_uid]
    );
    if (result.affectedRows === 0) return res.status(404).json({ error: 'Deuda no encontrada' });
    res.json({ message: 'Deuda archivada' });
    _logInfo(`/deudas/${id}`, `Deuda archivada (id=${id})`, firebase_uid);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: error.message });
  }
});

// =============================================================================
// GET /presupuestos/:id/proyeccion — Vista mes a mes (pasado real + futuro estimado)
// Máximo 2 queries al pool. Devuelve 12 tarjetas mensuales.
// =============================================================================
app.get('/presupuestos/:id/proyeccion', async (req, res) => {
  const id = parseInt(req.params.id);
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });

  try {
    // Query 1: income + datos del presupuesto
    const [[presRow]] = await db.execute(
      `SELECT p.monto_total, p.tipo_periodo, p.dia_inicio_periodo,
              bi.ingreso_neto
       FROM presupuestos p
       LEFT JOIN budget_income bi ON bi.presupuesto_id = p.id AND bi.firebase_uid = p.firebase_uid
       WHERE p.id = ? AND p.firebase_uid = ? LIMIT 1`,
      [id, firebase_uid]
    );
    if (!presRow) return res.status(404).json({ error: 'Presupuesto no encontrado' });

    const ingresoNeto    = presRow.ingreso_neto   ? parseFloat(presRow.ingreso_neto)   : parseFloat(presRow.monto_total);
    const tipoPeriodo    = presRow.tipo_periodo;
    const diaInicio      = presRow.dia_inicio_periodo || 1;

    // Query 2: todos los periodos con totales (single JOIN — no N+1)
    const [rows] = await db.execute(
      `SELECT
         p.id, p.numero_periodo, p.fecha_inicio, p.fecha_fin, p.estado,
         COALESCE(SUM(CASE WHEN m.tipo IN ('fijo','fijo_x_periodo') AND m.pagado=1
                          THEN COALESCE(m.monto_pagado_real, m.monto) ELSE 0 END), 0) AS total_fijo,
         COALESCE(SUM(CASE WHEN m.tipo = 'no fijo' AND m.pagado=1
                          THEN COALESCE(m.monto_pagado_real, m.monto) ELSE 0 END), 0) AS total_variable,
         COALESCE(SUM(CASE WHEN m.tipo = 'ahorro' AND m.pagado=1
                          THEN COALESCE(m.monto_pagado_real, m.monto) ELSE 0 END), 0) AS total_ahorro,
         COALESCE(SUM(CASE WHEN m.pagado=1
                          THEN COALESCE(m.monto_pagado_real, m.monto) ELSE 0 END), 0) AS total_gastado,
         COUNT(m.id) AS total_movimientos
       FROM periodos p
       LEFT JOIN movimientos m ON m.periodo_id = p.id AND m.firebase_uid = p.firebase_uid
       WHERE p.presupuesto_id = ? AND p.firebase_uid = ?
       GROUP BY p.id ORDER BY p.fecha_inicio ASC`,
      [id, firebase_uid]
    );

    // Calcular promedios de los últimos 3 periodos cerrados
    const cerrados = rows.filter(r => r.estado === 'cerrado');
    const ultimos3 = cerrados.slice(-3);
    const avgFijo     = ultimos3.length > 0 ? ultimos3.reduce((s, r) => s + parseFloat(r.total_fijo),     0) / ultimos3.length : 0;
    const avgVariable = ultimos3.length > 0 ? ultimos3.reduce((s, r) => s + parseFloat(r.total_variable), 0) / ultimos3.length : 0;
    const avgAhorro   = ultimos3.length > 0 ? ultimos3.reduce((s, r) => s + parseFloat(r.total_ahorro),   0) / ultimos3.length : 0;

    // Construir el mes_label en formato "Ene 2026"
    const MESES = ['Ene','Feb','Mar','Abr','May','Jun','Jul','Ago','Sep','Oct','Nov','Dic'];
    const mesLabel = (fechaStr) => {
      const d = new Date(fechaStr + 'T12:00:00Z');
      return `${MESES[d.getUTCMonth()]} ${d.getUTCFullYear()}`;
    };

    // Función para calcular siguiente fecha_fin desde un fecha_inicio y tipo
    const siguienteFechaFin = (inicioStr, tipo) => {
      const d = new Date(inicioStr + 'T12:00:00Z');
      const dias = tipo === 'quincenal' ? 14 : 30;
      d.setUTCDate(d.getUTCDate() + dias - 1);
      return d.toISOString().slice(0, 10);
    };

    const siguienteFechaInicio = (finStr, tipo, dia) => {
      const d = new Date(finStr + 'T12:00:00Z');
      d.setUTCDate(d.getUTCDate() + 1);
      return d.toISOString().slice(0, 10);
    };

    // Helper: normaliza fecha de MySQL (Date object o ISO string) a 'YYYY-MM-DD'
    const toDateStr = (v) => {
      if (!v) return new Date().toISOString().slice(0, 10);
      if (v instanceof Date) return v.toISOString().slice(0, 10);
      return String(v).slice(0, 10);
    };

    // Construir meses reales
    const meses = rows.map(r => {
      const fi = toDateStr(r.fecha_inicio);
      const ff = toDateStr(r.fecha_fin);
      return {
        tipo:                r.estado === 'cerrado' ? 'real' : 'activo',
        periodo_id:          r.id,
        numero_periodo:      r.numero_periodo,
        mes_label:           mesLabel(fi),
        fecha_inicio:        fi,
        fecha_fin:           ff,
        ingreso_proyectado:  ingresoNeto,
        gastos_proyectados:  parseFloat(r.total_fijo) + parseFloat(r.total_variable) + parseFloat(r.total_ahorro),
        saldo_estimado:      ingresoNeto - parseFloat(r.total_fijo) - parseFloat(r.total_variable) - parseFloat(r.total_ahorro),
        total_fijo:          parseFloat(r.total_fijo),
        total_variable:      parseFloat(r.total_variable),
        total_ahorro:        parseFloat(r.total_ahorro),
        total_gastado:       parseFloat(r.total_gastado),
        porcentaje_ejecutado: ingresoNeto > 0 ? parseFloat(r.total_gastado) / ingresoNeto : null,
      };
    });

    // Rellenar con meses proyectados hasta llegar a 12
    const activo = rows.find(r => r.estado === 'activo');
    let ultimaFechaFin = activo
      ? toDateStr(activo.fecha_fin)
      : (rows.length > 0 ? toDateStr(rows[rows.length - 1].fecha_fin) : new Date().toISOString().slice(0, 10));
    let numeroPeriodo = rows.length > 0 ? rows[rows.length - 1].numero_periodo : 0;

    while (meses.length < 12) {
      const nuevoInicio = siguienteFechaInicio(ultimaFechaFin, tipoPeriodo, diaInicio);
      const nuevoFin    = siguienteFechaFin(nuevoInicio, tipoPeriodo);
      numeroPeriodo++;
      const gastosProyect = avgFijo + avgVariable + avgAhorro;
      meses.push({
        tipo:                'proyectado',
        periodo_id:          null,
        numero_periodo:      numeroPeriodo,
        mes_label:           mesLabel(nuevoInicio),
        fecha_inicio:        nuevoInicio,
        fecha_fin:           nuevoFin,
        ingreso_proyectado:  ingresoNeto,
        gastos_proyectados:  parseFloat(gastosProyect.toFixed(2)),
        saldo_estimado:      parseFloat((ingresoNeto - gastosProyect).toFixed(2)),
        total_fijo:          parseFloat(avgFijo.toFixed(2)),
        total_variable:      parseFloat(avgVariable.toFixed(2)),
        total_ahorro:        parseFloat(avgAhorro.toFixed(2)),
        total_gastado:       null,
        porcentaje_ejecutado: null,
      });
      ultimaFechaFin = nuevoFin;
    }

    res.json({
      ingreso_neto:  ingresoNeto,
      tiene_income:  !!presRow.ingreso_neto,
      avg_fijo:      parseFloat(avgFijo.toFixed(2)),
      avg_variable:  parseFloat(avgVariable.toFixed(2)),
      avg_ahorro:    parseFloat(avgAhorro.toFixed(2)),
      meses,
    });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: error.message });
  }
});

// =============================================================================
// MÓDULO: SOBRES (categorías de gasto variable por presupuesto)
// =============================================================================

// GET /presupuestos/:id/categorias
app.get('/presupuestos/:id/categorias', async (req, res) => {
  const presupuestoId = parseInt(req.params.id);
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [cats] = await db.execute(
      `SELECT * FROM presupuesto_categorias
       WHERE presupuesto_id = ? AND firebase_uid = ? AND activa = 1
       ORDER BY orden ASC, id ASC`,
      [presupuestoId, firebase_uid]
    );
    res.json({ categorias: cats });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// POST /presupuestos/:id/categorias
app.post('/presupuestos/:id/categorias', async (req, res) => {
  const presupuestoId = parseInt(req.params.id);
  const { firebase_uid, nombre, icono = 'category', color = '#6B7280', monto_asignado = 0, orden = 0 } = req.body;
  if (!firebase_uid || !nombre) return res.status(400).json({ error: 'firebase_uid y nombre son requeridos' });
  try {
    const [r] = await db.execute(
      `INSERT INTO presupuesto_categorias (presupuesto_id, firebase_uid, nombre, icono, color, monto_asignado, orden)
       VALUES (?, ?, ?, ?, ?, ?, ?)`,
      [presupuestoId, firebase_uid, nombre, icono, color, monto_asignado, orden]
    );
    const [[cat]] = await db.execute(`SELECT * FROM presupuesto_categorias WHERE id = ?`, [r.insertId]);
    res.status(201).json(cat);
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// PUT /presupuestos/:id/categorias/:catId
app.put('/presupuestos/:id/categorias/:catId', async (req, res) => {
  const { catId } = req.params;
  const { firebase_uid, nombre, icono, color, monto_asignado, orden } = req.body;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const fields = [], vals = [];
    if (nombre !== undefined)         { fields.push('nombre = ?');         vals.push(nombre); }
    if (icono !== undefined)          { fields.push('icono = ?');          vals.push(icono); }
    if (color !== undefined)          { fields.push('color = ?');          vals.push(color); }
    if (monto_asignado !== undefined) { fields.push('monto_asignado = ?'); vals.push(monto_asignado); }
    if (orden !== undefined)          { fields.push('orden = ?');          vals.push(orden); }
    if (!fields.length) return res.status(400).json({ error: 'Nada que actualizar' });
    vals.push(catId, firebase_uid);
    const [result] = await db.execute(
      `UPDATE presupuesto_categorias SET ${fields.join(', ')} WHERE id = ? AND firebase_uid = ?`, vals
    );
    if (result.affectedRows === 0) return res.status(404).json({ error: 'Categoría no encontrada' });
    const [[cat]] = await db.execute(`SELECT * FROM presupuesto_categorias WHERE id = ?`, [catId]);
    res.json(cat);
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// DELETE /presupuestos/:id/categorias/:catId
app.delete('/presupuestos/:id/categorias/:catId', async (req, res) => {
  const { catId } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    await db.execute(
      `UPDATE presupuesto_categorias SET activa = 0 WHERE id = ? AND firebase_uid = ?`,
      [catId, firebase_uid]
    );
    res.json({ message: 'Categoría eliminada' });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// POST /presupuestos/:id/gastos-rapidos — registrar gasto en sobre
app.post('/presupuestos/:id/gastos-rapidos', async (req, res) => {
  const presupuestoId = parseInt(req.params.id);
  const { firebase_uid, categoria_id = null, descripcion = '', monto, fecha, es_hormiga = 0, periodo_id = null } = req.body;
  if (!firebase_uid || monto == null) return res.status(400).json({ error: 'firebase_uid y monto son requeridos' });
  try {
    const fechaFinal = fecha || new Date().toISOString().slice(0, 10);
    const [r] = await db.execute(
      `INSERT INTO presupuesto_gastos (presupuesto_id, periodo_id, categoria_id, firebase_uid, descripcion, monto, fecha, es_hormiga)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
      [presupuestoId, periodo_id, categoria_id, firebase_uid, descripcion, monto, fechaFinal, es_hormiga]
    );
    const [[gasto]] = await db.execute(`SELECT * FROM presupuesto_gastos WHERE id = ?`, [r.insertId]);
    res.status(201).json(gasto);
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// DELETE /presupuestos/:id/gastos-rapidos/:gastoId
app.delete('/presupuestos/:id/gastos-rapidos/:gastoId', async (req, res) => {
  const { gastoId } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [result] = await db.execute(
      `DELETE FROM presupuesto_gastos WHERE id = ? AND firebase_uid = ?`, [gastoId, firebase_uid]
    );
    if (result.affectedRows === 0) return res.status(404).json({ error: 'Gasto no encontrado' });
    res.json({ message: 'Eliminado' });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// GET /presupuestos/:id/resumen-sobres?periodo_id=X — resumen por categoría
app.get('/presupuestos/:id/resumen-sobres', async (req, res) => {
  const presupuestoId = parseInt(req.params.id);
  const { firebase_uid, periodo_id } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [cats] = await db.execute(
      `SELECT * FROM presupuesto_categorias
       WHERE presupuesto_id = ? AND firebase_uid = ? AND activa = 1
       ORDER BY orden ASC, id ASC`,
      [presupuestoId, firebase_uid]
    );

    const periodoFilter = periodo_id ? 'AND pg.periodo_id = ?' : '';
    const periodoParams = periodo_id ? [presupuestoId, firebase_uid, periodo_id] : [presupuestoId, firebase_uid];
    const [gastos] = await db.execute(
      `SELECT pg.categoria_id, COALESCE(SUM(pg.monto), 0) AS gastado
       FROM presupuesto_gastos pg
       WHERE pg.presupuesto_id = ? AND pg.firebase_uid = ? ${periodoFilter}
       GROUP BY pg.categoria_id`,
      periodoParams
    );

    const gastoMap = {};
    gastos.forEach(g => { gastoMap[g.categoria_id ?? 'sin_categoria'] = Number(g.gastado); });

    const totalAsignado = cats.reduce((s, c) => s + Number(c.monto_asignado), 0);
    const totalGastado  = Object.values(gastoMap).reduce((s, v) => s + v, 0);

    const categoriasConGasto = cats.map(c => {
      const gastado = gastoMap[c.id] || 0;
      return {
        ...c,
        monto_asignado: Number(c.monto_asignado),
        monto_gastado: gastado,
        restante: Number(c.monto_asignado) - gastado,
        porcentaje: c.monto_asignado > 0 ? Math.round((gastado / Number(c.monto_asignado)) * 100) : 0,
      };
    });

    // Gastos sin categoría asignada
    const sinCategoria = gastoMap['sin_categoria'] || 0;

    res.json({
      total_asignado: parseFloat(totalAsignado.toFixed(2)),
      total_gastado:  parseFloat(totalGastado.toFixed(2)),
      sin_asignar:    parseFloat((totalAsignado - totalGastado).toFixed(2)),
      gastos_sin_categoria: parseFloat(sinCategoria.toFixed(2)),
      categorias: categoriasConGasto,
    });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// GET /presupuestos/:id/gastos-rapidos?periodo_id=X — lista de gastos del período
app.get('/presupuestos/:id/gastos-rapidos', async (req, res) => {
  const presupuestoId = parseInt(req.params.id);
  const { firebase_uid, periodo_id } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const periodoFilter = periodo_id ? 'AND pg.periodo_id = ?' : '';
    const params = periodo_id ? [presupuestoId, firebase_uid, periodo_id] : [presupuestoId, firebase_uid];
    const [gastos] = await db.execute(
      `SELECT pg.*, pc.nombre AS categoria_nombre, pc.icono AS categoria_icono, pc.color AS categoria_color
       FROM presupuesto_gastos pg
       LEFT JOIN presupuesto_categorias pc ON pc.id = pg.categoria_id
       WHERE pg.presupuesto_id = ? AND pg.firebase_uid = ? ${periodoFilter}
       ORDER BY pg.fecha DESC, pg.id DESC`,
      params
    );
    const total = gastos.reduce((s, g) => s + Number(g.monto), 0);
    res.json({ gastos, total: parseFloat(total.toFixed(2)) });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// =============================================================================
// MÓDULO: TIMELINE FINANCIERO Y PROYECCIÓN DE ESCENARIOS
// Proyecta mes a mes el estado financiero del usuario a partir del perfil.
// Las deudas disminuyen cada mes; cuando se saldan, el dinero queda disponible.
// El simulador aplica un escenario hipotético y devuelve el delta de impacto.
// =============================================================================

/**
 * Construye la proyección mes a mes del perfil financiero.
 * @param {object} income - Registro de user_income
 * @param {Array}  gastosFijos - Registros de user_gastos_fijos activos
 * @param {Array}  deudas - Registros de deudas activas
 * @param {number} meses - Cuántos meses proyectar (default 12)
 * @returns {Array} Array de objetos mensuales con disponible, eventos, etc.
 */
function _construirTimeline(income, gastosFijos, deudas, meses = 12) {
  const ingresoNeto   = income ? Number(income.ingreso_neto_mensual) : 0;
  const totalGastosFijos = gastosFijos.reduce((s, g) => s + Number(g.monto_mensual), 0);

  // Clonar estado de deudas para simular mes a mes
  const estadoDeudas = deudas.map(d => ({
    id:          d.id,
    nombre:      d.nombre,
    pendiente:   Number(d.monto_pendiente),
    tasa_mensual: Number(d.tasa_interes || 0) / 100 / 12,
    cuota:       d.es_letra ? Number(d.cuota_fija || 0) : Number(d.pago_minimo || 0),
    es_letra:    Boolean(d.es_letra),
    mes_saldado: null,
  }));

  const MESES_LABEL = ['Ene','Feb','Mar','Abr','May','Jun','Jul','Ago','Sep','Oct','Nov','Dic'];
  const hoy = new Date();
  const timeline = [];

  for (let m = 1; m <= meses; m++) {
    const fechaMes  = new Date(hoy.getFullYear(), hoy.getMonth() + m - 1, 1);
    const label     = `${MESES_LABEL[fechaMes.getMonth()]} ${fechaMes.getFullYear()}`;
    const eventos   = [];

    // Simular un mes de deudas: aplicar interés + cuota
    let cuotasTotales = 0;
    for (const d of estadoDeudas) {
      if (d.pendiente <= 0) continue;
      if (!d.es_letra) {
        const interes = d.pendiente * d.tasa_mensual;
        d.pendiente = Math.max(0, d.pendiente + interes - d.cuota);
      } else {
        d.pendiente = Math.max(0, d.pendiente - d.cuota);
      }
      const cuotaEfectiva = d.pendiente <= 0 ? 0 : d.cuota;
      cuotasTotales += cuotaEfectiva;

      if (d.pendiente <= 0 && d.mes_saldado === null) {
        d.mes_saldado = m;
        eventos.push({
          tipo:    'deuda_saldada',
          mensaje: `"${d.nombre}" queda saldada — libera $${d.cuota.toFixed(2)}/mes`,
          deuda_id: d.id,
          cuota_liberada: d.cuota,
        });
      }
    }

    const compromisos  = parseFloat((totalGastosFijos + cuotasTotales).toFixed(2));
    const disponible   = parseFloat((ingresoNeto - compromisos).toFixed(2));

    timeline.push({
      mes:             m,
      label,
      fecha:           fechaMes.toISOString().slice(0, 7),   // "YYYY-MM"
      ingreso_neto:    parseFloat(ingresoNeto.toFixed(2)),
      gastos_fijos:    parseFloat(totalGastosFijos.toFixed(2)),
      cuotas_deudas:   parseFloat(cuotasTotales.toFixed(2)),
      compromisos,
      disponible,
      ratio_compromiso: ingresoNeto > 0
        ? parseFloat((compromisos / ingresoNeto * 100).toFixed(1)) : 0,
      salud: disponible >= 0
        ? (compromisos / ingresoNeto < 0.7 ? 'buena' : 'ajustada')
        : 'critica',
      eventos,
    });
  }
  return timeline;
}

// GET /user/timeline?firebase_uid=&meses=12
// Proyecta el estado financiero mes a mes desde el perfil del usuario.
// Refleja deudas que se saldan y el dinero que liberan.
app.get('/user/timeline', async (req, res) => {
  const { firebase_uid, meses = 12 } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [[income]] = await db.execute(
      `SELECT * FROM user_income WHERE firebase_uid = ?`, [firebase_uid]
    );
    const [gastosFijos] = await db.execute(
      `SELECT * FROM user_gastos_fijos WHERE firebase_uid = ? AND activo = 1`, [firebase_uid]
    );
    const [deudas] = await db.execute(
      `SELECT * FROM deudas WHERE firebase_uid = ? AND activa = 1 AND monto_pendiente > 0`,
      [firebase_uid]
    );

    const mesesNum = Math.min(Math.max(Number(meses) || 12, 3), 36);
    const timeline = _construirTimeline(income, gastosFijos, deudas, mesesNum);

    // Resumen ejecutivo del timeline
    const mesActual      = timeline[0];
    const mesMejor       = timeline.reduce((a, b) => b.disponible > a.disponible ? b : a);
    const mesesCriticos  = timeline.filter(t => t.salud === 'critica').length;
    const totalIntereses = deudas.reduce((s, d) => {
      // Estimación simplificada de intereses totales
      const tasa = Number(d.tasa_interes || 0) / 100 / 12;
      return s + Number(d.monto_pendiente) * tasa * mesesNum;
    }, 0);

    res.json({
      tiene_perfil_completo: !!income,
      resumen: {
        ingreso_neto_mensual:    income ? parseFloat(Number(income.ingreso_neto_mensual).toFixed(2)) : 0,
        disponible_hoy:          mesActual.disponible,
        mejor_mes:               { label: mesMejor.label, disponible: mesMejor.disponible },
        meses_criticos:          mesesCriticos,
        deudas_activas:          deudas.length,
        fecha_libertad_deudas:   deudas.length === 0 ? null : (() => {
          const ultimo = [...timeline].reverse().find(t => t.eventos.some(e => e.tipo === 'deuda_saldada'));
          return ultimo ? ultimo.fecha : null;
        })(),
      },
      meses: timeline,
    });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// POST /user/timeline/simular
// Aplica un escenario hipotético al perfil y devuelve el timeline modificado
// con el delta de impacto vs el timeline base.
//
// Escenarios soportados (campo "tipo"):
//   eliminar_gasto    → elimina un user_gasto_fijo del cálculo (gasto_fijo_id requerido)
//   pagar_deuda_hoy   → marca una deuda como saldada desde mes 1 (deuda_id requerido)
//   extra_pago_deuda  → añade un pago extra mensual a una deuda (deuda_id + extra_mensual)
//   nuevo_compromiso  → agrega un gasto fijo nuevo (nombre + monto)
//   cambiar_ingreso   → simula cambio de ingreso (nuevo_ingreso)
app.post('/user/timeline/simular', async (req, res) => {
  const { firebase_uid, tipo, meses = 12, gasto_fijo_id, deuda_id, extra_mensual, monto, nombre, nuevo_ingreso } = req.body;
  if (!firebase_uid || !tipo) return res.status(400).json({ error: 'firebase_uid y tipo son requeridos' });

  try {
    const [[income]] = await db.execute(
      `SELECT * FROM user_income WHERE firebase_uid = ?`, [firebase_uid]
    );
    const [gastosFijos] = await db.execute(
      `SELECT * FROM user_gastos_fijos WHERE firebase_uid = ? AND activo = 1`, [firebase_uid]
    );
    const [deudas] = await db.execute(
      `SELECT * FROM deudas WHERE firebase_uid = ? AND activa = 1 AND monto_pendiente > 0`, [firebase_uid]
    );

    const mesesNum = Math.min(Math.max(Number(meses) || 12, 3), 36);

    // Timeline BASE (sin escenario)
    const timelineBase = _construirTimeline(income, gastosFijos, deudas, mesesNum);

    // Aplicar mutación al escenario
    let incomeEsc      = income ? { ...income } : null;
    let gastosFijosEsc = gastosFijos.map(g => ({ ...g }));
    let deudasEsc      = deudas.map(d => ({ ...d }));
    let descripcionEscenario = '';

    switch (tipo) {
      case 'eliminar_gasto':
        if (!gasto_fijo_id) return res.status(400).json({ error: 'gasto_fijo_id requerido' });
        gastosFijosEsc = gastosFijosEsc.filter(g => g.id !== Number(gasto_fijo_id));
        const gastoEliminado = gastosFijos.find(g => g.id === Number(gasto_fijo_id));
        descripcionEscenario = `Eliminar "${gastoEliminado?.descripcion || 'gasto'}" ($${gastoEliminado?.monto_mensual}/mes)`;
        break;

      case 'pagar_deuda_hoy':
        if (!deuda_id) return res.status(400).json({ error: 'deuda_id requerido' });
        deudasEsc = deudasEsc.filter(d => d.id !== Number(deuda_id));
        const deudaEliminada = deudas.find(d => d.id === Number(deuda_id));
        descripcionEscenario = `Saldar "${deudaEliminada?.nombre || 'deuda'}" hoy ($${deudaEliminada?.pago_minimo}/mes liberados)`;
        break;

      case 'extra_pago_deuda':
        if (!deuda_id || !extra_mensual) return res.status(400).json({ error: 'deuda_id y extra_mensual requeridos' });
        deudasEsc = deudasEsc.map(d =>
          d.id === Number(deuda_id)
            ? { ...d, pago_minimo: Number(d.pago_minimo || 0) + Number(extra_mensual), cuota_fija: d.es_letra ? Number(d.cuota_fija || 0) + Number(extra_mensual) : d.cuota_fija }
            : d
        );
        const deudaExtra = deudas.find(d => d.id === Number(deuda_id));
        descripcionEscenario = `Pagar $${extra_mensual}/mes extra en "${deudaExtra?.nombre || 'deuda'}"`;
        break;

      case 'nuevo_compromiso':
        if (monto == null) return res.status(400).json({ error: 'monto requerido' });
        gastosFijosEsc.push({ id: -1, descripcion: nombre || 'Nuevo compromiso', monto_mensual: Number(monto), activo: 1 });
        descripcionEscenario = `Agregar "${nombre || 'Nuevo compromiso'}" ($${monto}/mes)`;
        break;

      case 'cambiar_ingreso':
        if (nuevo_ingreso == null) return res.status(400).json({ error: 'nuevo_ingreso requerido' });
        if (incomeEsc) incomeEsc.ingreso_neto_mensual = Number(nuevo_ingreso);
        else incomeEsc = { ingreso_neto_mensual: Number(nuevo_ingreso) };
        descripcionEscenario = `Cambiar ingreso neto a $${nuevo_ingreso}/mes`;
        break;

      default:
        return res.status(400).json({ error: `Tipo de escenario desconocido: ${tipo}` });
    }

    // Timeline con escenario aplicado
    const timelineEsc = _construirTimeline(incomeEsc, gastosFijosEsc, deudasEsc, mesesNum);

    // Calcular delta mes a mes
    const mesesConDelta = timelineEsc.map((mes, i) => ({
      ...mes,
      delta_disponible:   parseFloat((mes.disponible - timelineBase[i].disponible).toFixed(2)),
      disponible_base:    timelineBase[i].disponible,
    }));

    const gananciaTotalEstimada = mesesConDelta.reduce((s, m) => s + m.delta_disponible, 0);

    res.json({
      escenario: { tipo, descripcion: descripcionEscenario },
      impacto: {
        delta_mes1:                parseFloat(mesesConDelta[0].delta_disponible.toFixed(2)),
        ganancia_total_estimada:   parseFloat(gananciaTotalEstimada.toFixed(2)),
        meses_analizados:          mesesNum,
      },
      meses: mesesConDelta,
    });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// =============================================================================
// MÓDULO: GASTOS GLOBALES
// Gastos reutilizables independientes de presupuesto.
// Flag individual/compartido. Pueden usarse en cualquier presupuesto.
// =============================================================================

// GET /gastos-globales/stats?firebase_uid= — totales para widget del AppBar
app.get('/gastos-globales/stats', async (req, res) => {
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [[stats]] = await db.execute(
      `SELECT
         COUNT(*)                                        AS total,
         SUM(modalidad = 'individual')                  AS individuales,
         SUM(modalidad = 'compartido')                  AS compartidos,
         SUM(tipo = 'fijo')                             AS fijos,
         SUM(tipo = 'variable')                         AS variables,
         COALESCE(SUM(CASE WHEN frecuencia = 'mensual' THEN monto ELSE 0 END), 0) AS total_mensual_estimado
       FROM gastos_globales
       WHERE firebase_uid = ? AND activo = 1`,
      [firebase_uid]
    );
    // Cuántos gastos globales están en uso en presupuestos activos
    const [[enUso]] = await db.execute(
      `SELECT COUNT(DISTINCT g.gasto_global_id) AS en_uso
       FROM gastos g
       JOIN presupuestos p ON p.id = g.presupuesto_id
       WHERE g.firebase_uid = ? AND g.gasto_global_id IS NOT NULL`,
      [firebase_uid]
    );
    res.json({
      total:                    Number(stats.total),
      individuales:             Number(stats.individuales),
      compartidos:              Number(stats.compartidos),
      fijos:                    Number(stats.fijos),
      variables:                Number(stats.variables),
      total_mensual_estimado:   parseFloat(Number(stats.total_mensual_estimado).toFixed(2)),
      en_uso_en_presupuestos:   Number(enUso.en_uso),
    });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// GET /gastos-globales?firebase_uid=&modalidad=&tipo=&buscar=&activo=1
app.get('/gastos-globales', async (req, res) => {
  const { firebase_uid, modalidad, tipo, buscar, activo = '1' } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    // veces_usado = cuántos gastos en presupuestos enlazan a este global
    let sql = `
      SELECT gg.*,
             COALESCE(uso.veces_usado, 0) AS veces_usado,
             uso.ultimo_presupuesto_id
      FROM gastos_globales gg
      LEFT JOIN (
        SELECT gasto_global_id,
               COUNT(*)  AS veces_usado,
               MAX(presupuesto_id) AS ultimo_presupuesto_id
        FROM gastos
        WHERE gasto_global_id IS NOT NULL
        GROUP BY gasto_global_id
      ) uso ON uso.gasto_global_id = gg.id
      WHERE gg.firebase_uid = ?`;
    const params = [firebase_uid];
    if (activo !== 'todos') { sql += ` AND gg.activo = ?`;    params.push(Number(activo)); }
    if (modalidad)          { sql += ` AND gg.modalidad = ?`; params.push(modalidad); }
    if (tipo)               { sql += ` AND gg.tipo = ?`;      params.push(tipo); }
    if (buscar)             { sql += ` AND gg.nombre LIKE ?`; params.push(`%${buscar}%`); }
    sql += ` ORDER BY uso.veces_usado DESC, gg.nombre ASC`;
    const [rows] = await db.execute(sql, params);
    const totalMensual = rows
      .filter(g => g.activo && g.frecuencia === 'mensual')
      .reduce((s, g) => s + Number(g.monto), 0);
    res.json({ gastos: rows, total_mensual: parseFloat(totalMensual.toFixed(2)) });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// POST /gastos-globales — crear gasto global
app.post('/gastos-globales', async (req, res) => {
  const {
    firebase_uid, nombre, descripcion, monto,
    categoria = 'otro', tipo = 'variable', modalidad = 'individual',
    frecuencia = 'mensual', dia_pago = null, notas = null,
  } = req.body;
  if (!firebase_uid || !nombre || monto == null)
    return res.status(400).json({ error: 'firebase_uid, nombre y monto son requeridos' });
  try {
    const [result] = await db.execute(
      `INSERT INTO gastos_globales
         (firebase_uid, nombre, descripcion, monto, categoria, tipo, modalidad, frecuencia, dia_pago, notas)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [firebase_uid, nombre, descripcion || null, monto, categoria, tipo, modalidad, frecuencia, dia_pago, notas]
    );
    if (dia_pago) {
      await _generarEventosPerfilGasto(firebase_uid, null, nombre, monto, dia_pago);
    }
    const [[created]] = await db.execute(`SELECT * FROM gastos_globales WHERE id = ?`, [result.insertId]);
    res.status(201).json(created);
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// PUT /gastos-globales/:id — editar gasto global (incluyendo cambio individual↔compartido)
app.put('/gastos-globales/:id', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid, nombre, descripcion, monto, categoria, tipo, modalidad, frecuencia, dia_pago, notas, activo } = req.body;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [[existing]] = await db.execute(
      `SELECT * FROM gastos_globales WHERE id = ? AND firebase_uid = ?`, [id, firebase_uid]
    );
    if (!existing) return res.status(404).json({ error: 'Gasto no encontrado' });

    const fields = [], vals = [];
    if (nombre !== undefined)      { fields.push('nombre = ?');      vals.push(nombre); }
    if (descripcion !== undefined) { fields.push('descripcion = ?'); vals.push(descripcion); }
    if (monto !== undefined)       { fields.push('monto = ?');       vals.push(monto); }
    if (categoria !== undefined)   { fields.push('categoria = ?');   vals.push(categoria); }
    if (tipo !== undefined)        { fields.push('tipo = ?');         vals.push(tipo); }
    if (modalidad !== undefined)   { fields.push('modalidad = ?');   vals.push(modalidad); }
    if (frecuencia !== undefined)  { fields.push('frecuencia = ?');  vals.push(frecuencia); }
    if (dia_pago !== undefined)    { fields.push('dia_pago = ?');    vals.push(dia_pago); }
    if (notas !== undefined)       { fields.push('notas = ?');       vals.push(notas); }
    if (activo !== undefined)      { fields.push('activo = ?');      vals.push(activo); }
    if (fields.length === 0) return res.status(400).json({ error: 'Nada que actualizar' });

    vals.push(id, firebase_uid);
    await db.execute(`UPDATE gastos_globales SET ${fields.join(', ')} WHERE id = ? AND firebase_uid = ?`, vals);
    const [[updated]] = await db.execute(`SELECT * FROM gastos_globales WHERE id = ?`, [id]);
    res.json(updated);
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// POST /gastos-globales/:id/usar — agrega un gasto global al período activo de un presupuesto
// Cuerpo: { firebase_uid, presupuesto_id, fecha, tipo? }
// Copia nombre/monto/dia_pago/frecuencia del global. El tipo por defecto es 'no fijo' (variable).
app.post('/gastos-globales/:id/usar', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid, presupuesto_id, fecha, tipo = 'no fijo', subcategoria, clasificacion } = req.body;
  if (!firebase_uid || !presupuesto_id || !fecha)
    return res.status(400).json({ error: 'firebase_uid, presupuesto_id y fecha son requeridos' });
  try {
    const [[global]] = await db.execute(
      `SELECT * FROM gastos_globales WHERE id = ? AND firebase_uid = ? AND activo = 1`,
      [id, firebase_uid]
    );
    if (!global) return res.status(404).json({ error: 'Gasto global no encontrado o inactivo' });

    const fechaStr   = fecha.split('T')[0];
    const tipofecha  = global.dia_pago ? 'fija' : 'flexible';
    const [result] = await db.execute(
      `INSERT INTO gastos
         (presupuesto_id, descripcion, monto, tipo, fecha, pagado, firebase_uid,
          tipo_fecha, dia_pago, frecuencia_pago, subcategoria, clasificacion, gasto_global_id)
       VALUES (?, ?, ?, ?, ?, 0, ?, ?, ?, ?, ?, ?, ?)`,
      [presupuesto_id, global.nombre, global.monto, tipo, fechaStr, firebase_uid,
       tipofecha, global.dia_pago, global.frecuencia,
       subcategoria || null, clasificacion || null, global.id]
    );
    const gastoId = result.insertId;

    // Generar eventos de calendario si tiene día de pago
    if (tipofecha === 'fija') {
      await generarEventosCalendario(gastoId, firebase_uid);
    }

    const [[creado]] = await db.execute(`SELECT * FROM gastos WHERE id = ?`, [gastoId]);
    res.status(201).json({ gasto: creado, gasto_global: global });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// DELETE /gastos-globales/:id — soft delete
app.delete('/gastos-globales/:id', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [result] = await db.execute(
      `UPDATE gastos_globales SET activo = 0 WHERE id = ? AND firebase_uid = ?`, [id, firebase_uid]
    );
    if (result.affectedRows === 0) return res.status(404).json({ error: 'Gasto no encontrado' });
    res.json({ success: true });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// =============================================================================
// MÓDULO: ESTRATEGIA DE DEUDAS — proyección y simulador
// =============================================================================

function _simularDeudas(deudas, extraMensual, estrategia) {
  // Clona y filtra deudas activas con saldo pendiente
  let pendientes = deudas
    .filter(d => d.activa && Number(d.monto_pendiente) > 0)
    .map(d => ({
      id: d.id,
      nombre: d.nombre,
      tipo: d.tipo,
      pendiente: Number(d.monto_pendiente),
      tasa_mensual: Number(d.tasa_interes || 0) / 100 / 12,
      pago_minimo: Number(d.pago_minimo || 0),
      total_intereses: 0,
      mes_saldado: null,
    }));

  if (!pendientes.length) return { meses_totales: 0, total_intereses: 0, orden: [] };

  // Orden según estrategia
  if (estrategia === 'avalanche') {
    pendientes.sort((a, b) => b.tasa_mensual - a.tasa_mensual);
  } else {
    pendientes.sort((a, b) => a.pendiente - b.pendiente);
  }

  let mes = 0;
  const MAX_MESES = 600;

  while (pendientes.some(d => d.pendiente > 0) && mes < MAX_MESES) {
    mes++;
    let extraDisp = Number(extraMensual) || 0;

    for (const d of pendientes) {
      if (d.pendiente <= 0) {
        // Pago mínimo liberado se redirige a la siguiente deuda objetivo
        extraDisp += d.pago_minimo;
        continue;
      }
      // Aplica interés
      const interes = d.pendiente * d.tasa_mensual;
      d.total_intereses += interes;
      d.pendiente += interes;
      // Pago mínimo
      const pago = Math.min(d.pago_minimo, d.pendiente);
      d.pendiente = Math.max(0, d.pendiente - pago);
      if (d.pendiente === 0 && !d.mes_saldado) d.mes_saldado = mes;
    }

    // Aplica monto extra (+ liberados) a la primera deuda con saldo (orden estratégico)
    for (const d of pendientes) {
      if (d.pendiente <= 0 || extraDisp <= 0) continue;
      const aplicar = Math.min(extraDisp, d.pendiente);
      d.pendiente = Math.max(0, d.pendiente - aplicar);
      extraDisp -= aplicar;
      if (d.pendiente === 0 && !d.mes_saldado) d.mes_saldado = mes;
      break;
    }
  }

  const hoy = new Date();
  const fechaFin = new Date(hoy.getFullYear(), hoy.getMonth() + mes, hoy.getDate());

  return {
    meses_totales: mes,
    fecha_fin: fechaFin.toISOString().slice(0, 10),
    total_intereses: parseFloat(pendientes.reduce((s, d) => s + d.total_intereses, 0).toFixed(2)),
    orden: pendientes.map(d => ({
      id: d.id, nombre: d.nombre, tipo: d.tipo,
      mes_saldado: d.mes_saldado,
      intereses_pagados: parseFloat(d.total_intereses.toFixed(2)),
    })),
  };
}

// GET /deudas/proyeccion?firebase_uid=X — situación actual sin extra
app.get('/deudas/proyeccion', async (req, res) => {
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [deudas] = await db.execute(
      `SELECT * FROM deudas WHERE firebase_uid = ? AND activa = 1 AND monto_pendiente > 0`,
      [firebase_uid]
    );
    if (!deudas.length) return res.json({ sin_deudas: true });

    const totalPendiente  = deudas.reduce((s, d) => s + Number(d.monto_pendiente), 0);
    const totalPagoMinimo = deudas.reduce((s, d) => s + Number(d.pago_minimo || 0), 0);

    const avalanche = _simularDeudas(deudas, 0, 'avalanche');
    const snowball  = _simularDeudas(deudas, 0, 'snowball');

    res.json({
      sin_deudas: false,
      total_pendiente:   parseFloat(totalPendiente.toFixed(2)),
      total_pago_minimo: parseFloat(totalPagoMinimo.toFixed(2)),
      trayectoria_actual: {
        meses: avalanche.meses_totales,
        fecha_fin: avalanche.fecha_fin,
        total_intereses: avalanche.total_intereses,
      },
      avalanche,
      snowball,
      ahorro_avalanche_vs_snowball: parseFloat((snowball.total_intereses - avalanche.total_intereses).toFixed(2)),
    });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// GET /deudas/simulador?firebase_uid=X&extra_mensual=150&estrategia=avalanche
app.get('/deudas/simulador', async (req, res) => {
  const { firebase_uid, extra_mensual = 0, estrategia = 'avalanche' } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [deudas] = await db.execute(
      `SELECT * FROM deudas WHERE firebase_uid = ? AND activa = 1 AND monto_pendiente > 0`,
      [firebase_uid]
    );
    if (!deudas.length) return res.json({ sin_deudas: true });

    const sinExtra  = _simularDeudas(deudas, 0, estrategia);
    const conExtra  = _simularDeudas(deudas, Number(extra_mensual), estrategia);
    const mesesAhorrados = sinExtra.meses_totales - conExtra.meses_totales;
    const interesesAhorrados = parseFloat((sinExtra.total_intereses - conExtra.total_intereses).toFixed(2));

    // Cuál deuda se ataca primero con el extra
    const deudaObjetivo = conExtra.orden.find(d => d.mes_saldado != null);

    res.json({
      extra_mensual: Number(extra_mensual),
      estrategia,
      sin_extra: sinExtra,
      con_extra:  conExtra,
      meses_ahorrados: mesesAhorrados,
      intereses_ahorrados: interesesAhorrados,
      deuda_objetivo: deudaObjetivo || null,
    });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// GET /deudas/plan?firebase_uid=X&estrategia=avalanche&extra_mensual=0
app.get('/deudas/plan', async (req, res) => {
  const { firebase_uid, estrategia = 'avalanche', extra_mensual = 0 } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [deudas] = await db.execute(
      `SELECT * FROM deudas WHERE firebase_uid = ? AND activa = 1 AND monto_pendiente > 0`,
      [firebase_uid]
    );
    if (!deudas.length) return res.json({ sin_deudas: true });

    const simulacion = _simularDeudas(deudas, Number(extra_mensual), estrategia);
    const hoy = new Date();

    const pasos = simulacion.orden.map((d, i) => {
      const fechaSaldada = d.mes_saldado
        ? new Date(hoy.getFullYear(), hoy.getMonth() + d.mes_saldado, hoy.getDate()).toISOString().slice(0, 10)
        : null;
      return {
        paso: i + 1,
        id: d.id,
        nombre: d.nombre,
        tipo: d.tipo,
        mes_saldado: d.mes_saldado,
        fecha_saldada: fechaSaldada,
        intereses_pagados: d.intereses_pagados,
        recomendacion: i === 0
          ? `Ataca esta primero. Cuando la saldas, mueve su cuota a la siguiente.`
          : `Cuando saldas la anterior, dirige los pagos liberados aquí.`,
      };
    });

    res.json({
      estrategia,
      extra_mensual: Number(extra_mensual),
      meses_totales: simulacion.meses_totales,
      fecha_libertad: simulacion.fecha_fin,
      total_intereses: simulacion.total_intereses,
      pasos,
    });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// GET /shared-budgets/:id/balance-detalle?firebase_uid=X
app.get('/shared-budgets/:id/balance-detalle', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [[budget]] = await db.execute(
      `SELECT sb.*, sbm.aporte_periodo AS mi_aporte
       FROM shared_budgets sb
       JOIN shared_budget_members sbm ON sbm.shared_budget_id = sb.id AND sbm.firebase_uid = ?
       WHERE sb.id = ?`,
      [firebase_uid, id]
    );
    if (!budget) return res.status(404).json({ error: 'Presupuesto compartido no encontrado' });

    const [miembros] = await db.execute(
      `SELECT sbm.firebase_uid, sbm.rol, sbm.aporte_periodo,
              COALESCE(SUM(se.monto), 0) AS total_gastado
       FROM shared_budget_members sbm
       LEFT JOIN shared_expenses se ON se.shared_budget_id = sbm.shared_budget_id
                                    AND se.paid_by = sbm.firebase_uid
       WHERE sbm.shared_budget_id = ?
       GROUP BY sbm.firebase_uid, sbm.rol, sbm.aporte_periodo`,
      [id]
    );

    const totalPool = miembros.reduce((s, m) => s + Number(m.aporte_periodo || 0), 0);
    const totalGastado = miembros.reduce((s, m) => s + Number(m.total_gastado || 0), 0);

    const miembrosDetalle = miembros.map(m => {
      const aporte = Number(m.aporte_periodo || 0);
      const gastado = Number(m.total_gastado || 0);
      const diferencia = aporte - gastado;
      return {
        firebase_uid: m.firebase_uid,
        rol: m.rol,
        aporte_periodo: aporte,
        total_gastado: gastado,
        diferencia,
        estado: diferencia > 0 ? 'a_favor' : diferencia < 0 ? 'debe' : 'equilibrado',
      };
    });

    res.json({
      budget_id: Number(id),
      nombre: budget.nombre,
      total_pool: parseFloat(totalPool.toFixed(2)),
      total_gastado: parseFloat(totalGastado.toFixed(2)),
      saldo_pool: parseFloat((totalPool - totalGastado).toFixed(2)),
      miembros: miembrosDetalle,
    });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// PATCH /shared-budgets/:id/mi-aporte — actualizar el aporte mensual del usuario al shared
app.patch('/shared-budgets/:id/mi-aporte', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid, aporte_periodo } = req.body;
  if (!firebase_uid || aporte_periodo == null) return res.status(400).json({ error: 'firebase_uid y aporte_periodo son requeridos' });
  try {
    const [result] = await db.execute(
      `UPDATE shared_budget_members SET aporte_periodo = ?
       WHERE shared_budget_id = ? AND firebase_uid = ?`,
      [aporte_periodo, id, firebase_uid]
    );
    if (result.affectedRows === 0) return res.status(404).json({ error: 'Membresía no encontrada' });
    res.json({ message: 'Aporte actualizado', aporte_periodo: Number(aporte_periodo) });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// =============================================================================
// MÓDULO: GASTOS VARIABLES BASE
// Gastos esperados pero variables: supermercado, gasolina, medicinas, etc.
// Son la segunda capa del perfil financiero (después de los compromisos fijos).
// =============================================================================

const CATEGORIAS_VALIDAS = [
  'vivienda','alimentacion','transporte','deudas','salud','educacion',
  'ocio','familia','emergencias','deportes','ropa','tecnologia','otro',
];

// GET /user/gastos-variables-base?firebase_uid=
app.get('/user/gastos-variables-base', async (req, res) => {
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [rows] = await db.execute(
      `SELECT gvb.*, s.nombre AS subcategoria_nombre
       FROM gastos_variables_base gvb
       LEFT JOIN subcategorias s ON s.id = gvb.subcategoria_id
       WHERE gvb.firebase_uid = ? AND gvb.activo = 1
       ORDER BY gvb.categoria ASC, gvb.monto_estimado DESC`,
      [firebase_uid]
    );
    const totalMensual = rows.reduce((s, g) => {
      const factor = g.frecuencia === 'quincenal' ? 2
                   : g.frecuencia === 'semanal'   ? 4.33
                   : g.frecuencia === 'anual'      ? 1/12
                   : 1;
      return s + Number(g.monto_estimado) * factor;
    }, 0);
    // Agrupar por categoría
    const porCategoria = {};
    for (const g of rows) {
      if (!porCategoria[g.categoria]) porCategoria[g.categoria] = { categoria: g.categoria, items: [], subtotal: 0 };
      porCategoria[g.categoria].items.push(g);
      porCategoria[g.categoria].subtotal += Number(g.monto_estimado);
    }
    res.json({ gastos: rows, total_mensual: parseFloat(totalMensual.toFixed(2)), por_categoria: Object.values(porCategoria) });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// Helper: genera el array aplica_meses desde mes_inicio y mes_fin
function _generarAplicaMeses(mesInicio, mesFin) {
  const inicio = Math.max(1, Math.min(12, Number(mesInicio) || 1));
  const fin    = Math.max(inicio, Math.min(12, Number(mesFin) || 12));
  const meses  = [];
  for (let m = inicio; m <= fin; m++) meses.push(m);
  return meses;
}

// POST /user/gastos-variables-base
// mes_inicio (1-12): mes desde el cual aplica. Default 1 (enero)
// mes_fin    (1-12): mes hasta el cual aplica. Default 12 (diciembre)
app.post('/user/gastos-variables-base', async (req, res) => {
  const { firebase_uid, nombre, categoria = 'otro', categoria_custom,
    subcategoria_id, monto_estimado, frecuencia = 'mensual',
    mes_inicio = 1, mes_fin = 12, en_calendario = 0, notas } = req.body;
  if (!firebase_uid || !nombre || monto_estimado == null)
    return res.status(400).json({ error: 'firebase_uid, nombre y monto_estimado requeridos' });
  try {
    // Si la categoría es "otro" y hay una personalizada, crearla/buscarla primero
    let categoriaFinal = categoria;
    if (categoria === 'otro' && categoria_custom) {
      const nombreCat = categoria_custom.trim().toLowerCase();
      const [[existeCat]] = await db.execute(
        `SELECT id FROM subcategorias WHERE firebase_uid = ? AND categoria = 'custom' AND nombre = ?`,
        [firebase_uid, nombreCat]
      );
      if (!existeCat) {
        await db.execute(
          `INSERT INTO subcategorias (firebase_uid, categoria, nombre) VALUES (?, 'custom', ?)`,
          [firebase_uid, nombreCat]
        );
      }
      categoriaFinal = nombreCat;
    }
    const aplicaMeses = _generarAplicaMeses(mes_inicio, mes_fin);
    const [r] = await db.execute(
      `INSERT INTO gastos_variables_base
         (firebase_uid, nombre, categoria, subcategoria_id, monto_estimado, frecuencia,
          aplica_meses, mes_inicio, mes_fin, en_calendario, notas)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [firebase_uid, nombre, categoriaFinal, subcategoria_id || null, monto_estimado, frecuencia,
       JSON.stringify(aplicaMeses), Number(mes_inicio), Number(mes_fin), en_calendario ? 1 : 0, notas || null]
    );
    const [[created]] = await db.execute(`SELECT * FROM gastos_variables_base WHERE id = ?`, [r.insertId]);
    res.status(201).json(created);
    _recalcularEstimadosAnio(firebase_uid, new Date().getFullYear()).catch(() => {});
    _logInfo('/user/gastos-variables-base', `Variable base creada: "${nombre}" $${Number(monto_estimado).toFixed(2)} - meses ${mes_inicio}-${mes_fin}`, firebase_uid);
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// PUT /user/gastos-variables-base/:id
app.put('/user/gastos-variables-base/:id', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid, nombre, categoria, categoria_custom, subcategoria_id,
    monto_estimado, frecuencia, mes_inicio, mes_fin, en_calendario, notas, activo } = req.body;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const fields = [], vals = [];
    let categoriaFinal = categoria;
    if (categoria === 'otro' && categoria_custom) {
      categoriaFinal = categoria_custom.trim().toLowerCase();
      const [[existeCat]] = await db.execute(
        `SELECT id FROM subcategorias WHERE firebase_uid = ? AND categoria = 'custom' AND nombre = ?`,
        [firebase_uid, categoriaFinal]
      );
      if (!existeCat) {
        await db.execute(
          `INSERT INTO subcategorias (firebase_uid, categoria, nombre) VALUES (?, 'custom', ?)`,
          [firebase_uid, categoriaFinal]
        );
      }
    }
    if (nombre !== undefined)          { fields.push('nombre = ?');          vals.push(nombre); }
    if (categoriaFinal !== undefined)  { fields.push('categoria = ?');       vals.push(categoriaFinal); }
    if (subcategoria_id !== undefined) { fields.push('subcategoria_id = ?'); vals.push(subcategoria_id); }
    if (monto_estimado !== undefined)  { fields.push('monto_estimado = ?');  vals.push(monto_estimado); }
    if (frecuencia !== undefined)      { fields.push('frecuencia = ?');      vals.push(frecuencia); }
    if (en_calendario !== undefined)   { fields.push('en_calendario = ?');   vals.push(en_calendario ? 1 : 0); }
    if (notas !== undefined)           { fields.push('notas = ?');           vals.push(notas); }
    if (activo !== undefined)          { fields.push('activo = ?');          vals.push(activo); }
    // Recalcular aplica_meses si cambia el rango
    if (mes_inicio !== undefined || mes_fin !== undefined) {
      const [[existing]] = await db.execute(`SELECT mes_inicio, mes_fin FROM gastos_variables_base WHERE id = ?`, [id]);
      const nuevoInicio = mes_inicio ?? existing?.mes_inicio ?? 1;
      const nuevoFin    = mes_fin    ?? existing?.mes_fin    ?? 12;
      const nuevosM = _generarAplicaMeses(nuevoInicio, nuevoFin);
      fields.push('mes_inicio = ?', 'mes_fin = ?', 'aplica_meses = ?');
      vals.push(Number(nuevoInicio), Number(nuevoFin), JSON.stringify(nuevosM));
    }
    if (!fields.length) return res.status(400).json({ error: 'Nada que actualizar' });
    vals.push(id, firebase_uid);
    const [r] = await db.execute(`UPDATE gastos_variables_base SET ${fields.join(', ')} WHERE id = ? AND firebase_uid = ?`, vals);
    if (!r.affectedRows) return res.status(404).json({ error: 'No encontrado' });
    const [[updated]] = await db.execute(`SELECT * FROM gastos_variables_base WHERE id = ?`, [id]);
    res.json(updated);
    _recalcularEstimadosAnio(firebase_uid, new Date().getFullYear()).catch(() => {});
    _logInfo(`/user/gastos-variables-base/${id}`, `Variable base editada: "${updated.nombre}" $${Number(updated.monto_estimado).toFixed(2)}`, firebase_uid);
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// DELETE /user/gastos-variables-base/:id
app.delete('/user/gastos-variables-base/:id', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [r] = await db.execute(`UPDATE gastos_variables_base SET activo = 0 WHERE id = ? AND firebase_uid = ?`, [id, firebase_uid]);
    if (!r.affectedRows) return res.status(404).json({ error: 'No encontrado' });
    res.json({ success: true });
    _recalcularEstimadosAnio(firebase_uid, new Date().getFullYear()).catch(() => {});
    _logInfo(`/user/gastos-variables-base/${id}`, `Variable base eliminada (id=${id})`, firebase_uid);
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// GET /user/subcategorias?firebase_uid=&categoria=alimentacion
app.get('/user/subcategorias', async (req, res) => {
  const { firebase_uid, categoria } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    let sql = `SELECT * FROM subcategorias WHERE (firebase_uid = ? OR es_global = 1) AND activa = 1`;
    const params = [firebase_uid];
    if (categoria) { sql += ` AND categoria = ?`; params.push(categoria); }
    sql += ` ORDER BY categoria, nombre`;
    const [rows] = await db.execute(sql, params);
    res.json(rows);
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// POST /user/subcategorias
app.post('/user/subcategorias', async (req, res) => {
  const { firebase_uid, categoria, nombre } = req.body;
  if (!firebase_uid || !categoria || !nombre) return res.status(400).json({ error: 'Datos incompletos' });
  try {
    const [r] = await db.execute(
      `INSERT INTO subcategorias (firebase_uid, categoria, nombre) VALUES (?, ?, ?)`,
      [firebase_uid, categoria, nombre]
    );
    const [[created]] = await db.execute(`SELECT * FROM subcategorias WHERE id = ?`, [r.insertId]);
    res.status(201).json(created);
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// =============================================================================
// MÓDULO: ESTADO FINANCIERO ANUAL
// Núcleo central del nuevo modelo. Se genera desde el perfil y se actualiza
// automáticamente cuando el usuario registra gastos reales.
// =============================================================================

// Helper: calcular monto mensual normalizado de un gasto variable base
function _montoMensual(gasto) {
  const m = Number(gasto.monto_estimado);
  if (gasto.frecuencia === 'quincenal') return m * 2;
  if (gasto.frecuencia === 'semanal')   return parseFloat((m * 4.33).toFixed(2));
  if (gasto.frecuencia === 'anual')     return parseFloat((m / 12).toFixed(2));
  return m; // mensual
}

// POST /user/estado-anual/generar
// Genera el estado financiero anual y los 12 meses desde el perfil del usuario.
// Si ya existe para ese año, recalcula (upsert).
app.post('/user/estado-anual/generar', async (req, res) => {
  const { firebase_uid, anio } = req.body;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  const year = anio || new Date().getFullYear();
  try {
    const [[income]] = await db.execute(`SELECT * FROM user_income WHERE firebase_uid = ?`, [firebase_uid]);
    if (!income) return res.status(400).json({ error: 'Registra tu ingreso primero' });

    const [gastosFijos] = await db.execute(
      `SELECT * FROM user_gastos_fijos WHERE firebase_uid = ? AND activo = 1`, [firebase_uid]
    );
    const [deudasIndep] = await db.execute(
      `SELECT d.* FROM deudas d
       LEFT JOIN user_gastos_fijos ugf ON ugf.deuda_id = d.id
       WHERE d.firebase_uid = ? AND d.activa = 1 AND ugf.id IS NULL`, [firebase_uid]
    );
    const [variablesBase] = await db.execute(
      `SELECT * FROM gastos_variables_base WHERE firebase_uid = ? AND activo = 1`, [firebase_uid]
    );

    const ingresoMensual   = Number(income.ingreso_neto_mensual);
    const totalFijosMensual = gastosFijos.reduce((s, g) => s + Number(g.monto_mensual), 0)
                            + deudasIndep.reduce((s, d) => s + Number(d.pago_minimo || 0), 0);
    const totalVarMensual   = variablesBase.reduce((s, g) => s + _montoMensual(g), 0);
    const remanenteEstimado = ingresoMensual - totalFijosMensual - totalVarMensual;

    // Upsert estado anual
    await db.execute(
      `INSERT INTO estado_financiero_anual
         (firebase_uid, anio, ingreso_anual_estimado, gastos_fijos_anuales,
          gastos_variables_anuales, remanente_anual_estimado)
       VALUES (?, ?, ?, ?, ?, ?)
       ON DUPLICATE KEY UPDATE
         ingreso_anual_estimado   = VALUES(ingreso_anual_estimado),
         gastos_fijos_anuales     = VALUES(gastos_fijos_anuales),
         gastos_variables_anuales = VALUES(gastos_variables_anuales),
         remanente_anual_estimado = VALUES(remanente_anual_estimado),
         updated_at               = NOW()`,
      [firebase_uid, year,
       parseFloat((ingresoMensual * 12).toFixed(2)),
       parseFloat((totalFijosMensual * 12).toFixed(2)),
       parseFloat((totalVarMensual * 12).toFixed(2)),
       parseFloat((remanenteEstimado * 12).toFixed(2))]
    );

    const [[efa]] = await db.execute(
      `SELECT * FROM estado_financiero_anual WHERE firebase_uid = ? AND anio = ?`, [firebase_uid, year]
    );

    // Generar/actualizar los 12 meses
    const hoyMes = new Date().getMonth() + 1; // 1-12
    const mesesCreados = [];
    for (let m = 1; m <= 12; m++) {
      // Calcular ingreso del mes (puede variar si tiene frecuencia quincenal)
      const ingresoMes = parseFloat(ingresoMensual.toFixed(2));
      const fijosMes   = parseFloat(totalFijosMensual.toFixed(2));
      // Gastos variables del mes — respetar aplica_meses si está definido
      const varMes = variablesBase.reduce((s, g) => {
        if (g.aplica_meses) {
          const meses = typeof g.aplica_meses === 'string' ? JSON.parse(g.aplica_meses) : g.aplica_meses;
          if (!meses.includes(m)) return s;
        }
        return s + _montoMensual(g);
      }, 0);
      const estado = m < hoyMes ? 'cerrado' : m === hoyMes ? 'activo' : 'futuro';

      await db.execute(
        `INSERT INTO meses_financieros
           (firebase_uid, estado_anual_id, anio, mes,
            ingreso_estimado, fijos_estimados, variables_estimados, remanente_estimado, estado)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
         ON DUPLICATE KEY UPDATE
           ingreso_estimado   = VALUES(ingreso_estimado),
           fijos_estimados    = VALUES(fijos_estimados),
           variables_estimados = VALUES(variables_estimados),
           remanente_estimado = VALUES(remanente_estimado),
           estado             = IF(estado = 'cerrado', 'cerrado', VALUES(estado))`,
        [firebase_uid, efa.id, year, m,
         ingresoMes, parseFloat(fijosMes.toFixed(2)),
         parseFloat(varMes.toFixed(2)),
         parseFloat((ingresoMes - fijosMes - varMes).toFixed(2)), estado]
      );
      mesesCreados.push({ mes: m, ingreso: ingresoMes, fijos: fijosMes, variables: parseFloat(varMes.toFixed(2)) });
    }

    res.status(201).json({ estado_anual: efa, meses_generados: 12 });
    _logInfo('/user/estado-anual/generar', `Estado financiero ${year} generado/recalculado - ingreso $${Number(ingresoMensual).toFixed(2)}/mes`, firebase_uid);
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// GET /user/estado-anual/:anio?firebase_uid=
// Retorna el estado anual con los 12 meses resumidos.
app.get('/user/estado-anual/:anio', async (req, res) => {
  const { anio } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [[efa]] = await db.execute(
      `SELECT * FROM estado_financiero_anual WHERE firebase_uid = ? AND anio = ?`, [firebase_uid, anio]
    );
    if (!efa) return res.json({ existe: false, anio: Number(anio) });

    const [meses] = await db.execute(
      `SELECT mf.*,
              COALESCE(SUM(rg.monto), 0) AS total_registrado,
              COUNT(rg.id)               AS num_registros
       FROM meses_financieros mf
       LEFT JOIN registros_gasto rg ON rg.mes_id = mf.id AND rg.firebase_uid = mf.firebase_uid
       WHERE mf.firebase_uid = ? AND mf.anio = ?
       GROUP BY mf.id ORDER BY mf.mes ASC`,
      [firebase_uid, anio]
    );

    // Recalcular reales del estado anual desde los meses
    const totalFijosReales = meses.reduce((s, m) => s + Number(m.fijos_reales), 0);
    const totalVarReales   = meses.reduce((s, m) => s + Number(m.variables_reales), 0);
    const totalNoPres      = meses.reduce((s, m) => s + Number(m.no_presupuestados_reales), 0);
    const totalIngReal     = meses.reduce((s, m) => s + Number(m.ingreso_real || m.ingreso_estimado), 0);

    const MESES_LABEL = ['','Ene','Feb','Mar','Abr','May','Jun','Jul','Ago','Sep','Oct','Nov','Dic'];
    res.json({
      existe: true,
      estado_anual: {
        ...efa,
        ingreso_anual_real:       parseFloat(totalIngReal.toFixed(2)),
        gastos_fijos_reales:      parseFloat(totalFijosReales.toFixed(2)),
        gastos_variables_reales:  parseFloat(totalVarReales.toFixed(2)),
        compras_no_presup_reales: parseFloat(totalNoPres.toFixed(2)),
        remanente_anual_real:     parseFloat((totalIngReal - totalFijosReales - totalVarReales - totalNoPres).toFixed(2)),
      },
      meses: meses.map(m => ({
        ...m,
        label: MESES_LABEL[m.mes],
        remanente_real: parseFloat((
          Number(m.ingreso_real || m.ingreso_estimado)
          - Number(m.fijos_reales)
          - Number(m.variables_reales)
          - Number(m.no_presupuestados_reales)
        ).toFixed(2)),
        total_registrado: parseFloat(Number(m.total_registrado).toFixed(2)),
      })),
    });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// GET /user/meses/:anio/:mes?firebase_uid=
// Detalle completo de un mes: estimado vs real + registros de gasto.
app.get('/user/meses/:anio/:mes', async (req, res) => {
  const { anio, mes } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [[mesRow]] = await db.execute(
      `SELECT * FROM meses_financieros WHERE firebase_uid = ? AND anio = ? AND mes = ?`,
      [firebase_uid, anio, mes]
    );
    if (!mesRow) return res.status(404).json({ error: 'Mes no encontrado. Genera el estado anual primero.' });

    const [registros] = await db.execute(
      `SELECT rg.*, s.nombre AS subcategoria_nombre
       FROM registros_gasto rg
       LEFT JOIN subcategorias s ON s.id = rg.subcategoria_id
       WHERE rg.mes_id = ? AND rg.firebase_uid = ?
       ORDER BY rg.fecha DESC, rg.created_at DESC`,
      [mesRow.id, firebase_uid]
    );

    // Totales reales agrupados
    let fijosReales = 0, variablesReales = 0, noPresReales = 0;
    for (const r of registros) {
      if (r.tipo === 'fijo') fijosReales += Number(r.monto);
      else if (r.tipo === 'variable') variablesReales += Number(r.monto);
      else noPresReales += Number(r.monto);
    }
    const ingresoReal  = Number(mesRow.ingreso_real || mesRow.ingreso_estimado);
    const remanenteReal = ingresoReal - fijosReales - variablesReales - noPresReales;

    // Análisis por categoría
    const porCategoria = {};
    for (const r of registros) {
      if (!porCategoria[r.categoria]) porCategoria[r.categoria] = { categoria: r.categoria, fijo: 0, variable: 0, no_presupuestado: 0, total: 0 };
      porCategoria[r.categoria][r.tipo === 'no_presupuestado' ? 'no_presupuestado' : r.tipo] += Number(r.monto);
      porCategoria[r.categoria].total += Number(r.monto);
    }

    // Deudas activas del usuario para este mes — su pago mínimo es un compromiso fijo
    const [deudasActivas] = await db.execute(
      `SELECT d.id, d.nombre, d.tipo, d.es_letra, d.cuota_fija, d.pago_minimo,
              d.fecha_proximo_pago, d.num_cuotas_total, d.num_cuotas_pagadas, d.mes_inicio_pago
       FROM deudas d
       WHERE d.firebase_uid = ? AND d.activa = 1 AND d.monto_pendiente > 0`,
      [firebase_uid]
    );
    // Solo contar deudas que aplican en este mes según mes_inicio_pago
    const deudasDelMes = deudasActivas.filter(d => Number(d.mes_inicio_pago || 1) <= Number(mes));
    const totalCuotasDeudas = deudasDelMes.reduce((s, d) => {
      return s + (d.es_letra ? Number(d.cuota_fija || 0) : Number(d.pago_minimo || 0));
    }, 0);

    // Variables base presupuestadas para este mes (para calcular desviación)
    const [varBase] = await db.execute(
      `SELECT * FROM gastos_variables_base WHERE firebase_uid = ? AND activo = 1`, [firebase_uid]
    );
    const presupuestadoPorCat = {};
    for (const g of varBase) {
      if (g.aplica_meses) {
        const meses = typeof g.aplica_meses === 'string' ? JSON.parse(g.aplica_meses) : g.aplica_meses;
        if (!meses.includes(Number(mes))) continue;
      }
      presupuestadoPorCat[g.categoria] = (presupuestadoPorCat[g.categoria] || 0) + _montoMensual(g);
    }

    const analisisCategorias = Object.entries(porCategoria).map(([cat, datos]) => {
      const presup = presupuestadoPorCat[cat] || 0;
      const desv   = datos.total - presup;
      return {
        categoria: cat,
        presupuestado: parseFloat(presup.toFixed(2)),
        gastado_variable: parseFloat(datos.variable.toFixed(2)),
        gastado_no_presup: parseFloat(datos.no_presupuestado.toFixed(2)),
        total_gastado: parseFloat(datos.total.toFixed(2)),
        desviacion: parseFloat(desv.toFixed(2)),
        pct_desviacion: presup > 0 ? parseFloat((desv / presup * 100).toFixed(1)) : null,
      };
    });

    // Gastos fijos del perfil para este mes (para mostrar compromisos)
    const [gastosFijosPerfil] = await db.execute(
      `SELECT id, descripcion, monto_mensual, tipo, dia_pago, dia_pago_2, frecuencia
       FROM user_gastos_fijos WHERE firebase_uid = ? AND activo = 1`,
      [firebase_uid]
    );
    const totalFijosEstimado = gastosFijosPerfil.reduce((s, g) => s + Number(g.monto_mensual), 0)
                             + totalCuotasDeudas;

    res.json({
      mes: mesRow,
      compromisos_fijos: {
        gastos_fijos: gastosFijosPerfil.map(g => ({
          id: g.id, nombre: g.descripcion, monto: Number(g.monto_mensual),
          tipo: g.tipo, dia_pago: g.dia_pago, dia_pago_2: g.dia_pago_2, frecuencia: g.frecuencia,
        })),
        deudas: deudasDelMes.map(d => ({
          id: d.id, nombre: d.nombre, tipo: d.tipo,
          cuota: d.es_letra ? Number(d.cuota_fija) : Number(d.pago_minimo),
          es_letra: Boolean(d.es_letra),
          proxima_fecha: d.fecha_proximo_pago,
          cuotas_restantes: d.num_cuotas_total
            ? Math.max(0, Number(d.num_cuotas_total) - Number(d.num_cuotas_pagadas || 0)) : null,
        })),
        total_estimado: parseFloat(totalFijosEstimado.toFixed(2)),
      },
      resumen: {
        ingreso_estimado:    Number(mesRow.ingreso_estimado),
        fijos_estimados:     parseFloat(totalFijosEstimado.toFixed(2)),
        variables_estimados: Number(mesRow.variables_estimados),
        remanente_estimado:  parseFloat((Number(mesRow.ingreso_estimado) - totalFijosEstimado - Number(mesRow.variables_estimados)).toFixed(2)),
        ingreso_real:        parseFloat(ingresoReal.toFixed(2)),
        fijos_reales:        parseFloat(fijosReales.toFixed(2)),
        variables_reales:    parseFloat(variablesReales.toFixed(2)),
        no_presupuestados:   parseFloat(noPresReales.toFixed(2)),
        remanente_real:      parseFloat(remanenteReal.toFixed(2)),
        presupuesto_sano:    remanenteReal >= 0,
      },
      registros,
      analisis_categorias: analisisCategorias,
    });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// PATCH /user/estado-anual/:anio/recalcular?firebase_uid=
// Recalcula estimados del estado anual cuando el perfil cambia.
app.patch('/user/estado-anual/:anio/recalcular', async (req, res) => {
  const { anio } = req.params;
  const { firebase_uid } = req.body;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [[income]] = await db.execute(`SELECT * FROM user_income WHERE firebase_uid = ?`, [firebase_uid]);
    if (!income) return res.status(400).json({ error: 'Registra tu ingreso primero' });
    const [gastosFijos] = await db.execute(`SELECT * FROM user_gastos_fijos WHERE firebase_uid = ? AND activo = 1`, [firebase_uid]);
    const [deudasIndep] = await db.execute(
      `SELECT d.* FROM deudas d LEFT JOIN user_gastos_fijos ugf ON ugf.deuda_id = d.id
       WHERE d.firebase_uid = ? AND d.activa = 1 AND ugf.id IS NULL`, [firebase_uid]
    );
    const [variablesBase] = await db.execute(`SELECT * FROM gastos_variables_base WHERE firebase_uid = ? AND activo = 1`, [firebase_uid]);
    const ingresoMensual    = Number(income.ingreso_neto_mensual);
    const totalFijosMensual = gastosFijos.reduce((s, g) => s + Number(g.monto_mensual), 0)
                            + deudasIndep.reduce((s, d) => s + Number(d.pago_minimo || 0), 0);
    const totalVarMensual   = variablesBase.reduce((s, g) => s + _montoMensual(g), 0);
    const remanenteEstimado = ingresoMensual - totalFijosMensual - totalVarMensual;
    await db.execute(
      `UPDATE estado_financiero_anual SET
         ingreso_anual_estimado   = ?,
         gastos_fijos_anuales     = ?,
         gastos_variables_anuales = ?,
         remanente_anual_estimado = ?,
         updated_at               = NOW()
       WHERE firebase_uid = ? AND anio = ?`,
      [parseFloat((ingresoMensual * 12).toFixed(2)),
       parseFloat((totalFijosMensual * 12).toFixed(2)),
       parseFloat((totalVarMensual * 12).toFixed(2)),
       parseFloat((remanenteEstimado * 12).toFixed(2)),
       firebase_uid, anio]
    );
    res.json({ recalculado: true, anio: Number(anio) });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// =============================================================================
// MÓDULO: REGISTROS DE GASTO
// Lo que realmente ocurrió en cada mes. Tres tipos:
//   fijo            → compromiso del perfil que se pagó
//   variable        → gasto esperado (del presupuesto variable base)
//   no_presupuestado → gasto no planificado
// Cada registro actualiza automáticamente los totales del mes y del año.
// =============================================================================

// Helper: recalcula los estimados en meses_financieros y estado_financiero_anual
// cuando el perfil del usuario cambia (gastos fijos, variables base, deudas).
// Fire-and-forget: llámalo con .catch() para no bloquear la respuesta principal.
async function _recalcularEstimadosAnio(firebase_uid, anio) {
  const year = anio || new Date().getFullYear();
  const [[efa]] = await db.execute(
    `SELECT id FROM estado_financiero_anual WHERE firebase_uid = ? AND anio = ?`,
    [firebase_uid, year]
  );
  if (!efa) return; // aún no se generó el estado anual — nada que actualizar

  const [[income]] = await db.execute(
    `SELECT ingreso_neto_mensual FROM user_income WHERE firebase_uid = ?`, [firebase_uid]
  );
  if (!income) return;

  const [gastosFijos] = await db.execute(
    `SELECT * FROM user_gastos_fijos WHERE firebase_uid = ? AND activo = 1`, [firebase_uid]
  );
  const [deudasIndep] = await db.execute(
    `SELECT d.* FROM deudas d
     LEFT JOIN user_gastos_fijos ugf ON ugf.deuda_id = d.id
     WHERE d.firebase_uid = ? AND d.activa = 1 AND ugf.id IS NULL`, [firebase_uid]
  );
  const [variablesBase] = await db.execute(
    `SELECT * FROM gastos_variables_base WHERE firebase_uid = ? AND activo = 1`, [firebase_uid]
  );

  const ingresoMensual    = Number(income.ingreso_neto_mensual);
  const totalFijosMensual = gastosFijos.reduce((s, g) => s + Number(g.monto_mensual), 0)
                          + deudasIndep.reduce((s, d) => s + Number(d.pago_minimo || d.cuota_fija || 0), 0);
  const totalVarAnual     = variablesBase.reduce((s, g) => {
    const arr = g.aplica_meses
      ? (typeof g.aplica_meses === 'string' ? JSON.parse(g.aplica_meses) : g.aplica_meses)
      : [1,2,3,4,5,6,7,8,9,10,11,12];
    return s + _montoMensual(g) * arr.length;
  }, 0);

  // Actualizar estado_financiero_anual
  await db.execute(
    `UPDATE estado_financiero_anual SET
       ingreso_anual_estimado   = ?,
       gastos_fijos_anuales     = ?,
       gastos_variables_anuales = ?,
       remanente_anual_estimado = ?,
       updated_at               = NOW()
     WHERE firebase_uid = ? AND anio = ?`,
    [parseFloat((ingresoMensual * 12).toFixed(2)),
     parseFloat((totalFijosMensual * 12).toFixed(2)),
     parseFloat(totalVarAnual.toFixed(2)),
     parseFloat(((ingresoMensual - totalFijosMensual) * 12 - totalVarAnual).toFixed(2)),
     firebase_uid, year]
  );

  // Actualizar meses_financieros — estimados por mes (respeta aplica_meses)
  const [meses] = await db.execute(
    `SELECT id, mes FROM meses_financieros WHERE firebase_uid = ? AND anio = ?`,
    [firebase_uid, year]
  );
  for (const mesRow of meses) {
    const m = mesRow.mes;
    const varMes = variablesBase.reduce((s, g) => {
      if (g.aplica_meses) {
        const arr = typeof g.aplica_meses === 'string' ? JSON.parse(g.aplica_meses) : g.aplica_meses;
        if (!arr.includes(Number(m))) return s;
      }
      return s + _montoMensual(g);
    }, 0);
    await db.execute(
      `UPDATE meses_financieros SET
         fijos_estimados     = ?,
         variables_estimados = ?,
         remanente_estimado  = ?
       WHERE id = ?`,
      [parseFloat(totalFijosMensual.toFixed(2)),
       parseFloat(varMes.toFixed(2)),
       parseFloat((ingresoMensual - totalFijosMensual - varMes).toFixed(2)),
       mesRow.id]
    );
  }
}

// Helper: actualizar totales del mes_financiero después de cualquier cambio en registros
async function _actualizarTotalesMes(mesId, firebaseUid) {
  const [rows] = await db.execute(
    `SELECT tipo, SUM(monto) AS total FROM registros_gasto
     WHERE mes_id = ? AND firebase_uid = ? GROUP BY tipo`,
    [mesId, firebaseUid]
  );
  const totales = { fijo: 0, variable: 0, no_presupuestado: 0 };
  for (const r of rows) totales[r.tipo] = Number(r.total);

  await db.execute(
    `UPDATE meses_financieros SET
       fijos_reales             = ?,
       variables_reales         = ?,
       no_presupuestados_reales = ?
     WHERE id = ?`,
    [totales.fijo, totales.variable, totales.no_presupuestado, mesId]
  );
}

// GET /registros/:anio/:mes?firebase_uid=&tipo=&categoria=
app.get('/registros/:anio/:mes', async (req, res) => {
  const { anio, mes } = req.params;
  const { firebase_uid, tipo, categoria } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [[mesRow]] = await db.execute(
      `SELECT id FROM meses_financieros WHERE firebase_uid = ? AND anio = ? AND mes = ?`,
      [firebase_uid, anio, mes]
    );
    if (!mesRow) return res.json({ registros: [], total: 0 });

    let sql = `SELECT rg.*, s.nombre AS subcategoria_nombre
               FROM registros_gasto rg
               LEFT JOIN subcategorias s ON s.id = rg.subcategoria_id
               WHERE rg.mes_id = ? AND rg.firebase_uid = ?`;
    const params = [mesRow.id, firebase_uid];
    if (tipo)      { sql += ` AND rg.tipo = ?`;      params.push(tipo); }
    if (categoria) { sql += ` AND rg.categoria = ?`; params.push(categoria); }
    sql += ` ORDER BY rg.fecha DESC, rg.created_at DESC`;
    const [registros] = await db.execute(sql, params);
    const total = registros.reduce((s, r) => s + Number(r.monto), 0);
    res.json({ registros, total: parseFloat(total.toFixed(2)) });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// POST /registros — registrar un gasto real en un mes
app.post('/registros', async (req, res) => {
  const {
    firebase_uid, anio, mes, tipo, categoria = 'otro', subcategoria_id,
    nombre, monto, fecha, pagado = 0, origen_fijo_id, origen_variable_id, notas, en_calendario = 0,
  } = req.body;
  if (!firebase_uid || !anio || !mes || !tipo || !nombre || monto == null || !fecha)
    return res.status(400).json({ error: 'firebase_uid, anio, mes, tipo, nombre, monto y fecha son requeridos' });
  if (!['fijo','variable','no_presupuestado'].includes(tipo))
    return res.status(400).json({ error: 'tipo debe ser fijo, variable o no_presupuestado' });
  try {
    const [[mesRow]] = await db.execute(
      `SELECT id FROM meses_financieros WHERE firebase_uid = ? AND anio = ? AND mes = ?`,
      [firebase_uid, anio, mes]
    );
    if (!mesRow) return res.status(404).json({ error: 'Mes no encontrado. Genera el estado anual primero.' });

    const [r] = await db.execute(
      `INSERT INTO registros_gasto
         (firebase_uid, mes_id, anio, mes, tipo, categoria, subcategoria_id,
          nombre, monto, fecha, pagado, origen_fijo_id, origen_variable_id, notas, en_calendario)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [firebase_uid, mesRow.id, anio, mes, tipo, categoria, subcategoria_id || null,
       nombre, monto, fecha, pagado ? 1 : 0, origen_fijo_id || null,
       origen_variable_id || null, notas || null, en_calendario ? 1 : 0]
    );
    await _actualizarTotalesMes(mesRow.id, firebase_uid);

    const [[created]] = await db.execute(`SELECT * FROM registros_gasto WHERE id = ?`, [r.insertId]);
    res.status(201).json(created);
    _logInfo('/registros', `Gasto registrado: "${nombre}" $${Number(monto).toFixed(2)} (${tipo} · ${categoria}) en ${anio}/${mes}`, firebase_uid);
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// PUT /registros/:id
app.put('/registros/:id', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid, nombre, categoria, subcategoria_id, monto, fecha, tipo, pagado, notas } = req.body;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [[existing]] = await db.execute(`SELECT * FROM registros_gasto WHERE id = ? AND firebase_uid = ?`, [id, firebase_uid]);
    if (!existing) return res.status(404).json({ error: 'Registro no encontrado' });

    const fields = [], vals = [];
    if (nombre !== undefined)          { fields.push('nombre = ?');          vals.push(nombre); }
    if (categoria !== undefined)       { fields.push('categoria = ?');       vals.push(categoria); }
    if (subcategoria_id !== undefined) { fields.push('subcategoria_id = ?'); vals.push(subcategoria_id); }
    if (monto !== undefined)           { fields.push('monto = ?');           vals.push(monto); }
    if (fecha !== undefined)           { fields.push('fecha = ?');           vals.push(fecha); }
    if (tipo !== undefined)            { fields.push('tipo = ?');            vals.push(tipo); }
    if (pagado !== undefined)          { fields.push('pagado = ?');          vals.push(pagado ? 1 : 0); }
    if (notas !== undefined)           { fields.push('notas = ?');           vals.push(notas); }
    if (!fields.length) return res.status(400).json({ error: 'Nada que actualizar' });
    vals.push(id, firebase_uid);
    await db.execute(`UPDATE registros_gasto SET ${fields.join(', ')} WHERE id = ? AND firebase_uid = ?`, vals);
    await _actualizarTotalesMes(existing.mes_id, firebase_uid);
    const [[updated]] = await db.execute(`SELECT * FROM registros_gasto WHERE id = ?`, [id]);
    res.json(updated);
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// DELETE /registros/:id
app.delete('/registros/:id', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [[existing]] = await db.execute(`SELECT * FROM registros_gasto WHERE id = ? AND firebase_uid = ?`, [id, firebase_uid]);
    if (!existing) return res.status(404).json({ error: 'Registro no encontrado' });
    await db.execute(`DELETE FROM registros_gasto WHERE id = ?`, [id]);
    await _actualizarTotalesMes(existing.mes_id, firebase_uid);
    res.json({ success: true });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// PATCH /registros/:id/pagar
app.patch('/registros/:id/pagar', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid, pagado } = req.body;
  if (!firebase_uid || pagado === undefined) return res.status(400).json({ error: 'firebase_uid y pagado requeridos' });
  try {
    const [r] = await db.execute(
      `UPDATE registros_gasto SET pagado = ? WHERE id = ? AND firebase_uid = ?`,
      [pagado ? 1 : 0, id, firebase_uid]
    );
    if (!r.affectedRows) return res.status(404).json({ error: 'Registro no encontrado' });
    res.json({ success: true, pagado: pagado ? 1 : 0 });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// POST /registros/:id/convertir-a-variable
// Convierte una compra no presupuestada en gasto variable base para el mes actual y siguientes.
app.post('/registros/:id/convertir-a-variable', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid, frecuencia = 'mensual' } = req.body;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [[reg]] = await db.execute(`SELECT * FROM registros_gasto WHERE id = ? AND firebase_uid = ?`, [id, firebase_uid]);
    if (!reg) return res.status(404).json({ error: 'Registro no encontrado' });
    if (reg.tipo !== 'no_presupuestado') return res.status(400).json({ error: 'Solo se pueden convertir gastos no presupuestados' });

    // Crear el gasto variable base
    const [r] = await db.execute(
      `INSERT INTO gastos_variables_base (firebase_uid, nombre, categoria, monto_estimado, frecuencia)
       VALUES (?, ?, ?, ?, ?)`,
      [firebase_uid, reg.nombre, reg.categoria, reg.monto, frecuencia]
    );
    // Actualizar el registro para marcarlo como variable
    await db.execute(`UPDATE registros_gasto SET tipo = 'variable', origen_variable_id = ? WHERE id = ?`, [r.insertId, id]);
    await _actualizarTotalesMes(reg.mes_id, firebase_uid);

    const [[varBase]] = await db.execute(`SELECT * FROM gastos_variables_base WHERE id = ?`, [r.insertId]);
    res.status(201).json({ message: 'Convertido a gasto variable base', gasto_variable: varBase });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// =============================================================================
// MÓDULO: ALERTAS FINANCIERAS INTELIGENTES
// Detecta patrones: presupuesto excedido, gastos repetidos no presupuestados,
// categorías que necesitan ajuste.
// =============================================================================

async function _generarAlertasMes(firebase_uid, anio, mes) {
  const alertas = [];
  const [[mesRow]] = await db.execute(
    `SELECT * FROM meses_financieros WHERE firebase_uid = ? AND anio = ? AND mes = ?`,
    [firebase_uid, anio, mes]
  );
  if (!mesRow) return alertas;

  // Gastos variables base del usuario (presupuesto estimado por categoría)
  const [varBase] = await db.execute(
    `SELECT categoria, SUM(monto_estimado) AS presupuestado
     FROM gastos_variables_base WHERE firebase_uid = ? AND activo = 1
     GROUP BY categoria`,
    [firebase_uid]
  );
  const presupPorCat = {};
  for (const g of varBase) presupPorCat[g.categoria] = Number(g.presupuestado);

  // Gastos reales del mes por categoría
  const [reales] = await db.execute(
    `SELECT categoria,
            SUM(CASE WHEN tipo='no_presupuestado' THEN monto ELSE 0 END) AS no_presup,
            SUM(CASE WHEN tipo='variable' THEN monto ELSE 0 END)         AS variable,
            SUM(monto) AS total
     FROM registros_gasto WHERE mes_id = ? AND firebase_uid = ? GROUP BY categoria`,
    [mesRow.id, firebase_uid]
  );

  for (const cat of reales) {
    const presup   = presupPorCat[cat.categoria] || 0;
    const noPresup = Number(cat.no_presup);
    const total    = Number(cat.total);

    // Alerta 1: no-presupuestados superan el 20% del presupuesto de la categoría
    if (presup > 0 && noPresup / presup > 0.20) {
      alertas.push({
        tipo: 'no_presup_alto', categoria: cat.categoria, nivel: 'warning',
        titulo: `Gastos no presupuestados altos en ${cat.categoria}`,
        mensaje: `Tienes $${noPresup.toFixed(2)} en compras no presupuestadas en ${cat.categoria}, que es el ${(noPresup/presup*100).toFixed(0)}% de tu presupuesto ($${presup.toFixed(2)}).`,
        accion_sugerida: `Considera aumentar tu presupuesto de ${cat.categoria} o revisar estos gastos.`,
      });
    }

    // Alerta 2: gasto total supera el presupuesto
    if (presup > 0 && total > presup * 1.30) {
      alertas.push({
        tipo: 'categoria_excedida', categoria: cat.categoria, nivel: 'danger',
        titulo: `Presupuesto excedido en ${cat.categoria}`,
        mensaje: `Gastaste $${total.toFixed(2)} en ${cat.categoria} pero presupuestaste $${presup.toFixed(2)} (${((total/presup-1)*100).toFixed(0)}% de exceso).`,
        accion_sugerida: `Revisa tus gastos de ${cat.categoria} y ajusta el presupuesto si este nivel es frecuente.`,
      });
    }
  }

  // Alerta 3: repetición — categoría no presupuestada 3+ meses consecutivos
  if (mes >= 3) {
    const [repetidos] = await db.execute(
      `SELECT rg.categoria, COUNT(DISTINCT rg.mes) AS meses_repetidos
       FROM registros_gasto rg
       WHERE rg.firebase_uid = ? AND rg.anio = ? AND rg.mes BETWEEN ? AND ?
         AND rg.tipo = 'no_presupuestado'
         AND rg.categoria NOT IN (
           SELECT DISTINCT categoria FROM gastos_variables_base WHERE firebase_uid = ? AND activo = 1
         )
       GROUP BY rg.categoria HAVING meses_repetidos >= 3`,
      [firebase_uid, anio, mes - 2, mes, firebase_uid]
    );
    for (const r of repetidos) {
      alertas.push({
        tipo: 'repeticion_no_presup', categoria: r.categoria, nivel: 'info',
        titulo: `Gasto repetido en ${r.categoria}`,
        mensaje: `Llevas ${r.meses_repetidos} meses con gastos no presupuestados en ${r.categoria}.`,
        accion_sugerida: `Considera agregar ${r.categoria} a tu presupuesto variable base para controlarlo mejor.`,
      });
    }
  }

  // Guardar alertas nuevas (evitar duplicados del mismo mes/tipo/categoría)
  for (const a of alertas) {
    try {
      await db.execute(
        `INSERT INTO alertas_financieras (firebase_uid, anio, mes, tipo, categoria, nivel, titulo, mensaje, accion_sugerida)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [firebase_uid, anio, mes, a.tipo, a.categoria || null, a.nivel, a.titulo, a.mensaje, a.accion_sugerida || null]
      );
    } catch (_) { /* ignorar duplicados */ }
  }
  return alertas;
}

// GET /user/alertas?firebase_uid=&anio=&mes=&leidas=0
app.get('/user/alertas', async (req, res) => {
  const { firebase_uid, anio, mes, leidas } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    let sql = `SELECT * FROM alertas_financieras WHERE firebase_uid = ?`;
    const params = [firebase_uid];
    if (anio)   { sql += ` AND anio = ?`;  params.push(anio); }
    if (mes)    { sql += ` AND mes = ?`;   params.push(mes); }
    if (leidas !== undefined) { sql += ` AND leida = ?`; params.push(leidas === '1' ? 1 : 0); }
    sql += ` ORDER BY created_at DESC LIMIT 50`;
    const [rows] = await db.execute(sql, params);
    res.json({ alertas: rows, total: rows.length, no_leidas: rows.filter(a => !a.leida).length });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// POST /user/alertas/generar/:anio/:mes
app.post('/user/alertas/generar/:anio/:mes', async (req, res) => {
  const { anio, mes } = req.params;
  const { firebase_uid } = req.body;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const alertas = await _generarAlertasMes(firebase_uid, Number(anio), Number(mes));
    res.json({ alertas_generadas: alertas.length, alertas });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// PATCH /user/alertas/:id/leer
app.patch('/user/alertas/:id/leer', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.body;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    await db.execute(`UPDATE alertas_financieras SET leida = 1 WHERE id = ? AND firebase_uid = ?`, [id, firebase_uid]);
    res.json({ success: true });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// GET /user/proyeccion-siguiente-anio/:anio?firebase_uid=
// Usa el comportamiento real del año actual para proponer el presupuesto del siguiente.
app.get('/user/proyeccion-siguiente-anio/:anio', async (req, res) => {
  const { anio } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    // Promedio real por categoría durante el año
    const [analisis] = await db.execute(
      `SELECT categoria,
              AVG(CASE WHEN tipo='variable' THEN monto ELSE 0 END)          AS avg_variable,
              AVG(CASE WHEN tipo='no_presupuestado' THEN monto ELSE 0 END)  AS avg_no_presup,
              SUM(monto)                                                      AS total_anual,
              COUNT(DISTINCT mes)                                             AS meses_presentes
       FROM registros_gasto
       WHERE firebase_uid = ? AND anio = ?
       GROUP BY categoria ORDER BY total_anual DESC`,
      [firebase_uid, anio]
    );

    const [varBase] = await db.execute(
      `SELECT categoria, SUM(monto_estimado) AS presupuestado_mensual
       FROM gastos_variables_base WHERE firebase_uid = ? AND activo = 1 GROUP BY categoria`,
      [firebase_uid]
    );
    const presupActual = {};
    for (const g of varBase) presupActual[g.categoria] = Number(g.presupuestado_mensual);

    const recomendaciones = analisis.map(a => {
      const avgReal    = Number(a.avg_variable) + Number(a.avg_no_presup);
      const presup     = presupActual[a.categoria] || 0;
      const diferencia = parseFloat((avgReal - presup).toFixed(2));
      return {
        categoria: a.categoria,
        presupuesto_actual: parseFloat(presup.toFixed(2)),
        promedio_real_mensual: parseFloat(avgReal.toFixed(2)),
        promedio_no_presupuestado: parseFloat(Number(a.avg_no_presup).toFixed(2)),
        diferencia,
        recomendacion: diferencia > 5
          ? `Aumentar presupuesto de ${a.categoria} en $${diferencia.toFixed(2)}/mes`
          : diferencia < -20
            ? `Podrías reducir presupuesto de ${a.categoria} en $${Math.abs(diferencia).toFixed(2)}/mes`
            : 'Presupuesto adecuado',
        accion: diferencia > 5 ? 'aumentar' : diferencia < -20 ? 'reducir' : 'mantener',
      };
    });

    res.json({
      anio_analizado: Number(anio),
      anio_proyectado: Number(anio) + 1,
      recomendaciones,
      resumen: `Basado en tu comportamiento real de ${anio}, se sugieren ${recomendaciones.filter(r => r.accion !== 'mantener').length} ajustes al presupuesto.`,
    });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// POST /user/cerrar-mes-financiero/:anio/:mes
app.post('/user/cerrar-mes-financiero/:anio/:mes', async (req, res) => {
  const { anio, mes } = req.params;
  const { firebase_uid } = req.body;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [[mesRow]] = await db.execute(
      `SELECT * FROM meses_financieros WHERE firebase_uid = ? AND anio = ? AND mes = ?`,
      [firebase_uid, anio, mes]
    );
    if (!mesRow) return res.status(404).json({ error: 'Mes no encontrado' });
    if (mesRow.estado === 'cerrado') return res.status(400).json({ error: 'Mes ya cerrado' });

    // Generar alertas del mes antes de cerrar
    const alertas = await _generarAlertasMes(firebase_uid, Number(anio), Number(mes));

    // Análisis de categorías con desviación
    const [catAnalisis] = await db.execute(
      `SELECT categoria, SUM(monto) AS total, tipo FROM registros_gasto
       WHERE mes_id = ? AND firebase_uid = ? GROUP BY categoria, tipo`,
      [mesRow.id, firebase_uid]
    );

    // Cerrar el mes
    await db.execute(
      `UPDATE meses_financieros SET estado = 'cerrado', cerrado_at = NOW() WHERE id = ?`,
      [mesRow.id]
    );

    // Snapshot en cierres_mensuales
    await db.execute(
      `INSERT INTO cierres_mensuales
         (firebase_uid, mes_id, anio, mes, ingreso_real, fijos_pagados,
          variables_reales, no_presupuestados, remanente_real, recomendaciones)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
       ON DUPLICATE KEY UPDATE
         ingreso_real = VALUES(ingreso_real), fijos_pagados = VALUES(fijos_pagados),
         variables_reales = VALUES(variables_reales), no_presupuestados = VALUES(no_presupuestados),
         remanente_real = VALUES(remanente_real), recomendaciones = VALUES(recomendaciones)`,
      [firebase_uid, mesRow.id, anio, mes,
       mesRow.ingreso_real || mesRow.ingreso_estimado,
       mesRow.fijos_reales, mesRow.variables_reales, mesRow.no_presupuestados_reales,
       parseFloat((Number(mesRow.ingreso_real || mesRow.ingreso_estimado) - Number(mesRow.fijos_reales) - Number(mesRow.variables_reales) - Number(mesRow.no_presupuestados_reales)).toFixed(2)),
       JSON.stringify(alertas.map(a => ({ tipo: a.tipo, categoria: a.categoria, mensaje: a.mensaje })))]
    );

    res.json({ cerrado: true, alertas_generadas: alertas.length, alertas });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// =============================================================================
// INICIO DEL SERVIDOR
// =============================================================================
const PORT = process.env.PORT || 3002;
app.listen(PORT, () => console.log(`🚀 Servidor activo en puerto ${PORT}`));
