-- =============================================================================
-- MIGRACIÓN: Índices de performance
-- Ejecutar UNA SOLA VEZ en Clever Cloud (consola MySQL)
-- Generado: 2026-05-04
-- =============================================================================

-- -----------------------------------------------------------------------------
-- TABLA: cobros_clientes
-- -----------------------------------------------------------------------------
-- idx_estado: usada por GET /ventas?firebase_uid filtra cobros pendientes/cobrados.
-- Evita full scan de la tabla cuando hay muchos clientes por usuario.
ALTER TABLE cobros_clientes
  ADD INDEX idx_estado (estado),
  -- idx_venta_estado: usada por GET /ventas/:id que hace WHERE venta_id = ? y agrupa
  -- cobros por estado para calcular total_cobrado y total_pendiente del resumen.
  ADD INDEX idx_venta_estado (venta_id, estado);

-- -----------------------------------------------------------------------------
-- TABLA: ventas
-- -----------------------------------------------------------------------------
-- idx_estado: GET /ventas?firebase_uid filtra WHERE firebase_uid = ? AND estado='activa'.
-- Sin índice hace full scan cada vez que el usuario abre la pantalla de ventas.
ALTER TABLE ventas
  ADD INDEX idx_estado (estado);

-- -----------------------------------------------------------------------------
-- TABLA: calendario_eventos
-- -----------------------------------------------------------------------------
-- idx_firebase_estado: el cron job de medianoche busca eventos con
--   WHERE firebase_uid = ? AND estado = 'pendiente' AND fecha_evento < TODAY.
-- También usado por la pantalla de calendario para filtrar pendientes del mes.
-- (idx_estado individual ya existe; este compuesto evita un lookup adicional por uid)
ALTER TABLE calendario_eventos
  ADD INDEX idx_firebase_estado (firebase_uid, estado);

-- -----------------------------------------------------------------------------
-- TABLA: receta_insumos
-- -----------------------------------------------------------------------------
-- idx_receta ya existe en el schema original → no se agrega (evitar duplicado).
-- ALTER TABLE receta_insumos ADD INDEX idx_receta (receta_id); -- YA EXISTE
