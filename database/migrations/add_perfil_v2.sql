-- =============================================================================
-- MIGRACIÓN: Perfil Financiero v2
-- Agrega soporte de gastos variables, día de pago y recordatorio al perfil.
-- =============================================================================

-- Nuevos campos en user_gastos_fijos
ALTER TABLE user_gastos_fijos
  ADD COLUMN frecuencia ENUM('fijo','variable') NOT NULL DEFAULT 'fijo' AFTER notas,
  ADD COLUMN dia_pago   TINYINT UNSIGNED NULL AFTER frecuencia,
  ADD COLUMN recordatorio TINYINT(1) NOT NULL DEFAULT 0 AFTER dia_pago;

-- Nuevo FK en calendario_eventos para eventos generados desde el perfil
ALTER TABLE calendario_eventos
  ADD COLUMN user_gasto_fijo_id INT NULL AFTER cobro_id,
  ADD INDEX  idx_cal_ugf (user_gasto_fijo_id);
