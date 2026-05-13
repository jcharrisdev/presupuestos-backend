-- Migración: soporte para precio de paquete y cantidad usada en producción
-- Fecha: 2026-05-12
--
-- Contexto: el usuario compra insumos en paquetes (ej: 100 bolsitas a $3.00 el paquete)
-- pero solo usa una parte para la producción actual (ej: 32 de 100 bolsitas).
-- Los campos nuevos permiten calcular el costo real asignado a la producción.
--
-- Costo asignado = precio_total_paquete × (cantidad_usada / cantidad)
-- Retrocompatible: si los campos son NULL, se sigue usando cantidad × precio_unitario.

ALTER TABLE items_produccion
  ADD COLUMN precio_total_paquete DECIMAL(10,2) DEFAULT NULL
    COMMENT 'Precio pagado por el lote completo del insumo',
  ADD COLUMN cantidad_usada DECIMAL(10,3) DEFAULT NULL
    COMMENT 'Unidades del paquete realmente usadas en esta produccion';
