'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { db } = require('../lib/db');

// Mismo patrón que calendario-eventos-endpoint.test.js: sobrescribe db.execute
// ANTES de requerir el router, para que routes/deudas.js reciba la referencia
// mockeada (Node cachea lib/db.js).
let mockImpl;
db.execute = async (sql, params) => mockImpl(sql, params);

const router = require('../routes/deudas');

function insertsDeCalendario(calls) {
  return calls.filter(c => c.sql.includes('INSERT INTO calendario_eventos')).map(c => c.params);
}

test('J2: deuda sin fecha_proximo_pago genera recordatorio los días 15 y fin de mes, partido a la mitad', async () => {
  const calls = [];
  mockImpl = async (sql, params) => {
    calls.push({ sql, params });
    if (sql.includes('SELECT id, nombre, fecha_proximo_pago')) {
      return [[{ id: 1, nombre: 'Préstamo personal', fecha_proximo_pago: null, cuota: '80.00' }]];
    }
    return [{}];
  };

  await router._sincronizarEventosDeudas('u1');

  const inserts = insertsDeCalendario(calls);
  // 3 meses × 2 fechas (15 y último día) = 6 eventos
  assert.equal(inserts.length, 6);
  for (const p of inserts) {
    // params: [firebase_uid, deuda_id, titulo, fecha, monto, estado]
    assert.equal(p[4], 40, 'cada ocurrencia debe llevar la mitad del monto');
    assert.match(p[2], /\(fecha estimada\)/, 'el título debe dejar claro que la fecha no es confirmada');
  }
});

test('J2: deuda con fecha_proximo_pago conocida sigue generando un evento mensual con el monto completo', async () => {
  const calls = [];
  mockImpl = async (sql, params) => {
    calls.push({ sql, params });
    if (sql.includes('SELECT id, nombre, fecha_proximo_pago')) {
      return [[{ id: 2, nombre: 'Carro', fecha_proximo_pago: '2026-09-03', cuota: '200.00' }]];
    }
    return [{}];
  };

  await router._sincronizarEventosDeudas('u1');

  const inserts = insertsDeCalendario(calls);
  assert.equal(inserts.length, 3, 'un evento por cada uno de los próximos 3 meses');
  for (const p of inserts) {
    assert.equal(p[4], 200, 'con fecha conocida se usa el monto completo, sin dividir');
    assert.equal(p[2], 'Carro', 'el título no debe llevar la etiqueta de fecha estimada');
  }
});

test('J2: SELECT de deudas activas ya no excluye las que no tienen fecha_proximo_pago', async () => {
  let sqlCapturado;
  mockImpl = async (sql) => {
    if (sql.includes('SELECT id, nombre, fecha_proximo_pago')) sqlCapturado = sql;
    return [[]];
  };
  await router._sincronizarEventosDeudas('u1');
  assert.doesNotMatch(sqlCapturado, /fecha_proximo_pago IS NOT NULL/);
});
