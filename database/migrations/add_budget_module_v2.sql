-- ============================================================
-- MIGRATION: add_budget_module_v2
-- Fecha: 2026-05-13
-- ADDITIVE ONLY — sin DROP, sin pérdida de datos
-- ============================================================

-- ── gastos: temporalidad + deudas ────────────────────────────
ALTER TABLE gastos
  ADD COLUMN tipo_deuda        TINYINT(1)    NOT NULL DEFAULT 0,
  ADD COLUMN descuento_directo TINYINT(1)    NOT NULL DEFAULT 0,
  ADD COLUMN fecha_fin         DATE          NULL DEFAULT NULL,
  ADD COLUMN num_cuotas        INT           NULL DEFAULT NULL;

-- ── budget_income: flag auto-cálculo Panamá ──────────────────
ALTER TABLE budget_income
  ADD COLUMN calcular_automatico   TINYINT(1)    NOT NULL DEFAULT 0,
  ADD COLUMN ingreso_bruto_mensual DECIMAL(10,2) NULL DEFAULT NULL;
