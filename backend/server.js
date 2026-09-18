/**
 * server.js — Backend principal de Salarying
 *
 * Stack: Node.js + Express + MySQL (mysql2) + node-cron
 * Desplegado en: Render (free tier)
 * Base de datos: Clever Cloud MySQL
 *
 * MÓDULOS QUE GESTIONA ESTE ARCHIVO:
 *  Perfil financiero (income + gastos fijos), dashboard, producción/ventas/cobros a
 *  clientes, catálogo de productos, presupuestos compartidos, jobs, patrimonio/
 *  objetivos/comparativa/consejero-ia/subcategorias, estado financiero anual,
 *  registros de gasto, y el cron job de marcado automático de eventos vencidos
 *  cada medianoche.
 *  El resto vive en routes/*.js (montados abajo) y lib/*.js (lógica compartida
 *  como períodos, calendario y recálculo de estimados).
 *
 * AUTENTICACIÓN:
 *  Por ahora se usa firebase_uid = email del usuario.
 *  Cuando se implemente Firebase Auth real, vendrá del JWT en el header.
 *  Todos los endpoints ya reciben y filtran por firebase_uid para estar
 *  preparados para ese cambio sin refactorizaciones mayores.
 */

const express = require('express');
const cors    = require('cors');
const cron    = require('node-cron');
const fetch   = (...args) => import('node-fetch').then(({default: f}) => f(...args));
const {
  _montoMensual,
  _generarAplicaMeses,
  _construirTimeline,
  calcularSplits,
  _calcularScore,
} = require('./lib/calculos_financieros');
const { pool, db } = require('./lib/db');
const { LOG_SECRET, _logError, _logInfo } = require('./lib/logger');
const { calcularFechasEvento, generarEventosCalendario, generarEventosPerfilGasto: _generarEventosPerfilGasto } = require('./lib/calendario_helpers');
const { _actualizarTotalesMes, _generarAlertasMes, _recalcularEstimadosAnio } = require('./lib/mes_helpers');
const { getPeriodoActivo, crearPrimerPeriodo, crearNuevoPeriodo } = require('./lib/periodo_helpers');

const app = express();
app.use(cors());          // Permite peticiones desde el app Flutter (cross-origin)
app.use(express.json());  // Parsea el body de las peticiones como JSON
app.use(require('./routes/logs'));
app.use(require('./routes/ahorros'));
app.use(require('./routes/calendario'));
app.use(require('./routes/gustitos'));
app.use(require('./routes/expense_definitions'));
app.use(require('./routes/timeline'));
app.use(require('./routes/quincena'));
app.use(require('./routes/alertas'));
app.use(require('./routes/eventos'));
app.use(require('./routes/deudas'));
app.use(require('./routes/presupuestos'));
app.use(require('./routes/gastos'));
app.use(require('./routes/movimientos'));
app.use(require('./routes/sobres'));
app.use(require('./routes/ingresos_extra'));
app.use(require('./routes/gastos_globales'));
app.use(require('./routes/gastos_variables_base'));

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

    // Tabla de acciones propuestas por el asistente IA (pendiente de confirmación del usuario)
    await db.execute(`CREATE TABLE IF NOT EXISTS acciones_pendientes (
      id                   INT AUTO_INCREMENT PRIMARY KEY,
      firebase_uid         VARCHAR(255) NOT NULL,
      tipo                 ENUM('registrar_pago','marcar_pagado','crear_gasto','abonar_deuda') NOT NULL,
      parametros           LONGTEXT NOT NULL,
      resumen_para_usuario TEXT NOT NULL,
      status               ENUM('pendiente','confirmada','cancelada','expirada') DEFAULT 'pendiente',
      created_at           TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      executed_at          TIMESTAMP NULL,
      KEY idx_acc_user (firebase_uid),
      KEY idx_acc_status (status)
    )`).catch(() => {});

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

  // Migración: columnas adicionales en calendario_eventos (MySQL 5.6 no soporta IF NOT EXISTS en ADD COLUMN)
  const _migrCalEvCols = [
    [`ALTER TABLE calendario_eventos ADD COLUMN deuda_id INT DEFAULT NULL`, 'deuda_id'],
    [`ALTER TABLE calendario_eventos ADD COLUMN notificacion_enviada TINYINT DEFAULT 0`, 'notificacion_enviada'],
    [`ALTER TABLE calendario_eventos ADD COLUMN google_event_id VARCHAR(255) DEFAULT NULL`, 'google_event_id'],
    [`ALTER TABLE calendario_eventos ADD COLUMN periodo_id INT DEFAULT NULL`, 'periodo_id'],
    [`ALTER TABLE calendario_eventos ADD COLUMN cobro_id INT DEFAULT NULL`, 'cobro_id'],
  ];
  for (const [sql, col] of _migrCalEvCols) {
    try { await db.execute(sql); } catch (e) { /* columna ya existe */ }
  }
  console.log('✅ Migración calendario_eventos columnas extra OK');

  // Limpieza de alertas duplicadas: mantener solo la más reciente por (firebase_uid, anio, mes, tipo, categoria)
  try {
    await db.execute(`
      DELETE a1 FROM alertas_financieras a1
      INNER JOIN alertas_financieras a2
        ON a1.firebase_uid = a2.firebase_uid
        AND a1.anio = a2.anio
        AND a1.mes = a2.mes
        AND a1.tipo = a2.tipo
        AND (a1.categoria = a2.categoria OR (a1.categoria IS NULL AND a2.categoria IS NULL))
        AND a1.id < a2.id
    `);
    console.log('✅ Limpieza alertas duplicadas OK');
  } catch (e) {
    console.error('⚠️ Limpieza alertas duplicadas:', e.message);
  }

  // Migración: columna categoria en user_gastos_fijos (para análisis presupuesto por categoría)
  try {
    await db.execute(`ALTER TABLE user_gastos_fijos ADD COLUMN categoria VARCHAR(100) DEFAULT NULL`);
    console.log('✅ Migración user_gastos_fijos.categoria OK');
  } catch (e) { /* columna ya existe */ }

  // Limpieza: eventos de calendario que referencian gastos_fijos eliminados
  try {
    await db.execute(`
      DELETE ce FROM calendario_eventos ce
      WHERE ce.user_gasto_fijo_id IS NOT NULL
        AND NOT EXISTS (
          SELECT 1 FROM user_gastos_fijos ugf
          WHERE ugf.id = ce.user_gasto_fijo_id AND ugf.activo = 1
        )
    `);
    console.log('✅ Limpieza eventos calendario huérfanos OK');
  } catch (e) {
    console.error('⚠️ Limpieza eventos calendario huérfanos:', e.message);
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

  // Fase 2: gastos reutilizables — definiciones y vínculo en registros
  try {
    await db.execute(`CREATE TABLE IF NOT EXISTS expense_definitions (
      id           INT AUTO_INCREMENT PRIMARY KEY,
      firebase_uid VARCHAR(255) NOT NULL,
      nombre       VARCHAR(255) NOT NULL,
      categoria    VARCHAR(100) NOT NULL,
      tipo_habitual ENUM('fijo','variable','no_presupuestado') DEFAULT 'variable',
      activo       TINYINT DEFAULT 1,
      created_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      KEY idx_ed_uid (firebase_uid),
      KEY idx_ed_uid_activo (firebase_uid, activo)
    )`);
    await db.execute(`ALTER TABLE registros_gasto ADD COLUMN definition_id INT DEFAULT NULL`).catch(() => {});
    console.log('✅ Migración expense_definitions OK');
  } catch (e) {
    console.error('⚠️ Migración expense_definitions:', e.message);
  }

  // Migración: presupuestos de eventos (Sprint 7)
  try {
    await db.execute(`CREATE TABLE IF NOT EXISTS eventos_presupuesto (
      id                  INT AUTO_INCREMENT PRIMARY KEY,
      firebase_uid        VARCHAR(255) NOT NULL,
      nombre              VARCHAR(255) NOT NULL,
      descripcion         TEXT,
      emoji               VARCHAR(10) DEFAULT NULL,
      monto_total         DECIMAL(12,2) NOT NULL,
      anio                YEAR NOT NULL,
      mes_inicio          TINYINT NOT NULL,
      mes_fin             TINYINT NOT NULL,
      cuota_mensual       DECIMAL(12,2) NOT NULL,
      gastado_real        DECIMAL(12,2) DEFAULT 0.00,
      estado              ENUM('activo','cerrado','cancelado') DEFAULT 'activo',
      created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      KEY idx_ep_user (firebase_uid),
      KEY idx_ep_anio (firebase_uid, anio)
    )`);
    await db.execute(`CREATE TABLE IF NOT EXISTS eventos_gastos (
      id           INT AUTO_INCREMENT PRIMARY KEY,
      firebase_uid VARCHAR(255) NOT NULL,
      evento_id    INT NOT NULL,
      nombre       VARCHAR(255) NOT NULL,
      monto        DECIMAL(12,2) NOT NULL,
      fecha        DATE DEFAULT NULL,
      notas        TEXT,
      created_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      KEY idx_eg_evento (evento_id)
    )`);
    console.log('✅ Migración eventos_presupuesto OK');
  } catch (e) {
    console.error('⚠️ Migración eventos_presupuesto:', e.message);
  }

  // Migración: shared_expense_id en registros_gasto para vincular gastos compartidos con estado financiero
  try {
    await db.execute(`ALTER TABLE registros_gasto ADD COLUMN shared_expense_id INT DEFAULT NULL`);
    console.log('✅ Migración shared_expense_id en registros_gasto OK');
  } catch (e) {
    if (!e.message.includes('Duplicate column') && !e.message.includes('already exists')) {
      console.error('⚠️ Migración shared_expense_id:', e.message);
    }
  }

  // Migración: roles en presupuesto compartido (Sprint 8)
  try {
    // ENUM ampliado: creador | admin | participante | lectura (owner queda como alias legacy)
    await db.execute(`ALTER TABLE shared_budget_members
      MODIFY COLUMN rol ENUM('owner','creador','admin','participante','lectura') NOT NULL DEFAULT 'participante'`);
    // owner existente → creador
    await db.execute(`UPDATE shared_budget_members SET rol = 'creador' WHERE rol = 'owner'`);
    // member / vacío / inválido → participante (fix Sprint 8: el ENUM nuevo no incluye 'member')
    await db.execute(`UPDATE shared_budget_members SET rol = 'participante' WHERE rol NOT IN ('owner','creador','admin','participante','lectura') OR rol = '' OR rol IS NULL`);
    // rol_invitado en invitaciones para que el owner elija el rol al invitar
    await db.execute(`ALTER TABLE shared_budget_invitations
      ADD COLUMN rol_invitado ENUM('admin','participante','lectura') NOT NULL DEFAULT 'participante'`);
    console.log('✅ Migración roles shared_budget OK');
  } catch (e) {
    // Silencioso si las columnas ya existen
  }

  // Migración Z2: display_name en miembros de shared budget (nombre real del usuario)
  try {
    await db.execute(`ALTER TABLE shared_budget_members ADD COLUMN display_name VARCHAR(255) DEFAULT NULL`);
    console.log('✅ Migración display_name shared_budget_members OK');
  } catch (e) {
    if (!e.message.includes('Duplicate column') && !e.message.includes('already exists')) {
      console.error('⚠️ Migración display_name shared_budget_members:', e.message);
    }
  }

  // Migración Sprint 9: catálogo de productos e historial de precios (facturas QR mejoradas)
  try {
    await db.execute(`CREATE TABLE IF NOT EXISTS productos_catalogo (
      id                    INT AUTO_INCREMENT PRIMARY KEY,
      firebase_uid          VARCHAR(255) NOT NULL,
      nombre                VARCHAR(255) NOT NULL,
      nombre_normalizado    VARCHAR(255) NOT NULL,
      categoria             VARCHAR(100) DEFAULT NULL,
      merchant_name_habitual VARCHAR(255) DEFAULT NULL,
      veces_comprado        INT DEFAULT 1,
      ultimo_precio         DECIMAL(12,2) DEFAULT NULL,
      ultima_compra         DATE DEFAULT NULL,
      activo                TINYINT DEFAULT 1,
      created_at            TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      UNIQUE KEY uq_uid_nombre (firebase_uid, nombre_normalizado),
      KEY idx_pc_uid (firebase_uid)
    )`);
    await db.execute(`CREATE TABLE IF NOT EXISTS historial_precios_producto (
      id              INT AUTO_INCREMENT PRIMARY KEY,
      producto_id     INT NOT NULL,
      firebase_uid    VARCHAR(255) NOT NULL,
      invoice_id      INT DEFAULT NULL,
      precio_unitario DECIMAL(12,2) NOT NULL,
      cantidad        DECIMAL(10,3) DEFAULT 1,
      merchant_name   VARCHAR(255) DEFAULT NULL,
      fecha_compra    DATE DEFAULT NULL,
      created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      KEY idx_hpp_producto (producto_id),
      KEY idx_hpp_uid_fecha (firebase_uid, fecha_compra)
    )`);
    // Columna para vincular registros_gasto con factura QR
    await db.execute(`ALTER TABLE registros_gasto ADD COLUMN scanned_invoice_id INT DEFAULT NULL`);
    console.log('✅ Migración Sprint 9: productos_catalogo OK');
  } catch (e) {
    if (!e.message.includes('Duplicate column') && !e.message.includes('already exists')) {
      console.error('⚠️ Migración Sprint 9 productos:', e.message);
    }
  }

  // Migración: es_hormiga en registros_gasto (gastos no presupuestados pequeños)
  try {
    await db.execute(`ALTER TABLE registros_gasto ADD COLUMN es_hormiga TINYINT DEFAULT 0`);
    console.log('✅ Migración es_hormiga en registros_gasto OK');
  } catch (e) {
    if (!e.message.includes('Duplicate column') && !e.message.includes('already exists')) {
      console.error('⚠️ Migración es_hormiga:', e.message);
    }
  }

  // Migración: origen_deuda_id en registros_gasto — vincula un pago mensual con su deuda
  try {
    await db.execute(`ALTER TABLE registros_gasto ADD COLUMN origen_deuda_id INT DEFAULT NULL`);
    console.log('✅ Migración origen_deuda_id en registros_gasto OK');
  } catch (e) {
    if (!e.message.includes('Duplicate column') && !e.message.includes('already exists')) {
      console.error('⚠️ Migración origen_deuda_id:', e.message);
    }
  }

  // Migración: origen_gustito_id en registros_gasto — vincula un registro con su gustito de origen
  try {
    await db.execute(`ALTER TABLE registros_gasto ADD COLUMN origen_gustito_id INT DEFAULT NULL`);
    console.log('✅ Migración origen_gustito_id en registros_gasto OK');
  } catch (e) {
    if (!e.message.includes('Duplicate column') && !e.message.includes('already exists')) {
      console.error('⚠️ Migración origen_gustito_id:', e.message);
    }
  }

  // Migración: unificación de categorías (V1/O2) — normaliza valores stray a la lista canónica.
  // Idempotente: re-ejecutarla no tiene efecto una vez normalizados los datos.
  // Equivalencias: deuda→deudas, General→otro, Compartido→compartido
  try {
    let total = 0;
    const [r1] = await db.execute(
      `UPDATE registros_gasto SET categoria = 'deudas' WHERE categoria = 'deuda'`);
    const [r2] = await db.execute(
      `UPDATE registros_gasto SET categoria = 'otro' WHERE categoria = 'General'`);
    const [r3] = await db.execute(
      `UPDATE registros_gasto SET categoria = 'compartido' WHERE categoria = 'Compartido'`);
    const [r4] = await db.execute(
      `UPDATE gastos_variables_base SET categoria = 'deudas' WHERE categoria = 'deuda'`);
    const [r5] = await db.execute(
      `UPDATE user_gastos_fijos SET categoria = 'deudas' WHERE categoria = 'deuda'`);
    // otros (plural) → otro (canónico singular) — fix QA 2026-06
    const [r6] = await db.execute(
      `UPDATE registros_gasto SET categoria = 'otro' WHERE categoria = 'otros'`);
    const [r7] = await db.execute(
      `UPDATE gastos_variables_base SET categoria = 'otro' WHERE categoria = 'otros'`);
    total = r1.affectedRows + r2.affectedRows + r3.affectedRows + r4.affectedRows
          + r5.affectedRows + r6.affectedRows + r7.affectedRows;
    if (total > 0) console.log(`✅ Migración unificación categorías: ${total} filas normalizadas`);
  } catch (e) {
    console.error('⚠️ Migración unificación categorías:', e.message);
  }

  // Migración: origen_evento_id en registros_gasto — vincula un registro con su evento de origen (AA1)
  try {
    await db.execute(`ALTER TABLE registros_gasto ADD COLUMN origen_evento_id INT DEFAULT NULL`);
    console.log('✅ Migración origen_evento_id en registros_gasto OK');
  } catch (e) {
    if (!e.message.includes('Duplicate column') && !e.message.includes('already exists')) {
      console.error('⚠️ Migración origen_evento_id:', e.message);
    }
  }

  // Migración: todos los registros_gasto existentes → día 15 para distribución quincenal 50/50
  try {
    const [res] = await db.execute(
      `UPDATE registros_gasto
       SET fecha = DATE_FORMAT(fecha, '%Y-%m-15')
       WHERE DAY(fecha) != 15`
    );
    if (res.affectedRows > 0) console.log(`✅ Migración quincenal completa: ${res.affectedRows} registros movidos a día 15`);
  } catch (e) {
    console.error('⚠️ Migración quincenal completa:', e.message);
  }

  // Migración: tabla para splits puntuales de gastos con notificación por email
  try {
    await db.execute(`CREATE TABLE IF NOT EXISTS gasto_splits_puntual (
      id                  INT AUTO_INCREMENT PRIMARY KEY,
      firebase_uid        VARCHAR(255) NOT NULL,
      registro_gasto_id   INT DEFAULT NULL,
      descripcion         VARCHAR(255) NOT NULL,
      monto_total         DECIMAL(10,2) NOT NULL,
      email_participante  VARCHAR(255) NOT NULL,
      monto_participante  DECIMAL(10,2) NOT NULL,
      notificado_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      KEY idx_gsp_uid (firebase_uid),
      KEY idx_gsp_registro (registro_gasto_id)
    )`);
    console.log('✅ Migración gasto_splits_puntual OK');
  } catch (e) {
    if (!e.message.includes('already exists')) console.error('⚠️ Migración gasto_splits_puntual:', e.message);
  }

  // Migración: configuración de usuario (modo_negocio, futuras preferencias)
  try {
    await db.execute(`CREATE TABLE IF NOT EXISTS user_settings (
      firebase_uid      VARCHAR(255) PRIMARY KEY,
      modo_negocio      TINYINT     NOT NULL DEFAULT 0,
      periodo_preferido ENUM('mensual','quincenal') DEFAULT 'mensual',
      updated_at        TIMESTAMP   DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    )`);
    await db.execute(`ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS periodo_preferido ENUM('mensual','quincenal') DEFAULT 'mensual'`).catch(()=>{});
    // L2 — presupuesto mensual de gustitos (0 = sin límite)
    await db.execute(`ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS presupuesto_gustitos DECIMAL(10,2) DEFAULT 0`).catch(()=>{});
    console.log('✅ Migración user_settings OK');
  } catch (e) {
    if (!e.message.includes('already exists')) {
      console.error('⚠️ Migración user_settings:', e.message);
    }
  }

  // Migración: activos del usuario (para patrimonio neto)
  try {
    await db.execute(`CREATE TABLE IF NOT EXISTS activos (
      id           INT AUTO_INCREMENT PRIMARY KEY,
      firebase_uid VARCHAR(255) NOT NULL,
      nombre       VARCHAR(255) NOT NULL,
      tipo         ENUM('inmueble','vehiculo','cuenta_banco','inversiones','efectivo','otro') DEFAULT 'otro',
      valor        DECIMAL(14,2) NOT NULL DEFAULT 0,
      descripcion  TEXT,
      activo       TINYINT DEFAULT 1,
      created_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      updated_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      KEY idx_activos_uid (firebase_uid)
    )`);
    console.log('✅ Migración activos OK');
  } catch (e) { if (!e.message.includes('already exists')) console.error('⚠️ activos:', e.message); }

  // Migración: objetivos financieros a largo plazo
  try {
    await db.execute(`CREATE TABLE IF NOT EXISTS objetivos_financieros (
      id           INT AUTO_INCREMENT PRIMARY KEY,
      firebase_uid VARCHAR(255) NOT NULL,
      nombre       VARCHAR(255) NOT NULL,
      descripcion  TEXT,
      monto_meta   DECIMAL(14,2) NOT NULL,
      monto_actual DECIMAL(14,2) DEFAULT 0,
      fecha_limite DATE,
      tipo         ENUM('ahorro','compra','emergencia','inversion','otro') DEFAULT 'otro',
      activo       TINYINT DEFAULT 1,
      created_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      updated_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      KEY idx_obj_uid (firebase_uid)
    )`);
    console.log('✅ Migración objetivos_financieros OK');
  } catch (e) { if (!e.message.includes('already exists')) console.error('⚠️ objetivos:', e.message); }

  // Migración: registros de ingresos extra (fotografía, freelance, bonos, etc.)
  try {
    await db.execute(`CREATE TABLE IF NOT EXISTS registros_ingreso (
      id            INT AUTO_INCREMENT PRIMARY KEY,
      firebase_uid  VARCHAR(255) NOT NULL,
      monto         DECIMAL(10,2) NOT NULL,
      descripcion   VARCHAR(255),
      fuente_nombre VARCHAR(100) NOT NULL DEFAULT 'Extra',
      fecha         DATE NOT NULL,
      anio          SMALLINT NOT NULL,
      mes           TINYINT NOT NULL,
      created_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      KEY idx_ri_user_mes (firebase_uid, anio, mes)
    )`);
    console.log('✅ Migración registros_ingreso OK');
  } catch (e) { if (!e.message.includes('already exists')) console.error('⚠️ registros_ingreso:', e.message); }

  // Migración: fuente_ingreso en registros_gasto (de qué ingreso salió este gasto)
  try {
    await db.execute(`ALTER TABLE registros_gasto ADD COLUMN fuente_ingreso VARCHAR(100) DEFAULT NULL`);
    console.log('✅ Migración fuente_ingreso en registros_gasto OK');
  } catch (e) {
    if (!e.message.includes('Duplicate column') && !e.message.includes('already exists')) {
      console.error('⚠️ Migración fuente_ingreso:', e.message);
    }
  }
});

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

// Lógica de períodos (getPeriodoActivo, generarMovimientosPeriodo, crearPrimerPeriodo,
// crearNuevoPeriodo, _insertarPeriodo) vive en lib/periodo_helpers.js — requerida al
// inicio de este archivo.
// Lógica de calendario (calcularFechasEvento, generarEventosCalendario) vive en
// lib/calendario_helpers.js — requerida al inicio de este archivo.

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
    _recalcularEstimadosAnio(firebase_uid, new Date().getFullYear()).catch(() => {});
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

// =============================================================================
// Módulo Ingresos Extra movido a routes/ingresos_extra.js (montado al inicio de este archivo).

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

