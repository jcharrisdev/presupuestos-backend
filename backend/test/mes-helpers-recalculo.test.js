'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { db } = require('../lib/db');

// Mismo patrón que quincena-endpoint.test.js: sobrescribe db.execute ANTES de
// requerir el módulo, para que lib/mes_helpers.js reciba la referencia mockeada
// (Node cachea lib/db.js).
let mockImpl;
db.execute = async (sql, params) => mockImpl(sql, params);

const { _recalcularEstimadosAnio } = require('../lib/mes_helpers');

function mockRecalculo({ meses }) {
  const updatesMesesFinancieros = [];
  mockImpl = async (sql, params) => {
    if (sql.includes('FROM estado_financiero_anual WHERE')) return [[{ id: 1 }]];
    if (sql.includes('FROM user_income')) return [[{ ingreso_neto_mensual: '1000.00' }]];
    if (sql.includes('FROM user_gastos_fijos WHERE')) return [[]];
    if (sql.includes('FROM deudas d')) return [[]];
    if (sql.includes('FROM gastos_variables_base WHERE')) return [[]];
    if (sql.includes('UPDATE estado_financiero_anual')) return [{}];
    if (sql.includes('SELECT id, mes, estado FROM meses_financieros')) return [meses];
    if (sql.includes('FROM registros_ingreso')) return [[{ total: 0 }]];
    if (sql.includes('UPDATE meses_financieros')) { updatesMesesFinancieros.push(params); return [{}]; }
    throw new Error(`Consulta no esperada en el mock: ${sql}`);
  };
  return updatesMesesFinancieros;
}

const MESES = [
  { id: 1, mes: 1, estado: 'cerrado' },
  { id: 2, mes: 9, estado: 'activo' },
  { id: 3, mes: 10, estado: 'futuro' },
];

test('sin soloDesdeAqui (default): recalcula los 12 meses, incluyendo los cerrados', async () => {
  const updates = mockRecalculo({ meses: MESES });
  await _recalcularEstimadosAnio('u1', 2026);
  assert.equal(updates.length, 3, 'debe actualizar los 3 meses del mock, cerrado incluido');
});

test('con soloDesdeAqui=true: no reescribe el estimado de un mes ya cerrado', async () => {
  const updates = mockRecalculo({ meses: MESES });
  await _recalcularEstimadosAnio('u1', 2026, { soloDesdeAqui: true });
  assert.equal(updates.length, 2, 'solo debe tocar el mes activo y el futuro');
  const idsActualizados = updates.map(p => p[p.length - 1]);
  assert.ok(!idsActualizados.includes(1), 'el mes cerrado (id=1) no debe recibir UPDATE');
  assert.ok(idsActualizados.includes(2) && idsActualizados.includes(3));
});

test('con soloDesdeAqui=true y ningún mes cerrado: se comporta igual que el default', async () => {
  const sinCerrados = [
    { id: 2, mes: 9, estado: 'activo' },
    { id: 3, mes: 10, estado: 'futuro' },
  ];
  const updates = mockRecalculo({ meses: sinCerrados });
  await _recalcularEstimadosAnio('u1', 2026, { soloDesdeAqui: true });
  assert.equal(updates.length, 2);
});
