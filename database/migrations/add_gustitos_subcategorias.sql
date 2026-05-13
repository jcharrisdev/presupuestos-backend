-- Migración: Subcategorías de gastos + Módulo Gustitos
-- Fecha: 2026-05-13

-- 1. Subcategoria en gastos (nullable, no rompe registros existentes)
ALTER TABLE gastos ADD COLUMN subcategoria VARCHAR(100) NULL DEFAULT NULL;

-- 2. Subcategoria en movimientos (nullable, se propaga desde el gasto al crear movimiento)
ALTER TABLE movimientos ADD COLUMN subcategoria VARCHAR(100) NULL DEFAULT NULL;

-- 3. Nueva tabla gustitos (módulo independiente, no modifica tablas existentes)
CREATE TABLE gustitos (
  id                 INT AUTO_INCREMENT PRIMARY KEY,
  user_id            VARCHAR(128)   NOT NULL,
  budget_id          INT            NOT NULL,
  scanned_invoice_id INT            NULL,
  name               VARCHAR(255)   NOT NULL,
  description        TEXT           NULL,
  merchant           VARCHAR(255)   NULL,
  amount             DECIMAL(10,2)  NOT NULL,
  category           VARCHAR(100)   NULL,
  emotion_tag        ENUM('antojo','premio','social','impulso','estres','otro') NULL,
  source             ENUM('manual','scanned_invoice','imported') NOT NULL DEFAULT 'manual',
  spent_at           DATE           NOT NULL,
  created_at         TIMESTAMP      DEFAULT CURRENT_TIMESTAMP,
  updated_at         TIMESTAMP      DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at         TIMESTAMP      NULL,
  INDEX idx_gustitos_user   (user_id),
  INDEX idx_gustitos_budget (budget_id),
  FOREIGN KEY (budget_id) REFERENCES presupuestos(id) ON DELETE CASCADE
);
