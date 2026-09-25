'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { db } = require('../lib/db');

// Sobrescribe el método real ANTES de requerir el router, para que nunca
// intente conectar a MySQL de verdad durante los tests. Node cachea el
// módulo lib/db.js, así que routes/calendario.js recibe la misma referencia.
let mockImpl;
db.execute = async (sql, params) => mockImpl(sql, params);

const router = require('../routes/calendario');

function handlerDe(method, path) {
  const layer = router.stack.find(l => l.route && l.route.path === path && l.route.methods[method]);
  assert.ok(layer, `No se encontró ${method.toUpperCase()} ${path}`);
  return layer.route.stack[0].handle;
}

async function llamar(handler, req) {
  let status = 200, body;
  const res = {
    status(v) { status = v; return res; },
    json(v) { body = v; return res; },
  };
  await handler(req, res);
  return { status, body };
}

const handlerGetEventos = handlerDe('get', '/calendario/eventos');

test('J3: GET /calendario/eventos sin firebase_uid devuelve 400 sin consultar la BD', async () => {
  mockImpl = () => { throw new Error('No debería consultar la BD'); };
  const { status, body } = await llamar(handlerGetEventos, { query: {} });
  assert.equal(status, 400);
  assert.match(body.error, /firebase_uid/);
});

test('J3: GET /calendario/eventos hace JOIN con user_gastos_fijos y deudas para traer el nombre vinculado', async () => {
  let sqlCapturado;
  mockImpl = async (sql, params) => {
    sqlCapturado = sql;
    assert.deepEqual(Array.from(params), ['prueba-usuario']);
    return [[
      { id: 1, titulo: 'Renta', user_gasto_fijo_id: 5, deuda_id: null, fijo_nombre: 'Renta apartamento', deuda_nombre: null },
      { id: 2, titulo: 'Tarjeta BAC', user_gasto_fijo_id: null, deuda_id: 9, fijo_nombre: null, deuda_nombre: 'Tarjeta BAC Visa' },
      { id: 3, titulo: 'Gasto suelto', user_gasto_fijo_id: null, deuda_id: null, fijo_nombre: null, deuda_nombre: null },
    ]];
  };
  const { status, body } = await llamar(handlerGetEventos, { query: { firebase_uid: 'prueba-usuario' } });

  assert.equal(status, 200);
  assert.match(sqlCapturado, /LEFT JOIN user_gastos_fijos gf ON ce\.user_gasto_fijo_id = gf\.id/);
  assert.match(sqlCapturado, /LEFT JOIN deudas d ON ce\.deuda_id = d\.id/);
  assert.match(sqlCapturado, /gf\.descripcion AS fijo_nombre/);
  assert.match(sqlCapturado, /d\.nombre AS deuda_nombre/);

  assert.equal(body[0].fijo_nombre, 'Renta apartamento');
  assert.equal(body[1].deuda_nombre, 'Tarjeta BAC Visa');
  assert.equal(body[2].fijo_nombre, null);
  assert.equal(body[2].deuda_nombre, null);
});

test('J3: GET /calendario/eventos sigue filtrando por mes/anio cuando se pasan', async () => {
  let paramsCapturados;
  mockImpl = async (sql, params) => { paramsCapturados = params; return [[]]; };
  await llamar(handlerGetEventos, { query: { firebase_uid: 'prueba-usuario', mes: '9', anio: '2026' } });
  assert.deepEqual(Array.from(paramsCapturados), ['prueba-usuario', '2026', '9']);
});
