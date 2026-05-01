-- =============================================
-- SCHEMA: presupuestos-backend
-- =============================================

CREATE TABLE IF NOT EXISTS presupuestos (
  id INT PRIMARY KEY AUTO_INCREMENT,
  nombre VARCHAR(255) NOT NULL,
  monto_total DECIMAL(10,2) NOT NULL,
  firebase_uid VARCHAR(255) NOT NULL,
  tipo_periodo ENUM('quincenal','mensual') NOT NULL DEFAULT 'quincenal',
  dia_inicio_periodo INT NOT NULL DEFAULT 1,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_firebase_uid (firebase_uid)
);

CREATE TABLE IF NOT EXISTS periodos (
  id INT PRIMARY KEY AUTO_INCREMENT,
  presupuesto_id INT NOT NULL,
  firebase_uid VARCHAR(255) NOT NULL,
  numero_periodo INT NOT NULL,
  tipo_periodo ENUM('quincenal','mensual') NOT NULL,
  fecha_inicio DATE NOT NULL,
  fecha_fin DATE NOT NULL,
  estado ENUM('activo','cerrado') NOT NULL DEFAULT 'activo',
  closed_at TIMESTAMP NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (presupuesto_id) REFERENCES presupuestos(id) ON DELETE CASCADE,
  INDEX idx_firebase_uid (firebase_uid),
  INDEX idx_presupuesto_estado (presupuesto_id, estado)
);

CREATE TABLE IF NOT EXISTS gastos (
  id INT PRIMARY KEY AUTO_INCREMENT,
  presupuesto_id INT NOT NULL,
  descripcion VARCHAR(255) NOT NULL,
  monto DECIMAL(10,2) NOT NULL,
  tipo ENUM('fijo','no fijo','fijo_x_periodo','ahorro') NOT NULL,
  fecha DATE NOT NULL,
  pagado TINYINT(1) NOT NULL DEFAULT 0,
  firebase_uid VARCHAR(255) NOT NULL,
  numero_quincena INT NULL,
  periodos_restantes INT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (presupuesto_id) REFERENCES presupuestos(id) ON DELETE CASCADE,
  INDEX idx_firebase_uid (firebase_uid),
  INDEX idx_presupuesto_tipo (presupuesto_id, tipo)
);

CREATE TABLE IF NOT EXISTS movimientos (
  id INT PRIMARY KEY AUTO_INCREMENT,
  presupuesto_id INT NOT NULL,
  periodo_id INT NOT NULL,
  gasto_id INT NULL,
  descripcion VARCHAR(255) NOT NULL,
  monto DECIMAL(10,2) NOT NULL,
  tipo ENUM('fijo','no fijo','fijo_x_periodo','ahorro') NOT NULL,
  pagado TINYINT(1) NOT NULL DEFAULT 0,
  monto_pagado_real DECIMAL(10,2) NULL,
  pagado_por_uid VARCHAR(255) NULL,
  fecha_pagado TIMESTAMP NULL,
  firebase_uid VARCHAR(255) NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (presupuesto_id) REFERENCES presupuestos(id) ON DELETE CASCADE,
  FOREIGN KEY (periodo_id) REFERENCES periodos(id) ON DELETE CASCADE,
  FOREIGN KEY (gasto_id) REFERENCES gastos(id) ON DELETE SET NULL,
  INDEX idx_firebase_uid (firebase_uid),
  INDEX idx_periodo_firebase (periodo_id, firebase_uid)
);
