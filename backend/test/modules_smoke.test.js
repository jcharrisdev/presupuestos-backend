// Smoke test: cada módulo extraído de server.js debe poder cargarse sin
// errores de sintaxis ni de require, y exponer la forma esperada.
// No requiere conexión a MySQL — mysql2.createPool() no conecta hasta la
// primera query, así que require('../lib/db') es seguro sin credenciales.
process.env.MYSQLHOST = process.env.MYSQLHOST || 'localhost';
process.env.MYSQLUSER = process.env.MYSQLUSER || 'test';
process.env.MYSQLPASSWORD = process.env.MYSQLPASSWORD || 'test';
process.env.MYSQLDATABASE = process.env.MYSQLDATABASE || 'test';
process.env.MYSQLPORT = process.env.MYSQLPORT || '3306';

const { test } = require('node:test');
const assert = require('node:assert/strict');

test('lib/db expone pool y db', () => {
  const { pool, db } = require('../lib/db');
  assert.ok(pool, 'pool debe existir');
  assert.equal(typeof db.execute, 'function');
});

test('lib/logger expone _logError, _logInfo y LOG_SECRET', () => {
  const { LOG_SECRET, _logError, _logInfo } = require('../lib/logger');
  assert.equal(typeof LOG_SECRET, 'string');
  assert.equal(typeof _logError, 'function');
  assert.equal(typeof _logInfo, 'function');
});

test('lib/calendario_helpers expone calcularFechasEvento, generarEventosCalendario y generarEventosPerfilGasto', () => {
  const { calcularFechasEvento, generarEventosCalendario, generarEventosPerfilGasto } = require('../lib/calendario_helpers');
  assert.equal(typeof calcularFechasEvento, 'function');
  assert.equal(typeof generarEventosCalendario, 'function');
  assert.equal(typeof generarEventosPerfilGasto, 'function');
  // calcularFechasEvento no toca la BD — verificable en el smoke test
  assert.deepEqual(calcularFechasEvento('unico', 15, '2026-06-10'), ['2026-06-10']);
});

test('lib/mes_helpers expone _actualizarTotalesMes, _generarAlertasMes y _recalcularEstimadosAnio', () => {
  const { _actualizarTotalesMes, _generarAlertasMes, _recalcularEstimadosAnio } = require('../lib/mes_helpers');
  assert.equal(typeof _actualizarTotalesMes, 'function');
  assert.equal(typeof _generarAlertasMes, 'function');
  assert.equal(typeof _recalcularEstimadosAnio, 'function');
});

test('lib/periodo_helpers expone getPeriodoActivo, crearPrimerPeriodo, crearNuevoPeriodo, generarMovimientosPeriodo y _insertarPeriodo', () => {
  const {
    getPeriodoActivo, crearPrimerPeriodo, crearNuevoPeriodo, generarMovimientosPeriodo, _insertarPeriodo,
  } = require('../lib/periodo_helpers');
  assert.equal(typeof getPeriodoActivo, 'function');
  assert.equal(typeof crearPrimerPeriodo, 'function');
  assert.equal(typeof crearNuevoPeriodo, 'function');
  assert.equal(typeof generarMovimientosPeriodo, 'function');
  assert.equal(typeof _insertarPeriodo, 'function');
});

for (const modulo of [
  'logs', 'ahorros', 'calendario', 'gustitos',
  'expense_definitions', 'timeline', 'quincena', 'alertas', 'eventos', 'deudas',
  'presupuestos', 'gastos', 'movimientos', 'sobres',
  'ingresos_extra', 'gastos_globales', 'gastos_variables_base',
]) {
  test(`routes/${modulo} exporta un Express Router`, () => {
    const router = require(`../routes/${modulo}`);
    // Un Router de Express es una función con .stack (las rutas registradas)
    assert.equal(typeof router, 'function');
    assert.ok(Array.isArray(router.stack) && router.stack.length > 0, 'debe tener rutas registradas');
  });
}
