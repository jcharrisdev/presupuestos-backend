'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { calcularResumenMensual } = require('../finanzas/resumen-mensual');
const { calcularAnalisisCategorias } = require('../finanzas/analisis-variaciones');

// Ejecuta el handler real con una BD en memoria. No importa server.js:
// importar el monolito arrancaría migraciones, cron y conexiones externas.
const source = fs.readFileSync(path.join(__dirname, '../server.js'), 'utf8');
const start = source.indexOf("app.get('/user/meses/:anio/:mes',");
const end = source.indexOf('// GET /user/meses/:anio/:mes/analisis-variaciones', start);
assert.ok(start >= 0 && end > start, 'No se encontró el handler mensual');

function crearEndpoint({ mes = { id: 7, ingreso_estimado: '1000.00', ingreso_real: '1000.00', variables_estimados: '0.00' }, registros = [], fijos = [], deudas = [], eventos = [] } = {}) {
  let handler;
  const consultas = [];
  const db = {
    async execute(sql, params) {
      consultas.push({ sql, params });
      assert.ok(/^\s*SELECT\b/.test(sql), 'La consulta del resumen debe ser de solo lectura');
      assert.ok(params.includes('prueba-usuario'), 'Toda consulta debe estar limitada al usuario');
      if (sql.includes('FROM meses_financieros')) {
        assert.deepEqual(Array.from(params), ['prueba-usuario', '2026', '9']);
        return [[mes].filter(Boolean)];
      }
      if (sql.includes('FROM registros_gasto rg')) {
        assert.deepEqual(Array.from(params), [7, 'prueba-usuario']);
        assert.match(sql, /LEFT JOIN eventos_gastos eg/);
        assert.match(sql, /eg\.evento_id AS origen_evento_presupuesto_id/);
        return [registros];
      }
      if (sql.includes('FROM deudas d')) return [deudas];
      if (sql.includes('FROM gastos_variables_base')) return [[]];
      if (sql.includes('FROM user_gastos_fijos')) {
        return [sql.includes('categoria IS NOT NULL') ? [] : fijos];
      }
      if (sql.includes('FROM eventos_presupuesto ep')) {
        assert.deepEqual(Array.from(params), ['prueba-usuario', '2026', '9', '9']);
        return [eventos];
      }
      if (sql.includes('FROM registros_ingreso')) return [[]];
      throw new Error(`Consulta inesperada: ${sql}`);
    },
  };
  vm.runInNewContext(source.slice(start, end), {
    app: { get(route, callback) { handler = callback; } }, db, calcularResumenMensual, calcularAnalisisCategorias,
    _montoMensual: g => Number(g.monto_mensual),
  });
  return {
    consultas,
    async get(uid = 'prueba-usuario') {
      let status = 200, body;
      const res = {
        status(value) { status = value; return res; },
        json(value) { body = JSON.parse(JSON.stringify(value)); return res; },
      };
      await handler({ params: { anio: '2026', mes: '9' }, query: { firebase_uid: uid } }, res);
      return { status, body };
    },
  };
}

test('GET mensual conserva campos anteriores y entrega caja para Dashboard y Mes', async () => {
  const registros = [
    { id: 1, tipo: 'variable', categoria: 'otro', monto: '200.00', pagado: 1 },
    { id: 2, tipo: 'fijo', categoria: 'otro', monto: '100.00', pagado: 0, origen_fijo_id: 3 },
  ];
  const api = crearEndpoint({ registros, fijos: [{ id: 3, descripcion: 'Renta', monto_mensual: '300.00' }] });
  const antes = await api.get();
  assert.equal(antes.status, 200, JSON.stringify(antes.body));
  assert.equal(antes.body.resumen.fijos_reales, 100); // compatibilidad del total registrado
  assert.equal(antes.body.resumen.remanente_real, 700);
  assert.equal(antes.body.resumen.gastos_pagados, 200);
  assert.equal(antes.body.resumen.gastos_pendientes, 100);
  assert.equal(antes.body.resumen.compromisos_pendientes, 200);
  assert.equal(antes.body.resumen.total_pendiente, 300);
  assert.equal(antes.body.resumen.disponible_real, 800);
  assert.equal(antes.body.resumen.disponible_proyectado, 500);

  registros[1].pagado = 1; // estado que devuelve la BD tras confirmar el pago
  const despues = await api.get();
  assert.equal(despues.status, 200);
  assert.equal(despues.body.resumen.gastos_pagados, 300);
  assert.equal(despues.body.resumen.total_pendiente, 200);
  assert.equal(despues.body.resumen.disponible_real, 700);
  assert.equal(despues.body.resumen.disponible_proyectado, 500);
  assert.deepEqual((await api.get()).body, despues.body);
});

test('GET excluye del pendiente las deudas cuyo primer pago es posterior al mes', async () => {
  const api = crearEndpoint({ deudas: [
    { id: 1, pago_minimo: '90.00', es_letra: 0, mes_inicio_pago: 9 },
    { id: 2, pago_minimo: '200.00', es_letra: 0, mes_inicio_pago: 10 },
  ] });
  const { status, body } = await api.get();
  assert.equal(status, 200);
  assert.equal(body.resumen.total_pendiente, 90);
  assert.equal(body.resumen.disponible_proyectado, 910);
});

test('GET atribuye un gasto de evento al presupuesto padre y no al id del detalle', async () => {
  const api = crearEndpoint({
    registros: [{
      id: 9,
      tipo: 'variable',
      categoria: 'eventos',
      monto: '20.00',
      pagado: 1,
      origen_evento_id: 42,
      origen_evento_presupuesto_id: 3,
    }],
    eventos: [{ id: 3, nombre: 'Viaje', cuota_mensual: '60.00' }],
  });
  const { status, body } = await api.get();
  assert.equal(status, 200);
  assert.equal(body.resumen.gastos_pagados, 20);
  assert.equal(body.resumen.compromisos_pendientes, 40);
  assert.equal(body.resumen.total_pendiente, 40);
  assert.equal(body.resumen.disponible_proyectado, 940);
});

test('GET conserva la selección histórica del ingreso y la identifica como estimada', async () => {
  const api = crearEndpoint({ mes: { id: 7, ingreso_estimado: '1000.00', ingreso_real: '0.00', variables_estimados: 0 } });
  const { status, body } = await api.get();
  assert.equal(status, 200);
  assert.equal(body.resumen.ingreso_real, 1000);
  assert.equal(body.resumen.ingreso_es_estimado, true);
  assert.equal(body.resumen.disponible_real, 1000);
});

test('GET con ingreso cero y gasto pendiente no cambia un déficit por cero', async () => {
  const api = crearEndpoint({
    mes: { id: 7, ingreso_estimado: '0.00', ingreso_real: '0.00', variables_estimados: 0 },
    registros: [{ tipo: 'variable', categoria: 'otro', monto: 100, pagado: 0 }],
  });
  const { status, body } = await api.get();
  assert.equal(status, 200);
  assert.equal(body.resumen.disponible_real, 0);
  assert.equal(body.resumen.disponible_proyectado, -100);
});

test('GET sin usuario devuelve 400 sin consultar la BD', async () => {
  const api = crearEndpoint();
  assert.equal((await api.get(null)).status, 400);
  assert.equal(api.consultas.length, 0);
});

test('GET de un mes inexistente devuelve 404 sin inventar un resumen', async () => {
  const api = crearEndpoint({ mes: null });
  const { status, body } = await api.get();
  assert.equal(status, 404);
  assert.ok(body.error);
  assert.equal(api.consultas.length, 1);
});
