-- Migración: #4 Clasificación de gastos + #9 Deudas como entidad propia
-- Fecha: 2026-05-13

-- =========================================================================
-- #4 CLASIFICACIÓN FINANCIERA DE GASTOS
-- esencial  → necesidad básica (alquiler, comida, servicios)
-- importante→ relevante pero no urgente (seguro, educación)
-- flexible  → discrecional (ocio, ropa, salidas)
-- =========================================================================

-- 1. Clasificación en gastos (nullable — no rompe registros existentes)
ALTER TABLE gastos
  ADD COLUMN clasificacion ENUM('esencial','importante','flexible') NULL DEFAULT NULL;

-- 2. Clasificación en movimientos (se propaga desde el gasto al crear)
ALTER TABLE movimientos
  ADD COLUMN clasificacion VARCHAR(20) NULL DEFAULT NULL;

-- =========================================================================
-- #9 DEUDAS COMO ENTIDAD PROPIA
-- =========================================================================

CREATE TABLE IF NOT EXISTS deudas (
  id               INT AUTO_INCREMENT PRIMARY KEY,
  firebase_uid     VARCHAR(255)   NOT NULL,
  nombre           VARCHAR(255)   NOT NULL,
  tipo             ENUM('tarjeta_credito','prestamo','hipoteca','auto','personal','otro')
                   NOT NULL DEFAULT 'personal',
  monto_total      DECIMAL(10,2)  NOT NULL,
  monto_pendiente  DECIMAL(10,2)  NOT NULL,
  tasa_interes     DECIMAL(5,2)   NULL DEFAULT NULL,  -- porcentaje mensual
  pago_minimo      DECIMAL(10,2)  NULL DEFAULT NULL,
  fecha_proximo_pago DATE         NULL DEFAULT NULL,
  notas            TEXT           NULL,
  activa           TINYINT(1)     NOT NULL DEFAULT 1,  -- 0 = saldada/archivada
  created_at       TIMESTAMP      DEFAULT CURRENT_TIMESTAMP,
  updated_at       TIMESTAMP      DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX idx_deudas_uid (firebase_uid),
  INDEX idx_deudas_activa (firebase_uid, activa)
);
