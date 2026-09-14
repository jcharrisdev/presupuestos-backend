'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { calcularResumenMensual } = require('../finanzas/resumen-mensual');

const registro = (monto, pagado, extra = {}) => ({ monto, pagado, ...extra });
const resumen = (registros, extra = {}) => calcularResumenMensual({ ingreso: 1000, registros, ...extra });

test('E-01: ingreso 1000, pagado 200, pendientes 100 + 200', () => {
  const r = resumen([registro('200.00', 1), registro('100.00', 0), registro('200.00', '0')]);
  assert.equal(r.gastos_registrados, 500);
  assert.equal(r.gastos_pagados, 200);
  assert.equal(r.gastos_pendientes, 300);
  assert.equal(r.total_pendiente, 300);
  assert.equal(r.disponible_real, 800);
  assert.equal(r.disponible_proyectado, 500);
});

test('E-01: pagar 100 mueve pendiente a pagado sin volver a descontarlo del proyectado', () => {
  const registros = [registro(200, 1), registro(100, 0), registro(200, 0)];
  const antes = resumen(registros);
  registros[1].pagado = 1;
  const despues = resumen(registros);
  assert.equal(despues.gastos_pagados, 300);
  assert.equal(despues.total_pendiente, 200);
  assert.equal(despues.disponible_real, 700);
  assert.equal(despues.disponible_proyectado, antes.disponible_proyectado);
  assert.deepEqual(resumen(JSON.parse(JSON.stringify(registros))), despues);
  registros[1].pagado = 0;
  assert.deepEqual(resumen(registros), antes);
});

test('E-01: ingreso cero conserva el saldo proyectado negativo', () => {
  const r = resumen([registro('100.00', 0)], { ingreso: '0.00' });
  assert.equal(r.disponible_real, 0);
  assert.equal(r.disponible_proyectado, -100);
});

test('un compromiso parcialmente pagado conserva la parte restante', () => {
  const r = resumen([registro(30, 1, { origen_fijo_id: 1 }), registro(20, true, { origen_fijo_id: '1' })],
    { gastosFijos: [{ id: 1, descripcion: 'Renta', monto_mensual: '100.00' }] });
  assert.equal(r.gastos_pagados, 50);
  assert.equal(r.compromisos_pendientes, 50);
  assert.equal(r.disponible_proyectado, 900);
  assert.equal(r.compromisos_pendientes_detalle[0].pendiente, 50);
});

test('un registro pendiente vinculado cubre presupuesto sin duplicar la obligación', () => {
  const registros = [registro(30, 1, { origen_fijo_id: 1 }), registro(20, '0', { origen_fijo_id: 1 })];
  const extra = { gastosFijos: [{ id: 1, monto_mensual: 100 }] };
  const antes = resumen(registros, extra);
  assert.equal(antes.gastos_pendientes, 20);
  assert.equal(antes.compromisos_pendientes, 50);
  assert.equal(antes.total_pendiente, 70);
  registros[1].pagado = '1';
  const despues = resumen(registros, extra);
  assert.equal(despues.total_pendiente, 50);
  assert.equal(despues.disponible_proyectado, antes.disponible_proyectado);
});

test('el mismo pago no cubre dos veces una deuda vinculada a un gasto fijo', () => {
  const r = resumen([registro(40, 1, { origen_fijo_id: 1, origen_deuda_id: 8 })], {
    gastosFijos: [{ id: 1, deuda_id: 8, monto_mensual: 100 }],
    deudas: [{ id: '8', es_letra: 1, cuota_fija: '100.00' }],
  });
  assert.equal(r.compromisos_pendientes_detalle.length, 1);
  assert.equal(r.total_pendiente, 60);
  assert.equal(r.disponible_proyectado, 900);
});

test('deudas y eventos sin registrar se incluyen, sin duplicar sus pagos', () => {
  const r = resumen([registro(15, 1, { origen_deuda_id: 2 }), registro(20, 1, { origen_evento_id: 3 })], {
    deudas: [{ id: 2, es_letra: '0', cuota_fija: 999, pago_minimo: 45 }],
    eventos: [{ id: 3, cuota_mensual: 60 }],
  });
  assert.equal(r.total_pendiente, 70);
  assert.equal(r.disponible_real, 965);
  assert.equal(r.disponible_proyectado, 895);
});

test('un vínculo de evento resuelto como nulo no se confunde con el id del detalle', () => {
  const r = resumen([
    registro(20, 1, {
      origen_evento_id: 3,
      origen_evento_presupuesto_id: null,
    }),
  ], {
    eventos: [{ id: 3, cuota_mensual: 60 }],
  });
  assert.equal(r.gastos_pagados, 20);
  assert.equal(r.compromisos_pendientes, 60);
  assert.equal(r.total_pendiente, 60);
  assert.equal(r.disponible_proyectado, 920);
});

test('un sobrepago no reduce otro compromiso ni produce pendientes negativos', () => {
  const r = resumen([registro(120, 1, { origen_fijo_id: 1 }), registro(10, 0, { origen_fijo_id: 1 })], {
    gastosFijos: [{ id: 1, monto_mensual: 100 }, { id: 2, monto_mensual: 50 }],
  });
  assert.equal(r.compromisos_pendientes, 50);
  assert.equal(r.total_pendiente, 60);
  assert.equal(r.disponible_proyectado, 820);
});

test('usa centavos y no modifica los registros de entrada', () => {
  const registros = Object.freeze([Object.freeze(registro('0.10', 1)), Object.freeze(registro('0.20', 1))]);
  const r = resumen(registros, { ingreso: '0.40' });
  assert.equal(r.gastos_pagados, 0.3);
  assert.equal(r.disponible_real, 0.1);
});

test('mes sin registros conserva los compromisos pendientes y no inventa pagos', () => {
  const r = resumen([], { gastosFijos: [{ id: 1, monto_mensual: 250 }] });
  assert.equal(r.gastos_registrados, 0);
  assert.equal(r.gastos_pagados, 0);
  assert.equal(r.total_pendiente, 250);
  assert.equal(r.disponible_real, 1000);
  assert.equal(r.disponible_proyectado, 750);
});
