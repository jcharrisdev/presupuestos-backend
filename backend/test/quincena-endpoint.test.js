'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { db } = require('../lib/db');

// Sobrescribe el método real ANTES de requerir el router (mismo patrón que
// calendario-eventos-endpoint.test.js): Node cachea lib/db.js, así que
// routes/quincena.js recibe la misma referencia mockeada.
let mockImpl;
db.execute = async (sql, params) => mockImpl(sql, params);

const router = require('../routes/quincena');

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

const handlerQuincena = handlerDe('get', '/user/quincena/:anio/:mes/:num');

/**
 * Arma un mock de db.execute que responde según qué tabla consulta cada
 * SELECT, sin depender del orden en que quincena.js las dispare.
 * `deuda` es la fila cruda que debe devolver la consulta a `deudas` (o
 * `null` para simular que el usuario no tiene deudas activas).
 */
function mockQuincena({ deuda = null } = {}) {
  mockImpl = async (sql) => {
    if (sql.includes('FROM meses_financieros')) return [[]];
    if (sql.includes('FROM user_income')) return [[{ ingreso_neto_mensual: '1000.00' }]];
    if (sql.includes('FROM registros_gasto rg')) return [[]];
    if (sql.includes('FROM user_gastos_fijos ugf')) return [[]];
    if (sql.includes('FROM gastos_variables_base gvb')) return [[]];
    if (sql.includes('FROM deudas d')) return [deuda ? [deuda] : []];
    throw new Error(`Consulta no esperada en el mock: ${sql}`);
  };
}

function deudaCompromiso(compromisos) {
  return compromisos.find(c => c.tipo === 'deuda');
}

test('J2: deuda con fecha_proximo_pago día 3 aparece completa en Q1 y ausente en Q2', async () => {
  mockQuincena({
    deuda: {
      id: 1, nombre: 'Carro', monto: '200.00',
      fecha_proximo_pago: new Date(Date.UTC(2026, 8, 3)), // 3 de septiembre
      monto_pagado: 0, registro_ids_str: null,
    },
  });

  const q1 = await llamar(handlerQuincena, { params: { anio: '2026', mes: '9', num: '1' }, query: { firebase_uid: 'u1' } });
  const q2 = await llamar(handlerQuincena, { params: { anio: '2026', mes: '9', num: '2' }, query: { firebase_uid: 'u1' } });

  const cQ1 = deudaCompromiso(q1.body.compromisos_quincenal);
  const cQ2 = deudaCompromiso(q2.body.compromisos_quincenal);

  assert.ok(cQ1, 'la deuda debe aparecer en Q1, donde cae su fecha real');
  assert.equal(cQ1.monto, 200, 'debe mostrar el monto completo, no la mitad');
  assert.equal(cQ2, undefined, 'la deuda no debe aparecer en Q2 — ya no vence ahí');
});

test('J2: deuda con fecha_proximo_pago día 20 aparece completa en Q2 y ausente en Q1', async () => {
  mockQuincena({
    deuda: {
      id: 1, nombre: 'Tarjeta', monto: '150.00',
      fecha_proximo_pago: new Date(Date.UTC(2026, 8, 20)),
      monto_pagado: 0, registro_ids_str: null,
    },
  });

  const q1 = await llamar(handlerQuincena, { params: { anio: '2026', mes: '9', num: '1' }, query: { firebase_uid: 'u1' } });
  const q2 = await llamar(handlerQuincena, { params: { anio: '2026', mes: '9', num: '2' }, query: { firebase_uid: 'u1' } });

  assert.equal(deudaCompromiso(q1.body.compromisos_quincenal), undefined);
  const cQ2 = deudaCompromiso(q2.body.compromisos_quincenal);
  assert.ok(cQ2);
  assert.equal(cQ2.monto, 150);
});

test('J2: deuda con dos días de pago (quincenal) aparece partida a la mitad en cada quincena', async () => {
  mockQuincena({
    deuda: {
      id: 1, nombre: 'Préstamo quincenal', monto: '100.00',
      fecha_proximo_pago: null, dia_pago: 1, dia_pago_2: 15,
      monto_pagado: 0, registro_ids_str: null,
    },
  });

  const q1 = await llamar(handlerQuincena, { params: { anio: '2026', mes: '9', num: '1' }, query: { firebase_uid: 'u1' } });
  const q2 = await llamar(handlerQuincena, { params: { anio: '2026', mes: '9', num: '2' }, query: { firebase_uid: 'u1' } });

  assert.equal(deudaCompromiso(q1.body.compromisos_quincenal).monto, 50);
  assert.equal(deudaCompromiso(q2.body.compromisos_quincenal).monto, 50);
});

test('J2: deuda con un solo día de pago manda sobre fecha_proximo_pago', async () => {
  mockQuincena({
    deuda: {
      // dia_pago=5 (Q1) contradice fecha_proximo_pago=día 20 (Q2): debe ganar dia_pago.
      id: 1, nombre: 'Tarjeta', monto: '60.00',
      fecha_proximo_pago: new Date(Date.UTC(2026, 8, 20)), dia_pago: 5, dia_pago_2: null,
      monto_pagado: 0, registro_ids_str: null,
    },
  });

  const q1 = await llamar(handlerQuincena, { params: { anio: '2026', mes: '9', num: '1' }, query: { firebase_uid: 'u1' } });
  const q2 = await llamar(handlerQuincena, { params: { anio: '2026', mes: '9', num: '2' }, query: { firebase_uid: 'u1' } });

  assert.equal(deudaCompromiso(q1.body.compromisos_quincenal).monto, 60);
  assert.equal(deudaCompromiso(q2.body.compromisos_quincenal), undefined);
});

test('J2: deuda sin fecha_proximo_pago conocida sigue con el fallback 50/50 en ambas quincenas', async () => {
  mockQuincena({
    deuda: {
      id: 1, nombre: 'Préstamo personal', monto: '80.00',
      fecha_proximo_pago: null,
      monto_pagado: 0, registro_ids_str: null,
    },
  });

  const q1 = await llamar(handlerQuincena, { params: { anio: '2026', mes: '9', num: '1' }, query: { firebase_uid: 'u1' } });
  const q2 = await llamar(handlerQuincena, { params: { anio: '2026', mes: '9', num: '2' }, query: { firebase_uid: 'u1' } });

  assert.equal(deudaCompromiso(q1.body.compromisos_quincenal).monto, 40);
  assert.equal(deudaCompromiso(q2.body.compromisos_quincenal).monto, 40);
});
