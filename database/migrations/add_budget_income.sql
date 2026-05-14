-- Migración: Ingreso neto real por presupuesto
-- Fecha: 2026-05-13
-- Propósito: Asociar un ingreso configurable a cada presupuesto.
-- IMPORTANTE: Todo es nullable-compatible. Presupuestos sin income siguen funcionando igual.
-- income es INFORMATIVO: no modifica monto_total del presupuesto.

CREATE TABLE IF NOT EXISTS budget_income (
  id              INT AUTO_INCREMENT PRIMARY KEY,
  presupuesto_id  INT           NOT NULL,
  firebase_uid    VARCHAR(255)  NOT NULL,

  tipo_ingreso    ENUM('salario','informal','ocasional','prestamo','otro')
                  NOT NULL DEFAULT 'salario',

  -- Campos de salario (NULL si tipo != 'salario')
  ingreso_bruto   DECIMAL(10,2) NULL,
  desc_seguro     DECIMAL(10,2) NULL DEFAULT 0,
  desc_pension    DECIMAL(10,2) NULL DEFAULT 0,
  desc_impuesto   DECIMAL(10,2) NULL DEFAULT 0,
  desc_otros      DECIMAL(10,2) NULL DEFAULT 0,

  -- Ingreso neto final (calculado en backend para salario, ingresado directo para otros)
  ingreso_neto    DECIMAL(10,2) NOT NULL,

  nota            VARCHAR(255)  NULL,

  created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  UNIQUE KEY uq_presupuesto_income (presupuesto_id),
  FOREIGN KEY (presupuesto_id) REFERENCES presupuestos(id) ON DELETE CASCADE,
  INDEX idx_budget_income_uid (firebase_uid)
);
