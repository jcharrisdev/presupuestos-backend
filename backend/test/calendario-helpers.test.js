'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { db } = require('../lib/db');

let inserts;
db.execute = async (sql, params) => {
  if (sql.includes('INSERT INTO calendario_eventos')) inserts.push(params);
  return [{ affectedRows: 1 }];
};

const { generarEventosPerfilGasto } = require('../lib/calendario_helpers');

test('J2: fijo con dos días de pago genera cada evento por la mitad del monto mensual', async () => {
  inserts = [];
  await generarEventosPerfilGasto('u1', 5, 'Renta', 200, 1, 15);

  assert.ok(inserts.length > 0);
  // params: [firebase_uid, ugfId, titulo, fechaStr, montoPorEvento, estado]
  for (const p of inserts) {
    assert.equal(p[4], 100, 'cada ocurrencia debe llevar la mitad del monto mensual, no el completo');
  }
});

test('J2: fijo con un solo día de pago mantiene el monto mensual completo por evento', async () => {
  inserts = [];
  await generarEventosPerfilGasto('u1', 5, 'Internet', 60, 10, null);

  assert.ok(inserts.length > 0);
  for (const p of inserts) {
    assert.equal(p[4], 60, 'con un solo día de pago no hay que dividir el monto');
  }
});
