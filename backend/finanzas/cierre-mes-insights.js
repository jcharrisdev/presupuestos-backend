'use strict';

// FIN-03: cierre de mes con aprendizaje — si una categoría se desvió de forma
// consistente (no solo un mes atípico), sugerir ajustar su presupuesto para
// el mes siguiente. Nunca se auto-aplica: el usuario decide.
//
// Guardrails (validados con el asesor financiero del proyecto):
// - Una categoría FLEXIBLE (discrecional) que gasta de más nunca recibe
//   sugerencia de subir su límite — normalizaría el sobregasto. Solo se
//   sugiere bajar cuando hay ahorro consistente (libera dinero real).
// - Una categoría ESENCIAL que gasta de más sí puede subir: el presupuesto
//   original probablemente estaba mal calibrado, y seguir mostrándolo en
//   rojo cada mes sin corregirlo solo genera ansiedad sin ayudar.
// - Se requieren al menos 3 meses de datos (actual + 2 anteriores) en la
//   MISMA dirección para hablar de patrón, no de un mes atípico.

const CATEGORIAS_FLEXIBLES = new Set(['ocio', 'ropa', 'deportes', 'tecnologia', 'otro']);

function clasificarCategoria(categoria) {
  return CATEGORIAS_FLEXIBLES.has(categoria) ? 'flexible' : 'esencial';
}

const UMBRAL_DESVIACION_PCT = 15;
const MESES_MINIMOS_PATRON = 3;

// serie: [mes actual, mes-1, mes-2, ...] gasto real por mes, más reciente primero.
// presupuestoActual: única referencia disponible (no hay snapshot histórico del
// presupuesto vigente en cada mes — limitación conocida, documentada en PR #4).
function detectarDesviacionConsistente(serie, presupuestoActual) {
  if (!(presupuestoActual > 0)) return null;
  if (!serie || serie.length < MESES_MINIMOS_PATRON) return null;
  const pct = serie.map(gasto => (gasto - presupuestoActual) / presupuestoActual * 100);
  if (pct.every(p => p > UMBRAL_DESVIACION_PCT)) return 'exceso';
  if (pct.every(p => p < -UMBRAL_DESVIACION_PCT)) return 'ahorro';
  return null;
}

function redondeoAmigable(monto) {
  return Math.round(monto / 5) * 5;
}

// itemsVariablesPorCategoria: { categoria: [{id, nombre, monto_estimado}, ...] }
//   — solo gastos_variables_base (lo único ajustable desde aquí).
// fijoPorCategoria: { categoria: montoFijoMensual } — si una categoría mezcla
//   fijo + variable, se omite (no se sabe cuánto del presupuesto total es ajustable).
function calcularSugerenciasPresupuesto({
  categoriasActual, historicoPorCategoria = {}, itemsVariablesPorCategoria = {}, fijoPorCategoria = {},
}) {
  const sugerencias = [];
  for (const cat of categoriasActual) {
    const items = itemsVariablesPorCategoria[cat.categoria];
    if (!items || items.length === 0) continue;
    if ((fijoPorCategoria[cat.categoria] || 0) > 0) continue;
    const presupuestoActual = cat.presupuestado;
    if (!(presupuestoActual > 0)) continue;

    const historico = historicoPorCategoria[cat.categoria] || [];
    const serie = [cat.total_gastado, ...historico];
    const patron = detectarDesviacionConsistente(serie, presupuestoActual);
    if (!patron) continue;

    const clasificacion = clasificarCategoria(cat.categoria);
    const direccion = patron === 'ahorro' ? 'bajar' : (clasificacion === 'esencial' ? 'subir' : null);
    if (!direccion) continue;

    const puntos = serie.slice(0, MESES_MINIMOS_PATRON);
    const promedio = puntos.reduce((s, v) => s + v, 0) / puntos.length;
    const sugerido = redondeoAmigable(promedio);
    if (sugerido === presupuestoActual) continue;

    sugerencias.push({
      categoria: cat.categoria,
      clasificacion,
      direccion,
      presupuesto_actual: presupuestoActual,
      presupuesto_sugerido: sugerido,
      meses_considerados: puntos.length,
      razon: direccion === 'subir'
        ? `Llevas ${puntos.length} meses gastando más de lo presupuestado en esta categoría.`
        : `Llevas ${puntos.length} meses gastando menos de lo presupuestado en esta categoría.`,
      items: items.map(i => ({ id: i.id, nombre: i.nombre, monto_estimado: Number(i.monto_estimado) })),
    });
  }
  return sugerencias;
}

module.exports = { clasificarCategoria, detectarDesviacionConsistente, calcularSugerenciasPresupuesto };