// E1 — GET /user/gastos-fijos/:id/historial?firebase_uid=&anio=
// Historial de pagos del compromiso por mes (verde=pagado / gris=no) + promedio.
app.get('/user/gastos-fijos/:id/historial', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid, anio } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  const year = parseInt(anio) || new Date().getFullYear();
  try {
    const [[fijo]] = await db.execute(
      `SELECT id, descripcion, monto_mensual FROM user_gastos_fijos WHERE id = ? AND firebase_uid = ?`,
      [id, firebase_uid]
    );
    if (!fijo) return res.status(404).json({ error: 'Gasto fijo no encontrado' });
    const [regs] = await db.execute(
      `SELECT mes, SUM(monto) AS pagado
       FROM registros_gasto
       WHERE firebase_uid = ? AND origen_fijo_id = ? AND anio = ?
       GROUP BY mes`,
      [firebase_uid, id, year]
    );
    const porMes = {};
    for (const r of regs) porMes[Number(r.mes)] = Number(r.pagado);
    const now = new Date();
    const meses = [];
    let totalPagado = 0, mesesPagados = 0;
    for (let m = 1; m <= 12; m++) {
      const pagado = porMes[m] != null;
      const monto  = porMes[m] || 0;
      const futuro = year > now.getFullYear() || (year === now.getFullYear() && m > now.getMonth() + 1);
      if (pagado) { totalPagado += monto; mesesPagados++; }
      meses.push({ mes: m, pagado, monto: parseFloat(monto.toFixed(2)), futuro });
    }
    res.json({
      nombre: fijo.descripcion,
      presupuestado: parseFloat(Number(fijo.monto_mensual).toFixed(2)),
      anio: year,
      meses_pagados: mesesPagados,
      promedio_pagado: mesesPagados ? parseFloat((totalPagado / mesesPagados).toFixed(2)) : 0,
      meses,
    });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

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

// POST /user/gastos-fijos/bulk — importación masiva desde CSV
app.post('/user/gastos-fijos/bulk', async (req, res) => {
  const { firebase_uid, gastos } = req.body;
  if (!firebase_uid || !Array.isArray(gastos) || gastos.length === 0)
    return res.status(400).json({ error: 'firebase_uid y gastos[] requeridos' });
  try {
    let creados = 0;
    for (const g of gastos) {
      const { descripcion, monto_mensual, tipo = 'otro', clasificacion = 'esencial' } = g;
      if (!descripcion || monto_mensual == null || Number(monto_mensual) <= 0) continue;
      const tiposValidos = ['vivienda','transporte','deuda','servicios','educacion','salud','alimentacion','otro'];
      const clasifValidas = ['esencial','importante','flexible'];
      await db.execute(
        `INSERT INTO user_gastos_fijos
           (firebase_uid, descripcion, monto_mensual, tipo, clasificacion, frecuencia, activo)
         VALUES (?, ?, ?, ?, ?, 'fijo', 1)`,
        [firebase_uid, descripcion, Number(monto_mensual),
         tiposValidos.includes(tipo) ? tipo : 'otro',
         clasifValidas.includes(clasificacion) ? clasificacion : 'esencial']
      );
      creados++;
    }
    _recalcularEstimadosAnio(firebase_uid, new Date().getFullYear()).catch(() => {});
    res.status(201).json({ creados });
    _logInfo('/user/gastos-fijos/bulk', `${creados} gastos importados por CSV`, firebase_uid);
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
    // ── Estado financiero anual (modelo actual) ───────────────────────────
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

    // ── Perfil financiero ─────────────────────────────────────────────────
    await db.execute(`DELETE FROM user_income WHERE firebase_uid = ?`, [firebase_uid]);
    await db.execute(`DELETE FROM user_gastos_fijos WHERE firebase_uid = ?`, [firebase_uid]);
    await db.execute(`DELETE FROM gastos_variables_base WHERE firebase_uid = ?`, [firebase_uid]);

    // ── Deudas y ahorros ──────────────────────────────────────────────────
    await db.execute(`DELETE FROM deudas WHERE firebase_uid = ?`, [firebase_uid]);
    await db.execute(`DELETE FROM aportaciones_ahorro WHERE firebase_uid = ?`, [firebase_uid]);

    // ── Presupuestos compartidos ──────────────────────────────────────────
    const [sbRows] = await db.execute(`SELECT id FROM shared_budgets WHERE owner_uid = ?`, [firebase_uid]);
    for (const sb of sbRows) {
      const [seRows] = await db.execute(`SELECT id FROM shared_expenses WHERE shared_budget_id = ?`, [sb.id]);
      for (const se of seRows) {
        await db.execute(`DELETE FROM shared_expense_splits WHERE expense_id = ?`, [se.id]);
      }
      await db.execute(`DELETE FROM shared_expenses WHERE shared_budget_id = ?`, [sb.id]);
      await db.execute(`DELETE FROM shared_budget_members WHERE shared_budget_id = ?`, [sb.id]);
      await db.execute(`DELETE FROM shared_budget_invitations WHERE shared_budget_id = ?`, [sb.id]);
      await db.execute(`DELETE FROM shared_settlements WHERE shared_budget_id = ?`, [sb.id]);
      await db.execute(`DELETE FROM shared_budget_activity_logs WHERE shared_budget_id = ?`, [sb.id]);
    }
    await db.execute(`DELETE FROM shared_budgets WHERE owner_uid = ?`, [firebase_uid]);
    // Eliminar también membresías en presupuestos ajenos
    await db.execute(`DELETE FROM shared_budget_members WHERE firebase_uid = ?`, [firebase_uid]);

    // ── Facturas QR y catálogo ────────────────────────────────────────────
    await db.execute(`DELETE FROM scanned_invoices WHERE firebase_uid = ?`, [firebase_uid]);
    await db.execute(`DELETE FROM productos_catalogo WHERE firebase_uid = ?`, [firebase_uid]);

    // ── Ventas ────────────────────────────────────────────────────────────
    const [ventasRows] = await db.execute(`SELECT id FROM ventas WHERE firebase_uid = ?`, [firebase_uid]);
    for (const v of ventasRows) {
      await db.execute(`DELETE FROM cobros_clientes WHERE venta_id = ?`, [v.id]);
    }
    await db.execute(`DELETE FROM ventas WHERE firebase_uid = ?`, [firebase_uid]);
    try { await db.execute(`DELETE FROM productos WHERE firebase_uid = ?`, [firebase_uid]); } catch(_) {}
    try { await db.execute(`DELETE FROM servicios WHERE firebase_uid = ?`, [firebase_uid]); } catch(_) {}

    // ── Calendario y configuración ────────────────────────────────────────
    await db.execute(`DELETE FROM calendario_eventos WHERE firebase_uid = ?`, [firebase_uid]);
    await db.execute(`DELETE FROM user_settings WHERE firebase_uid = ?`, [firebase_uid]);

    res.json({ success: true, message: 'Todos los datos del usuario eliminados' });
  } catch (e) {
    console.error('[DELETE /user/data]', e.message);
    res.status(500).json({ error: e.message });
  }
});

// =============================================================================
// MÓDULO: DASHBOARD Y REPORTES
// Dashboard consolidado, score de salud financiera y resumen mensual por correo.
// =============================================================================

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

    // Metas de ahorro activas
    const [objetivos] = await db.execute(
      `SELECT id, nombre, monto_meta, monto_actual, fecha_limite,
              DATEDIFF(fecha_limite, CURDATE()) AS dias_restantes
       FROM objetivos_financieros WHERE firebase_uid = ? AND activo = 1 ORDER BY fecha_limite ASC LIMIT 3`,
      [firebase_uid]);
    const objetivosResumen = objetivos.map(o => {
      const diasR = Math.max(0, Number(o.dias_restantes) || 365);
      const falta = Math.max(0, Number(o.monto_meta) - Number(o.monto_actual));
      return {
        id: o.id, nombre: o.nombre,
        monto_meta: Number(o.monto_meta), monto_actual: Number(o.monto_actual),
        pct_avance: Number(o.monto_meta) > 0 ? parseFloat((Number(o.monto_actual)/Number(o.monto_meta)*100).toFixed(1)) : 0,
        falta: parseFloat(falta.toFixed(2)),
        cuota_mensual: parseFloat((falta / Math.max(1, Math.ceil(diasR/30))).toFixed(2)),
        dias_restantes: diasR,
      };
    });

    // Score de salud (no punitivo)
    const totalAhorros = objetivos.reduce((s, o) => s + Number(o.monto_actual), 0);
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
      objetivos:          objetivosResumen,
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
       GROUP BY p.id ORDER BY p.fecha_inicio DESC LIMIT ${parseInt(meses)}`,
      [firebase_uid]
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

// Módulos Presupuestos, Gastos y Movimientos movidos a routes/presupuestos.js,
// routes/gastos.js y routes/movimientos.js (montados al inicio de este archivo).

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
    // Expirar acciones pendientes de IA no confirmadas en >24h
    const [accExp] = await db.execute(
      `UPDATE acciones_pendientes SET status='expirada'
       WHERE status='pendiente' AND created_at < DATE_SUB(NOW(), INTERVAL 24 HOUR)`
    );
    if (accExp.affectedRows > 0) console.log(`⏰ Cron IA: ${accExp.affectedRows} acciones expiradas`);
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

// Jerarquía de roles: creador > admin > participante > lectura
const ROLE_LEVEL = { creador: 4, admin: 3, participante: 2, lectura: 1, owner: 4, member: 2 };

// Retorna el rol del usuario en el presupuesto, o null si no es miembro
async function _getSharedRole(budgetId, uid) {
  const [[row]] = await db.execute(
    `SELECT rol FROM shared_budget_members WHERE shared_budget_id = ? AND firebase_uid = ?`,
    [budgetId, uid]
  );
  return row ? row.rol : null;
}

// Retorna true si el usuario tiene al menos el nivel de rol requerido
async function _hasSharedRole(budgetId, uid, minRole) {
  const rol = await _getSharedRole(budgetId, uid);
  if (!rol) return false;
  return (ROLE_LEVEL[rol] || 0) >= (ROLE_LEVEL[minRole] || 0);
}

// POST /shared-budgets
app.post('/shared-budgets', async (req, res) => {
  const { nombre, tipo_periodo, dia_inicio_periodo, regla_reparto, porcentaje_owner, ingreso_owner, contribucion_owner, aporte_periodo_owner = 0, firebase_uid, display_name } = req.body;
  if (!nombre || !firebase_uid) return res.status(400).json({ error: 'Datos incompletos' });
  const conn = await db.getConnection();
  await conn.beginTransaction();
  try {
    const [r] = await conn.execute(
      `INSERT INTO shared_budgets (nombre, tipo_periodo, dia_inicio_periodo, regla_reparto, estado, owner_uid)
       VALUES (?, ?, ?, ?, 'active', ?)`,
      [nombre, tipo_periodo || 'mensual', dia_inicio_periodo || 1, regla_reparto || 'equitativo', firebase_uid]
    );
    const budgetId = r.insertId;
    const pct = regla_reparto === 'porcentual' ? (porcentaje_owner || 50) : 50;
    const ingreso = regla_reparto === 'proporcional' ? (ingreso_owner || null) : null;
    const contribucion = regla_reparto === 'pool_contribucion' ? (contribucion_owner || null) : null;
    await conn.execute(
      `INSERT INTO shared_budget_members (shared_budget_id, firebase_uid, display_name, rol, porcentaje, ingreso_declarado, contribucion_mensual, aporte_periodo)
       VALUES (?, ?, ?, 'creador', ?, ?, ?, ?)`,
      [budgetId, firebase_uid, display_name || null, pct, ingreso, contribucion, Number(aporte_periodo_owner) || 0]
    );
    await conn.execute(
      `INSERT INTO shared_budget_activity_logs (shared_budget_id, actor_uid, accion, detalle)
       VALUES (?, ?, 'crear_presupuesto', ?)`,
      [budgetId, firebase_uid, JSON.stringify({ nombre })]
    );
    await conn.commit();
    conn.release();
    res.status(201).json({ id: budgetId, nombre, estado: 'active' });
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
              m.rol, m.porcentaje,
              COALESCE((
                SELECT SUM(ses.monto_responsabilidad)
                FROM shared_expense_splits ses
                JOIN shared_expenses se ON se.id = ses.expense_id
                WHERE se.shared_budget_id = sb.id AND ses.firebase_uid = ? AND ses.pagado = 0 AND se.es_personal = 0
              ), 0) AS mi_deuda,
              COALESCE((
                SELECT SUM(ses.monto_responsabilidad)
                FROM shared_expense_splits ses
                JOIN shared_expenses se ON se.id = ses.expense_id
                WHERE se.shared_budget_id = sb.id AND ses.firebase_uid != ? AND ses.pagado = 0 AND se.pagado_por = ? AND se.es_personal = 0
              ), 0) AS me_deben
       FROM shared_budgets sb
       JOIN shared_budget_members m ON m.shared_budget_id = sb.id AND m.firebase_uid = ?
       ORDER BY sb.created_at DESC`,
      [firebase_uid, firebase_uid, firebase_uid, firebase_uid]
    );
    const rowsConBalance = rows.map(r => ({
      ...r,
      balance_neto: Math.round((Number(r.mi_deuda) - Number(r.me_deben)) * 100) / 100,
    }));
    res.json(rowsConBalance);
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
      `SELECT firebase_uid, display_name, rol, porcentaje, ingreso_declarado, contribucion_mensual, joined_at FROM shared_budget_members WHERE shared_budget_id = ?`,
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
    // Solo creador o admin pueden editar el presupuesto
    if (!(await _hasSharedRole(id, firebase_uid, 'admin'))) {
      return res.status(403).json({ error: 'Se requiere rol admin o creador' });
    }
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
    // Solo el creador puede eliminar el presupuesto
    if (!(await _hasSharedRole(id, firebase_uid, 'creador'))) {
      return res.status(403).json({ error: 'Solo el creador puede eliminar el presupuesto' });
    }
    await db.execute(`DELETE FROM shared_budgets WHERE id = ?`, [id]);
    res.json({ message: 'Eliminado' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// POST /shared-budgets/:id/invitations
app.post('/shared-budgets/:id/invitations', async (req, res) => {
  const { id } = req.params;
  const { email_invitado, firebase_uid, rol_invitado = 'participante' } = req.body;
  if (!email_invitado || !firebase_uid) return res.status(400).json({ error: 'Datos incompletos' });
  const rolesValidos = ['admin', 'participante', 'lectura'];
  if (!rolesValidos.includes(rol_invitado)) return res.status(400).json({ error: 'rol_invitado inválido' });
  try {
    // Solo creador o admin pueden invitar
    const [[myMember]] = await db.execute(
      `SELECT rol FROM shared_budget_members WHERE shared_budget_id = ? AND firebase_uid = ?`, [id, firebase_uid]
    );
    if (!myMember || !['creador', 'admin'].includes(myMember.rol)) {
      return res.status(403).json({ error: 'Solo el creador o un admin puede invitar' });
    }
    // Admin no puede invitar a otro admin (solo creador puede)
    if (myMember.rol === 'admin' && rol_invitado === 'admin') {
      return res.status(403).json({ error: 'Solo el creador puede asignar rol admin' });
    }
    // Cancelar invitaciones previas pendientes al mismo email
    await db.execute(
      `UPDATE shared_budget_invitations SET estado = 'cancelled'
       WHERE shared_budget_id = ? AND email_invitado = ? AND estado = 'pending'`,
      [id, email_invitado]
    );
    const token = require('crypto').randomBytes(32).toString('hex');
    const expiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000);
    await db.execute(
      `INSERT INTO shared_budget_invitations (shared_budget_id, email_invitado, token, expires_at, rol_invitado)
       VALUES (?, ?, ?, ?, ?)`,
      [id, email_invitado, token, expiresAt, rol_invitado]
    );
    await db.execute(
      `INSERT INTO shared_budget_activity_logs (shared_budget_id, actor_uid, accion, detalle)
       VALUES (?, ?, 'invitar_usuario', ?)`,
      [id, firebase_uid, JSON.stringify({ email_invitado, rol_invitado })]
    );
    const [[budgetInfo]] = await db.execute(`SELECT nombre FROM shared_budgets WHERE id = ?`, [id]);
    sendInvitationEmail({ emailInvitado: email_invitado, ownerUid: firebase_uid, presupuestoNombre: budgetInfo.nombre });
    res.status(201).json({ token, email_invitado, rol_invitado, expires_at: expiresAt });
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
  const { firebase_uid, ingreso_declarado, display_name } = req.body;
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
    // Nuevo miembro entra con el rol definido en la invitación
    const rolNuevo = inv.rol_invitado || 'participante';
    const contribucionNuevo = budget.regla_reparto === 'pool_contribucion' ? (ingreso_declarado || null) : null;
    await conn.execute(
      `INSERT IGNORE INTO shared_budget_members (shared_budget_id, firebase_uid, display_name, rol, porcentaje, ingreso_declarado, contribucion_mensual)
       VALUES (?, ?, ?, ?, 0, ?, ?)`,
      [inv.shared_budget_id, firebase_uid, display_name || null, rolNuevo, ingreso_declarado || null, contribucionNuevo]
    );
    await conn.execute(
      `UPDATE shared_budgets SET estado = 'active' WHERE id = ?`, [inv.shared_budget_id]
    );

    // Recalcular splits de todos los gastos pendientes (no pagados) con los nuevos miembros
    // Solo se tocan gastos donde NINGÚN split ha sido confirmado (pagado=0 en todos)
    try {
      const [allMembers] = await conn.execute(
        `SELECT firebase_uid, porcentaje, ingreso_declarado FROM shared_budget_members WHERE shared_budget_id = ?`,
        [inv.shared_budget_id]
      );
      // Gastos compartidos del presupuesto donde ningún split está confirmado
      const [gastosPendientes] = await conn.execute(
        `SELECT DISTINCT se.id, se.monto, se.regla_override
         FROM shared_expenses se
         WHERE se.shared_budget_id = ? AND se.es_personal = 0
           AND NOT EXISTS (
             SELECT 1 FROM shared_expense_splits s2
             WHERE s2.expense_id = se.id AND s2.pagado = 1
           )`,
        [inv.shared_budget_id]
      );
      for (const gasto of gastosPendientes) {
        const reglaGasto = gasto.regla_override || budget.regla_reparto;
        const nuevosSplits = calcularSplits(parseFloat(gasto.monto), reglaGasto, allMembers);
        // Borrar splits anteriores y recalcular
        await conn.execute(`DELETE FROM shared_expense_splits WHERE expense_id = ?`, [gasto.id]);
        for (const sp of nuevosSplits) {
          await conn.execute(
            `INSERT INTO shared_expense_splits (expense_id, firebase_uid, monto_responsabilidad) VALUES (?, ?, ?)`,
            [gasto.id, sp.firebase_uid, sp.monto_responsabilidad]
          );
        }
      }
    } catch (_) { /* fire-and-forget — no bloquear el accept */ }

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

// Z4 — POST /shared-budgets/:id/invite-code
// Genera (o reutiliza) un código de invitación abierto que el creador/admin puede
// compartir por WhatsApp/SMS. Cualquiera con el código puede unirse sin que el
// anfitrión conozca su email exacto. Invitación "abierta": email_invitado = '__open__'
// (nunca coincide con un firebase_uid real, así el accept por email la ignora).
app.post('/shared-budgets/:id/invite-code', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid, rol_invitado = 'participante' } = req.body;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  const rolesValidos = ['admin', 'participante', 'lectura'];
  if (!rolesValidos.includes(rol_invitado)) return res.status(400).json({ error: 'rol_invitado inválido' });
  try {
    const [[myMember]] = await db.execute(
      `SELECT rol FROM shared_budget_members WHERE shared_budget_id = ? AND firebase_uid = ?`, [id, firebase_uid]
    );
    if (!myMember || !['creador', 'admin'].includes(myMember.rol)) {
      return res.status(403).json({ error: 'Solo el creador o un admin puede invitar' });
    }
    if (myMember.rol === 'admin' && rol_invitado === 'admin') {
      return res.status(403).json({ error: 'Solo el creador puede asignar rol admin' });
    }
    // Reutilizar un código abierto vigente con el mismo rol (evita acumular códigos)
    const [[existing]] = await db.execute(
      `SELECT token FROM shared_budget_invitations
        WHERE shared_budget_id = ? AND email_invitado = '__open__' AND rol_invitado = ?
          AND estado = 'pending' AND expires_at > NOW()
        ORDER BY created_at DESC LIMIT 1`,
      [id, rol_invitado]
    );
    let code;
    if (existing) {
      code = existing.token;
    } else {
      const gen = () => require('crypto').randomBytes(4).toString('hex').toUpperCase(); // 8 chars
      code = gen();
      for (let i = 0; i < 5; i++) {
        const [[clash]] = await db.execute(`SELECT id FROM shared_budget_invitations WHERE token = ?`, [code]);
        if (!clash) break;
        code = gen();
      }
      const expiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);
      await db.execute(
        `INSERT INTO shared_budget_invitations (shared_budget_id, email_invitado, token, expires_at, rol_invitado)
         VALUES (?, '__open__', ?, ?, ?)`,
        [id, code, expiresAt, rol_invitado]
      );
    }
    res.status(201).json({ code, rol_invitado });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Z4 — POST /shared-budget-invitations/code/:code/join
// Une al usuario actual a un presupuesto usando un código abierto. Aditivo: no
// toca el accept por email. Reutilizable hasta que expire (varias personas pueden
// unirse con el mismo código). Guarda contra unirse dos veces.
app.post('/shared-budget-invitations/code/:code/join', async (req, res) => {
  const { code } = req.params;
  const { firebase_uid, ingreso_declarado, display_name } = req.body;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  const conn = await db.getConnection();
  await conn.beginTransaction();
  try {
    const [[inv]] = await conn.execute(
      `SELECT * FROM shared_budget_invitations
        WHERE token = ? AND email_invitado = '__open__' AND estado = 'pending' AND expires_at > NOW()`,
      [code]
    );
    if (!inv) { await conn.rollback(); conn.release(); return res.status(404).json({ error: 'Código no válido o expirado' }); }
    const [[yaMiembro]] = await conn.execute(
      `SELECT 1 AS x FROM shared_budget_members WHERE shared_budget_id = ? AND firebase_uid = ?`,
      [inv.shared_budget_id, firebase_uid]
    );
    if (yaMiembro) { await conn.rollback(); conn.release(); return res.status(409).json({ error: 'Ya eres miembro de este presupuesto' }); }

    const [[budget]] = await conn.execute(`SELECT regla_reparto FROM shared_budgets WHERE id = ?`, [inv.shared_budget_id]);
    const rolNuevo = inv.rol_invitado || 'participante';
    const contribucionNuevo = budget.regla_reparto === 'pool_contribucion' ? (ingreso_declarado || null) : null;
    await conn.execute(
      `INSERT IGNORE INTO shared_budget_members (shared_budget_id, firebase_uid, display_name, rol, porcentaje, ingreso_declarado, contribucion_mensual)
       VALUES (?, ?, ?, ?, 0, ?, ?)`,
      [inv.shared_budget_id, firebase_uid, display_name || null, rolNuevo, ingreso_declarado || null, contribucionNuevo]
    );
    await conn.execute(`UPDATE shared_budgets SET estado = 'active' WHERE id = ?`, [inv.shared_budget_id]);

    // Recalcular splits de los gastos pendientes con el nuevo miembro (igual que en accept)
    try {
      const [allMembers] = await conn.execute(
        `SELECT firebase_uid, porcentaje, ingreso_declarado FROM shared_budget_members WHERE shared_budget_id = ?`,
        [inv.shared_budget_id]
      );
      const [gastosPendientes] = await conn.execute(
        `SELECT DISTINCT se.id, se.monto, se.regla_override
         FROM shared_expenses se
         WHERE se.shared_budget_id = ? AND se.es_personal = 0
           AND NOT EXISTS (SELECT 1 FROM shared_expense_splits s2 WHERE s2.expense_id = se.id AND s2.pagado = 1)`,
        [inv.shared_budget_id]
      );
      for (const gasto of gastosPendientes) {
        const reglaGasto = gasto.regla_override || budget.regla_reparto;
        const nuevosSplits = calcularSplits(parseFloat(gasto.monto), reglaGasto, allMembers);
        await conn.execute(`DELETE FROM shared_expense_splits WHERE expense_id = ?`, [gasto.id]);
        for (const sp of nuevosSplits) {
          await conn.execute(
            `INSERT INTO shared_expense_splits (expense_id, firebase_uid, monto_responsabilidad) VALUES (?, ?, ?)`,
            [gasto.id, sp.firebase_uid, sp.monto_responsabilidad]
          );
        }
      }
    } catch (_) { /* fire-and-forget */ }

    await conn.execute(
      `INSERT INTO shared_budget_activity_logs (shared_budget_id, actor_uid, accion, detalle)
       VALUES (?, ?, 'unirse_por_codigo', NULL)`,
      [inv.shared_budget_id, firebase_uid]
    );
    await conn.commit();
    conn.release();
    res.json({ message: 'Te uniste al presupuesto', shared_budget_id: inv.shared_budget_id });
  } catch (err) {
    await conn.rollback();
    conn.release();
    res.status(500).json({ error: err.message });
  }
});

// PATCH /shared-budgets/:id/members/:uid — Editar porcentaje/contribución de un miembro (admin o creador)
app.patch('/shared-budgets/:id/members/:uid', async (req, res) => {
  const { id, uid } = req.params;
  const { porcentaje, ingreso_declarado, contribucion_mensual, firebase_uid } = req.body;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    if (!(await _hasSharedRole(id, firebase_uid, 'admin'))) {
      return res.status(403).json({ error: 'Se requiere rol admin o creador' });
    }
    const [[budget]] = await db.execute(
      `SELECT regla_reparto FROM shared_budgets WHERE id = ?`, [id]
    );
    if (!budget) return res.status(404).json({ error: 'Presupuesto no encontrado' });

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

// PATCH /shared-budgets/:id/members/:uid/rol — Cambiar rol de un miembro (Sprint 8)
app.patch('/shared-budgets/:id/members/:uid/rol', async (req, res) => {
  const { id, uid } = req.params;
  const { rol, firebase_uid } = req.body;
  if (!firebase_uid || !rol) return res.status(400).json({ error: 'firebase_uid y rol requeridos' });
  const rolesAsignables = ['admin', 'participante', 'lectura'];
  if (!rolesAsignables.includes(rol)) return res.status(400).json({ error: 'Rol inválido. Valores: admin, participante, lectura' });
  try {
    const miRol = await _getSharedRole(id, firebase_uid);
    if (!miRol || (ROLE_LEVEL[miRol] || 0) < ROLE_LEVEL['admin']) {
      return res.status(403).json({ error: 'Se requiere rol admin o creador' });
    }
    // Admin no puede asignar rol admin a otro
    if (miRol === 'admin' && rol === 'admin') {
      return res.status(403).json({ error: 'Solo el creador puede asignar rol admin' });
    }
    // No se puede cambiar el rol del creador
    const rolTarget = await _getSharedRole(id, uid);
    if (rolTarget === 'creador') {
      return res.status(403).json({ error: 'No se puede cambiar el rol del creador' });
    }
    if (!rolTarget) return res.status(404).json({ error: 'Miembro no encontrado' });
    await db.execute(
      `UPDATE shared_budget_members SET rol = ? WHERE shared_budget_id = ? AND firebase_uid = ?`,
      [rol, id, uid]
    );
    await db.execute(
      `INSERT INTO shared_budget_activity_logs (shared_budget_id, actor_uid, accion, detalle)
       VALUES (?, ?, 'cambiar_rol', ?)`,
      [id, firebase_uid, JSON.stringify({ uid, rol_anterior: rolTarget, rol_nuevo: rol })]
    );
    res.json({ message: 'Rol actualizado', uid, rol });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// POST /shared-budgets/:id/expenses
app.post('/shared-budgets/:id/expenses', async (req, res) => {
  const { id } = req.params;
  const { descripcion, monto, pagado_por, regla_override, es_personal, firebase_uid_personal, fecha, firebase_uid, ya_pagado } = req.body;
  if (!descripcion || monto == null || !pagado_por || !fecha || !firebase_uid) return res.status(400).json({ error: 'Datos incompletos' });
  // lectura no puede agregar gastos
  if (!(await _hasSharedRole(id, firebase_uid, 'participante'))) {
    return res.status(403).json({ error: 'Sin permiso para agregar gastos (rol lectura)' });
  }
  const conn = await db.getConnection();
  await conn.beginTransaction();
  try {
    const [[budget]] = await conn.execute(
      `SELECT sb.regla_reparto FROM shared_budgets sb
       JOIN shared_budget_members m ON m.shared_budget_id = sb.id AND m.firebase_uid = ?
       WHERE sb.id = ? AND sb.estado NOT IN ('closed','paused')`,
      [firebase_uid, id]
    );
    if (!budget) { await conn.rollback(); conn.release(); return res.status(403).json({ error: 'No autorizado o presupuesto cerrado' }); }
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
    // Si ya_pagado=true: confirmar el split del pagador y registrar en su estado financiero
    if (ya_pagado && pagado_por) {
      try {
        await conn.execute(
          `UPDATE shared_expense_splits SET pagado=1 WHERE expense_id=? AND firebase_uid=?`,
          [expenseId, pagado_por]
        );
        const hoy = new Date();
        const anioHoy = hoy.getFullYear();
        const mesHoy = hoy.getMonth() + 1;
        const [[mesRow]] = await conn.execute(
          `SELECT id FROM meses_financieros WHERE firebase_uid=? AND anio=? AND mes=? AND estado='activo'`,
          [pagado_por, anioHoy, mesHoy]
        );
        if (mesRow) {
          // Calcular el monto del split del pagador
          const [[payerSplit]] = await conn.execute(
            `SELECT monto_responsabilidad FROM shared_expense_splits WHERE expense_id=? AND firebase_uid=?`,
            [expenseId, pagado_por]
          );
          const montoRegistro = es_personal ? parseFloat(monto) : (payerSplit ? Number(payerSplit.monto_responsabilidad) : parseFloat(monto));
          if (montoRegistro > 0) {
            await conn.execute(
              `INSERT INTO registros_gasto (firebase_uid, mes_id, anio, mes, tipo, categoria, nombre, monto, fecha, pagado, shared_expense_id)
               VALUES (?, ?, ?, ?, 'no_presupuestado', 'compartido', ?, ?, ?, 1, ?)`,
              [pagado_por, mesRow.id, anioHoy, mesHoy, descripcion, montoRegistro, fecha, expenseId]
            );
            _actualizarTotalesMes(mesRow.id, pagado_por).catch(() => {});
          }
        }
      } catch (_) { /* fire-and-forget */ }
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
              CASE WHEN my_split.pagado = 1 THEN 1 ELSE 0 END AS mi_parte_pagada,
              CASE WHEN other_split.pagado = 1 THEN 1 ELSE 0 END AS su_parte_pagada
       FROM shared_expenses se
       LEFT JOIN shared_expense_splits my_split
         ON my_split.expense_id = se.id AND my_split.firebase_uid = ?
       LEFT JOIN shared_expense_splits other_split
         ON other_split.expense_id = se.id AND other_split.firebase_uid != ?
       WHERE se.shared_budget_id = ?
       ORDER BY se.fecha DESC, se.created_at DESC`,
      [firebase_uid, firebase_uid, id]
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

    // Limpiar registros_gasto vinculados antes de borrar el gasto compartido
    try {
      const [afectados] = await db.execute(
        `SELECT DISTINCT firebase_uid, mes_id FROM registros_gasto WHERE shared_expense_id = ?`, [expenseId]
      );
      await db.execute(`DELETE FROM registros_gasto WHERE shared_expense_id = ?`, [expenseId]);
      for (const a of afectados) {
        _actualizarTotalesMes(a.mes_id, a.firebase_uid).catch(() => {});
      }
    } catch (_) { /* fire-and-forget */ }

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
      `SELECT ses.id, ses.monto_responsabilidad, ses.pagado,
              se.descripcion, se.fecha
       FROM shared_expense_splits ses
       JOIN shared_expenses se ON se.id = ses.expense_id
       JOIN shared_budget_members m ON m.shared_budget_id = se.shared_budget_id AND m.firebase_uid = ?
       WHERE ses.expense_id = ? AND ses.firebase_uid = ?`,
      [firebase_uid, expenseId, firebase_uid]
    );
    if (!split) return res.status(403).json({ error: 'No autorizado o split no encontrado' });
    // Evitar doble pago
    if (split.pagado === 1) return res.json({ message: 'Ya confirmado' });

    await db.execute(
      `UPDATE shared_expense_splits SET pagado = 1 WHERE expense_id = ? AND firebase_uid = ?`,
      [expenseId, firebase_uid]
    );

    // Integración financiera: registrar en estado financiero del confirmante
    try {
      const hoy = new Date();
      const anioHoy = hoy.getFullYear();
      const mesHoy = hoy.getMonth() + 1;
      const [[mesRow]] = await db.execute(
        `SELECT id FROM meses_financieros WHERE firebase_uid = ? AND anio = ? AND mes = ? AND estado = 'activo'`,
        [firebase_uid, anioHoy, mesHoy]
      );
      if (mesRow) {
        // Verificar que no exista ya un registro para este split (evitar duplicado)
        const [[existing]] = await db.execute(
          `SELECT id FROM registros_gasto WHERE firebase_uid = ? AND shared_expense_id = ?`,
          [firebase_uid, expenseId]
        );
        if (!existing) {
          await db.execute(
            `INSERT INTO registros_gasto (firebase_uid, mes_id, anio, mes, tipo, categoria, nombre, monto, fecha, pagado, shared_expense_id)
             VALUES (?, ?, ?, ?, 'no_presupuestado', 'compartido', ?, ?, ?, 1, ?)`,
            [firebase_uid, mesRow.id, anioHoy, mesHoy, split.descripcion,
             Number(split.monto_responsabilidad), split.fecha || hoy.toISOString().split('T')[0], expenseId]
          );
          _actualizarTotalesMes(mesRow.id, firebase_uid).catch(() => {});
        }
      }
    } catch (_) { /* fire-and-forget */ }

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

// Módulo Gustitos movido a routes/gustitos.js (montado al inicio de este archivo).

// =============================================================================
// ─── SPRINT 9: CATÁLOGO DE PRODUCTOS ─────────────────────────────────────────

async function _indexarProductosFactura(firebase_uid, invoiceId, items, merchantName, fechaCompra) {
  for (const item of items) {
    if (!item.descripcion || !item.precio_unitario) continue;
    const nombreNorm = item.descripcion.trim().toLowerCase().replace(/\s+/g, ' ');
    const precio = parseFloat(item.precio_unitario);
    const cantidad = parseFloat(item.cantidad) || 1;
    const fecha = fechaCompra || new Date().toISOString().split('T')[0];

    // Upsert en catálogo
    const [[existing]] = await db.execute(
      `SELECT id FROM productos_catalogo WHERE firebase_uid = ? AND nombre_normalizado = ?`,
      [firebase_uid, nombreNorm]
    );
    let productoId;
    if (existing) {
      productoId = existing.id;
      await db.execute(
        `UPDATE productos_catalogo SET
           veces_comprado = veces_comprado + 1,
           ultimo_precio = ?,
           ultima_compra = ?,
           merchant_name_habitual = COALESCE(?, merchant_name_habitual)
         WHERE id = ?`,
        [precio, fecha, merchantName || null, productoId]
      );
    } else {
      const [r] = await db.execute(
        `INSERT INTO productos_catalogo (firebase_uid, nombre, nombre_normalizado, merchant_name_habitual, ultimo_precio, ultima_compra)
         VALUES (?, ?, ?, ?, ?, ?)`,
        [firebase_uid, item.descripcion.trim(), nombreNorm, merchantName || null, precio, fecha]
      );
      productoId = r.insertId;
    }

    // Registrar en historial de precios
    await db.execute(
      `INSERT INTO historial_precios_producto (producto_id, firebase_uid, invoice_id, precio_unitario, cantidad, merchant_name, fecha_compra)
       VALUES (?, ?, ?, ?, ?, ?, ?)`,
      [productoId, firebase_uid, invoiceId, precio, cantidad, merchantName || null, fecha]
    );
  }
}

// GET /user/productos-catalogo
app.get('/user/productos-catalogo', async (req, res) => {
  const { firebase_uid, q } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    let sql = `SELECT pc.*,
      (SELECT h2.precio_unitario FROM historial_precios_producto h2
       WHERE h2.producto_id = pc.id ORDER BY h2.fecha_compra DESC, h2.id DESC LIMIT 1 OFFSET 1
      ) AS precio_anterior
     FROM productos_catalogo pc
     WHERE pc.firebase_uid = ? AND pc.activo = 1`;
    const params = [firebase_uid];
    if (q) { sql += ` AND pc.nombre LIKE ?`; params.push(`%${q}%`); }
    sql += ` ORDER BY pc.ultima_compra DESC, pc.veces_comprado DESC LIMIT ${250}`;
    const [rows] = await db.execute(sql, params);
    const result = rows.map(r => ({
      ...r,
      tendencia: (() => {
        const act = Number(r.ultimo_precio);
        const ant = r.precio_anterior != null ? Number(r.precio_anterior) : null;
        if (ant == null || act === ant) return 'igual';
        return act > ant ? 'sube' : 'baja';
      })(),
      pct_cambio: (() => {
        const act = Number(r.ultimo_precio);
        const ant = r.precio_anterior != null ? Number(r.precio_anterior) : null;
        if (!ant || ant === 0) return null;
        return Math.round(((act - ant) / ant) * 100 * 10) / 10;
      })(),
    }));
    res.json(result);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// GET /user/productos-catalogo/:id/historial
app.get('/user/productos-catalogo/:id/historial', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [[producto]] = await db.execute(
      `SELECT * FROM productos_catalogo WHERE id = ? AND firebase_uid = ?`, [id, firebase_uid]
    );
    if (!producto) return res.status(404).json({ error: 'Producto no encontrado' });
    const [historial] = await db.execute(
      `SELECT h.*, si.merchant_name AS factura_merchant, si.numero_factura
       FROM historial_precios_producto h
       LEFT JOIN scanned_invoices si ON si.id = h.invoice_id
       WHERE h.producto_id = ? AND h.firebase_uid = ?
       ORDER BY h.fecha_compra DESC, h.id DESC LIMIT ${100}`,
      [id, firebase_uid]
    );
    res.json({ producto, historial });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// PATCH /user/productos-catalogo/:id — actualizar categoría del producto
app.patch('/user/productos-catalogo/:id', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid, categoria } = req.body;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [[p]] = await db.execute(
      `SELECT id FROM productos_catalogo WHERE id = ? AND firebase_uid = ?`, [id, firebase_uid]
    );
    if (!p) return res.status(404).json({ error: 'Producto no encontrado' });
    await db.execute(`UPDATE productos_catalogo SET categoria = ? WHERE id = ?`, [categoria ?? null, id]);
    res.json({ message: 'Categoría actualizada' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// GET /user/settings — configuración del usuario
app.get('/user/settings', async (req, res) => {
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [[row]] = await db.execute(
      `SELECT modo_negocio, periodo_preferido, presupuesto_gustitos FROM user_settings WHERE firebase_uid = ?`, [firebase_uid]
    );
    res.json({
      modo_negocio:         row ? Number(row.modo_negocio) : 0,
      periodo_preferido:    row?.periodo_preferido || 'mensual',
      presupuesto_gustitos: row ? Number(row.presupuesto_gustitos) : 0,
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// PATCH /user/settings — actualizar configuración del usuario
app.patch('/user/settings', async (req, res) => {
  const { firebase_uid, modo_negocio, periodo_preferido, presupuesto_gustitos } = req.body;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    // Asegura que existe el registro
    await db.execute(
      `INSERT IGNORE INTO user_settings (firebase_uid) VALUES (?)`, [firebase_uid]);
    if (modo_negocio !== undefined)
      await db.execute(`UPDATE user_settings SET modo_negocio=? WHERE firebase_uid=?`,
        [modo_negocio ? 1 : 0, firebase_uid]);
    if (periodo_preferido)
      await db.execute(`UPDATE user_settings SET periodo_preferido=? WHERE firebase_uid=?`,
        [periodo_preferido, firebase_uid]);
    if (presupuesto_gustitos !== undefined)
      await db.execute(`UPDATE user_settings SET presupuesto_gustitos=? WHERE firebase_uid=?`,
        [parseFloat(Number(presupuesto_gustitos).toFixed(2)) || 0, firebase_uid]);
    res.json({ ok: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// GET /user/gastos-para-vincular — lista de gastos fijos + variables disponibles para vincular a una factura
app.get('/user/gastos-para-vincular', async (req, res) => {
  const { firebase_uid, anio, mes } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  const anioN = parseInt(anio) || new Date().getFullYear();
  const mesN  = parseInt(mes)  || (new Date().getMonth() + 1);
  try {
    const [fijos] = await db.execute(
      `SELECT ugf.id, ugf.descripcion AS nombre, ugf.monto_mensual AS monto_presupuestado,
              'fijo' AS tipo,
              rg.id AS registro_id, rg.monto AS monto_real, rg.pagado
       FROM user_gastos_fijos ugf
       LEFT JOIN registros_gasto rg
         ON rg.origen_fijo_id = ugf.id AND rg.firebase_uid = ? AND rg.anio = ? AND rg.mes = ?
       WHERE ugf.firebase_uid = ? AND ugf.activo = 1
       ORDER BY ugf.descripcion`,
      [firebase_uid, anioN, mesN, firebase_uid]
    );
    const [variables] = await db.execute(
      `SELECT gvb.id, gvb.nombre, gvb.monto_estimado AS monto_presupuestado,
              'variable' AS tipo,
              rg.id AS registro_id, rg.monto AS monto_real, rg.pagado
       FROM gastos_variables_base gvb
       LEFT JOIN registros_gasto rg
         ON rg.origen_variable_id = gvb.id AND rg.firebase_uid = ? AND rg.anio = ? AND rg.mes = ?
       WHERE gvb.firebase_uid = ? AND gvb.activo = 1
       ORDER BY gvb.nombre`,
      [firebase_uid, anioN, mesN, firebase_uid]
    );
    res.json({ fijos, variables });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// POST /invoice-scanner/:id/registrar-en-mes — conecta factura con estado financiero
app.post('/invoice-scanner/:id/registrar-en-mes', async (req, res) => {
  const { id } = req.params;
  const {
    firebase_uid,
    categoria = 'Compras',
    nombre_gasto,
    origen_tipo,
    origen_id,
    tipo: tipoParam,
    fecha_override,
  } = req.body;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [[invoice]] = await db.execute(
      `SELECT * FROM scanned_invoices WHERE id = ? AND firebase_uid = ?`, [id, firebase_uid]
    );
    if (!invoice) return res.status(404).json({ error: 'Factura no encontrada' });
    if (!invoice.total_amount) return res.status(400).json({ error: 'La factura no tiene monto total' });

    // Verificar que no esté ya registrada
    const [[existing]] = await db.execute(
      `SELECT id FROM registros_gasto WHERE firebase_uid = ? AND scanned_invoice_id = ?`,
      [firebase_uid, id]
    );
    if (existing) return res.status(409).json({ error: 'Esta factura ya fue registrada en tu estado financiero' });

    const hoy = new Date();
    const anioHoy = hoy.getFullYear();
    const mesHoy  = hoy.getMonth() + 1;
    const [[mesRow]] = await db.execute(
      `SELECT id FROM meses_financieros WHERE firebase_uid = ? AND anio = ? AND mes = ? AND estado = 'activo'`,
      [firebase_uid, anioHoy, mesHoy]
    );
    if (!mesRow) return res.status(400).json({ error: 'No tienes un mes activo. Genera tu estado financiero anual primero.' });

    const montoReal = Number(invoice.total_amount);
    const fechaGasto = fecha_override || invoice.invoice_date || hoy.toISOString().split('T')[0];
    let registroId;

    if (origen_tipo && origen_id) {
      // ── VINCULAR A GASTO EXISTENTE ─────────────────────────────────────────
      const esFijo = origen_tipo === 'fijo';
      const origenCol = esFijo ? 'origen_fijo_id' : 'origen_variable_id';

      // Obtener nombre del gasto para el registro
      const tablaNombre = esFijo ? 'user_gastos_fijos' : 'gastos_variables_base';
      const campoNombre = 'descripcion';
      const [[gastoOrigen]] = await db.execute(
        `SELECT ${campoNombre} AS nombre, ${esFijo ? 'monto_mensual' : 'monto_estimado'} AS monto_presupuestado
         FROM ${tablaNombre} WHERE id = ? AND firebase_uid = ?`,
        [origen_id, firebase_uid]
      );
      if (!gastoOrigen) return res.status(404).json({ error: 'Gasto origen no encontrado' });

      // Buscar si ya existe un registros_gasto para ese origen en este mes
      const [[registroExistente]] = await db.execute(
        `SELECT id FROM registros_gasto WHERE firebase_uid = ? AND ${origenCol} = ? AND anio = ? AND mes = ?`,
        [firebase_uid, origen_id, anioHoy, mesHoy]
      );

      if (registroExistente) {
        // Actualizar el registro existente con el monto real de la factura
        await db.execute(
          `UPDATE registros_gasto SET monto = ?, pagado = 1, scanned_invoice_id = ?, fecha = ?
           WHERE id = ?`,
          [montoReal, id, fechaGasto, registroExistente.id]
        );
        registroId = registroExistente.id;
      } else {
        // Crear nuevo registro vinculado al gasto origen
        const [r] = await db.execute(
          `INSERT INTO registros_gasto
             (firebase_uid, mes_id, anio, mes, tipo, categoria, nombre, monto, fecha, pagado, ${origenCol}, scanned_invoice_id)
           VALUES (?, ?, ?, ?, ?, 'otro', ?, ?, ?, 1, ?, ?)`,
          [firebase_uid, mesRow.id, anioHoy, mesHoy, esFijo ? 'fijo' : 'variable',
           gastoOrigen.nombre, montoReal, fechaGasto, origen_id, id]
        );
        registroId = r.insertId;
      }
    } else {
      // ── NUEVO GASTO NO PRESUPUESTADO (o tipo elegido por el usuario) ───────
      const tipoFinal = ['fijo', 'variable', 'no_presupuestado'].includes(tipoParam) ? tipoParam : 'no_presupuestado';
      const nombre = nombre_gasto || `${invoice.merchant_name || 'Factura QR'} #${invoice.numero_factura || id}`;
      const [r] = await db.execute(
        `INSERT INTO registros_gasto (firebase_uid, mes_id, anio, mes, tipo, categoria, nombre, monto, fecha, pagado, scanned_invoice_id)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?)`,
        [firebase_uid, mesRow.id, anioHoy, mesHoy, tipoFinal, categoria, nombre, montoReal, fechaGasto, id]
      );
      registroId = r.insertId;
    }

    _actualizarTotalesMes(mesRow.id, firebase_uid).catch(() => {});
    _logInfo('/invoice-scanner/registrar-en-mes', `Factura ${id} registrada en mes ${mesHoy}/${anioHoy}`, firebase_uid);
    res.status(201).json({ id: registroId, monto: montoReal, vinculado: !!(origen_tipo && origen_id) });
  } catch (err) {
    _logError('/invoice-scanner/registrar-en-mes', err, firebase_uid);
    res.status(500).json({ error: err.message });
  }
});

// GET /user/analisis-vs-presupuesto — compara presupuestado vs real por gasto con recomendaciones
app.get('/user/analisis-vs-presupuesto', async (req, res) => {
  const { firebase_uid, meses = 6 } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  const nMeses = Math.min(parseInt(meses) || 6, 12);
  try {
    // Gastos fijos con historial de registros reales (últimos N meses)
    const [fijos] = await db.execute(
      `SELECT ugf.id, ugf.descripcion AS nombre, ugf.monto_mensual AS presupuestado,
              AVG(rg.monto) AS promedio_real,
              COUNT(rg.id) AS meses_con_registro,
              MIN(rg.monto) AS minimo_real,
              MAX(rg.monto) AS maximo_real,
              'fijo' AS tipo
       FROM user_gastos_fijos ugf
       LEFT JOIN registros_gasto rg
         ON rg.origen_fijo_id = ugf.id
         AND rg.firebase_uid = ugf.firebase_uid
         AND rg.pagado = 1
         AND (rg.anio * 12 + rg.mes) > ((YEAR(NOW()) * 12 + MONTH(NOW())) - ?)
       WHERE ugf.firebase_uid = ? AND ugf.activo = 1 AND ugf.monto_mensual > 0
       GROUP BY ugf.id, ugf.descripcion, ugf.monto_mensual
       HAVING meses_con_registro >= 2
       ORDER BY ABS(AVG(rg.monto) - ugf.monto_mensual) DESC`,
      [nMeses, firebase_uid]
    );

    const resultado = fijos.map(g => {
      const presup = Number(g.presupuestado);
      const promReal = Number(g.promedio_real);
      const mesesData = Number(g.meses_con_registro);
      const diferencia = presup - promReal; // positivo = gastas menos de lo presupuestado
      const pctDif = presup > 0 ? (diferencia / presup * 100) : 0;

      let recomendacion = null;
      let presupuestoSugerido = null;
      let ahorroSugerido = null;

      if (mesesData >= 3) {
        if (pctDif >= 10) {
          // Gastas consistentemente menos — recomienda bajar el presupuesto
          presupuestoSugerido = Math.ceil(promReal * 1.05 / 5) * 5; // +5% buffer, redondeado a $5
          ahorroSugerido = Math.round((presup - presupuestoSugerido) * 100) / 100;
          recomendacion = {
            tipo: 'reducir',
            mensaje: `Llevas ${mesesData} meses presupuestando $${presup.toFixed(2)} en "${g.nombre}" pero gastas en promedio $${promReal.toFixed(2)}. Te recomiendo bajar a $${presupuestoSugerido.toFixed(2)} y usar los $${ahorroSugerido.toFixed(2)} restantes para ahorro.`,
            presupuesto_actual: presup,
            presupuesto_sugerido: presupuestoSugerido,
            ahorro_mensual_posible: ahorroSugerido,
          };
        } else if (pctDif <= -10) {
          // Gastas consistentemente más — recomienda subir el presupuesto
          presupuestoSugerido = Math.ceil(promReal * 1.1 / 5) * 5;
          recomendacion = {
            tipo: 'aumentar',
            mensaje: `Llevas ${mesesData} meses excediendo tu presupuesto de "$${g.nombre}". Tu gasto promedio es $${promReal.toFixed(2)}, te recomiendo subir a $${presupuestoSugerido.toFixed(2)}.`,
            presupuesto_actual: presup,
            presupuesto_sugerido: presupuestoSugerido,
            ahorro_mensual_posible: null,
          };
        }
      }

      return {
        id: g.id,
        nombre: g.nombre,
        tipo: 'fijo',
        presupuestado: presup,
        promedio_real: Math.round(promReal * 100) / 100,
        minimo_real: Number(g.minimo_real),
        maximo_real: Number(g.maximo_real),
        meses_con_datos: mesesData,
        diferencia_promedio: Math.round(diferencia * 100) / 100,
        pct_diferencia: Math.round(pctDif * 10) / 10,
        recomendacion,
      };
    });

    res.json(resultado.filter(r => r.meses_con_datos >= 1));
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

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
      // Sprint 9: auto-indexar en catálogo de productos (fire-and-forget)
      _indexarProductosFactura(firebase_uid, invoiceId, dgiItems, dgiData?.merchant_name, dgiData?.invoice_date).catch(() => {});
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

// GET /invoice-scanner/invoices/pending-count — M2: facturas sin asignar (badge)
app.get('/invoice-scanner/invoices/pending-count', async (req, res) => {
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [[row]] = await db.query(
      `SELECT COUNT(*) AS pendientes FROM scanned_invoices
       WHERE firebase_uid = ? AND (status IS NULL OR status != 'assigned')`,
      [firebase_uid]);
    res.json({ pendientes: Number(row.pendientes) || 0 });
  } catch (e) { res.status(500).json({ error: e.message }); }
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

    // Sprint 9: ¿ya fue registrada en meses_financieros?
    const [[regRow]] = await db.query(
      `SELECT id FROM registros_gasto WHERE firebase_uid = ? AND scanned_invoice_id = ? LIMIT 1`,
      [firebase_uid, id]
    );

    res.json({
      ...invoice,
      items,
      assignments,
      total_assigned,
      remaining,
      is_overpaid: remaining < 0,
      ya_registrado_en_mes: !!regRow,
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

// Módulo Sobres movido a routes/sobres.js (montado al inicio de este archivo).

// =============================================================================
// Módulo Gastos Globales movido a routes/gastos_globales.js (montado al inicio de este archivo).
// Los 2 endpoints /shared-budgets/* debajo pertenecen a Presupuestos Compartidos, no a Gastos
// Globales (a pesar de estar bajo este header) — quedan en server.js hasta que se extraiga esa
// tanda completa.

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
// Módulo Gastos Variables Base movido a routes/gastos_variables_base.js (montado al inicio de
// este archivo). Los endpoints de comparativa/patrimonio/objetivos/consejero-ia/subcategorias
// debajo NO pertenecen a este módulo (a pesar de estar bajo el mismo header histórico) — quedan
// en server.js como dominios propios para una tanda futura.

// GET /user/comparativa?firebase_uid=&anio=&mes=
// Tendencia 12 meses + comparativa vs mes anterior
app.get('/user/comparativa', async (req, res) => {
  const { firebase_uid, anio, mes } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  const year  = Number(anio) || new Date().getFullYear();
  const month = Number(mes)  || (new Date().getMonth() + 1);
  const MESES_L = ['','Ene','Feb','Mar','Abr','May','Jun','Jul','Ago','Sep','Oct','Nov','Dic'];
  try {
    const [meses12] = await db.execute(
      `SELECT mes, ingreso_estimado, fijos_estimados, variables_estimados, remanente_estimado,
              fijos_reales, variables_reales, no_presupuestados_reales, remanente_real, estado
       FROM meses_financieros WHERE firebase_uid = ? AND anio = ? ORDER BY mes ASC`,
      [firebase_uid, year]
    );
    const prevMonth = month === 1 ? 12 : month - 1;
    const prevYear  = month === 1 ? year - 1 : year;
    const [[mesAnterior]] = await db.execute(
      `SELECT mes, fijos_reales, variables_reales, no_presupuestados_reales, remanente_real,
              fijos_estimados, variables_estimados, remanente_estimado
       FROM meses_financieros WHERE firebase_uid = ? AND anio = ? AND mes = ?`,
      [firebase_uid, prevYear, prevMonth]
    );
    const actual = meses12.find(m => m.mes === month);
    res.json({
      tendencia: meses12.map(m => ({
        mes: m.mes, label: MESES_L[m.mes],
        remanente_est:  parseFloat(Number(m.remanente_estimado).toFixed(2)),
        remanente_real: Number(m.remanente_real) ? parseFloat(Number(m.remanente_real).toFixed(2)) : null,
        total_gasto:    parseFloat((Number(m.fijos_reales) + Number(m.variables_reales) + Number(m.no_presupuestados_reales)).toFixed(2)),
        es_activo: m.estado === 'activo',
      })),
      actual: actual ? {
        label: MESES_L[month],
        fijos:     parseFloat((Number(actual.fijos_reales)     || Number(actual.fijos_estimados)).toFixed(2)),
        variables: parseFloat((Number(actual.variables_reales) || Number(actual.variables_estimados)).toFixed(2)),
        remanente: parseFloat((Number(actual.remanente_real)   || Number(actual.remanente_estimado)).toFixed(2)),
        es_estimado: !Number(actual.remanente_real),
      } : null,
      anterior: mesAnterior ? {
        label: MESES_L[prevMonth],
        fijos:     parseFloat((Number(mesAnterior.fijos_reales)     || Number(mesAnterior.fijos_estimados)).toFixed(2)),
        variables: parseFloat((Number(mesAnterior.variables_reales) || Number(mesAnterior.variables_estimados)).toFixed(2)),
        remanente: parseFloat((Number(mesAnterior.remanente_real)   || Number(mesAnterior.remanente_estimado)).toFixed(2)),
      } : null,
    });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// ── PATRIMONIO NETO ──────────────────────────────────────────────────────────
app.get('/user/patrimonio', async (req, res) => {
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [activos] = await db.execute(
      `SELECT * FROM activos WHERE firebase_uid = ? AND activo = 1 ORDER BY valor DESC`, [firebase_uid]);
    const [deudas] = await db.execute(
      `SELECT nombre, tipo, monto_pendiente, monto_total FROM deudas WHERE firebase_uid = ? AND activa = 1`,
      [firebase_uid]);
    const totalActivos = activos.reduce((s, a) => s + Number(a.valor), 0);
    const totalPasivos = deudas.reduce((s, d) => s + (Number(d.monto_pendiente) || Number(d.monto_total)), 0);
    res.json({
      activos, deudas,
      total_activos:   parseFloat(totalActivos.toFixed(2)),
      total_pasivos:   parseFloat(totalPasivos.toFixed(2)),
      patrimonio_neto: parseFloat((totalActivos - totalPasivos).toFixed(2)),
    });
  } catch (e) { res.status(500).json({ error: e.message }); }
});
app.post('/user/activos', async (req, res) => {
  const { firebase_uid, nombre, tipo, valor, descripcion } = req.body;
  if (!firebase_uid || !nombre || valor === undefined) return res.status(400).json({ error: 'firebase_uid, nombre y valor requeridos' });
  try {
    const [r] = await db.execute(
      `INSERT INTO activos (firebase_uid, nombre, tipo, valor, descripcion) VALUES (?, ?, ?, ?, ?)`,
      [firebase_uid, nombre, tipo || 'otro', Number(valor), descripcion || null]);
    res.status(201).json({ id: r.insertId });
  } catch (e) { res.status(500).json({ error: e.message }); }
});
app.put('/user/activos/:id', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid, nombre, tipo, valor, descripcion } = req.body;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    await db.execute(`UPDATE activos SET nombre=?, tipo=?, valor=?, descripcion=? WHERE id=? AND firebase_uid=?`,
      [nombre, tipo, Number(valor), descripcion, id, firebase_uid]);
    res.json({ success: true });
  } catch (e) { res.status(500).json({ error: e.message }); }
});
app.delete('/user/activos/:id', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    await db.execute(`UPDATE activos SET activo=0 WHERE id=? AND firebase_uid=?`, [id, firebase_uid]);
    res.json({ success: true });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// ── OBJETIVOS FINANCIEROS ─────────────────────────────────────────────────────
app.get('/user/objetivos', async (req, res) => {
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [rows] = await db.execute(
      `SELECT *, DATEDIFF(fecha_limite, CURDATE()) AS dias_restantes FROM objetivos_financieros
       WHERE firebase_uid = ? AND activo = 1 ORDER BY fecha_limite ASC`, [firebase_uid]);
    res.json(rows.map(o => {
      const diasR  = Math.max(0, Number(o.dias_restantes) || 365);
      const mesesR = Math.max(1, Math.ceil(diasR / 30));
      const falta  = Math.max(0, Number(o.monto_meta) - Number(o.monto_actual));
      return {
        ...o,
        monto_meta:      parseFloat(Number(o.monto_meta).toFixed(2)),
        monto_actual:    parseFloat(Number(o.monto_actual).toFixed(2)),
        falta:           parseFloat(falta.toFixed(2)),
        pct_avance:      Number(o.monto_meta) > 0 ? parseFloat((Number(o.monto_actual)/Number(o.monto_meta)*100).toFixed(1)) : 0,
        cuota_mensual:   parseFloat((falta / mesesR).toFixed(2)),
        dias_restantes:  diasR, meses_restantes: mesesR,
      };
    }));
  } catch (e) { res.status(500).json({ error: e.message }); }
});
app.post('/user/objetivos', async (req, res) => {
  const { firebase_uid, nombre, descripcion, monto_meta, fecha_limite, fecha_objetivo, tipo } = req.body;
  if (!firebase_uid || !nombre || !monto_meta) return res.status(400).json({ error: 'firebase_uid, nombre y monto_meta requeridos' });
  const fechaFinal = fecha_limite || fecha_objetivo || null;
  try {
    const [r] = await db.execute(
      `INSERT INTO objetivos_financieros (firebase_uid, nombre, descripcion, monto_meta, fecha_limite, tipo)
       VALUES (?, ?, ?, ?, ?, ?)`,
      [firebase_uid, nombre, descripcion || null, monto_meta, fechaFinal, tipo || 'otro']);
    res.status(201).json({ id: r.insertId });
  } catch (e) { res.status(500).json({ error: e.message }); }
});
app.patch('/user/objetivos/:id/abonar', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid, monto } = req.body;
  if (!firebase_uid || !monto) return res.status(400).json({ error: 'firebase_uid y monto requeridos' });
  try {
    await db.execute(
      `UPDATE objetivos_financieros SET monto_actual = monto_actual + ? WHERE id = ? AND firebase_uid = ?`,
      [Number(monto), id, firebase_uid]);
    res.json({ success: true });
  } catch (e) { res.status(500).json({ error: e.message }); }
});
app.delete('/user/objetivos/:id', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    await db.execute(`UPDATE objetivos_financieros SET activo=0 WHERE id=? AND firebase_uid=?`, [id, firebase_uid]);
    res.json({ success: true });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// ── CONSEJERO IA (Claude Haiku) ───────────────────────────────────────────────
// GET /user/consejero-ia?firebase_uid=&anio=&mes=
// Requiere ANTHROPIC_API_KEY en variables de entorno de Render.
app.get('/user/consejero-ia', async (req, res) => {
  const { firebase_uid, anio, mes } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) return res.json({ disponible: false, razon: 'sin_api_key' });
  const year  = Number(anio) || new Date().getFullYear();
  const month = Number(mes)  || (new Date().getMonth() + 1);
  const MESES = ['','enero','febrero','marzo','abril','mayo','junio',
                 'julio','agosto','septiembre','octubre','noviembre','diciembre'];
  try {
    const [[income]] = await db.execute(
      `SELECT ingreso_neto_mensual FROM user_income WHERE firebase_uid = ?`, [firebase_uid]);
    if (!income) return res.json({ disponible: false, razon: 'sin_perfil' });
    const [gastosFijos] = await db.execute(
      `SELECT descripcion AS nombre, monto_mensual FROM user_gastos_fijos WHERE firebase_uid = ? AND activo = 1`, [firebase_uid]);
    const [deudas] = await db.execute(
      `SELECT nombre, tasa_interes, monto_pendiente, monto_total, pago_minimo, cuota_fija, num_cuotas_total, num_pagos_realizados
       FROM deudas WHERE firebase_uid = ? AND activa = 1 ORDER BY tasa_interes DESC`, [firebase_uid]);
    // Deudas SIN gasto_fijo vinculado — para no doblar-contar
    const [deudasIndep] = await db.execute(
      `SELECT d.pago_minimo, d.cuota_fija FROM deudas d
       LEFT JOIN user_gastos_fijos ugf ON ugf.deuda_id = d.id
       WHERE d.firebase_uid = ? AND d.activa = 1 AND ugf.id IS NULL`, [firebase_uid]);
    const [variablesBase] = await db.execute(
      `SELECT nombre, categoria, monto_estimado FROM gastos_variables_base WHERE firebase_uid = ? AND activo = 1`, [firebase_uid]);
    const [[mesRow]] = await db.execute(
      `SELECT fijos_reales, variables_reales, remanente_real, remanente_estimado FROM meses_financieros
       WHERE firebase_uid = ? AND anio = ? AND mes = ?`, [firebase_uid, year, month]);

    const ingresoNeto     = Number(income.ingreso_neto_mensual);
    const totalFijosBase  = gastosFijos.reduce((s, g) => s + Number(g.monto_mensual), 0);
    const totalDeudaIndep = deudasIndep.reduce((s, d) => s + (Number(d.pago_minimo) || Number(d.cuota_fija) || 0), 0);
    const totalFijos      = totalFijosBase + totalDeudaIndep; // mismo cálculo que el card
    const totalVar        = variablesBase.reduce((s, v) => s + Number(v.monto_estimado), 0);
    const totalDeudas     = deudas.reduce((s, d) => s + (Number(d.pago_minimo) || Number(d.cuota_fija) || 0), 0);
    const remanente       = ingresoNeto - totalFijos - totalVar;

    const prompt = `Eres un asesor financiero personal experto y directo, especializado en Panamá. No uses lenguaje corporativo — habla como un amigo que sabe de finanzas.

SITUACIÓN FINANCIERA — ${MESES[month].toUpperCase()} ${year}:
Ingreso neto: $${ingresoNeto.toFixed(2)}/mes
Gastos fijos: $${totalFijosBase.toFixed(2)}: ${gastosFijos.slice(0,5).map(g=>`${g.nombre}:$${Number(g.monto_mensual).toFixed(0)}`).join(', ')}
Cuotas de deudas (mensuales): $${totalDeudaIndep.toFixed(2)}
Variables estimadas: $${totalVar.toFixed(2)}
REMANENTE REAL (lo que queda después de TODO): $${remanente.toFixed(2)}/mes — este es el único dinero disponible libre
${mesRow && Number(mesRow.fijos_reales) > 0 ? `Gastos reales este mes: fijos $${Number(mesRow.fijos_reales).toFixed(2)}, variables $${Number(mesRow.variables_reales).toFixed(2)}\n` : ''}Deudas activas (${deudas.length}, cuotas ya incluidas arriba): ${deudas.length > 0 ? deudas.slice(0,4).map(d=>`${d.nombre} ${d.tasa_interes}% TEA saldo $${Number(d.monto_pendiente||d.monto_total).toFixed(0)} cuota $${Number(d.pago_minimo||d.cuota_fija||0).toFixed(0)}/mes`).join(' | ') : 'ninguna'}

Da tu análisis en máximo 180 palabras:
1. Una frase de diagnóstico honesto (bueno o malo, con número clave)
2. El problema financiero #1 con acción concreta y monto exacto
3. Dos recomendaciones adicionales priorizadas
4. Una motivación breve y genuina

Sin bullets, párrafos cortos, español panameño natural.`;

    const https = require('https');
    const reqBody = JSON.stringify({ model: 'claude-haiku-4-5-20251001', max_tokens: 350,
      messages: [{ role: 'user', content: prompt }] });

    let claudeStatus = 0;
    const data = await new Promise((resolve, reject) => {
      const req = https.request({
        hostname: 'api.anthropic.com', path: '/v1/messages', method: 'POST',
        headers: { 'Content-Type': 'application/json',
          'Content-Length': Buffer.byteLength(reqBody),
          'x-api-key': apiKey, 'anthropic-version': '2023-06-01' },
      }, (httpRes) => {
        claudeStatus = httpRes.statusCode;
        let raw = '';
        httpRes.on('data', chunk => raw += chunk);
        httpRes.on('end', () => {
          try { resolve(JSON.parse(raw)); }
          catch (e) { reject(new Error('parse: ' + raw.slice(0, 200))); }
        });
      });
      req.on('error', reject);
      req.write(reqBody);
      req.end();
    });

    // Si Claude retornó error HTTP
    if (claudeStatus >= 400) {
      const detalle = data.error?.message || `HTTP ${claudeStatus}`;
      console.error(`[consejero-ia] Claude error ${claudeStatus}: ${detalle}`);
      return res.json({ disponible: false, razon: 'error_api', detalle });
    }

    const texto = data.content?.[0]?.text || '';
    if (!texto) {
      return res.json({ disponible: false, razon: 'error_api', detalle: 'respuesta vacía de Claude' });
    }

    const ahora = new Date();
    const hora  = `${ahora.getHours().toString().padStart(2,'0')}:${ahora.getMinutes().toString().padStart(2,'0')}`;
    res.json({
      disponible: true,
      analisis: texto,
      generado_a: hora,
      modelo: 'claude-haiku',
      tokens_usados: data.usage?.output_tokens || 0,
      mes: month, mes_label: MESES[month], anio: year,
    });
  } catch (e) {
    console.error('[consejero-ia] error:', e.message);
    res.json({ disponible: false, razon: 'error_api', detalle: e.message });
  }
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
    const totalIngReal     = meses.reduce((s, m) => s + (Number(m.ingreso_real) || Number(m.ingreso_estimado)), 0);
    // Cantidad de meses con datos reales (para calcular promedio mensual real correcto)
    const mesesConFijosReales = Math.max(1, meses.filter(m => Number(m.fijos_reales) > 0).length);
    const mesesConVarsReales  = Math.max(1, meses.filter(m => Number(m.variables_reales) > 0).length);
    const mesesConIngReal     = Math.max(1, meses.filter(m => Number(m.ingreso_real) > 0).length);
    const mesesConNoPres      = Math.max(1, meses.filter(m => Number(m.no_presupuestados_reales) > 0).length);

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
        meses_con_fijos_reales:   mesesConFijosReales,
        meses_con_vars_reales:    mesesConVarsReales,
        meses_con_ing_real:       mesesConIngReal,
        meses_con_no_pres:        mesesConNoPres,
      },
      meses: meses.map(m => ({
        ...m,
        label: MESES_LABEL[m.mes],
        remanente_real: parseFloat((
          (Number(m.ingreso_real) || Number(m.ingreso_estimado))
          - Number(m.fijos_reales)
          - Number(m.variables_reales)
          - Number(m.no_presupuestados_reales)
        ).toFixed(2)),
        total_registrado: parseFloat(Number(m.total_registrado).toFixed(2)),
      })),
    });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// GET /user/consejero?firebase_uid=&anio=&mes=
// Motor de análisis financiero: score de salud, insights y enfoque del mes.
app.get('/user/consejero', async (req, res) => {
  const { firebase_uid, anio, mes } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  const year  = Number(anio) || new Date().getFullYear();
  const month = Number(mes)  || (new Date().getMonth() + 1);
  const MESES = ['','enero','febrero','marzo','abril','mayo','junio',
                 'julio','agosto','septiembre','octubre','noviembre','diciembre'];
  try {
    const [[income]] = await db.execute(
      `SELECT ingreso_neto_mensual FROM user_income WHERE firebase_uid = ?`, [firebase_uid]);
    if (!income) return res.json({ sin_perfil: true });

    const ingresoNeto = Number(income.ingreso_neto_mensual);

    const [gastosFijos] = await db.execute(
      `SELECT * FROM user_gastos_fijos WHERE firebase_uid = ? AND activo = 1`, [firebase_uid]);
    const [deudas] = await db.execute(
      `SELECT * FROM deudas WHERE firebase_uid = ? AND activa = 1 ORDER BY tasa_interes DESC`, [firebase_uid]);
    // Deudas sin gasto_fijo vinculado — para no doblar-contar
    const [deudasIndep] = await db.execute(
      `SELECT d.* FROM deudas d
       LEFT JOIN user_gastos_fijos ugf ON ugf.deuda_id = d.id
       WHERE d.firebase_uid = ? AND d.activa = 1 AND ugf.id IS NULL`, [firebase_uid]);
    const [variablesBase] = await db.execute(
      `SELECT * FROM gastos_variables_base WHERE firebase_uid = ? AND activo = 1`, [firebase_uid]);
    const [[mesRow]] = await db.execute(
      `SELECT * FROM meses_financieros WHERE firebase_uid = ? AND anio = ? AND mes = ?`,
      [firebase_uid, year, month]);
    const [registros] = mesRow ? await db.execute(
      `SELECT tipo, categoria, SUM(monto) AS total FROM registros_gasto
       WHERE firebase_uid = ? AND mes_id = ? GROUP BY tipo, categoria`,
      [firebase_uid, mesRow.id]) : [[]];

    // ── Métricas base — misma lógica que _recalcularEstimadosAnio ────────────
    const totalFijosBase    = gastosFijos.reduce((s, g) => s + Number(g.monto_mensual), 0);
    const totalDeudaIndep   = deudasIndep.reduce((s, d) => s + (Number(d.pago_minimo) || Number(d.cuota_fija) || 0), 0);
    const totalFijosMensual = totalFijosBase + totalDeudaIndep; // coincide con el card
    const totalPagosDeuda   = deudas.reduce((s, d) => s + (Number(d.pago_minimo) || Number(d.cuota_fija) || 0), 0);
    const totalVarAnual     = variablesBase.reduce((s, g) => {
      const arr = g.aplica_meses ? (typeof g.aplica_meses === 'string' ? JSON.parse(g.aplica_meses) : g.aplica_meses) : [1,2,3,4,5,6,7,8,9,10,11,12];
      return s + _montoMensual(g) * arr.length;
    }, 0);
    const totalVarMensual = totalVarAnual / 12;
    const remanente         = ingresoNeto - totalFijosMensual - totalVarMensual; // coincide con el card
    const pctFijos          = ingresoNeto > 0 ? totalFijosMensual / ingresoNeto : 0;
    const pctDeuda          = ingresoNeto > 0 ? totalPagosDeuda / ingresoNeto : 0;
    const tasaAhorro        = ingresoNeto > 0 ? Math.max(0, remanente) / ingresoNeto : 0;

    const totalRealFijos = registros.filter(r => r.tipo === 'fijo').reduce((s, r) => s + Number(r.total), 0);
    const tieneRegistros = registros.length > 0;

    // ── Score (0-100) ────────────────────────────────────────────────────────
    const ptsDTI     = pctDeuda < 0.15 ? 25 : pctDeuda < 0.28 ? 20 : pctDeuda < 0.36 ? 12 : pctDeuda < 0.5 ? 5 : 0;
    const ptsAhorro  = tasaAhorro > 0.20 ? 25 : tasaAhorro > 0.15 ? 20 : tasaAhorro > 0.10 ? 15 : tasaAhorro > 0.05 ? 8 : tasaAhorro > 0 ? 3 : 0;
    const ptsFijos   = pctFijos < 0.40 ? 25 : pctFijos < 0.50 ? 20 : pctFijos < 0.60 ? 12 : pctFijos < 0.70 ? 5 : 0;
    let   ptsControl = 20;
    if (tieneRegistros && mesRow) {
      const fijosEst = Number(mesRow.fijos_estimados) || totalFijosMensual;
      const exceso   = totalRealFijos - fijosEst;
      ptsControl = exceso <= 0 ? 25 : exceso < fijosEst * 0.05 ? 20 : exceso < fijosEst * 0.15 ? 12 : exceso < fijosEst * 0.3 ? 5 : 0;
    }
    const score = ptsDTI + ptsAhorro + ptsFijos + ptsControl;

    // ── Insights ─────────────────────────────────────────────────────────────
    const insights = [];

    // 1. Remanente (siempre primero — responde "¿me sobra o me falta?")
    const remQ = remanente / 2;
    if (remanente >= 0) {
      insights.push({ tipo: 'positivo', icono: 'savings', titulo: 'Tu remanente real',
        texto: `Te sobran $${remanente.toFixed(2)}/mes ($${remQ.toFixed(2)} por quincena) después de fijos ($${totalFijosMensual.toFixed(2)}), deudas y variables estimadas ($${totalVarMensual.toFixed(2)}).` });
    } else {
      insights.push({ tipo: 'critico', icono: 'warning', titulo: 'Déficit mensual',
        texto: `Gastas $${Math.abs(remanente).toFixed(2)} más de lo que ganás por mes. Fijos+deudas: $${totalFijosMensual.toFixed(2)}, variables est.: $${totalVarMensual.toFixed(2)}, ingreso neto: $${ingresoNeto.toFixed(2)}.` });
    }

    // 2. Fijos vs regla 50/30/20
    const pctFijosPct = Math.round(pctFijos * 100);
    if (pctFijos > 0.50) {
      insights.push({ tipo: 'advertencia', icono: 'pie_chart', titulo: `Fijos altos: ${pctFijosPct}% de tu ingreso`,
        texto: `La regla 50/30/20 recomienda que los gastos fijos no superen el 50% del ingreso neto. Estás en ${pctFijosPct}%. Evalúa qué gasto fijo podés renegociar o eliminar.` });
    } else {
      insights.push({ tipo: 'positivo', icono: 'pie_chart', titulo: `Fijos saludables: ${pctFijosPct}% del ingreso`,
        texto: `Tus gastos fijos están dentro del rango recomendado (máx 50%). Tenés espacio para maniobrar si surge un imprevisto.` });
    }

    // 3. DTI — si hay deudas
    if (deudas.length > 0) {
      const pctDeudaPct = Math.round(pctDeuda * 100);
      if (pctDeuda > 0.36) {
        insights.push({ tipo: 'critico', icono: 'credit_card', titulo: `DTI crítico: ${pctDeudaPct}% en deudas`,
          texto: `El ${pctDeudaPct}% de tu ingreso mensual va directo a pagar deudas. El límite saludable internacionalmente aceptado es 36%. Estás en zona de riesgo — no contraigas más deuda ahora.` });
      } else if (pctDeuda > 0.15) {
        insights.push({ tipo: 'advertencia', icono: 'credit_card', titulo: `DTI moderado: ${pctDeudaPct}% en deudas`,
          texto: `El ${pctDeudaPct}% de tu ingreso va a pagar deudas. No es crítico, pero limita tu capacidad de ahorro. Prioriza liquidar primero la deuda de mayor tasa.` });
      }
    }

    // 4. Deuda más cara (tasa más alta)
    const deudaMasCara = deudas.find(d => Number(d.tasa_interes) > 12);
    if (deudaMasCara) {
      const saldo  = Number(deudaMasCara.monto_pendiente) || Number(deudaMasCara.monto_total) || 0;
      const tasaM  = Number(deudaMasCara.tasa_interes) / 100 / 12;
      const intMes = saldo > 0 ? saldo * tasaM : 0;
      insights.push({ tipo: 'advertencia', icono: 'trending_up',
        titulo: `"${deudaMasCara.nombre}" al ${deudaMasCara.tasa_interes}% TEA`,
        texto: `Esta deuda es tu enemigo financiero #1.${intMes > 0 ? ` Te cuesta aprox $${intMes.toFixed(2)} en intereses cada mes.` : ''} Pagá más del mínimo cuando puedas — cada dólar extra reduce drásticamente el total de intereses.` });
    }

    // 5. Proyección de liquidación de deuda con plazo definido
    const deudaConPlazo = deudas.find(d => Number(d.num_cuotas_total) > 0);
    if (deudaConPlazo) {
      const total     = Number(deudaConPlazo.num_cuotas_total);
      const pagados   = Number(deudaConPlazo.num_pagos_realizados) || 0;
      const restantes = Math.max(1, total - pagados);
      const fechaFin  = new Date();
      fechaFin.setMonth(fechaFin.getMonth() + restantes);
      const label = fechaFin.toLocaleDateString('es-PA', { month: 'long', year: 'numeric' });
      insights.push({ tipo: 'info', icono: 'schedule',
        titulo: `"${deudaConPlazo.nombre}" — libre en ${label}`,
        texto: `Te quedan ${restantes} cuota${restantes !== 1 ? 's' : ''} de ${total}. Mantené tus pagos puntuales y estarás libre de esta deuda en ${label}.` });
    }

    // 6. Fondo de emergencia — 3 meses de todos los gastos (fijos + variables)
    const gastoMensualTotal = totalFijosMensual + totalVarMensual;
    const fondoRec = gastoMensualTotal * 3;
    insights.push({ tipo: 'info', icono: 'shield', titulo: 'Fondo de emergencia recomendado',
      texto: `Con tus gastos totales de $${gastoMensualTotal.toFixed(2)}/mes, tu fondo de emergencia debería ser $${fondoRec.toFixed(2)} (3 meses). Verificá si tenés esa liquidez disponible en efectivo o cuenta de ahorro.` });

    // ── Enfoque del mes (1 acción concreta) ──────────────────────────────────
    let enfoque;
    if (remanente < 0) {
      enfoque = { icono: 'cut', urgencia: 'alta', titulo: 'Reducí un gasto fijo este mes',
        texto: `Tenés un déficit de $${Math.abs(remanente).toFixed(2)}/mes. Identificá el compromiso fijo menos esencial y renegocialo o eliminalo. Cada dólar liberado mejora tu salud financiera.` };
    } else if (deudaMasCara && remanente > 30) {
      const extra = Math.min(remanente * 0.4, 150).toFixed(2);
      enfoque = { icono: 'bolt', urgencia: 'media', titulo: `Pagá $${extra} extra a "${deudaMasCara.nombre}"`,
        texto: `Tenés remanente. Destinar $${extra} extra a esta deuda este mes reduce años de plazo y cientos de dólares en intereses a lo largo del tiempo.` };
    } else if (tasaAhorro < 0.10 && remanente > 0) {
      const ahorro = (ingresoNeto * 0.10).toFixed(2);
      enfoque = { icono: 'savings', urgencia: 'media', titulo: `Reservá $${ahorro} antes de gastar`,
        texto: `Aplicá el principio de "pagarte primero": separá el 10% ($${ahorro}) de tu ingreso apenas lo recibís, antes de cualquier gasto variable. Lo que queda es lo que podés gastar libremente.` };
    } else {
      enfoque = { icono: 'check_circle', urgencia: 'baja', titulo: 'Mantené el rumbo',
        texto: `Tu planificación financiera es sólida. Seguí registrando tus gastos reales para que el análisis se afine cada mes con datos reales de tu vida.` };
    }

    res.json({
      score,
      score_breakdown: { dti: ptsDTI, ahorro: ptsAhorro, fijos: ptsFijos, control: ptsControl },
      metricas: {
        ingreso_neto:                parseFloat(ingresoNeto.toFixed(2)),
        total_fijos:                 parseFloat(totalFijosMensual.toFixed(2)),
        total_variables:             parseFloat(totalVarMensual.toFixed(2)),
        total_pagos_deuda:           parseFloat(totalPagosDeuda.toFixed(2)),
        remanente:                   parseFloat(remanente.toFixed(2)),
        remanente_quincenal:         parseFloat((remanente / 2).toFixed(2)),
        pct_fijos:                   parseFloat((pctFijos * 100).toFixed(1)),
        pct_deuda:                   parseFloat((pctDeuda * 100).toFixed(1)),
        tasa_ahorro_pct:             parseFloat((tasaAhorro * 100).toFixed(1)),
        fondo_emergencia_recomendado: parseFloat(fondoRec.toFixed(2)),
        num_deudas:                  deudas.length,
      },
      insights: insights.slice(0, 5),
      enfoque,
      mes: month, mes_label: MESES[month], anio: year,
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
    const ingresoReal  = Number(mesRow.ingreso_real) || Number(mesRow.ingreso_estimado);
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
        const mesesArr = typeof g.aplica_meses === 'string' ? JSON.parse(g.aplica_meses) : g.aplica_meses;
        if (!mesesArr.includes(Number(mes))) continue;
      }
      presupuestadoPorCat[g.categoria] = (presupuestadoPorCat[g.categoria] || 0) + _montoMensual(g);
    }
    // Incluir gastos fijos del perfil que tienen categoría asignada en el presupuesto por categoría
    const [fijosCat] = await db.execute(
      `SELECT descripcion, monto_mensual, categoria FROM user_gastos_fijos
       WHERE firebase_uid = ? AND activo = 1 AND categoria IS NOT NULL AND categoria != ''`,
      [firebase_uid]
    );
    for (const f of fijosCat) {
      presupuestadoPorCat[f.categoria] = (presupuestadoPorCat[f.categoria] || 0) + Number(f.monto_mensual);
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

    // Eventos presupuestados activos en este mes
    const [eventosDelMes] = await db.execute(
      `SELECT ep.*,
              COALESCE((SELECT SUM(eg.monto) FROM eventos_gastos eg WHERE eg.evento_id = ep.id), 0) AS gastado_real
       FROM eventos_presupuesto ep
       WHERE ep.firebase_uid = ? AND ep.anio = ? AND ep.mes_inicio <= ? AND ep.mes_fin >= ?
         AND ep.estado = 'activo'`,
      [firebase_uid, anio, mes, mes]
    );
    const totalEventosMes = eventosDelMes.reduce((s, e) => s + Number(e.cuota_mensual), 0);

    const hormigaRegistros = registros.filter(r => r.es_hormiga == 1);
    const hormigaTotal = hormigaRegistros.reduce((s, r) => s + Number(r.monto), 0);

    // Ingresos extra del mes (para vista bucket)
    const [ingresosExtra] = await db.execute(
      `SELECT * FROM registros_ingreso
       WHERE firebase_uid = ? AND anio = ? AND mes = ?
       ORDER BY fecha DESC`,
      [firebase_uid, anio, mes]
    );
    const totalIngresosExtra = ingresosExtra.reduce((s, r) => s + Number(r.monto), 0);

    // Buckets de gastos por fuente_ingreso (para vista bucket)
    const gastosPorFuente = {};
    for (const r of registros) {
      const fuente = r.fuente_ingreso || '__base__';
      if (!gastosPorFuente[fuente]) gastosPorFuente[fuente] = 0;
      gastosPorFuente[fuente] += Number(r.monto);
    }

    res.json({
      mes: mesRow,
      compromisos_fijos: {
        gastos_fijos: gastosFijosPerfil.map(g => ({
          id: g.id, nombre: g.descripcion, monto: Number(g.monto_mensual),
          tipo: g.tipo, dia_pago: g.dia_pago, dia_pago_2: g.dia_pago_2, frecuencia: g.frecuencia,
          categoria: g.categoria || null,
        })),
        deudas: deudasDelMes.map(d => ({
          id: d.id, nombre: d.nombre, tipo: d.tipo,
          cuota: d.es_letra ? Number(d.cuota_fija) : Number(d.pago_minimo),
          es_letra: Boolean(d.es_letra),
          proxima_fecha: d.fecha_proximo_pago,
          cuotas_restantes: d.num_cuotas_total
            ? Math.max(0, Number(d.num_cuotas_total) - Number(d.num_cuotas_pagadas || 0)) : null,
        })),
        eventos: eventosDelMes.map(e => ({
          id: e.id, nombre: e.nombre, emoji: e.emoji,
          monto_total: Number(e.monto_total),
          cuota_mensual: Number(e.cuota_mensual),
          gastado_real: Number(e.gastado_real),
          mes_inicio: e.mes_inicio, mes_fin: e.mes_fin,
          pct_avance: e.monto_total > 0
            ? parseFloat((Number(e.gastado_real) / Number(e.monto_total) * 100).toFixed(1)) : 0,
        })),
        total_estimado: parseFloat((totalFijosEstimado + totalEventosMes).toFixed(2)),
        total_eventos:  parseFloat(totalEventosMes.toFixed(2)),
      },
      resumen: {
        ingreso_estimado:    Number(mesRow.ingreso_estimado),
        fijos_estimados:     parseFloat(totalFijosEstimado.toFixed(2)),
        variables_estimados: Number(mesRow.variables_estimados),
        eventos_estimados:   parseFloat(totalEventosMes.toFixed(2)),
        // AA2 — la cuota mensual de eventos reduce el disponible estimado del mes
        remanente_estimado:  parseFloat((Number(mesRow.ingreso_estimado) - totalFijosEstimado - Number(mesRow.variables_estimados) - totalEventosMes).toFixed(2)),
        ingreso_real:        parseFloat(ingresoReal.toFixed(2)),
        ingreso_base:        Number(mesRow.ingreso_estimado),
        ingresos_extra_total: parseFloat(totalIngresosExtra.toFixed(2)),
        fijos_reales:        parseFloat(fijosReales.toFixed(2)),
        variables_reales:    parseFloat(variablesReales.toFixed(2)),
        no_presupuestados:   parseFloat(noPresReales.toFixed(2)),
        remanente_real:      parseFloat(remanenteReal.toFixed(2)),
        presupuesto_sano:    remanenteReal >= 0,
        hormiga_count:       hormigaRegistros.length,
        hormiga_total:       parseFloat(hormigaTotal.toFixed(2)),
      },
      ingresos_extra: ingresosExtra,
      gastos_por_fuente: gastosPorFuente,
      registros,
      analisis_categorias: analisisCategorias,
    });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// PATCH /user/estado-anual/:anio/recalcular
// Recalcula estimados del estado anual y los 12 meses usando _recalcularEstimadosAnio.
app.patch('/user/estado-anual/:anio/recalcular', async (req, res) => {
  const { anio } = req.params;
  const { firebase_uid } = req.body;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    await _recalcularEstimadosAnio(firebase_uid, Number(anio));
    res.json({ recalculado: true, anio: Number(anio) });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// PATCH /user/meses/:anio/:mes/ingreso
// Registra el ingreso real cobrado en un mes específico.
app.patch('/user/meses/:anio/:mes/ingreso', async (req, res) => {
  const { anio, mes } = req.params;
  const { firebase_uid, ingreso_real } = req.body;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  if (ingreso_real == null || isNaN(Number(ingreso_real)) || Number(ingreso_real) < 0)
    return res.status(400).json({ error: 'ingreso_real debe ser un número >= 0' });
  try {
    const [[mesRow]] = await db.execute(
      `SELECT id FROM meses_financieros WHERE firebase_uid = ? AND anio = ? AND mes = ?`,
      [firebase_uid, anio, mes]
    );
    if (!mesRow) return res.status(404).json({ error: 'Mes no encontrado. Genera el estado anual primero.' });
    await db.execute(
      `UPDATE meses_financieros SET ingreso_real = ? WHERE id = ?`,
      [parseFloat(Number(ingreso_real).toFixed(2)), mesRow.id]
    );
    const [[updated]] = await db.execute(`SELECT * FROM meses_financieros WHERE id = ?`, [mesRow.id]);
    res.json(updated);
    _logInfo(`/user/meses/${anio}/${mes}/ingreso`, `Ingreso real registrado: $${Number(ingreso_real).toFixed(2)} para ${anio}/${mes}`, firebase_uid);
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

// _recalcularEstimadosAnio y _actualizarTotalesMes movidos a lib/mes_helpers.js
// (requerido al inicio de este archivo).

// =============================================================================
// SPLITS PUNTUALES — notificación de gastos compartidos sin presupuesto
// =============================================================================

async function _enviarNotificacionSplit({ emailParticipante, remitente, descripcion, montoTotal, montoParticipante, participantes }) {
  if (!process.env.BREVO_API_KEY) return;
  const otros = participantes.filter(p => p.email !== emailParticipante)
    .map(p => `${p.email} — $${Number(p.monto).toFixed(2)}`).join('<br>');
  await fetch('https://api.brevo.com/v3/smtp/email', {
    method: 'POST',
    headers: { 'api-key': process.env.BREVO_API_KEY, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      sender: { email: process.env.BREVO_SENDER_EMAIL, name: 'Salarying' },
      to: [{ email: emailParticipante }],
      subject: `${remitente} compartió un gasto contigo`,
      htmlContent: `
        <div style="font-family:sans-serif;max-width:480px;margin:auto;padding:24px;background:#1E2026;color:#EAECEF;border-radius:12px;">
          <h2 style="color:#F0B90B;margin-bottom:4px;">Salarying</h2>
          <p style="color:#848E9C;margin-top:0;">Registro de gasto compartido</p>
          <p style="font-size:15px;"><b>${remitente}</b> registró un gasto compartido contigo:</p>
          <div style="background:#2B3139;border-radius:8px;padding:16px;margin:16px 0;">
            <p style="margin:0 0 6px;font-size:13px;color:#848E9C;">GASTO</p>
            <p style="margin:0;font-size:18px;font-weight:700;">${descripcion}</p>
            <p style="margin:4px 0 0;font-size:13px;color:#848E9C;">Total: <span style="color:#EAECEF;">$${Number(montoTotal).toFixed(2)}</span></p>
          </div>
          <div style="background:#F0B90B;border-radius:8px;padding:14px;text-align:center;">
            <p style="margin:0;font-size:12px;color:#1E2026;">TU PARTE</p>
            <p style="margin:4px 0 0;font-size:28px;font-weight:800;color:#1E2026;">$${Number(montoParticipante).toFixed(2)}</p>
          </div>
          ${otros ? `<p style="margin-top:16px;font-size:12px;color:#848E9C;">También incluye:<br>${otros}</p>` : ''}
          <p style="margin-top:20px;font-size:11px;color:#848E9C;text-align:center;">Aviso informativo de Salarying. No necesitas crear una cuenta.</p>
        </div>`,
    }),
  });
}

// POST /gastos/split-notificar
app.post('/gastos/split-notificar', async (req, res) => {
  const { firebase_uid, registro_gasto_id, descripcion, monto_total, participantes, remitente } = req.body;
  if (!firebase_uid || !descripcion || !monto_total || !Array.isArray(participantes) || participantes.length === 0)
    return res.status(400).json({ error: 'firebase_uid, descripcion, monto_total y participantes requeridos' });
  try {
    for (const p of participantes) {
      if (!p.email || !p.monto) continue;
      await db.execute(
        `INSERT INTO gasto_splits_puntual (firebase_uid, registro_gasto_id, descripcion, monto_total, email_participante, monto_participante)
         VALUES (?, ?, ?, ?, ?, ?)`,
        [firebase_uid, registro_gasto_id || null, descripcion, monto_total, p.email, p.monto]
      );
      _enviarNotificacionSplit({
        emailParticipante: p.email,
        remitente: remitente || firebase_uid,
        descripcion,
        montoTotal: monto_total,
        montoParticipante: p.monto,
        participantes,
      }).catch(() => {});
    }
    res.json({ enviado: true, cantidad: participantes.length });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

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
    const hormigaRegistros = registros.filter(r => r.es_hormiga === 1 || r.es_hormiga === true);
    const hormigaTotal = hormigaRegistros.reduce((s, r) => s + Number(r.monto), 0);
    res.json({
      registros,
      total: parseFloat(total.toFixed(2)),
      hormiga_count: hormigaRegistros.length,
      hormiga_total: parseFloat(hormigaTotal.toFixed(2)),
    });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// POST /registros — registrar un gasto real en un mes
app.post('/registros', async (req, res) => {
  const {
    firebase_uid, anio, mes, tipo, categoria = 'otro', subcategoria_id,
    nombre, monto, fecha, pagado = 0, origen_fijo_id, origen_variable_id, origen_deuda_id,
    notas, en_calendario = 0, definition_id: defIdParam, fuente_ingreso,
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

    // Resolver definition_id: usar el provisto, buscar por nombre+categoría, o crear nuevo
    let definitionId = defIdParam || null;
    if (!definitionId && tipo !== 'fijo') {
      const [[existingDef]] = await db.execute(
        `SELECT id FROM expense_definitions WHERE firebase_uid = ? AND nombre = ? AND categoria = ? AND activo = 1`,
        [firebase_uid, nombre.trim(), categoria]
      );
      if (existingDef) {
        definitionId = existingDef.id;
      } else {
        const [newDef] = await db.execute(
          `INSERT INTO expense_definitions (firebase_uid, nombre, categoria, tipo_habitual)
           VALUES (?, ?, ?, ?)`,
          [firebase_uid, nombre.trim(), categoria, tipo]
        );
        definitionId = newDef.insertId;
      }
    }

    const esHormiga = (tipo === 'no_presupuestado' && Number(monto) <= 25) ? 1 : 0;

    // Pagos parciales habilitados para todos los tipos: múltiples registros por mes
    // son válidos (ej. pagar $30 + $30 de una cuota de $60, o gasolina por tandas).
    // El Tab Quincenas agrega por origen_*_id con filtro de quincena.

    const [r] = await db.execute(
      `INSERT INTO registros_gasto
         (firebase_uid, mes_id, anio, mes, tipo, categoria, subcategoria_id,
          nombre, monto, fecha, pagado, origen_fijo_id, origen_variable_id, origen_deuda_id,
          notas, en_calendario, definition_id, es_hormiga, fuente_ingreso)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [firebase_uid, mesRow.id, anio, mes, tipo, categoria, subcategoria_id || null,
       nombre, monto, fecha, pagado ? 1 : 0, origen_fijo_id || null,
       origen_variable_id || null, origen_deuda_id || null, notas || null, en_calendario ? 1 : 0,
       definitionId, esHormiga, fuente_ingreso || null]
    );
    await _actualizarTotalesMes(mesRow.id, firebase_uid);

    const [[created]] = await db.execute(`SELECT * FROM registros_gasto WHERE id = ?`, [r.insertId]);
    res.status(201).json(created);
    _logInfo('/registros', `Gasto registrado: "${nombre}" $${Number(monto).toFixed(2)} (${tipo} · ${categoria}) en ${anio}/${mes}`, firebase_uid);
    _generarAlertasMes(firebase_uid, Number(anio), Number(mes)).catch(() => {});
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// PUT /registros/:id
app.put('/registros/:id', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid, nombre, categoria, subcategoria_id, monto, fecha, tipo, pagado, notas, fuente_ingreso } = req.body;
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
    if (fuente_ingreso !== undefined)  { fields.push('fuente_ingreso = ?');  vals.push(fuente_ingreso || null); }
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
    _generarAlertasMes(firebase_uid, Number(existing.anio), Number(existing.mes)).catch(() => {});
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
// MÓDULO: ESTADO ANUAL — proyección y cierre
// (las alertas en sí viven en routes/alertas.js y lib/mes_helpers.js)
// =============================================================================

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
       Number(mesRow.ingreso_real) || Number(mesRow.ingreso_estimado),
       mesRow.fijos_reales, mesRow.variables_reales, mesRow.no_presupuestados_reales,
       parseFloat(((Number(mesRow.ingreso_real) || Number(mesRow.ingreso_estimado)) - Number(mesRow.fijos_reales) - Number(mesRow.variables_reales) - Number(mesRow.no_presupuestados_reales)).toFixed(2)),
       JSON.stringify(alertas.map(a => ({ tipo: a.tipo, categoria: a.categoria, mensaje: a.mensaje })))]
    );

    res.json({ cerrado: true, alertas_generadas: alertas.length, alertas });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// =============================================================================
// MÓDULO: ESTADO ANUAL — cierre
// (los presupuestos de eventos viven en routes/eventos.js)
// =============================================================================

// POST /user/cerrar-anio/:anio
// Cierra el año financiero: snapshot en cierres_anuales + recomendaciones para el siguiente año.
app.post('/user/cerrar-anio/:anio', async (req, res) => {
  const { anio } = req.params;
  const { firebase_uid } = req.body;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    // Verificar que existe el estado anual
    const [[efa]] = await db.execute(
      `SELECT * FROM estado_financiero_anual WHERE firebase_uid = ? AND anio = ?`,
      [firebase_uid, anio]
    );
    if (!efa) return res.status(404).json({ error: 'Estado anual no encontrado. Genera el estado anual primero.' });

    // Obtener todos los meses del año
    const [meses] = await db.execute(
      `SELECT * FROM meses_financieros WHERE firebase_uid = ? AND anio = ? ORDER BY mes ASC`,
      [firebase_uid, anio]
    );
    if (!meses.length) return res.status(404).json({ error: 'No hay meses registrados para este año.' });

    // Calcular totales reales del año
    let ingresoTotal = 0, fijosTotal = 0, variablesTotal = 0, noPresTotal = 0;
    for (const m of meses) {
      ingresoTotal    += Number(m.ingreso_real) || Number(m.ingreso_estimado);
      fijosTotal      += Number(m.fijos_reales) || 0;
      variablesTotal  += Number(m.variables_reales) || 0;
      noPresTotal     += Number(m.no_presupuestados_reales) || 0;
    }
    const remanenteReal = parseFloat((ingresoTotal - fijosTotal - variablesTotal - noPresTotal).toFixed(2));

    // Análisis de categorías del año (para recomendaciones)
    const [analisis] = await db.execute(
      `SELECT categoria,
              SUM(CASE WHEN tipo='variable'          THEN monto ELSE 0 END) AS total_variable,
              SUM(CASE WHEN tipo='no_presupuestado'  THEN monto ELSE 0 END) AS total_no_presup,
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
      const promedioVariable  = Number(a.total_variable)  / Number(a.meses_presentes);
      const promedioNoPresup  = Number(a.total_no_presup) / Number(a.meses_presentes);
      const avgReal    = promedioVariable + promedioNoPresup;
      const presup     = presupActual[a.categoria] || 0;
      const diferencia = parseFloat((avgReal - presup).toFixed(2));
      return {
        categoria:                a.categoria,
        presupuesto_actual:       parseFloat(presup.toFixed(2)),
        promedio_real_mensual:    parseFloat(avgReal.toFixed(2)),
        promedio_no_presupuestado: parseFloat(promedioNoPresup.toFixed(2)),
        total_anual:              parseFloat(Number(a.total_anual).toFixed(2)),
        meses_presentes:          Number(a.meses_presentes),
        diferencia,
        recomendacion: diferencia > 5
          ? `Aumentar presupuesto de ${a.categoria} en $${diferencia.toFixed(2)}/mes`
          : diferencia < -20
            ? `Podrías reducir presupuesto de ${a.categoria} en $${Math.abs(diferencia).toFixed(2)}/mes`
            : 'Presupuesto adecuado',
        accion: diferencia > 5 ? 'aumentar' : diferencia < -20 ? 'reducir' : 'mantener',
      };
    });

    // Snapshot en cierres_anuales
    await db.execute(
      `INSERT INTO cierres_anuales
         (firebase_uid, anio, ingreso_total, fijos_total, variables_total,
          no_presupuestados_total, remanente_real, analisis_categorias, recomendaciones_sig)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
       ON DUPLICATE KEY UPDATE
         ingreso_total = VALUES(ingreso_total), fijos_total = VALUES(fijos_total),
         variables_total = VALUES(variables_total), no_presupuestados_total = VALUES(no_presupuestados_total),
         remanente_real = VALUES(remanente_real),
         analisis_categorias = VALUES(analisis_categorias),
         recomendaciones_sig = VALUES(recomendaciones_sig)`,
      [firebase_uid, anio,
       parseFloat(ingresoTotal.toFixed(2)), parseFloat(fijosTotal.toFixed(2)),
       parseFloat(variablesTotal.toFixed(2)), parseFloat(noPresTotal.toFixed(2)),
       remanenteReal,
       JSON.stringify(analisis),
       JSON.stringify(recomendaciones)]
    );

    _logInfo(`/user/cerrar-anio/${anio}`, `Cierre anual ${anio} generado`, firebase_uid);

    res.json({
      cerrado: true,
      anio: Number(anio),
      resumen_anual: {
        ingreso_total:           parseFloat(ingresoTotal.toFixed(2)),
        fijos_total:             parseFloat(fijosTotal.toFixed(2)),
        variables_total:         parseFloat(variablesTotal.toFixed(2)),
        no_presupuestados_total: parseFloat(noPresTotal.toFixed(2)),
        remanente_real:          remanenteReal,
      },
      recomendaciones,
      mensaje: `Cierre ${anio} completado. ${recomendaciones.filter(r => r.accion !== 'mantener').length} ajustes sugeridos para ${Number(anio) + 1}.`,
    });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// =============================================================================
// MÓDULO IA — Asistente financiero con Claude (tool_use loop)
// Regla de oro: Claude NUNCA calcula — solo lee resultados de tools existentes.
// Endpoints: POST /ai/diagnostico, /ai/chat, /ai/categorizar, /ai/reporte
// =============================================================================

const Anthropic = require('@anthropic-ai/sdk');
let _anthropicClient = null;
function _getAnthropic() {
  if (!_anthropicClient) {
    if (!process.env.ANTHROPIC_API_KEY || process.env.ANTHROPIC_API_KEY === 'tu-api-key-aqui')
      throw new Error('ANTHROPIC_API_KEY no configurada. Agrégala en las variables de entorno de Render.');
    _anthropicClient = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });
  }
  return _anthropicClient;
}

const AI_MODEL        = 'claude-haiku-4-5-20251001';
const AI_MODEL_SONNET = 'claude-sonnet-4-6';

// System prompt dinámico — incluye la fecha actual de Panamá para que Claude sepa
// en qué mes/año estamos sin que el usuario lo tenga que escribir.
function _aiGetSystemPrompt() {
  const ahora  = new Date();
  const opPA   = { timeZone: 'America/Panama' };
  const fechaPA = ahora.toLocaleDateString('es-PA', { ...opPA, year: 'numeric', month: 'long', day: 'numeric' });
  const horaPA  = ahora.toLocaleTimeString('es-PA', { ...opPA, hour: '2-digit', minute: '2-digit' });
  return `${AI_SYSTEM_PROMPT_BASE}\n\nContexto de sesión: Hoy es ${fechaPA}, ${horaPA} hora de Panamá (UTC-5). Año en curso: ${ahora.getFullYear()}.`;
}

// Cache de diagnóstico por usuario (1 hora) para no regenerar en cada tap.
const _aiDiagCache = new Map(); // uid → { resultado, expires }

// Rate limiting simple: máx 30 requests /ai/* por usuario por hora.
const _aiRateMap = new Map(); // uid → { count, resetAt }
function _aiCheckRate(uid) {
  const now = Date.now();
  let e = _aiRateMap.get(uid);
  if (!e || now > e.resetAt) e = { count: 0, resetAt: now + 3600000 };
  e.count++;
  _aiRateMap.set(uid, e);
  return e.count <= 30;
}

const AI_SYSTEM_PROMPT_BASE = `Eres el asistente financiero de Salarying, una app de presupuesto personal para usuarios de clase media a baja en Panamá. El salario típico es $600–$2,000 mensual. Muchos cobran quincenal, tienen deudas activas y un sobrante chico (a veces $40, a veces negativo).

Reglas no negociables:
1. Nunca recomiendes algo que el usuario no puede pagar. Ajusta cualquier consejo a su capacidad real.
2. Si hay deuda con interés alto activa, priorízala SIEMPRE sobre cualquier sugerencia de ahorro.
3. Cero jerga sin traducir: cuando uses "tasa de ahorro", "liquidez", etc., explícalo en palabras simples justo después.
4. Toda cifra estimada o proyectada se marca explícitamente con "~" y la palabra "estimado".
5. El ingreso es informativo: nunca lo uses para sugerir cambios al monto del presupuesto.
6. Las fórmulas son quincenal-first: no asumas ciclos mensuales por defecto.
7. Todo número negativo o alerta va acompañado de un siguiente paso concreto. Nunca muestres un problema sin una acción posible.
8. Usa SOLO datos devueltos por las tools. Si una tool no tiene el dato, dilo con honestidad en vez de inventar.
9. Sé empático y directo. No juzgues los hábitos del usuario. Informa, no sermonees.
10. Responde siempre en español, en un lenguaje claro y cercano.
11. NUNCA llames una tool de escritura directa — toda acción pasa por proponer_accion. Nunca ejecutes la acción dentro de la misma respuesta donde la propones: una vez que llamaste proponer_accion, para y deja que el usuario confirme.
11b. Antes de proponer_accion, llama get_presupuesto_actual para conocer la quincena actual. Siempre incluye en el resumen_para_usuario en qué quincena aparecerá el gasto (ej: "aparecerá en Quincena 2 de junio"). Para gastos fijos con dos días de pago, pregunta al usuario si es solo esta quincena o ambas antes de proponer.
12. El resumen_para_usuario en proponer_accion debe incluir siempre: qué va a cambiar, los números reales antes/después, y si la acción deja al usuario sobre presupuesto o afecta una deuda con interés. Nunca lo ocultes para que la propuesta "se vea bien".
13. Después de que el usuario confirme una acción, vuelve a consultar el dato real (tool de lectura) antes de confirmarle que se aplicó — nunca asumas que funcionó solo porque se llamó el endpoint.
14. NUNCA pidas al usuario un presupuesto_id, periodo_id u otro ID interno. Usa get_presupuesto_actual para resolverlo solo — pedir IDs internos a un usuario es exactamente la fricción y jerga que este asistente prohíbe.
12. Distingue siempre entre NEGATIVA POR DISEÑO (no puedo hacer X porque requiere confirmación del usuario antes de escribir en sus finanzas — esto es una barrera de seguridad intencional, no una brecha) y BRECHA REAL (ninguna tool cubre lo pedido). En la primera, explica el diseño. En la segunda, usa reportar_brecha_capacidad.
13. Redactar un prompt de texto para Claude Code es SIEMPRE seguro y permitido — nunca lo confundas con "ejecutar una acción". Si hay una brecha real, siempre ofrece el prompt, aunque no puedas ejecutar la funcionalidad.`;

// --- Definición de tools que Claude puede llamar ---

const AI_TOOLS = [
  // ── HERRAMIENTA OBLIGATORIA — siempre se llama primero ──────────────────
  {
    name: 'get_presupuesto_actual',
    description: 'LLAMAR SIEMPRE PRIMERO en cualquier conversación nueva. Resuelve automáticamente en qué período está el usuario ahora mismo: mes actual, quincena (1 o 2), fecha de inicio/fin, y si tiene presupuesto activo en el sistema legado. Nunca pidas al usuario un presupuesto_id — esta tool lo resuelve sola.',
    input_schema: {
      type: 'object',
      properties: { firebase_uid: { type: 'string' } },
      required: ['firebase_uid'],
    },
  },
  // ── HERRAMIENTA OBLIGATORIA ANTES DE CUALQUIER PAGO ────────────────────
  {
    name: 'get_compromisos_mes',
    description: `LLAMAR SIEMPRE antes de proponer cualquier acción de pago. Devuelve todos los compromisos del usuario (gastos fijos, variables presupuestadas, deudas) con sus IDs exactos.

Cómo usar los IDs devueltos:
- fijos[].gasto_fijo_id → usar en marcar_pagado parametros (para gastos fijos del perfil)
- variables_base[].origen_variable_id → usar en registrar_pago parametros (para variables presupuestadas)
- deudas[].deuda_id → usar en abonar_deuda parametros

Si el item que el usuario quiere pagar NO está en ninguna lista, NO crear automáticamente. Preguntar primero: "No tengo [item] en tu presupuesto. ¿Solo registrarlo como gasto puntual de esta quincena, o también quieres añadirlo a tu presupuesto base?"`,
    input_schema: {
      type: 'object',
      properties: { firebase_uid: { type: 'string' } },
      required: ['firebase_uid'],
    },
  },
  // ── HERRAMIENTA DE REPORTE DE BRECHAS ───────────────────────────────────
  {
    name: 'reportar_brecha_capacidad',
    description: 'Usa esta tool cuando ninguna otra tool puede cubrir lo que el usuario pidió (brecha real). NO la uses para negativas por diseño (cuando sí podrías técnicamente pero está prohibido sin confirmación del usuario). Registra la brecha y genera un prompt listo para Claude Code. En modo desarrollo, el prompt se muestra directamente en el chat.',
    input_schema: {
      type: 'object',
      properties: {
        lo_que_pidio_usuario: { type: 'string', description: 'Descripción exacta de lo que el usuario solicitó' },
        por_que_no_se_puede:  { type: 'string', description: 'Explicación técnica de por qué ninguna tool actual lo cubre' },
        que_haria_falta:      { type: 'string', description: 'Qué tool o funcionalidad habría que construir' },
        tipo_brecha:          { type: 'string', enum: ['total', 'aproximada'], description: 'total = ninguna tool sirve; aproximada = existe una parecida pero no calza exacto' },
        accion_tomada:        { type: 'string', enum: ['ninguna', 'uso_tool_aproximada'], description: 'Si se usó una alternativa parcial' },
      },
      required: ['lo_que_pidio_usuario', 'por_que_no_se_puede', 'que_haria_falta', 'tipo_brecha', 'accion_tomada'],
    },
  },
  // ── ÚNICA TOOL DE ESCRITURA — siempre propone, nunca ejecuta directamente ──
  {
    name: 'proponer_accion',
    description: `ÚNICA tool disponible para modificar datos. Propone una acción al usuario — NO la ejecuta. El usuario confirma tocando un botón.

FLUJO OBLIGATORIO antes de llamar esta tool:
1. Llama get_presupuesto_actual → obtén mes/quincena actual.
2. Llama get_compromisos_mes → obtén la lista de fijos, variables_base y deudas con sus IDs.
3. Busca si el item pedido coincide con algo en esas listas (por nombre, tipo o categoría):
   - Si COINCIDE con un fijo → usa tipo='marcar_pagado' + parametros.gasto_fijo_id=[ID del fijo]
   - Si COINCIDE con una variable_base → usa tipo='registrar_pago' + parametros.origen_variable_id=[ID]
   - Si COINCIDE con una deuda → usa tipo='abonar_deuda' + parametros.deuda_id=[ID]
   - Si NO coincide con nada → NO proponer todavía. Pregunta al usuario: "No tengo [item] en tu presupuesto. ¿Solo registro este gasto como puntual (no afecta tu presupuesto base), o también lo añado a tu presupuesto base para que aparezca cada mes?"
4. Solo si el usuario responde que sí a la pregunta anterior → usa tipo='crear_gasto' (sin origen_*_id).

NUNCA crear un gasto de tipo variable con la misma categoría/nombre que un compromiso existente en fijos o variables_base — eso crea duplicados.

El resumen_para_usuario DEBE incluir: qué va a cambiar, quincena donde aparecerá, antes/después en números reales, y advertencia si deja la categoría sobre presupuesto.`,
    input_schema: {
      type: 'object',
      properties: {
        firebase_uid:         { type: 'string' },
        tipo:                 { type: 'string', enum: ['registrar_pago', 'marcar_pagado', 'crear_gasto', 'abonar_deuda'] },
        parametros:           { type: 'object', description: 'Varía según tipo. crear_gasto/registrar_pago: {anio,mes,nombre,monto,categoria,tipo,fecha}. marcar_pagado: {anio,mes,gasto_fijo_id,nombre,monto,fecha}. abonar_deuda: {deuda_id,monto,anio?,mes?,fecha?}. NOTA: la fecha determina la quincena automáticamente.' },
        resumen_para_usuario: { type: 'string', description: 'Ejemplo: "Vas a registrar $20 de Gasolina en Transporte, el 22/06 (Quincena 2 de junio). Tu presupuesto de Transporte es $80/mes → llevarías $20 gastados → quedarían ~$60 disponibles. ✅ No te deja sobre presupuesto."' },
      },
      required: ['firebase_uid', 'tipo', 'parametros', 'resumen_para_usuario'],
    },
  },
  {
    name: 'get_dashboard_resumen',
    description: 'Resumen financiero del usuario: score de salud (0-100), ingreso neto mensual, gastos fijos totales, cuotas de deudas, disponible mensual, número de deudas activas y objetivos de ahorro.',
    input_schema: {
      type: 'object',
      properties: { firebase_uid: { type: 'string' } },
      required: ['firebase_uid'],
    },
  },
  {
    name: 'get_income',
    description: 'Ingreso registrado del usuario: tipo (salario/informal/ocasional), monto bruto, monto neto, deducciones totales y frecuencia de cobro (quincenal/mensual).',
    input_schema: {
      type: 'object',
      properties: { firebase_uid: { type: 'string' } },
      required: ['firebase_uid'],
    },
  },
  {
    name: 'get_capacidad_real',
    description: 'Capacidad real de gasto del período: ingreso neto del período menos gastos fijos menos promedio histórico de variables de los últimos 3 períodos cerrados.',
    input_schema: {
      type: 'object',
      properties: {
        presupuesto_id: { type: 'number' },
        firebase_uid: { type: 'string' },
      },
      required: ['presupuesto_id', 'firebase_uid'],
    },
  },
  {
    name: 'get_fondo_seguridad',
    description: 'Estado del fondo de emergencia: cuánto ha ahorrado el usuario y cuánto necesita para alcanzar nivel 1 (1 período de fijos), nivel 2 (2 períodos) y nivel 3 (6 períodos).',
    input_schema: {
      type: 'object',
      properties: {
        presupuesto_id: { type: 'number' },
        firebase_uid: { type: 'string' },
      },
      required: ['presupuesto_id', 'firebase_uid'],
    },
  },
  {
    name: 'get_deudas',
    description: 'Lista de deudas activas: nombre, tipo (revolving/letra), tasa de interés mensual en %, pago mensual y monto pendiente. Ordenadas de mayor a menor tasa.',
    input_schema: {
      type: 'object',
      properties: { firebase_uid: { type: 'string' } },
      required: ['firebase_uid'],
    },
  },
  {
    name: 'get_clasificacion_gastos',
    description: 'Distribución de gastos del período activo por clasificación: esencial, importante, flexible y sin clasificar. Incluye totales en $ y porcentajes vs el presupuesto.',
    input_schema: {
      type: 'object',
      properties: {
        presupuesto_id: { type: 'number' },
        firebase_uid: { type: 'string' },
      },
      required: ['presupuesto_id', 'firebase_uid'],
    },
  },
  {
    name: 'get_gastos_periodo',
    description: 'Lista de gastos registrados en el período activo: descripción, categoría, clasificación, tipo (fijo/variable), monto y si está pagado.',
    input_schema: {
      type: 'object',
      properties: {
        presupuesto_id: { type: 'number' },
        firebase_uid: { type: 'string' },
      },
      required: ['presupuesto_id', 'firebase_uid'],
    },
  },
  {
    name: 'get_historial_periodos',
    description: 'Historial de períodos cerrados con totales de gasto fijo, variable y ahorro. Útil para identificar tendencias entre períodos.',
    input_schema: {
      type: 'object',
      properties: {
        presupuesto_id: { type: 'number' },
        firebase_uid: { type: 'string' },
        n: { type: 'number', description: 'Cantidad de períodos a devolver (default 3, máx 6)' },
      },
      required: ['presupuesto_id', 'firebase_uid'],
    },
  },
  {
    name: 'get_patrones_gustitos',
    description: 'Patrones de gustitos (gastos pequeños frecuentes no presupuestados) detectados en el presupuesto: categoría, en cuántos períodos apareció, monto total y promedio.',
    input_schema: {
      type: 'object',
      properties: {
        presupuesto_id: { type: 'number' },
        firebase_uid: { type: 'string' },
      },
      required: ['presupuesto_id', 'firebase_uid'],
    },
  },
  // ── TOOLS DEL MODELO NUEVO (registros_gasto / meses_financieros) ──────────
  {
    name: 'get_registros_mes',
    description: 'Gastos reales registrados por el usuario en un mes del estado financiero anual. Es la fuente principal de datos reales. Devuelve cada gasto con descripción, categoría, tipo (fijo/variable/no_presupuestado), monto, fecha y si es gasto hormiga. También agrupa por categoría.',
    input_schema: {
      type: 'object',
      properties: {
        firebase_uid: { type: 'string' },
        anio: { type: 'number', description: 'Año del mes (ej: 2026)' },
        mes: { type: 'number', description: 'Mes numérico 1-12' },
      },
      required: ['firebase_uid', 'anio', 'mes'],
    },
  },
  {
    name: 'get_estado_mes',
    description: 'Estado financiero de un mes: lo que el usuario planificó (estimado) vs lo que realmente gastó (real). Incluye ingresos, fijos, variables, no presupuestados, remanente y si está sobre presupuesto.',
    input_schema: {
      type: 'object',
      properties: {
        firebase_uid: { type: 'string' },
        anio: { type: 'number' },
        mes: { type: 'number', description: 'Mes numérico 1-12' },
      },
      required: ['firebase_uid', 'anio', 'mes'],
    },
  },
  {
    name: 'get_alertas_mes',
    description: 'Alertas financieras ya calculadas para un mes por el motor de reglas de la app: DTI crítico, pagos vencidos, categorías que excedieron presupuesto, gastos hormiga frecuentes. Ordenadas por severidad.',
    input_schema: {
      type: 'object',
      properties: {
        firebase_uid: { type: 'string' },
        anio: { type: 'number' },
        mes: { type: 'number' },
      },
      required: ['firebase_uid', 'anio', 'mes'],
    },
  },
  {
    name: 'get_variables_base',
    description: 'Presupuesto mensual de gastos variables que el usuario definió: cuánto planea gastar por categoría (alimentación, transporte, ocio, etc.). Sirve para comparar contra lo que realmente gastó.',
    input_schema: {
      type: 'object',
      properties: { firebase_uid: { type: 'string' } },
      required: ['firebase_uid'],
    },
  },
  {
    name: 'get_estado_anual',
    description: 'Resumen del estado financiero anual: totales estimados vs reales de ingresos, fijos, variables y no presupuestados, más el detalle mes a mes. Útil para analizar tendencias del año.',
    input_schema: {
      type: 'object',
      properties: {
        firebase_uid: { type: 'string' },
        anio: { type: 'number', description: 'Año (ej: 2026)' },
      },
      required: ['firebase_uid', 'anio'],
    },
  },
];

// --- Implementaciones de tools contra la BD (solo lectura) ---

async function _aiToolDashboard(uid) {
  const [[income]] = await db.execute(`SELECT * FROM user_income WHERE firebase_uid = ?`, [uid]);
  const [gastosFijos] = await db.execute(`SELECT monto_mensual FROM user_gastos_fijos WHERE firebase_uid = ? AND activo = 1`, [uid]);
  const [deudas] = await db.execute(
    `SELECT id, nombre, tipo, tasa_interes_mensual, pago_minimo, cuota_fija, es_letra, monto_pendiente FROM deudas WHERE firebase_uid = ? AND activa = 1`,
    [uid]
  );
  const [objetivos] = await db.execute(`SELECT nombre, monto_meta, monto_actual FROM objetivos_financieros WHERE firebase_uid = ? AND activo = 1`, [uid]);

  const ingresoNeto  = income ? Number(income.ingreso_neto_mensual) : 0;
  const totalFijos   = gastosFijos.reduce((s, g) => s + Number(g.monto_mensual), 0);
  const totalDeudas  = deudas.reduce((s, d) => s + (d.es_letra ? Number(d.cuota_fija || 0) : Number(d.pago_minimo || 0)), 0);
  const totalAhorros = objetivos.reduce((s, o) => s + Number(o.monto_actual), 0);
  const disponible   = ingresoNeto - totalFijos - totalDeudas;
  const score        = _calcularScore({ ingresoNeto, totalGastosFijos: totalFijos, totalCuotasDeudas: totalDeudas, totalAhorros, pagosCumplidos: 0, pagosTotales: 0 });

  return {
    tiene_perfil: !!income,
    score_salud: score,
    ..._scoreLegible(score),
    ingreso_neto_mensual: parseFloat(ingresoNeto.toFixed(2)),
    gastos_fijos_total: parseFloat(totalFijos.toFixed(2)),
    cuotas_deudas_total: parseFloat(totalDeudas.toFixed(2)),
    disponible_mensual: parseFloat(disponible.toFixed(2)),
    ratio_comprometido_pct: ingresoNeto > 0 ? parseFloat(((totalFijos + totalDeudas) / ingresoNeto * 100).toFixed(1)) : 0,
    deudas_activas: deudas.length,
    monto_pendiente_deudas: parseFloat(deudas.reduce((s, d) => s + Number(d.monto_pendiente || 0), 0).toFixed(2)),
    objetivos_activos: objetivos.length,
  };
}

async function _aiToolIncome(uid) {
  const [[row]] = await db.execute(`SELECT * FROM user_income WHERE firebase_uid = ?`, [uid]);
  if (!row) return { tiene_income: false };
  return {
    tiene_income: true,
    tipo_ingreso: row.tipo_ingreso,
    ingreso_bruto_mensual: Number(row.ingreso_bruto_mensual),
    ingreso_neto_mensual: Number(row.ingreso_neto_mensual),
    frecuencia_cobro: row.frecuencia_cobro,
    deducciones_total: parseFloat((Number(row.desc_seguro) + Number(row.desc_pension) + Number(row.desc_impuesto) + Number(row.desc_otros)).toFixed(2)),
  };
}

async function _aiToolCapacidad(presupuestoId, uid) {
  const [[presRow]] = await db.execute(`SELECT tipo_periodo FROM presupuestos WHERE id = ? AND firebase_uid = ?`, [presupuestoId, uid]);
  if (!presRow) return { error: 'Presupuesto no encontrado' };
  const divisor = presRow.tipo_periodo === 'quincenal' ? 2 : 1;

  const [[incomeRow]] = await db.execute(`SELECT ingreso_neto_mensual FROM user_income WHERE firebase_uid = ?`, [uid]);
  const ingreso_neto_periodo = incomeRow ? parseFloat((Number(incomeRow.ingreso_neto_mensual) / divisor).toFixed(2)) : null;

  const [[gfRow]] = await db.execute(`SELECT COALESCE(SUM(monto_mensual), 0) AS total FROM user_gastos_fijos WHERE firebase_uid = ? AND activo = 1`, [uid]);
  const gastos_fijos_periodo = parseFloat((Number(gfRow.total) / divisor).toFixed(2));

  const [cerrados] = await db.execute(
    `SELECT SUM(CASE WHEN m.tipo='no fijo' AND m.pagado=1 THEN m.monto_pagado_real ELSE 0 END) AS total_variable
     FROM periodos p LEFT JOIN movimientos m ON m.periodo_id = p.id AND m.firebase_uid = p.firebase_uid
     WHERE p.presupuesto_id = ? AND p.firebase_uid = ? AND p.estado = 'cerrado'
     GROUP BY p.id ORDER BY p.numero_periodo DESC LIMIT 3`,
    [presupuestoId, uid]
  );
  const promedio_variable = cerrados.length > 0
    ? parseFloat((cerrados.reduce((s, r) => s + parseFloat(r.total_variable || 0), 0) / cerrados.length).toFixed(2))
    : 0;

  return {
    tipo_periodo: presRow.tipo_periodo,
    ingreso_neto_periodo,
    gastos_fijos_periodo,
    promedio_variable_historico: promedio_variable,
    capacidad_real: ingreso_neto_periodo !== null ? parseFloat((ingreso_neto_periodo - gastos_fijos_periodo - promedio_variable).toFixed(2)) : null,
    periodos_historico: cerrados.length,
  };
}

async function _aiToolFondoSeguridad(presupuestoId, uid) {
  const [[fijoRow]] = await db.execute(
    `SELECT COALESCE(SUM(m.monto), 0) AS gastos_fijos FROM movimientos m JOIN periodos p ON p.id = m.periodo_id
     WHERE m.presupuesto_id = ? AND m.firebase_uid = ? AND p.estado = 'activo' AND m.tipo IN ('fijo','fijo_x_periodo')`,
    [presupuestoId, uid]
  );
  const [[ahorroRow]] = await db.execute(
    `SELECT COALESCE(SUM(sub.total), 0) AS total_ahorrado FROM (
       SELECT g.id, COALESCE(SUM(CASE WHEN m.pagado=1 THEN m.monto_pagado_real ELSE 0 END), 0)
              + COALESCE((SELECT SUM(a.monto) FROM aportaciones_ahorro a WHERE a.gasto_id = g.id), 0) AS total
       FROM gastos g LEFT JOIN movimientos m ON m.gasto_id = g.id
       WHERE g.firebase_uid = ? AND g.tipo = 'ahorro' GROUP BY g.id
     ) sub`, [uid]
  );
  const gastos_fijos    = parseFloat(fijoRow.gastos_fijos);
  const total_ahorrado  = parseFloat(ahorroRow.total_ahorrado);
  const obj1 = Math.round(gastos_fijos * 100) / 100;
  const obj2 = Math.round(gastos_fijos * 2 * 100) / 100;
  const obj3 = Math.round(gastos_fijos * 6 * 100) / 100;
  let nivel_actual = 0;
  if (total_ahorrado >= obj3) nivel_actual = 3;
  else if (total_ahorrado >= obj2) nivel_actual = 2;
  else if (total_ahorrado >= obj1) nivel_actual = 1;
  return { total_ahorrado, gastos_fijos_un_periodo: gastos_fijos, objetivo_nivel1: obj1, objetivo_nivel2: obj2, objetivo_nivel3: obj3, nivel_actual };
}

async function _aiToolDeudas(uid) {
  const [rows] = await db.execute(
    `SELECT id, nombre, tipo, tasa_interes_mensual, pago_minimo, cuota_fija, es_letra, monto_pendiente
     FROM deudas WHERE firebase_uid = ? AND activa = 1 ORDER BY tasa_interes_mensual DESC`,
    [uid]
  );
  return {
    total_deudas: rows.length,
    deudas: rows.map(d => ({
      id: d.id,
      nombre: d.nombre,
      tipo: d.tipo,
      es_letra: !!d.es_letra,
      tasa_interes_mensual_pct: Number(d.tasa_interes_mensual || 0),
      pago_mensual: d.es_letra ? Number(d.cuota_fija || 0) : Number(d.pago_minimo || 0),
      monto_pendiente: Number(d.monto_pendiente || 0),
    })),
  };
}

async function _aiToolClasificacion(presupuestoId, uid) {
  try {
    const periodo = await getPeriodoActivo(presupuestoId, uid);
    const [[presRow]] = await db.execute(`SELECT monto_total FROM presupuestos WHERE id = ? AND firebase_uid = ?`, [presupuestoId, uid]);
    if (!presRow) return { error: 'Presupuesto no encontrado' };
    const [rows] = await db.execute(
      `SELECT COALESCE(clasificacion,'sin_clasificar') AS clasificacion, COUNT(*) AS cantidad, SUM(monto) AS total
       FROM movimientos WHERE presupuesto_id = ? AND periodo_id = ? AND firebase_uid = ? GROUP BY clasificacion`,
      [presupuestoId, periodo.id, uid]
    );
    const montoTotal = Number(presRow.monto_total);
    const dist = {};
    rows.forEach(r => {
      dist[r.clasificacion] = {
        total: parseFloat(Number(r.total).toFixed(2)),
        cantidad: Number(r.cantidad),
        pct: montoTotal > 0 ? parseFloat((Number(r.total) / montoTotal * 100).toFixed(1)) : 0,
      };
    });
    return { distribucion: dist, monto_total_presupuesto: montoTotal };
  } catch (e) { return { error: e.message }; }
}

async function _aiToolGastosPeriodo(presupuestoId, uid) {
  try {
    const periodo = await getPeriodoActivo(presupuestoId, uid);
    const [movs] = await db.execute(
      `SELECT descripcion, categoria, clasificacion, tipo, monto, monto_pagado_real, pagado
       FROM movimientos WHERE presupuesto_id = ? AND periodo_id = ? AND firebase_uid = ? ORDER BY monto DESC LIMIT 50`,
      [presupuestoId, periodo.id, uid]
    );
    return {
      periodo_id: periodo.id,
      fecha_inicio: periodo.fecha_inicio,
      fecha_fin: periodo.fecha_fin,
      gastos: movs.map(m => ({
        descripcion: m.descripcion,
        categoria: m.categoria,
        clasificacion: m.clasificacion,
        tipo: m.tipo,
        monto: Number(m.monto),
        monto_pagado: Number(m.monto_pagado_real || 0),
        pagado: !!m.pagado,
      })),
    };
  } catch (e) { return { error: e.message }; }
}

async function _aiToolHistorial(presupuestoId, uid, n) {
  const limite = Math.min(Math.max(Number(n) || 3, 1), 6);
  const [rows] = await db.execute(
    `SELECT p.numero_periodo, p.fecha_inicio, p.fecha_fin,
       COALESCE(SUM(CASE WHEN m.tipo IN ('fijo','fijo_x_periodo') AND m.pagado=1 THEN COALESCE(m.monto_pagado_real, m.monto) ELSE 0 END), 0) AS total_fijo,
       COALESCE(SUM(CASE WHEN m.tipo='no fijo' AND m.pagado=1 THEN COALESCE(m.monto_pagado_real, m.monto) ELSE 0 END), 0) AS total_variable,
       COALESCE(SUM(CASE WHEN m.tipo='ahorro' AND m.pagado=1 THEN COALESCE(m.monto_pagado_real, m.monto) ELSE 0 END), 0) AS total_ahorro,
       COALESCE(SUM(CASE WHEN m.pagado=1 THEN COALESCE(m.monto_pagado_real, m.monto) ELSE 0 END), 0) AS total_gastado
     FROM periodos p LEFT JOIN movimientos m ON m.periodo_id = p.id AND m.firebase_uid = p.firebase_uid
     WHERE p.presupuesto_id = ? AND p.firebase_uid = ? AND p.estado = 'cerrado'
     GROUP BY p.id ORDER BY p.numero_periodo DESC LIMIT ${parseInt(limite)}`,
    [presupuestoId, uid]
  );
  return {
    periodos: rows.map(r => ({
      numero: Number(r.numero_periodo),
      fecha_inicio: r.fecha_inicio,
      fecha_fin: r.fecha_fin,
      total_fijo: parseFloat(Number(r.total_fijo).toFixed(2)),
      total_variable: parseFloat(Number(r.total_variable).toFixed(2)),
      total_ahorro: parseFloat(Number(r.total_ahorro).toFixed(2)),
      total_gastado: parseFloat(Number(r.total_gastado).toFixed(2)),
    })),
  };
}

async function _aiToolPatrones(presupuestoId, uid) {
  const [rows] = await db.execute(
    `SELECT g.category, COUNT(DISTINCT p.id) AS periodos_con_gasto, COUNT(*) AS total_registros,
       ROUND(SUM(g.amount), 2) AS monto_total, ROUND(AVG(g.amount), 2) AS monto_promedio
     FROM gustitos g
     JOIN periodos p ON (g.spent_at >= p.fecha_inicio AND g.spent_at <= p.fecha_fin AND p.presupuesto_id = ? AND p.firebase_uid = ?)
     WHERE g.budget_id = ? AND g.user_id = ? AND g.deleted_at IS NULL AND g.category IS NOT NULL AND g.category != ''
     GROUP BY g.category HAVING periodos_con_gasto >= 2 ORDER BY periodos_con_gasto DESC, monto_total DESC`,
    [presupuestoId, uid, presupuestoId, uid]
  );
  return {
    patrones: rows.map(r => ({
      categoria: r.category,
      periodos: Number(r.periodos_con_gasto),
      registros: Number(r.total_registros),
      monto_total: Number(r.monto_total),
      monto_promedio: Number(r.monto_promedio),
    })),
  };
}

// =============================================================================
// MÓDULO DE ACCIONES — proponer → confirmar (determinístico) → ejecutar
// =============================================================================

async function _aiToolProponerAccion(uid, tipo, parametros, resumen) {
  if (!['registrar_pago','marcar_pagado','crear_gasto','abonar_deuda'].includes(tipo))
    return { error: `Tipo de acción desconocido: ${tipo}` };
  const monto = parametros.monto;
  if (monto !== undefined && (isNaN(Number(monto)) || Number(monto) <= 0))
    return { error: 'El monto debe ser un número mayor a 0' };

  const [r] = await db.execute(
    `INSERT INTO acciones_pendientes (firebase_uid, tipo, parametros, resumen_para_usuario, status)
     VALUES (?, ?, ?, ?, 'pendiente')`,
    [uid, tipo, JSON.stringify(parametros), resumen]
  );
  return {
    accion_id: r.insertId,
    tipo, resumen_para_usuario: resumen,
    instruccion: 'Tarjeta de confirmación enviada al usuario. NO ejecutes la acción — espera a que el usuario toque [Confirmar] o [Cancelar].',
  };
}

// --- Ejecutores determinísticos (sin LLM) — solo llamados desde /acciones/:id/confirmar ---

async function _ejecutarCrearGasto(uid, p) {
  const anio = Number(p.anio) || new Date().getFullYear();
  const mes  = Number(p.mes)  || (new Date().getMonth() + 1);
  const [[mesRow]] = await db.execute(
    `SELECT id FROM meses_financieros WHERE firebase_uid = ? AND anio = ? AND mes = ?`, [uid, anio, mes]
  );
  if (!mesRow) throw new Error(`No hay estado financiero para ${anio}/${mes}. Genera el estado anual primero.`);

  const fecha    = p.fecha || new Date().toISOString().slice(0, 10);
  const tipo     = p.tipo  || 'variable';
  const nombre   = (p.nombre || p.descripcion || '').trim();
  const categoria = p.categoria || 'otro';
  const esHormiga = (tipo === 'no_presupuestado' && Number(p.monto) <= 25) ? 1 : 0;
  const montoNum  = parseFloat(Number(p.monto).toFixed(2));

  // Resolver definition_id igual que POST /registros
  let definitionId = null;
  if (tipo !== 'fijo') {
    const [[existingDef]] = await db.execute(
      `SELECT id FROM expense_definitions WHERE firebase_uid = ? AND nombre = ? AND categoria = ? AND activo = 1`,
      [uid, nombre, categoria]
    );
    if (existingDef) {
      definitionId = existingDef.id;
    } else {
      const [newDef] = await db.execute(
        `INSERT INTO expense_definitions (firebase_uid, nombre, categoria, tipo_habitual) VALUES (?, ?, ?, ?)`,
        [uid, nombre, categoria, tipo]
      );
      definitionId = newDef.insertId;
    }
  }

  // origen_* debe venir explícito en parametros (Claude lo obtiene con get_compromisos_mes)
  const [r] = await db.execute(
    `INSERT INTO registros_gasto
       (firebase_uid, mes_id, anio, mes, tipo, categoria, nombre, monto, fecha,
        pagado, origen_fijo_id, origen_variable_id, origen_deuda_id, definition_id, es_hormiga)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?, ?, ?, ?)`,
    [uid, mesRow.id, anio, mes, tipo, categoria, nombre, montoNum, fecha,
     p.origen_fijo_id || null, p.origen_variable_id || null, p.origen_deuda_id || null, definitionId, esHormiga]
  );
  await _actualizarTotalesMes(mesRow.id, uid);
  _generarAlertasMes(uid, anio, mes).catch(() => {});
  return { registro_id: r.insertId, nombre, monto: montoNum, fecha, categoria, tipo };
}

async function _ejecutarRegistrarPago(uid, p) {
  // Alias: registrar_pago = crear_gasto (inserta en registros_gasto)
  return _ejecutarCrearGasto(uid, { ...p, tipo: p.tipo || 'fijo' });
}

async function _ejecutarMarcarPagado(uid, p) {
  // Marca un gasto fijo del perfil como pagado en el mes actual
  const [[gasto]] = await db.execute(
    `SELECT * FROM user_gastos_fijos WHERE id = ? AND firebase_uid = ?`, [p.gasto_fijo_id, uid]
  );
  if (!gasto) throw new Error('Gasto fijo no encontrado');
  return _ejecutarCrearGasto(uid, {
    anio: p.anio, mes: p.mes,
    nombre: p.nombre || gasto.descripcion,
    monto: p.monto  || gasto.monto_mensual,
    categoria: gasto.tipo || 'otro',
    tipo: 'fijo',
    fecha: p.fecha || new Date().toISOString().slice(0, 10),
    origen_fijo_id: gasto.id,
  });
}

async function _ejecutarAbonarDeuda(uid, p) {
  const [[deuda]] = await db.execute(
    `SELECT id, nombre, monto_pendiente, activa FROM deudas WHERE id = ? AND firebase_uid = ?`,
    [p.deuda_id, uid]
  );
  if (!deuda || !deuda.activa) throw new Error('Deuda no encontrada o no activa');

  const montoNum        = parseFloat(Number(p.monto).toFixed(2));
  const pendienteAntes  = Number(deuda.monto_pendiente);
  const nuevoPendiente  = parseFloat(Math.max(0, pendienteAntes - montoNum).toFixed(2));
  const saldada         = nuevoPendiente === 0;

  // Actualizar monto_pendiente en deudas
  await db.execute(
    `UPDATE deudas SET monto_pendiente = ?, activa = ? WHERE id = ? AND firebase_uid = ?`,
    [nuevoPendiente, saldada ? 0 : 1, p.deuda_id, uid]
  );

  // Registrar el abono en registros_gasto para historial y alertas
  const anio = Number(p.anio) || new Date().getFullYear();
  const mes  = Number(p.mes)  || (new Date().getMonth() + 1);
  const [[mesRow]] = await db.execute(
    `SELECT id FROM meses_financieros WHERE firebase_uid = ? AND anio = ? AND mes = ?`, [uid, anio, mes]
  );
  if (mesRow) {
    const fecha = p.fecha || new Date().toISOString().slice(0, 10);
    await db.execute(
      `INSERT INTO registros_gasto (firebase_uid, mes_id, anio, mes, tipo, categoria, nombre, monto, fecha, pagado, origen_deuda_id)
       VALUES (?, ?, ?, ?, 'fijo', 'deudas', ?, ?, ?, 1, ?)`,
      [uid, mesRow.id, anio, mes, `Abono ${deuda.nombre}`, montoNum, fecha, p.deuda_id]
    );
    await _actualizarTotalesMes(mesRow.id, uid);
    _generarAlertasMes(uid, anio, mes).catch(() => {});
  }

  return {
    deuda_nombre: deuda.nombre,
    monto_abonado: montoNum,
    monto_pendiente_antes: pendienteAntes,
    monto_pendiente_ahora: nuevoPendiente,
    saldada,
  };
}

// --- Tool: get_compromisos_mes — lista fijos, variables presupuestadas y deudas con IDs ---

async function _aiToolCompromisosMes(uid) {
  const [fijos] = await db.execute(
    `SELECT id AS gasto_fijo_id, descripcion AS nombre, monto_mensual, tipo, dia_pago, dia_pago_2
     FROM user_gastos_fijos WHERE firebase_uid = ? AND activo = 1 ORDER BY descripcion`, [uid]
  );
  const [variables] = await db.execute(
    `SELECT id AS origen_variable_id, nombre, categoria, monto_estimado AS monto_mensual
     FROM gastos_variables_base WHERE firebase_uid = ? AND activo = 1 ORDER BY nombre`, [uid]
  );
  const [deudas] = await db.execute(
    `SELECT id AS deuda_id, nombre, tipo,
            IF(es_letra=1, cuota_fija, pago_minimo) AS cuota_mensual, monto_pendiente
     FROM deudas WHERE firebase_uid = ? AND activa = 1 AND monto_pendiente > 0 ORDER BY nombre`, [uid]
  );
  return {
    fijos: fijos.map(f => ({
      gasto_fijo_id: f.gasto_fijo_id,
      nombre: f.nombre,
      monto_mensual: Number(f.monto_mensual),
      tipo: f.tipo,
      dia_pago: f.dia_pago,
    })),
    variables_base: variables.map(v => ({
      origen_variable_id: v.origen_variable_id,
      nombre: v.nombre,
      categoria: v.categoria,
      monto_mensual: Number(v.monto_mensual),
    })),
    deudas: deudas.map(d => ({
      deuda_id: d.deuda_id,
      nombre: d.nombre,
      tipo: d.tipo,
      cuota_mensual: Number(d.cuota_mensual),
      monto_pendiente: Number(d.monto_pendiente),
    })),
    instruccion: 'Usa estos IDs directamente en parametros de proponer_accion. Si el item pedido no está en ninguna lista, pregunta al usuario antes de crear algo nuevo.',
  };
}

// --- Tool: get_presupuesto_actual — resuelve período activo sin pedir IDs al usuario ---

async function _aiToolPresupuestoActual(uid) {
  const ahora  = new Date();
  const anio   = ahora.getFullYear();
  const mes    = ahora.getMonth() + 1;
  const dia    = ahora.getDate();
  const quincena = dia <= 15 ? 1 : 2;
  const ML = ['','Enero','Febrero','Marzo','Abril','Mayo','Junio','Julio','Agosto','Septiembre','Octubre','Noviembre','Diciembre'];

  // Modelo nuevo: ¿existe este mes en meses_financieros?
  const [[mesRow]] = await db.execute(
    `SELECT id, ingreso_estimado, fijos_estimados, variables_estimadas, remanente_estimado
     FROM meses_financieros WHERE firebase_uid = ? AND anio = ? AND mes = ?`,
    [uid, anio, mes]
  );

  // Modelo legado: presupuesto activo más reciente
  const [[presLegado]] = await db.execute(
    `SELECT p.id, p.nombre, p.tipo_periodo, p.monto_total,
            per.id AS periodo_id, per.numero_periodo, per.fecha_inicio, per.fecha_fin, per.estado
     FROM presupuestos p
     LEFT JOIN periodos per ON per.presupuesto_id = p.id AND per.estado = 'activo' AND per.firebase_uid = p.firebase_uid
     WHERE p.firebase_uid = ? ORDER BY p.id DESC LIMIT 1`,
    [uid]
  );

  // ¿Existe el estado financiero anual?
  const [[efa]] = await db.execute(
    `SELECT id FROM estado_financiero_anual WHERE firebase_uid = ? AND anio = ?`, [uid, anio]
  );

  const diasEnMes = new Date(anio, mes, 0).getDate();
  const diasRestantesQ = quincena === 1 ? 15 - dia : diasEnMes - dia;
  const fechaInicioQ = quincena === 1
    ? `${anio}-${String(mes).padStart(2,'0')}-01`
    : `${anio}-${String(mes).padStart(2,'0')}-16`;
  const fechaFinQ = quincena === 1
    ? `${anio}-${String(mes).padStart(2,'0')}-15`
    : `${anio}-${String(mes).padStart(2,'0')}-${diasEnMes}`;

  return {
    anio, mes, mes_label: ML[mes],
    quincena_actual: quincena,
    fecha_inicio_quincena: fechaInicioQ,
    fecha_fin_quincena: fechaFinQ,
    dias_restantes_quincena: Math.max(0, diasRestantesQ),
    modelo_nuevo: mesRow ? {
      mes_id: mesRow.id,
      ingreso_estimado: Number(mesRow.ingreso_estimado),
      fijos_estimados: Number(mesRow.fijos_estimados),
      variables_estimadas: Number(mesRow.variables_estimadas),
      remanente_estimado: Number(mesRow.remanente_estimado),
      tiene_estado_anual: !!efa,
    } : null,
    modelo_legado: presLegado ? {
      presupuesto_id: presLegado.id,
      nombre: presLegado.nombre,
      tipo_periodo: presLegado.tipo_periodo,
      monto_total: Number(presLegado.monto_total),
      periodo_activo_id: presLegado.periodo_id || null,
      numero_periodo: presLegado.numero_periodo || null,
    } : null,
    instruccion: `Usa anio=${anio}&mes=${mes} para consultas del modelo nuevo. Usa presupuesto_id=${presLegado?.id ?? 'no_disponible'} para consultas del modelo legado. Nunca le pidas estos IDs al usuario.`,
  };
}

// --- Tool: reportar_brecha_capacidad — registra gaps y genera prompts para Claude Code ---

function _aiToolReportarBrecha({ lo_que_pidio_usuario, por_que_no_se_puede, que_haria_falta, tipo_brecha, accion_tomada }) {
  const prompt = `## Brecha de capacidad — Asesor IA Salarying

**Usuario pidió:** ${lo_que_pidio_usuario}
**Por qué no se puede:** ${por_que_no_se_puede}
**Qué haría falta:** ${que_haria_falta}
**Tipo:** ${tipo_brecha === 'total' ? 'Total (ninguna tool sirve)' : 'Aproximada (existe alternativa parcial)'}
**Acción tomada:** ${accion_tomada}

### Prompt para implementar en Claude Code:
Agrega al módulo IA de Salarying (backend/server.js) la siguiente tool de solo lectura:
- **Funcionalidad:** ${que_haria_falta}
- **Caso de uso:** ${lo_que_pidio_usuario}
- **Restricciones:** solo lectura, no escribe a BD, firebase_uid siempre requerido, inyectar resultado en AI_TOOLS y _aiEjecutarTool
- Seguir el mismo patrón de las tools existentes (ver _aiToolRegistrosMes como ejemplo)`.trim();

  _logInfo('/ai/brecha', `tipo:${tipo_brecha} | ${lo_que_pidio_usuario.slice(0,60)}`, '-');

  return {
    registrado: true,
    tipo_brecha,
    accion_tomada,
    modo_dev: true,
    prompt_claude_code: prompt,
    mensaje_usuario: tipo_brecha === 'total'
      ? 'Aún no tengo esa función. Aquí abajo está el prompt para que José lo construya.'
      : `Usé una versión aproximada (${accion_tomada}). El prompt para la versión exacta está aquí abajo.`,
  };
}

// --- Implementaciones de tools del modelo nuevo (registros_gasto / meses_financieros) ---

async function _aiToolRegistrosMes(uid, anio, mes) {
  const [[mesRow]] = await db.execute(
    `SELECT id FROM meses_financieros WHERE firebase_uid = ? AND anio = ? AND mes = ?`,
    [uid, anio, mes]
  );
  if (!mesRow) return { error: `Sin datos para ${anio}/${mes}. Genera el estado financiero anual primero.` };

  const [registros] = await db.execute(
    `SELECT descripcion, categoria, tipo, monto, fecha, es_hormiga
     FROM registros_gasto WHERE mes_id = ? AND firebase_uid = ?
     ORDER BY monto DESC LIMIT 60`,
    [mesRow.id, uid]
  );
  const porCat = {};
  let totalF = 0, totalV = 0, totalNP = 0;
  for (const r of registros) {
    const cat = r.categoria || 'otro';
    if (!porCat[cat]) porCat[cat] = { fijo: 0, variable: 0, no_presupuestado: 0, total: 0 };
    const k = r.tipo === 'no_presupuestado' ? 'no_presupuestado' : (r.tipo || 'variable');
    porCat[cat][k] = (porCat[cat][k] || 0) + Number(r.monto);
    porCat[cat].total += Number(r.monto);
    if (r.tipo === 'fijo') totalF += Number(r.monto);
    else if (r.tipo === 'no_presupuestado') totalNP += Number(r.monto);
    else totalV += Number(r.monto);
  }
  return {
    anio: Number(anio), mes: Number(mes),
    total_fijo: parseFloat(totalF.toFixed(2)),
    total_variable: parseFloat(totalV.toFixed(2)),
    total_no_presupuestado: parseFloat(totalNP.toFixed(2)),
    total_gastado: parseFloat((totalF + totalV + totalNP).toFixed(2)),
    por_categoria: Object.entries(porCat)
      .map(([cat, v]) => ({ categoria: cat, ...Object.fromEntries(Object.entries(v).map(([k, val]) => [k, parseFloat(Number(val).toFixed(2))])) }))
      .sort((a, b) => b.total - a.total),
    registros: registros.map(r => ({
      descripcion: r.descripcion, categoria: r.categoria,
      tipo: r.tipo, monto: Number(r.monto),
      fecha: r.fecha, es_hormiga: !!r.es_hormiga,
    })),
  };
}

async function _aiToolEstadoMes(uid, anio, mes) {
  const [[mf]] = await db.execute(
    `SELECT * FROM meses_financieros WHERE firebase_uid = ? AND anio = ? AND mes = ?`,
    [uid, anio, mes]
  );
  if (!mf) return { error: `Sin estado financiero para ${anio}/${mes}.` };

  const [[tot]] = await db.execute(
    `SELECT COALESCE(SUM(CASE WHEN tipo='fijo' THEN monto ELSE 0 END),0) AS f_real,
            COALESCE(SUM(CASE WHEN tipo='variable' THEN monto ELSE 0 END),0) AS v_real,
            COALESCE(SUM(CASE WHEN tipo='no_presupuestado' THEN monto ELSE 0 END),0) AS np_real,
            COALESCE(SUM(monto),0) AS total_real
     FROM registros_gasto WHERE mes_id = ? AND firebase_uid = ?`,
    [mf.id, uid]
  );
  const ing = Number(mf.ingreso_real) || Number(mf.ingreso_estimado);
  const totalReal = parseFloat(tot.total_real);
  return {
    anio: Number(mf.anio), mes: Number(mf.mes),
    ingreso_estimado: Number(mf.ingreso_estimado),
    ingreso_real: ing,
    fijos_estimados: Number(mf.fijos_estimados),
    fijos_reales: parseFloat(tot.f_real),
    variables_estimadas: Number(mf.variables_estimadas),
    variables_reales: parseFloat(tot.v_real),
    no_presupuestados_reales: parseFloat(tot.np_real),
    total_gastado_real: totalReal,
    remanente_estimado: Number(mf.remanente_estimado),
    remanente_real: parseFloat((ing - totalReal).toFixed(2)),
    sobre_presupuesto: totalReal > ing,
    pct_ejecutado: ing > 0 ? parseFloat((totalReal / ing * 100).toFixed(1)) : 0,
  };
}

async function _aiToolAlertasMes(uid, anio, mes) {
  const [rows] = await db.execute(
    `SELECT tipo, nivel, titulo, mensaje, accion_sugerida, categoria, leida
     FROM alertas_financieras
     WHERE firebase_uid = ? AND anio = ? AND mes = ?
     ORDER BY FIELD(nivel,'danger','warning','info') LIMIT 10`,
    [uid, anio, mes]
  );
  return {
    total: rows.length,
    no_leidas: rows.filter(a => !a.leida).length,
    alertas: rows.map(a => ({
      tipo: a.tipo, nivel: a.nivel, titulo: a.titulo,
      mensaje: a.mensaje, accion: a.accion_sugerida, categoria: a.categoria,
    })),
  };
}

async function _aiToolVariablesBase(uid) {
  const [rows] = await db.execute(
    `SELECT nombre, categoria, monto_estimado
     FROM gastos_variables_base WHERE firebase_uid = ? AND activo = 1
     ORDER BY monto_estimado DESC`,
    [uid]
  );
  const porCat = {};
  for (const r of rows) {
    const cat = r.categoria || 'otro';
    porCat[cat] = (porCat[cat] || 0) + Number(r.monto_estimado);
  }
  return {
    total_presupuestado: parseFloat(rows.reduce((s, r) => s + Number(r.monto_estimado), 0).toFixed(2)),
    por_categoria: Object.entries(porCat)
      .map(([cat, total]) => ({ categoria: cat, presupuestado: parseFloat(total.toFixed(2)) }))
      .sort((a, b) => b.presupuestado - a.presupuestado),
    detalle: rows.map(r => ({ nombre: r.nombre, categoria: r.categoria, monto_estimado: Number(r.monto_estimado) })),
  };
}

async function _aiToolEstadoAnual(uid, anio) {
  const [[efa]] = await db.execute(
    `SELECT * FROM estado_financiero_anual WHERE firebase_uid = ? AND anio = ?`, [uid, anio]
  );
  if (!efa) return { error: `Sin estado financiero anual para ${anio}.` };

  const [meses] = await db.execute(
    `SELECT mf.mes, mf.ingreso_estimado, mf.ingreso_real, mf.fijos_estimados, mf.fijos_reales,
            mf.variables_estimadas, mf.variables_reales, mf.remanente_estimado, mf.remanente_real,
            COALESCE(SUM(rg.monto),0) AS total_registrado, COUNT(rg.id) AS num_registros
     FROM meses_financieros mf
     LEFT JOIN registros_gasto rg ON rg.mes_id = mf.id AND rg.firebase_uid = mf.firebase_uid
     WHERE mf.firebase_uid = ? AND mf.anio = ?
     GROUP BY mf.id ORDER BY mf.mes ASC`,
    [uid, anio]
  );
  const ML = ['','Ene','Feb','Mar','Abr','May','Jun','Jul','Ago','Sep','Oct','Nov','Dic'];
  return {
    anio: Number(anio),
    ingreso_anual_estimado: Number(efa.ingreso_anual_estimado),
    fijos_anuales_estimados: Number(efa.fijos_anuales_estimados),
    variables_anuales_estimadas: Number(efa.variables_anuales_estimadas),
    remanente_anual_estimado: Number(efa.remanente_anual_estimado),
    meses: meses.map(m => ({
      mes: Number(m.mes), label: ML[m.mes],
      ingreso_estimado: Number(m.ingreso_estimado),
      ingreso_real: Number(m.ingreso_real) || 0,
      fijos_estimados: Number(m.fijos_estimados), fijos_reales: Number(m.fijos_reales),
      variables_estimadas: Number(m.variables_estimadas), variables_reales: Number(m.variables_reales),
      total_registrado: parseFloat(Number(m.total_registrado).toFixed(2)),
      num_registros: Number(m.num_registros),
    })),
  };
}

// --- Ejecutor central: despacha tool_name → función de BD ---

async function _aiEjecutarTool(toolName, input, requestCache) {
  const cacheKey = `${toolName}:${JSON.stringify(input)}`;
  if (requestCache.has(cacheKey)) return requestCache.get(cacheKey);

  const uid = input.firebase_uid;
  const pid = input.presupuesto_id;
  let result;
  try {
    switch (toolName) {
      case 'get_compromisos_mes':       result = await _aiToolCompromisosMes(uid); break;
      case 'get_presupuesto_actual':    result = await _aiToolPresupuestoActual(uid); break;
      case 'reportar_brecha_capacidad': result = _aiToolReportarBrecha(input); break;
      case 'proponer_accion':           result = await _aiToolProponerAccion(uid, input.tipo, input.parametros || {}, input.resumen_para_usuario || ''); break;
      case 'get_dashboard_resumen':    result = await _aiToolDashboard(uid); break;
      case 'get_income':               result = await _aiToolIncome(uid); break;
      case 'get_capacidad_real':       result = await _aiToolCapacidad(pid, uid); break;
      case 'get_fondo_seguridad':      result = await _aiToolFondoSeguridad(pid, uid); break;
      case 'get_deudas':               result = await _aiToolDeudas(uid); break;
      case 'get_clasificacion_gastos': result = await _aiToolClasificacion(pid, uid); break;
      case 'get_gastos_periodo':       result = await _aiToolGastosPeriodo(pid, uid); break;
      case 'get_historial_periodos':   result = await _aiToolHistorial(pid, uid, input.n); break;
      case 'get_patrones_gustitos':    result = await _aiToolPatrones(pid, uid); break;
      case 'get_registros_mes':        result = await _aiToolRegistrosMes(uid, input.anio, input.mes); break;
      case 'get_estado_mes':           result = await _aiToolEstadoMes(uid, input.anio, input.mes); break;
      case 'get_alertas_mes':          result = await _aiToolAlertasMes(uid, input.anio, input.mes); break;
      case 'get_variables_base':       result = await _aiToolVariablesBase(uid); break;
      case 'get_estado_anual':         result = await _aiToolEstadoAnual(uid, input.anio); break;
      default:                         result = { error: `Tool desconocida: ${toolName}` };
    }
  } catch (e) { result = { error: e.message }; }

  requestCache.set(cacheKey, result);
  return result;
}

// --- Loop de tool_use: envía → ejecuta → repite hasta respuesta texto ---

async function _aiLoopConTools(mensajes, tools, maxTokens = 1024, model = AI_MODEL) {
  const claude  = _getAnthropic();
  const sysPrompt = _aiGetSystemPrompt();
  const loggedTools = [];
  const requestCache = new Map();
  let currentMessages = [...mensajes];
  let accionPendiente = null; // Captura el resultado de proponer_accion si Claude la llama

  let response = await claude.messages.create({
    model, max_tokens: maxTokens,
    system: sysPrompt, messages: currentMessages, tools,
  });

  while (response.stop_reason === 'tool_use') {
    const toolBlocks = response.content.filter(b => b.type === 'tool_use');
    loggedTools.push(...toolBlocks.map(b => b.name));

    const toolResults = await Promise.all(
      toolBlocks.map(async block => {
        const result = await _aiEjecutarTool(block.name, block.input, requestCache);
        if (block.name === 'proponer_accion' && result.accion_id) accionPendiente = result;
        return { type: 'tool_result', tool_use_id: block.id, content: JSON.stringify(result) };
      })
    );

    currentMessages = [
      ...currentMessages,
      { role: 'assistant', content: response.content },
      { role: 'user', content: toolResults },
    ];

    response = await claude.messages.create({
      model, max_tokens: maxTokens,
      system: sysPrompt, messages: currentMessages, tools,
    });
  }

  const texto = response.content.find(b => b.type === 'text')?.text || '';
  return { respuesta: texto, tools_usadas: loggedTools, tokens: response.usage?.output_tokens || 0, accion_pendiente: accionPendiente };
}

// POST /ai/diagnostico
// body: { firebase_uid, presupuesto_id?, force? }
app.post('/ai/diagnostico', async (req, res) => {
  const { firebase_uid, presupuesto_id, force } = req.body;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  if (!_aiCheckRate(firebase_uid)) return res.status(429).json({ error: 'Demasiadas consultas. Espera unos minutos.' });

  // Retornar resultado cacheado si existe y no se fuerza regeneración
  const cacheKey = `diag:${firebase_uid}`;
  const cached = _aiDiagCache.get(cacheKey);
  if (cached && Date.now() < cached.expires && !force) {
    return res.json({ ...cached.data, desde_cache: true });
  }

  try {
    const anioActual = new Date().getFullYear();
    const mesActual  = new Date().getMonth() + 1;
    let prompt = `Analiza el estado financiero del usuario (uid: ${firebase_uid}) y detecta qué información mínima le falta para entender su situación con claridad.`;
    if (presupuesto_id) prompt += ` Tiene además un presupuesto antiguo ID ${presupuesto_id}.`;
    prompt += `

Revisa usando las tools disponibles (empieza por get_dashboard_resumen, get_income y get_alertas_mes para ${anioActual}/${mesActual}):
1. Si tiene ingreso registrado — sin ingreso no se puede calcular capacidad real.
2. Si tiene deudas con interés activas — van SIEMPRE primero si existen.
3. Si tiene gastos variables base definidos (presupuesto por categoría).
4. Si tiene alertas activas sin atender este mes.
5. Si el estado del mes actual tiene registros reales o está vacío.

Devuelve una lista de **3 a 5 brechas** priorizadas (la más crítica primero). Para cada brecha:
- **Qué falta** — en palabras simples, sin jerga.
- Por qué importa para su situación real.
- El siguiente paso concreto (pantalla o botón de la app).

Si no hay brechas: "Tu perfil está completo, tienes todo para entender tus finanzas."`;

    const { respuesta, tools_usadas } = await _aiLoopConTools(
      [{ role: 'user', content: prompt }], AI_TOOLS, 1400
    );
    const data = { diagnostico: respuesta, tools_usadas };
    _aiDiagCache.set(cacheKey, { data, expires: Date.now() + 3600000 });
    _logInfo('/ai/diagnostico', `tools:[${tools_usadas.join(',')}]`, firebase_uid);
    res.json(data);
  } catch (e) {
    console.error('AI /diagnostico:', e.message);
    res.status(500).json({ error: e.message });
  }
});

// POST /ai/chat
// body: { firebase_uid, mensaje, presupuesto_id?, historial? }
app.post('/ai/chat', async (req, res) => {
  const { firebase_uid, mensaje, presupuesto_id, historial = [] } = req.body;
  if (!firebase_uid || !mensaje) return res.status(400).json({ error: 'firebase_uid y mensaje requeridos' });
  if (!_aiCheckRate(firebase_uid)) return res.status(429).json({ error: 'Demasiadas consultas. Espera unos minutos.' });
  try {
    // Pre-resolver el período activo para que Claude no necesite llamar get_presupuesto_actual
    // explícitamente en cada mensaje (ahorra un round-trip de ~500ms).
    let contextoperiodo = '';
    try {
      const pa = await _aiToolPresupuestoActual(firebase_uid);
      contextoperiodo = pa.instruccion;
    } catch (_) {}

    const contextoMsg = `[uid=${firebase_uid} | ${contextoperiodo}] ${mensaje}`;

    const mensajes = [
      ...historial.slice(-6),
      { role: 'user', content: contextoMsg },
    ];

    const { respuesta, tools_usadas, tokens, accion_pendiente } = await _aiLoopConTools(mensajes, AI_TOOLS, 2000, AI_MODEL_SONNET);
    _logInfo('/ai/chat', `tools:[${tools_usadas.join(',')}] tokens:${tokens}${accion_pendiente ? ` accion:${accion_pendiente.accion_id}` : ''}`, firebase_uid);
    res.json({ respuesta, tools_usadas, accion_pendiente: accion_pendiente || null });
  } catch (e) {
    console.error('AI /chat error:', e.message);
    res.status(500).json({ error: e.message });
  }
});

// POST /ai/categorizar
// body: { firebase_uid, descripcion, monto }
// NO escribe a BD — devuelve sugerencia para que el usuario confirme en UI.
app.post('/ai/categorizar', async (req, res) => {
  const { firebase_uid, descripcion, monto } = req.body;
  if (!firebase_uid || !descripcion) return res.status(400).json({ error: 'firebase_uid y descripcion requeridos' });
  try {
    const montoNum = Number(monto) || 0;
    const prompt = `Analiza este gasto y sugiere cómo categorizarlo. Responde ÚNICAMENTE con un objeto JSON válido, sin texto adicional.

Gasto: "${descripcion}"
Monto: $${montoNum.toFixed(2)}

JSON esperado:
{
  "categoria": "una de: Comida, Transporte, Entretenimiento, Salud, Servicios, Educacion, Ropa, Ahorro, Otro",
  "clasificacion": "una de: esencial, importante, flexible",
  "es_hormiga": true o false,
  "razon": "explicación breve en 1 línea"
}

Criterios de clasificación:
- esencial: necesidades básicas (comida básica, transporte al trabajo, salud, servicios del hogar)
- importante: mejora calidad de vida pero no es urgente (ropa necesaria, educación)
- flexible: discrecional, puede posponerse (entretenimiento, gustos, salidas)
- es_hormiga: true si monto <= $25 Y la descripción sugiere gasto frecuente/pequeño (café, snack, taxi corto, propina)`;

    const claude = _getAnthropic();
    const response = await claude.messages.create({
      model: AI_MODEL,
      max_tokens: 300,
      system: AI_SYSTEM_PROMPT,
      messages: [{ role: 'user', content: prompt }],
    });

    const texto = response.content.find(b => b.type === 'text')?.text || '{}';
    let sugerencia;
    try {
      const match = texto.match(/\{[\s\S]*\}/);
      sugerencia = JSON.parse(match ? match[0] : texto);
    } catch {
      sugerencia = { categoria: 'Otro', clasificacion: 'flexible', es_hormiga: montoNum <= 25, razon: texto };
    }

    _logInfo('/ai/categorizar', `"${descripcion}" → ${sugerencia.categoria}/${sugerencia.clasificacion}`, firebase_uid);
    res.json({ sugerencia, nota: 'Sugerencia pendiente de confirmación. No se escribe a la BD hasta que el usuario la apruebe.' });
  } catch (e) {
    console.error('AI /categorizar error:', e.message);
    res.status(500).json({ error: e.message });
  }
});

// POST /ai/reporte
// body: { firebase_uid, presupuesto_id?, anio?, mes? }
app.post('/ai/reporte', async (req, res) => {
  const { firebase_uid, presupuesto_id } = req.body;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  if (!_aiCheckRate(firebase_uid)) return res.status(429).json({ error: 'Demasiadas consultas. Espera unos minutos.' });
  try {
    const anio = Number(req.body.anio) || new Date().getFullYear();
    const mes  = Number(req.body.mes)  || (new Date().getMonth() + 1);

    const prompt = `Genera un reporte financiero narrativo del mes ${mes}/${anio} para el usuario (uid: ${firebase_uid}).

Usa las tools para recopilar:
1. get_dashboard_resumen — score, disponible, deudas
2. get_estado_mes — estimado vs real del mes ${mes}/${anio}
3. get_registros_mes — en qué se fue el dinero realmente
4. get_alertas_mes — alertas activas del mes
5. get_variables_base — presupuesto planeado por categoría
${presupuesto_id ? `6. get_historial_periodos (presupuesto_id=${presupuesto_id}) — tendencia de períodos anteriores` : '6. get_estado_anual — tendencia de los meses anteriores del año'}

Estructura el reporte con estas secciones en **markdown**:

## ¿Cómo vas este mes?
Estado real: cuánto llevas gastado, cuánto queda, score de salud.

## ¿En qué se va el dinero?
Top 3-5 categorías con más gasto. Compara con lo presupuestado si tienes el dato.

## Tendencia
¿Mejor o peor que meses anteriores? Marca con ~ las cifras estimadas.

## Lo más importante ahora
1 o 2 acciones priorizadas. Deudas con interés van primero siempre.

Tono: amigable, directo. Explica cualquier término técnico en la misma oración.`;

    const { respuesta, tools_usadas, tokens } = await _aiLoopConTools(
      [{ role: 'user', content: prompt }], AI_TOOLS, 3000, AI_MODEL_SONNET
    );
    _logInfo('/ai/reporte', `tools:[${tools_usadas.join(',')}] tokens:${tokens}`, firebase_uid);
    res.json({ reporte: respuesta, tools_usadas });
  } catch (e) {
    console.error('AI /reporte error:', e.message);
    res.status(500).json({ error: e.message });
  }
});

// =============================================================================
// MÓDULO DE ACCIONES — endpoints determinísticos (sin LLM)
// =============================================================================

// GET /acciones/pendientes?firebase_uid=
app.get('/acciones/pendientes', async (req, res) => {
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [rows] = await db.execute(
      `SELECT id, tipo, parametros, resumen_para_usuario, status, created_at
       FROM acciones_pendientes
       WHERE firebase_uid = ? AND status = 'pendiente'
         AND created_at > DATE_SUB(NOW(), INTERVAL 24 HOUR)
       ORDER BY created_at DESC`,
      [firebase_uid]
    );
    res.json({ acciones: rows.map(r => ({
      ...r,
      parametros: typeof r.parametros === 'string' ? JSON.parse(r.parametros) : r.parametros,
    }))});
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// POST /acciones/:id/confirmar
app.post('/acciones/:id/confirmar', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.body;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [[accion]] = await db.execute(
      `SELECT * FROM acciones_pendientes WHERE id = ? AND firebase_uid = ? AND status = 'pendiente'`,
      [id, firebase_uid]
    );
    if (!accion) return res.status(404).json({ error: 'Acción no encontrada, ya procesada o cancelada' });

    // Verificar que no haya expirado
    const creadaHace = Date.now() - new Date(accion.created_at).getTime();
    if (creadaHace > 86400000) {
      await db.execute(`UPDATE acciones_pendientes SET status='expirada' WHERE id=?`, [id]);
      return res.status(410).json({ error: 'Esta propuesta expiró (más de 24h). Solicítala de nuevo.' });
    }

    const params = typeof accion.parametros === 'string' ? JSON.parse(accion.parametros) : accion.parametros;
    let resultado;
    switch (accion.tipo) {
      case 'registrar_pago':  resultado = await _ejecutarRegistrarPago(firebase_uid, params); break;
      case 'marcar_pagado':   resultado = await _ejecutarMarcarPagado(firebase_uid, params);  break;
      case 'crear_gasto':     resultado = await _ejecutarCrearGasto(firebase_uid, params);    break;
      case 'abonar_deuda':    resultado = await _ejecutarAbonarDeuda(firebase_uid, params);   break;
      default: return res.status(400).json({ error: `Tipo desconocido: ${accion.tipo}` });
    }

    await db.execute(
      `UPDATE acciones_pendientes SET status='confirmada', executed_at=NOW() WHERE id=?`, [id]
    );
    _logInfo(`/acciones/${id}/confirmar`, `tipo:${accion.tipo}`, firebase_uid);
    res.json({ success: true, tipo: accion.tipo, resultado });
  } catch (e) {
    console.error('confirmar accion:', e.message);
    res.status(500).json({ error: e.message });
  }
});

// POST /acciones/:id/cancelar
app.post('/acciones/:id/cancelar', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.body;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [r] = await db.execute(
      `UPDATE acciones_pendientes SET status='cancelada' WHERE id=? AND firebase_uid=? AND status='pendiente'`,
      [id, firebase_uid]
    );
    if (r.affectedRows === 0) return res.status(404).json({ error: 'Acción no encontrada o ya procesada' });
    res.json({ success: true, cancelada: true });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// POST /ai/nudge
// body: { firebase_uid, anio?, mes? }
// Insight proactivo de 1-2 frases para mostrar en el Dashboard. Rápido (Haiku).
app.post('/ai/nudge', async (req, res) => {
  const { firebase_uid } = req.body;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  if (!_aiCheckRate(firebase_uid)) return res.status(429).json({ error: 'Demasiadas consultas.' });
  try {
    const anio = Number(req.body.anio) || new Date().getFullYear();
    const mes  = Number(req.body.mes)  || (new Date().getMonth() + 1);

    const prompt = `Para el usuario (uid: ${firebase_uid}), mes ${mes}/${anio}:
Consulta get_dashboard_resumen, get_alertas_mes y get_estado_mes.
Luego devuelve UN SOLO insight proactivo de máximo 2 frases. Debe ser:
- Concreto (incluir una cifra real si es posible).
- Accionable (decir qué hacer, no solo describir el problema).
- En español cotidiano, sin jerga.
Ejemplos de estilo: "Llevas $380 gastados de $600 presupuestados — vas bien, pero cuidado con los próximos 10 días." | "Tu deuda del carro tiene 18% mensual — pagarla primero te ahorra ~$45/mes estimado."
Solo devuelve el insight, sin encabezados ni explicaciones.`;

    const { respuesta, tools_usadas } = await _aiLoopConTools(
      [{ role: 'user', content: prompt }], AI_TOOLS, 300
    );
    _logInfo('/ai/nudge', `tools:[${tools_usadas.join(',')}]`, firebase_uid);
    res.json({ nudge: respuesta.trim() });
  } catch (e) {
    console.error('AI /nudge:', e.message);
    res.status(500).json({ error: e.message });
  }
});

// POST /ai/explicar-alerta
// body: { firebase_uid, alerta_id }
// Traduce una alerta del motor de reglas a lenguaje humano + acción personalizada.
app.post('/ai/explicar-alerta', async (req, res) => {
  const { firebase_uid, alerta_id } = req.body;
  if (!firebase_uid || !alerta_id) return res.status(400).json({ error: 'firebase_uid y alerta_id requeridos' });
  if (!_aiCheckRate(firebase_uid)) return res.status(429).json({ error: 'Demasiadas consultas.' });
  try {
    const [[alerta]] = await db.execute(
      `SELECT tipo, nivel, titulo, mensaje, accion_sugerida, categoria, anio, mes
       FROM alertas_financieras WHERE id = ? AND firebase_uid = ?`,
      [alerta_id, firebase_uid]
    );
    if (!alerta) return res.status(404).json({ error: 'Alerta no encontrada' });

    const prompt = `El usuario (uid: ${firebase_uid}) tiene esta alerta financiera del mes ${alerta.mes}/${alerta.anio}:

**${alerta.titulo}** (nivel: ${alerta.nivel})
${alerta.mensaje}
Acción sugerida por la app: ${alerta.accion_sugerida || 'ninguna'}

Usando get_dashboard_resumen y get_estado_mes para ${alerta.anio}/${alerta.mes}, explícale:
1. Por qué esto le afecta a ÉL (con sus números reales, no genéricos).
2. Exactamente qué puede hacer esta semana — algo específico y realista para su ingreso real.

Máximo 3 frases. Tono: directo, como un amigo que sabe de finanzas.`;

    const { respuesta, tools_usadas } = await _aiLoopConTools(
      [{ role: 'user', content: prompt }], AI_TOOLS, 500
    );
    _logInfo('/ai/explicar-alerta', `alerta:${alerta_id} tools:[${tools_usadas.join(',')}]`, firebase_uid);
    res.json({ explicacion: respuesta.trim(), alerta: { titulo: alerta.titulo, nivel: alerta.nivel } });
  } catch (e) {
    console.error('AI /explicar-alerta:', e.message);
    res.status(500).json({ error: e.message });
  }
});

// POST /ai/simular-decision
// body: { firebase_uid, pregunta }
// "¿Qué pasa si...?" — llama al simulador real y explica el resultado en lenguaje humano.
app.post('/ai/simular-decision', async (req, res) => {
  const { firebase_uid, pregunta } = req.body;
  if (!firebase_uid || !pregunta) return res.status(400).json({ error: 'firebase_uid y pregunta requeridos' });
  if (!_aiCheckRate(firebase_uid)) return res.status(429).json({ error: 'Demasiadas consultas.' });
  try {
    // Primero Claude extrae parámetros de la pregunta para saber qué simular
    const extractPrompt = `El usuario pregunta: "${pregunta}"
Usa get_dashboard_resumen y get_deudas para entender su situación actual.
Luego responde en JSON exacto (sin texto adicional):
{
  "tipo": "eliminar_gasto"|"pagar_deuda_hoy"|"extra_pago_deuda"|"nuevo_compromiso"|"cambiar_ingreso",
  "descripcion_escenario": "frase corta de qué se va a simular",
  "gasto_fijo_id": número o null,
  "deuda_id": número o null,
  "extra_mensual": número o null,
  "monto": número o null,
  "nombre": "string o null",
  "nuevo_ingreso": número o null
}`;

    const { respuesta: jsonRaw, tools_usadas: t1 } = await _aiLoopConTools(
      [{ role: 'user', content: extractPrompt }], AI_TOOLS, 400
    );

    let params;
    try {
      const m = jsonRaw.match(/\{[\s\S]*\}/);
      params = JSON.parse(m ? m[0] : jsonRaw);
    } catch { return res.json({ respuesta: 'No pude interpretar esa pregunta. Intenta ser más específico, por ejemplo: "¿Qué pasa si pago $50 extra en mi deuda del carro?"' }); }

    // Llamar al simulador real
    const simRes = await fetch(`http://localhost:${process.env.PORT || 3002}/user/timeline/simular`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ firebase_uid, meses: 12, ...params }),
    });
    const simData = await simRes.json();
    if (simData.error) return res.json({ respuesta: `No pude simular ese escenario: ${simData.error}` });

    // Claude interpreta el resultado
    const interpretPrompt = `El usuario preguntó: "${pregunta}"
El simulador muestra este resultado para los próximos 12 meses:
${JSON.stringify({ descripcion: simData.descripcion_escenario, comparativa: simData.comparativa, meses_resumen: (simData.escenario || []).slice(0, 6) })}

Explica en 2-3 frases en lenguaje simple:
- ¿Vale la pena hacer ese cambio?
- ¿Cuánto dinero se libera o cuánto cuesta?
- ¿Cuándo se nota el impacto?
Usa números reales del resultado. Marca estimados con ~.`;

    const { respuesta, tools_usadas: t2 } = await _aiLoopConTools(
      [{ role: 'user', content: interpretPrompt }], [], 600
    );
    _logInfo('/ai/simular-decision', `tipo:${params.tipo} tools:[${[...t1,...t2].join(',')}]`, firebase_uid);
    res.json({ respuesta: respuesta.trim(), escenario: params.descripcion_escenario });
  } catch (e) {
    console.error('AI /simular-decision:', e.message);
    res.status(500).json({ error: e.message });
  }
});

// =============================================================================
// INICIO DEL SERVIDOR
// =============================================================================
const PORT = process.env.PORT || 3002;
app.listen(PORT, () => console.log(`🚀 Servidor activo en puerto ${PORT}`));
