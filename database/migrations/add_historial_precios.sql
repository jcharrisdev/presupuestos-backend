-- =============================================================================
-- MIGRACIÓN: Tabla historial_precios_variante
-- Ejecutar UNA SOLA VEZ en Clever Cloud (consola MySQL)
-- Generado: 2026-05-04
-- =============================================================================

CREATE TABLE IF NOT EXISTS historial_precios_variante (
  id              INT PRIMARY KEY AUTO_INCREMENT,
  variante_id     INT NOT NULL,
  firebase_uid    VARCHAR(255) NOT NULL,
  precio_anterior DECIMAL(10,2) NOT NULL,
  precio_nuevo    DECIMAL(10,2) NOT NULL,
  changed_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (variante_id) REFERENCES variantes_producto(id) ON DELETE CASCADE,
  INDEX idx_variante (variante_id),
  INDEX idx_uid_fecha (firebase_uid, changed_at)
);
