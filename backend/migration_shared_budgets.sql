-- ============================================================
-- MIGRACIÓN: Módulo Presupuesto Compartido - Salarying
-- Fecha: 2026-05-09
-- Ejecutar una sola vez en la base de datos de producción
-- ============================================================

CREATE TABLE IF NOT EXISTS shared_budgets (
  id INT AUTO_INCREMENT PRIMARY KEY,
  nombre VARCHAR(255) NOT NULL,
  tipo_periodo ENUM('mensual','quincenal') DEFAULT 'mensual',
  dia_inicio_periodo TINYINT DEFAULT 1,
  regla_reparto ENUM('equitativo','porcentual','proporcional') DEFAULT 'equitativo',
  estado ENUM('draft','waiting_for_members','active','paused','closed') DEFAULT 'draft',
  owner_uid VARCHAR(255) NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS shared_budget_members (
  id INT AUTO_INCREMENT PRIMARY KEY,
  shared_budget_id INT NOT NULL,
  firebase_uid VARCHAR(255) NOT NULL,
  rol ENUM('owner','member') DEFAULT 'member',
  porcentaje DECIMAL(5,2) DEFAULT 50.00,
  ingreso_declarado DECIMAL(12,2) DEFAULT NULL,
  joined_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (shared_budget_id) REFERENCES shared_budgets(id) ON DELETE CASCADE,
  UNIQUE KEY uk_member (shared_budget_id, firebase_uid)
);

CREATE TABLE IF NOT EXISTS shared_budget_invitations (
  id INT AUTO_INCREMENT PRIMARY KEY,
  shared_budget_id INT NOT NULL,
  email_invitado VARCHAR(255) NOT NULL,
  token VARCHAR(64) NOT NULL UNIQUE,
  estado ENUM('pending','accepted','rejected','expired','cancelled') DEFAULT 'pending',
  expires_at TIMESTAMP NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (shared_budget_id) REFERENCES shared_budgets(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS shared_expenses (
  id INT AUTO_INCREMENT PRIMARY KEY,
  shared_budget_id INT NOT NULL,
  descripcion VARCHAR(255) NOT NULL,
  monto DECIMAL(12,2) NOT NULL,
  pagado_por VARCHAR(255) NOT NULL,
  regla_override ENUM('equitativo','porcentual','proporcional') DEFAULT NULL,
  es_personal TINYINT(1) DEFAULT 0,
  firebase_uid_personal VARCHAR(255) DEFAULT NULL,
  fecha DATE NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (shared_budget_id) REFERENCES shared_budgets(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS shared_expense_splits (
  id INT AUTO_INCREMENT PRIMARY KEY,
  expense_id INT NOT NULL,
  firebase_uid VARCHAR(255) NOT NULL,
  monto_responsabilidad DECIMAL(12,2) NOT NULL,
  pagado TINYINT(1) DEFAULT 0,
  FOREIGN KEY (expense_id) REFERENCES shared_expenses(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS shared_settlements (
  id INT AUTO_INCREMENT PRIMARY KEY,
  shared_budget_id INT NOT NULL,
  pagador_uid VARCHAR(255) NOT NULL,
  receptor_uid VARCHAR(255) NOT NULL,
  monto DECIMAL(12,2) NOT NULL,
  nota VARCHAR(255) DEFAULT NULL,
  fecha DATE NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (shared_budget_id) REFERENCES shared_budgets(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS shared_budget_activity_logs (
  id INT AUTO_INCREMENT PRIMARY KEY,
  shared_budget_id INT NOT NULL,
  actor_uid VARCHAR(255) NOT NULL,
  accion VARCHAR(100) NOT NULL,
  detalle JSON DEFAULT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (shared_budget_id) REFERENCES shared_budgets(id) ON DELETE CASCADE
);

-- Migración 2: columna para solicitud de eliminación (ejecutar si ya existe la tabla)
ALTER TABLE shared_budgets ADD COLUMN IF NOT EXISTS delete_requested_by VARCHAR(255) DEFAULT NULL;
