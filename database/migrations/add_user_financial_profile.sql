-- =============================================================================
-- MIGRACIÓN: Perfil Financiero del Usuario
-- Ingreso y compromisos fijos son realidades de la vida del usuario,
-- no de un presupuesto específico. Se crean una sola vez y persisten.
-- =============================================================================

CREATE TABLE IF NOT EXISTS user_income (
  id INT AUTO_INCREMENT PRIMARY KEY,
  firebase_uid VARCHAR(255) NOT NULL,
  tipo_ingreso ENUM('salario','informal','ocasional','otro') DEFAULT 'salario',
  ingreso_bruto_mensual DECIMAL(10,2) DEFAULT 0,
  desc_seguro    DECIMAL(10,2) DEFAULT 0,
  desc_pension   DECIMAL(10,2) DEFAULT 0,
  desc_impuesto  DECIMAL(10,2) DEFAULT 0,
  desc_otros     DECIMAL(10,2) DEFAULT 0,
  ingreso_neto_mensual DECIMAL(10,2) NOT NULL,
  calcular_automatico TINYINT DEFAULT 0,
  frecuencia_cobro ENUM('mensual','quincenal') DEFAULT 'quincenal',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_user_income (firebase_uid)
);

CREATE TABLE IF NOT EXISTS user_gastos_fijos (
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
  KEY idx_ugf_user (firebase_uid),
  KEY idx_ugf_activo (firebase_uid, activo)
);
