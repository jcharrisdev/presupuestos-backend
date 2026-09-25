'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { calcularAnalisisCategorias, calcularVariaciones } = require('../finanzas/analisis-variaciones');
const { calcularSugerenciasPresupuesto } = require('../finanzas/cierre-mes-insights');

// Ejecuta el handler real con una BD en memoria, igual que resumen-mensual-endpoint.test.js:
// no se importa server.js completo para evitar migraciones/cron/conexiones externas.
const source = fs.readFileSync(path.join(__dirname, '../server.js'), 'utf8');
const start = source.indexOf("app.get('/user/meses/:anio/:mes/analisis-variaciones',");
const end = source.indexOf('// PATCH /user/estado-anual/:anio/recalcular', start);
assert.ok(start >= 0 && end > start, 'No se encontró el handler de análisis de variaciones');

function crearEndpoint({ mesId = 7, registros = [], varBase = [], fijosCat = [], mesesAnteriores = [], historicosPorMes = [] } = {}) {
  let handler;
  const db = {
    async execute(sql, params) {
      assert.ok(/^\s*SELECT\b/.test(sql), 'La consulta debe ser de solo lectura');
      assert.ok(Array.from(params).includes('prueba-usuario'), 'Toda consulta debe estar limitada al usuario');
      if (sql.includes('FROM meses_financieros') && sql.includes('SELECT id FROM')) {
        assert.deepEqual(Array.from(params), ['prueba-usuario', '2026', '9']);
        return [mesId != null ? [{ id: mesId }] : []];
      }
      if (sql.includes('FROM registros_gasto') && sql.includes('WHERE mes_id = ?')) {
        assert.deepEqual(Array.from(params), [mesId, 'prueba-usuario']);
        return [registros];
      }
      if (sql.includes('FROM gastos_variables_base')) return [varBase];
      if (sql.includes('FROM user_gastos_fijos')) return [fijosCat];
      if (sql.includes('FROM meses_financieros') && sql.includes('anio < ?')) {
        assert.deepEqual(Array.from(params), ['prueba-usuario', '2026', '2026', '9']);
        return [mesesAnteriores];
      }
      if (sql.includes('FROM registros_gasto') && sql.includes('mes_id IN')) {
        const idsEsperados = mesesAnteriores.map(m => m.id);
        assert.deepEqual(Array.from(params), ['prueba-usuario', ...idsEsperados]);
        return [historicosPorMes];
      }
      throw new Error(`Consulta inesperada: ${sql}`);
    },
  };
  vm.runInNewContext(source.slice(start, end), {
    app: { get(route, callback) { handler = callback; } }, db,
    calcularAnalisisCategorias, calcularVariaciones, calcularSugerenciasPresupuesto,
    _montoMensual: g => Number(g.monto_mensual),
    parseInt, ANALISIS_VARIACIONES_MESES_HISTORICO: 3,
  });
  return {
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

test('FIN-02: sin firebase_uid devuelve 400 sin consultar la BD', async () => {
  const api = crearEndpoint();
  const { status, body } = await api.get('');
  assert.equal(status, 400);
  assert.match(body.error, /firebase_uid/);
});

test('FIN-02: mes inexistente devuelve 404', async () => {
  const api = crearEndpoint({ mesId: null });
  const { status } = await api.get();
  assert.equal(status, 404);
});

test('FIN-02: sin meses anteriores, no hay histórico pero sí categorías y rankings del mes actual', async () => {
  const registros = [
    { categoria: 'ocio', tipo: 'variable', monto: '220.00' },
    { categoria: 'comida', tipo: 'variable', monto: '280.00' },
  ];
  const varBase = [
    { categoria: 'ocio', monto_mensual: '150.00', aplica_meses: null },
    { categoria: 'comida', monto_mensual: '300.00', aplica_meses: null },
  ];
  const api = crearEndpoint({ registros, varBase });
  const { status, body } = await api.get();

  assert.equal(status, 200, JSON.stringify(body));
  assert.deepEqual(body.meses_comparados, []);
  const ocio = body.categorias.find(c => c.categoria === 'ocio');
  assert.equal(ocio.desviacion, 70);
  assert.equal(ocio.variacion_vs_mes_anterior, null);
  assert.deepEqual(body.ranking_exceso.map(c => c.categoria), ['ocio']);
  assert.deepEqual(body.ranking_ahorro.map(c => c.categoria), ['comida']);
});

test('FIN-02: con meses anteriores, calcula variación vs mes pasado e insight de alza', async () => {
  const registros = [{ categoria: 'ocio', tipo: 'variable', monto: '220.00' }];
  const varBase = [{ categoria: 'ocio', monto_mensual: '150.00', aplica_meses: null }];
  const mesesAnteriores = [{ id: 6, anio: 2026, mes: 8 }, { id: 5, anio: 2026, mes: 7 }];
  const historicosPorMes = [
    { mes_id: 6, categoria: 'ocio', total: '150.00' },
    { mes_id: 5, categoria: 'ocio', total: '140.00' },
  ];
  const api = crearEndpoint({ registros, varBase, mesesAnteriores, historicosPorMes });
  const { status, body } = await api.get();

  assert.equal(status, 200, JSON.stringify(body));
  assert.deepEqual(body.meses_comparados, [{ anio: 2026, mes: 8 }, { anio: 2026, mes: 7 }]);
  const ocio = body.categorias.find(c => c.categoria === 'ocio');
  assert.equal(ocio.variacion_vs_mes_anterior, 70);
  assert.equal(ocio.pct_variacion_vs_mes_anterior, 46.7);
  assert.ok(body.insights.some(i => i.tipo === 'alza_vs_mes_anterior' && i.categoria === 'ocio'));
});

test('FIN-03: exceso consistente en categoría esencial devuelve sugerencia de subir presupuesto con sus items', async () => {
  const registros = [{ categoria: 'alimentacion', tipo: 'variable', monto: '400.00' }];
  const varBase = [{
    id: 10, nombre: 'Supermercado', categoria: 'alimentacion',
    monto_estimado: '300.00', monto_mensual: '300.00', aplica_meses: null,
  }];
  const mesesAnteriores = [{ id: 6, anio: 2026, mes: 8 }, { id: 5, anio: 2026, mes: 7 }];
  const historicosPorMes = [
    { mes_id: 6, categoria: 'alimentacion', total: '390.00' },
    { mes_id: 5, categoria: 'alimentacion', total: '410.00' },
  ];
  const api = crearEndpoint({ registros, varBase, mesesAnteriores, historicosPorMes });
  const { status, body } = await api.get();

  assert.equal(status, 200, JSON.stringify(body));
  assert.equal(body.sugerencias_presupuesto.length, 1);
  const sug = body.sugerencias_presupuesto[0];
  assert.equal(sug.categoria, 'alimentacion');
  assert.equal(sug.clasificacion, 'esencial');
  assert.equal(sug.direccion, 'subir');
  assert.equal(sug.presupuesto_actual, 300);
  assert.deepEqual(sug.items, [{ id: 10, nombre: 'Supermercado', monto_estimado: 300 }]);
});

test('FIN-03: sin patrón consistente (solo el mes actual), no hay sugerencias', async () => {
  const registros = [{ categoria: 'alimentacion', tipo: 'variable', monto: '400.00' }];
  const varBase = [{
    id: 10, nombre: 'Supermercado', categoria: 'alimentacion',
    monto_estimado: '300.00', monto_mensual: '300.00', aplica_meses: null,
  }];
  const api = crearEndpoint({ registros, varBase });
  const { status, body } = await api.get();

  assert.equal(status, 200, JSON.stringify(body));
  assert.deepEqual(body.sugerencias_presupuesto, []);
});
