-- =============================================================================
-- MIGRACIÓN: Tabla aportaciones_ahorro
-- Ejecutar UNA SOLA VEZ en Clever Cloud (consola MySQL)
-- Generado: 2026-05-04
-- =============================================================================

CREATE TABLE IF NOT EXISTS aportaciones_ahorro (
  id           INT PRIMARY KEY AUTO_INCREMENT,
  gasto_id     INT NOT NULL,           -- referencia al gasto tipo='ahorro'
  firebase_uid VARCHAR(255) NOT NULL,
  monto        DECIMAL(10,2) NOT NULL,
  nota         VARCHAR(255) NULL,
  fecha        DATE NOT NULL,
  created_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (gasto_id) REFERENCES gastos(id) ON DELETE CASCADE,
  INDEX idx_gasto (gasto_id),
  INDEX idx_uid (firebase_uid)
);
