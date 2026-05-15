-- =============================================================================
-- MIGRACIÓN: Link perfil financiero ↔ módulo Deudas
-- user_gastos_fijos.deuda_id apunta al registro en tabla deudas
-- que se crea automáticamente cuando es_deuda=1
-- =============================================================================

ALTER TABLE user_gastos_fijos
  ADD COLUMN deuda_id INT NULL AFTER recordatorio,
  ADD INDEX  idx_ugf_deuda (deuda_id);
