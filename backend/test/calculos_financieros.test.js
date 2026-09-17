// Fija la zona horaria para que las fechas no varíen según dónde corra el test
process.env.TZ = 'UTC';

const { test } = require('node:test');
const assert = require('node:assert/strict');

const {
  _montoMensual,
  _generarAplicaMeses,
  calcularFechaFin,
  _simularDeudas,
  _construirTimeline,
  calcularSplits,
  _calcularScore,
} = require('../lib/calculos_financieros');

test('_montoMensual: normaliza cada frecuencia a mensual', () => {
  assert.equal(_montoMensual({ monto_estimado: 50, frecuencia: 'quincenal' }), 100);
  assert.equal(_montoMensual({ monto_estimado: 10, frecuencia: 'semanal' }), 43.3);
  assert.equal(_montoMensual({ monto_estimado: 120, frecuencia: 'anual' }), 10);
  assert.equal(_montoMensual({ monto_estimado: 75, frecuencia: 'mensual' }), 75);
});

test('_generarAplicaMeses: genera el rango de meses y respeta límites 1-12', () => {
  assert.deepEqual(_generarAplicaMeses(3, 6), [3, 4, 5, 6]);
  assert.deepEqual(_generarAplicaMeses(1, 12), [1,2,3,4,5,6,7,8,9,10,11,12]);
  assert.deepEqual(_generarAplicaMeses(0, 15), [1,2,3,4,5,6,7,8,9,10,11,12]);
  // mes_fin menor que mes_inicio: la quincena de un solo mes
  assert.deepEqual(_generarAplicaMeses(8, 5), [8]);
});

test('calcularFechaFin: quincena 1 termina el día 15', () => {
  assert.equal(calcularFechaFin('2026-03-01', 'quincenal'), '2026-03-15');
});

test('calcularFechaFin: quincena 2 termina el último día del mes (incluye febrero corto)', () => {
  assert.equal(calcularFechaFin('2026-02-16', 'quincenal'), '2026-02-28');
});

test('calcularFechaFin: mensual termina el día anterior al mismo día del mes siguiente', () => {
  assert.equal(calcularFechaFin('2026-05-01', 'mensual'), '2026-05-31');
});

test('_simularDeudas: sin deudas activas devuelve 0 meses', () => {
  const r = _simularDeudas([], 0, 'avalanche');
  assert.equal(r.meses_totales, 0);
  assert.deepEqual(r.orden, []);
});

test('_simularDeudas: avalanche prioriza la tasa de interés más alta primero', () => {
  const deudas = [
    { id: 1, nombre: 'Tarjeta cara', activa: 1, tipo: 'revolving', monto_pendiente: 1000, tasa_interes: 36, pago_minimo: 50 },
    { id: 2, nombre: 'Préstamo barato', activa: 1, tipo: 'letra', monto_pendiente: 1000, tasa_interes: 6, pago_minimo: 50 },
  ];
  const r = _simularDeudas(deudas, 200, 'avalanche');
  // La deuda con mayor tasa (id 1) debe saldarse antes o al mismo tiempo que la de menor tasa
  const mesCara   = r.orden.find(d => d.id === 1).mes_saldado;
  const mesBarata = r.orden.find(d => d.id === 2).mes_saldado;
  assert.ok(mesCara <= mesBarata);
});

test('_simularDeudas: snowball prioriza el saldo más pequeño primero', () => {
  const deudas = [
    { id: 1, nombre: 'Saldo grande', activa: 1, tipo: 'revolving', monto_pendiente: 2000, tasa_interes: 10, pago_minimo: 50 },
    { id: 2, nombre: 'Saldo chico', activa: 1, tipo: 'revolving', monto_pendiente: 200, tasa_interes: 10, pago_minimo: 50 },
  ];
  const r = _simularDeudas(deudas, 200, 'snowball');
  const mesGrande = r.orden.find(d => d.id === 1).mes_saldado;
  const mesChico  = r.orden.find(d => d.id === 2).mes_saldado;
  assert.ok(mesChico <= mesGrande);
});

test('_construirTimeline: un mes con ingreso fijo y sin deudas queda "buena" si compromisos < 70%', () => {
  const income = { ingreso_neto_mensual: 1000 };
  const gastosFijos = [{ monto_mensual: 300 }];
  const timeline = _construirTimeline(income, gastosFijos, [], 1);
  assert.equal(timeline.length, 1);
  assert.equal(timeline[0].disponible, 700);
  assert.equal(timeline[0].salud, 'buena');
});

test('_construirTimeline: una deuda tipo letra se salda cuando la cuota agota el pendiente', () => {
  const income = { ingreso_neto_mensual: 1000 };
  const deudas = [{ id: 9, nombre: 'Letra carro', monto_pendiente: 300, tasa_interes: 0, cuota_fija: 300, es_letra: true }];
  const timeline = _construirTimeline(income, [], deudas, 2);
  assert.equal(timeline[0].eventos.length, 1);
  assert.equal(timeline[0].eventos[0].tipo, 'deuda_saldada');
  // Mes 2 ya no debe cobrar la cuota liberada
  assert.equal(timeline[1].cuotas_deudas, 0);
});

test('calcularSplits: equitativo divide el monto entre todos los miembros', () => {
  const r = calcularSplits(100, 'equitativo', [{ firebase_uid: 'a' }, { firebase_uid: 'b' }]);
  assert.deepEqual(r, [
    { firebase_uid: 'a', monto_responsabilidad: 50 },
    { firebase_uid: 'b', monto_responsabilidad: 50 },
  ]);
});

test('calcularSplits: porcentual normaliza porcentajes que no suman 100', () => {
  const r = calcularSplits(100, 'porcentual', [
    { firebase_uid: 'a', porcentaje: 30 },
    { firebase_uid: 'b', porcentaje: 30 },
  ]);
  assert.equal(r[0].monto_responsabilidad, 50);
  assert.equal(r[1].monto_responsabilidad, 50);
});

test('calcularSplits: proporcional reparte según ingreso declarado', () => {
  const r = calcularSplits(100, 'proporcional', [
    { firebase_uid: 'a', ingreso_declarado: 3000 },
    { firebase_uid: 'b', ingreso_declarado: 1000 },
  ]);
  assert.equal(r[0].monto_responsabilidad, 75);
  assert.equal(r[1].monto_responsabilidad, 25);
});

test('calcularSplits: pool_contribucion no genera splits individuales', () => {
  assert.deepEqual(calcularSplits(100, 'pool_contribucion', [{ firebase_uid: 'a' }]), []);
});

test('_calcularScore: sin ingreso devuelve neutral (50)', () => {
  assert.equal(_calcularScore({ ingresoNeto: 0, totalGastosFijos: 0, totalCuotasDeudas: 0, totalAhorros: 0, pagosCumplidos: 0, pagosTotales: 0 }), 50);
});

test('_calcularScore: sin deudas, gastos bajos y buen ahorro da un score alto', () => {
  const score = _calcularScore({
    ingresoNeto: 1000, totalGastosFijos: 300, totalCuotasDeudas: 0,
    totalAhorros: 250, pagosCumplidos: 10, pagosTotales: 10,
  });
  assert.ok(score >= 80, `esperaba score >= 80, dio ${score}`);
});

test('_calcularScore: deudas altas y sin ahorro dan un score bajo', () => {
  const score = _calcularScore({
    ingresoNeto: 1000, totalGastosFijos: 900, totalCuotasDeudas: 600,
    totalAhorros: 0, pagosCumplidos: 2, pagosTotales: 10,
  });
  assert.ok(score <= 40, `esperaba score <= 40, dio ${score}`);
});
