'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { calcularAnalisisCategorias, calcularVariaciones, variabilidad } = require('../finanzas/analisis-variaciones');

const registro = (categoria, tipo, monto) => ({ categoria, tipo, monto });

test('FIN-02: agrupa registros por categoría y calcula desviación vs presupuesto', () => {
  const registros = [
    registro('comida', 'variable', '280.00'),
    registro('ocio', 'variable', '150.00'),
    registro('ocio', 'no_presupuestado', '70.00'),
  ];
  const cats = calcularAnalisisCategorias(registros, { comida: 300, ocio: 150 });
  const comida = cats.find(c => c.categoria === 'comida');
  const ocio = cats.find(c => c.categoria === 'ocio');

  assert.equal(comida.total_gastado, 280);
  assert.equal(comida.desviacion, -20);
  assert.equal(comida.pct_desviacion, -6.7);

  assert.equal(ocio.total_gastado, 220);
  assert.equal(ocio.gastado_no_presup, 70);
  assert.equal(ocio.desviacion, 70);
  assert.equal(ocio.pct_desviacion, 46.7);
});

test('FIN-02: sin presupuesto asignado, pct_desviacion es null (no se puede dividir por cero)', () => {
  const cats = calcularAnalisisCategorias([registro('transporte', 'no_presupuestado', '40.00')], {});
  assert.equal(cats[0].pct_desviacion, null);
  assert.equal(cats[0].desviacion, 40);
});

test('FIN-02: variabilidad requiere al menos 2 puntos y media positiva', () => {
  assert.equal(variabilidad([100]), null);
  assert.equal(variabilidad([]), null);
  assert.equal(variabilidad([0, 0]), null);
  assert.equal(variabilidad([100, 100]), 0);
  assert.ok(variabilidad([100, 50, 150]) > 0);
});

test('FIN-02: calcula variación vs mes anterior por categoría', () => {
  const categoriasActual = [
    { categoria: 'ocio', presupuestado: 150, total_gastado: 220, desviacion: 70, pct_desviacion: 46.7 },
    { categoria: 'transporte', presupuestado: 80, total_gastado: 80, desviacion: 0, pct_desviacion: 0 },
  ];
  const { categorias } = calcularVariaciones({
    categoriasActual,
    historicoPorCategoria: { ocio: [150, 100], transporte: [] },
  });
  const ocio = categorias.find(c => c.categoria === 'ocio');
  const transporte = categorias.find(c => c.categoria === 'transporte');

  assert.equal(ocio.variacion_vs_mes_anterior, 70);
  assert.equal(ocio.pct_variacion_vs_mes_anterior, 46.7);
  assert.equal(transporte.variacion_vs_mes_anterior, null);
  assert.equal(transporte.pct_variacion_vs_mes_anterior, null);
});

test('FIN-02: ranking de exceso y ahorro solo incluye categorías presupuestadas, ordenadas por magnitud', () => {
  const categoriasActual = [
    { categoria: 'ocio', presupuestado: 150, total_gastado: 220, desviacion: 70, pct_desviacion: 46.7 },
    { categoria: 'comida', presupuestado: 300, total_gastado: 280, desviacion: -20, pct_desviacion: -6.7 },
    { categoria: 'utilities', presupuestado: 100, total_gastado: 55, desviacion: -45, pct_desviacion: -45 },
    { categoria: 'regalos', presupuestado: 0, total_gastado: 30, desviacion: 30, pct_desviacion: null },
  ];
  const { ranking_exceso, ranking_ahorro } = calcularVariaciones({ categoriasActual, historicoPorCategoria: {} });

  assert.deepEqual(ranking_exceso.map(c => c.categoria), ['ocio']);
  assert.deepEqual(ranking_ahorro.map(c => c.categoria), ['utilities', 'comida']);
});

test('FIN-02: insight de alza vs mes anterior solo dispara sobre +30% y +$10 absolutos', () => {
  const categoriasActual = [
    { categoria: 'ocio', presupuestado: 150, total_gastado: 220, desviacion: 70, pct_desviacion: 46.7 },
  ];
  const conAlza = calcularVariaciones({ categoriasActual, historicoPorCategoria: { ocio: [150] } });
  assert.ok(conAlza.insights.some(i => i.tipo === 'alza_vs_mes_anterior' && i.categoria === 'ocio'));

  const chico = calcularVariaciones({
    categoriasActual: [{ categoria: 'ocio', presupuestado: 150, total_gastado: 12, desviacion: -138, pct_desviacion: -92 }],
    historicoPorCategoria: { ocio: [5] }, // +140% pero solo +$7 — no debe disparar
  });
  assert.ok(!chico.insights.some(i => i.tipo === 'alza_vs_mes_anterior'));
});

test('FIN-02: insight de variabilidad solo cuando una categoría destaca claramente sobre las demás', () => {
  const categoriasActual = [
    { categoria: 'comida', presupuestado: 300, total_gastado: 280, desviacion: -20, pct_desviacion: -6.7 },
    { categoria: 'transporte', presupuestado: 80, total_gastado: 80, desviacion: 0, pct_desviacion: 0 },
  ];
  const irregular = calcularVariaciones({
    categoriasActual,
    historicoPorCategoria: { comida: [100, 460], transporte: [79, 81] },
  });
  assert.ok(irregular.insights.some(i => i.tipo === 'variabilidad' && i.categoria === 'comida'));

  const parejo = calcularVariaciones({
    categoriasActual,
    historicoPorCategoria: { comida: [252, 308], transporte: [72, 88] }, // misma variabilidad relativa (~8%)
  });
  assert.ok(!parejo.insights.some(i => i.tipo === 'variabilidad'));
});

test('FIN-02: insight de oportunidad de ahorro apunta a la categoría con mayor ahorro absoluto', () => {
  const categoriasActual = [
    { categoria: 'comida', presupuestado: 300, total_gastado: 280, desviacion: -20, pct_desviacion: -6.7 },
    { categoria: 'utilities', presupuestado: 100, total_gastado: 55, desviacion: -45, pct_desviacion: -45 },
  ];
  const { insights } = calcularVariaciones({ categoriasActual, historicoPorCategoria: {} });
  const ahorro = insights.find(i => i.tipo === 'oportunidad_ahorro');
  assert.ok(ahorro);
  assert.equal(ahorro.categoria, 'utilities');
  assert.match(ahorro.mensaje, /45\.00/);
});

test('FIN-02: sin desviaciones ni histórico, no genera insights ni rankings', () => {
  const categoriasActual = [
    { categoria: 'comida', presupuestado: 300, total_gastado: 300, desviacion: 0, pct_desviacion: 0 },
  ];
  const r = calcularVariaciones({ categoriasActual, historicoPorCategoria: {} });
  assert.deepEqual(r.ranking_exceso, []);
  assert.deepEqual(r.ranking_ahorro, []);
  assert.deepEqual(r.insights, []);
});
