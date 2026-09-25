'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  clasificarCategoria, detectarDesviacionConsistente, calcularSugerenciasPresupuesto,
} = require('../finanzas/cierre-mes-insights');

test('FIN-03: clasifica categorías flexibles vs esenciales', () => {
  assert.equal(clasificarCategoria('ocio'), 'flexible');
  assert.equal(clasificarCategoria('ropa'), 'flexible');
  assert.equal(clasificarCategoria('otro'), 'flexible');
  assert.equal(clasificarCategoria('alimentacion'), 'esencial');
  assert.equal(clasificarCategoria('vivienda'), 'esencial');
  assert.equal(clasificarCategoria('deudas'), 'esencial');
});

test('FIN-03: detecta exceso consistente solo si TODOS los meses superan el umbral', () => {
  assert.equal(detectarDesviacionConsistente([140, 130, 135], 100), 'exceso');
  assert.equal(detectarDesviacionConsistente([140, 90, 135], 100), null); // un mes rompe el patrón
  assert.equal(detectarDesviacionConsistente([110, 111, 112], 100), null); // no supera el umbral (15%)
});

test('FIN-03: detecta ahorro consistente solo si TODOS los meses están por debajo del umbral', () => {
  assert.equal(detectarDesviacionConsistente([60, 70, 65], 100), 'ahorro');
  assert.equal(detectarDesviacionConsistente([60, 100, 65], 100), null);
});

test('FIN-03: sin al menos 3 meses de datos, no hay patrón (evita disparar con 1 mes atípico)', () => {
  assert.equal(detectarDesviacionConsistente([140, 130], 100), null);
  assert.equal(detectarDesviacionConsistente([140], 100), null);
});

test('FIN-03: sin presupuesto no hay patrón que detectar', () => {
  assert.equal(detectarDesviacionConsistente([140, 130, 135], 0), null);
});

const cat = (categoria, presupuestado, total_gastado) => ({ categoria, presupuestado, total_gastado });
const item = (id, nombre, monto_estimado) => ({ id, nombre, monto_estimado });

test('FIN-03: categoría esencial con exceso consistente sugiere SUBIR el presupuesto', () => {
  const sugerencias = calcularSugerenciasPresupuesto({
    categoriasActual: [cat('alimentacion', 300, 400)],
    historicoPorCategoria: { alimentacion: [390, 410] },
    itemsVariablesPorCategoria: { alimentacion: [item(1, 'Supermercado', 300)] },
  });
  assert.equal(sugerencias.length, 1);
  assert.equal(sugerencias[0].direccion, 'subir');
  assert.equal(sugerencias[0].presupuesto_actual, 300);
  assert.ok(sugerencias[0].presupuesto_sugerido > 300);
});

test('FIN-03: categoría FLEXIBLE con exceso consistente NUNCA sugiere subir el presupuesto', () => {
  const sugerencias = calcularSugerenciasPresupuesto({
    categoriasActual: [cat('ocio', 150, 220)],
    historicoPorCategoria: { ocio: [210, 230] },
    itemsVariablesPorCategoria: { ocio: [item(2, 'Salidas', 150)] },
  });
  assert.equal(sugerencias.length, 0);
});

test('FIN-03: cualquier categoría con ahorro consistente sugiere BAJAR el presupuesto (libera dinero)', () => {
  const flexible = calcularSugerenciasPresupuesto({
    categoriasActual: [cat('ocio', 150, 60)],
    historicoPorCategoria: { ocio: [65, 55] },
    itemsVariablesPorCategoria: { ocio: [item(2, 'Salidas', 150)] },
  });
  assert.equal(flexible.length, 1);
  assert.equal(flexible[0].direccion, 'bajar');

  const esencial = calcularSugerenciasPresupuesto({
    categoriasActual: [cat('transporte', 100, 60)],
    historicoPorCategoria: { transporte: [65, 55] },
    itemsVariablesPorCategoria: { transporte: [item(3, 'Gasolina', 100)] },
  });
  assert.equal(esencial.length, 1);
  assert.equal(esencial[0].direccion, 'bajar');
});

test('FIN-03: categoría sin ningún item en gastos_variables_base no genera sugerencia (nada ajustable)', () => {
  const sugerencias = calcularSugerenciasPresupuesto({
    categoriasActual: [cat('alimentacion', 300, 400)],
    historicoPorCategoria: { alimentacion: [390, 410] },
    itemsVariablesPorCategoria: {},
  });
  assert.equal(sugerencias.length, 0);
});

test('FIN-03: categoría con componente fijo mezclado se omite (no se sabe cuánto es ajustable)', () => {
  const sugerencias = calcularSugerenciasPresupuesto({
    categoriasActual: [cat('vivienda', 500, 650)],
    historicoPorCategoria: { vivienda: [640, 660] },
    itemsVariablesPorCategoria: { vivienda: [item(4, 'Mantenimiento', 100)] },
    fijoPorCategoria: { vivienda: 400 },
  });
  assert.equal(sugerencias.length, 0);
});

test('FIN-03: la sugerencia lleva los items ajustables para que el frontend prorratee el ajuste', () => {
  const sugerencias = calcularSugerenciasPresupuesto({
    categoriasActual: [cat('alimentacion', 300, 400)],
    historicoPorCategoria: { alimentacion: [390, 410] },
    itemsVariablesPorCategoria: {
      alimentacion: [item(1, 'Supermercado', 200), item(2, 'Restaurantes', 100)],
    },
  });
  assert.equal(sugerencias[0].items.length, 2);
  assert.deepEqual(sugerencias[0].items.map(i => i.nombre), ['Supermercado', 'Restaurantes']);
});
