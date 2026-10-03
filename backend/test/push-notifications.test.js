'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { db } = require('../lib/db');

// Mismo patrón que otros tests de lib/*: sobrescribe db.execute ANTES de
// requerir el módulo (Node cachea lib/db.js).
let mockImpl;
db.execute = async (sql, params) => mockImpl(sql, params);

const { _registrarToken, _eliminarToken, _enviarPushSiNueva } = require('../lib/push_notifications');

test('_registrarToken hace upsert en device_tokens', async () => {
  const calls = [];
  mockImpl = async (sql, params) => { calls.push({ sql, params }); return [{}]; };
  await _registrarToken('u1', 'tok123', 'web');
  assert.equal(calls.length, 1);
  assert.match(calls[0].sql, /INSERT INTO device_tokens/);
  assert.deepEqual(calls[0].params, ['u1', 'tok123', 'web']);
});

test('_eliminarToken borra por token', async () => {
  const calls = [];
  mockImpl = async (sql, params) => { calls.push({ sql, params }); return [{}]; };
  await _eliminarToken('tok123');
  assert.match(calls[0].sql, /DELETE FROM device_tokens WHERE token/);
  assert.deepEqual(calls[0].params, ['tok123']);
});

test('_enviarPushSiNueva: sin credenciales de Firebase configuradas, no truena y devuelve false', async () => {
  // El entorno de test no define FIREBASE_PROJECT_ID/CLIENT_EMAIL/PRIVATE_KEY,
  // así que el envío real debe quedar deshabilitado sin lanzar error.
  mockImpl = async (sql) => {
    if (sql.includes('INSERT INTO notificaciones_enviadas')) return [{}];
    throw new Error(`Consulta no esperada: ${sql}`);
  };
  const enviado = await _enviarPushSiNueva('u1', 'pago_vencido', 42, 'Un pago venció', 'cuerpo');
  assert.equal(enviado, false);
});

test('_enviarPushSiNueva: la misma (uid, tipo, referencia_id) no se reenvía', async () => {
  const yaEnviadas = new Set();
  mockImpl = async (sql, params) => {
    if (sql.includes('INSERT INTO notificaciones_enviadas')) {
      const key = params.join(':');
      if (yaEnviadas.has(key)) { const e = new Error('dup'); e.code = 'ER_DUP_ENTRY'; throw e; }
      yaEnviadas.add(key);
      return [{}];
    }
    throw new Error(`Consulta no esperada: ${sql}`);
  };
  const primera  = await _enviarPushSiNueva('u1', 'remanente_negativo', 7, 'Tu mes va ajustado', 'cuerpo');
  const segunda  = await _enviarPushSiNueva('u1', 'remanente_negativo', 7, 'Tu mes va ajustado', 'cuerpo');
  assert.equal(primera, false);  // sin credenciales en test, pero sí se registró
  assert.equal(segunda, false);  // bloqueada por duplicado, nunca llega a intentar enviar
});

test('_enviarPushSiNueva: distinto referencia_id sí permite un nuevo intento', async () => {
  const yaEnviadas = new Set();
  mockImpl = async (sql, params) => {
    if (sql.includes('INSERT INTO notificaciones_enviadas')) {
      const key = params.join(':');
      if (yaEnviadas.has(key)) { const e = new Error('dup'); e.code = 'ER_DUP_ENTRY'; throw e; }
      yaEnviadas.add(key);
      return [{}];
    }
    throw new Error(`Consulta no esperada: ${sql}`);
  };
  await _enviarPushSiNueva('u1', 'pago_vencido', 1, 't', 'c');
  const calls = [];
  mockImpl = async (sql, params) => {
    calls.push(sql);
    if (sql.includes('INSERT INTO notificaciones_enviadas')) {
      const key = params.join(':');
      if (yaEnviadas.has(key)) { const e = new Error('dup'); e.code = 'ER_DUP_ENTRY'; throw e; }
      yaEnviadas.add(key);
      return [{}];
    }
    throw new Error(`Consulta no esperada: ${sql}`);
  };
  await _enviarPushSiNueva('u1', 'pago_vencido', 2, 't', 'c');
  assert.ok(calls.some(sql => sql.includes('INSERT INTO notificaciones_enviadas')));
});
