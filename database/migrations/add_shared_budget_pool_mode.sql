-- Migración: modo "pool_contribucion" para presupuestos compartidos
-- Fecha: 2026-05-12
--
-- Contexto: el hermano pone todo su salario y la esposa pone otra cantidad.
-- Quieren ver el balance del fondo total sin rastrear "quién le debe a quién".
-- Este es un modo distinto a los 3 actuales: cada uno contribuye su monto mensual
-- y el sistema muestra el balance del fondo común.
--
-- También agrega soporte para contribución mensual por miembro.

-- 1. Nueva columna para contribución mensual del miembro en modo pool
ALTER TABLE shared_budget_members
  ADD COLUMN contribucion_mensual DECIMAL(12,2) DEFAULT NULL
    COMMENT 'Monto mensual que este miembro aporta al fondo en modo pool_contribucion';

-- 2. Agregar nuevo valor al ENUM de regla_reparto
ALTER TABLE shared_budgets
  MODIFY COLUMN regla_reparto ENUM('equitativo','porcentual','proporcional','pool_contribucion')
    NOT NULL DEFAULT 'equitativo';
