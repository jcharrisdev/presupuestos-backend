-- Hace monto_total y monto_pendiente nullable en deudas
-- para soportar deudas creadas desde el perfil con info incompleta
ALTER TABLE deudas MODIFY monto_total    DECIMAL(10,2) NULL;
ALTER TABLE deudas MODIFY monto_pendiente DECIMAL(10,2) NULL;
