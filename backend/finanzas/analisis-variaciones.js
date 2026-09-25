'use strict';

// FIN-02: por qué el usuario se desvió del presupuesto, categoría por categoría.
// Reutiliza el mismo agrupado que ya usa GET /user/meses/:anio/:mes (analisis_categorias)
// para no introducir un segundo criterio de "cuánto gastó" por categoría (ver V2).

function calcularAnalisisCategorias(registros, presupuestadoPorCat = {}) {
  const porCategoria = {};
  // Una categoría presupuestada con $0 gastado este mes es el mayor ahorro
  // posible (100%): debe seguir apareciendo, no solo las que tienen registros.
  for (const cat of Object.keys(presupuestadoPorCat)) {
    porCategoria[cat] = { categoria: cat, fijo: 0, variable: 0, no_presupuestado: 0, total: 0 };
  }
  for (const r of registros) {
    const cat = r.categoria;
    if (!porCategoria[cat]) {
      porCategoria[cat] = { categoria: cat, fijo: 0, variable: 0, no_presupuestado: 0, total: 0 };
    }
    const bucket = r.tipo === 'no_presupuestado' ? 'no_presupuestado' : r.tipo;
    porCategoria[cat][bucket] = (porCategoria[cat][bucket] || 0) + Number(r.monto);
    porCategoria[cat].total += Number(r.monto);
  }
  return Object.entries(porCategoria).map(([cat, datos]) => {
    const presup = presupuestadoPorCat[cat] || 0;
    const desv = datos.total - presup;
    return {
      categoria: cat,
      presupuestado: parseFloat(presup.toFixed(2)),
      gastado_variable: parseFloat(datos.variable.toFixed(2)),
      gastado_no_presup: parseFloat(datos.no_presupuestado.toFixed(2)),
      total_gastado: parseFloat(datos.total.toFixed(2)),
      desviacion: parseFloat(desv.toFixed(2)),
      pct_desviacion: presup > 0 ? parseFloat((desv / presup * 100).toFixed(1)) : null,
    };
  });
}

// Coeficiente de variación (desviación estándar / media) en %, sobre una serie
// de gastos reales mes a mes. Necesita al menos 2 puntos; con media 0 no hay
// variabilidad relativa que reportar.
function variabilidad(serie) {
  if (!serie || serie.length < 2) return null;
  const media = serie.reduce((s, v) => s + v, 0) / serie.length;
  if (media <= 0) return null;
  const varianza = serie.reduce((s, v) => s + (v - media) ** 2, 0) / serie.length;
  return parseFloat((Math.sqrt(varianza) / media * 100).toFixed(1));
}

const RANKING_TOP = 3;

function calcularVariaciones({ categoriasActual, historicoPorCategoria = {} }) {
  const categorias = categoriasActual.map(cat => {
    const historico = historicoPorCategoria[cat.categoria] || []; // más reciente primero
    const mesAnterior = historico[0];
    let variacionVsMesAnterior = null;
    let pctVariacionVsMesAnterior = null;
    if (mesAnterior != null) {
      variacionVsMesAnterior = parseFloat((cat.total_gastado - mesAnterior).toFixed(2));
      pctVariacionVsMesAnterior = mesAnterior > 0
        ? parseFloat((variacionVsMesAnterior / mesAnterior * 100).toFixed(1))
        : null;
    }
    return {
      ...cat,
      variacion_vs_mes_anterior: variacionVsMesAnterior,
      pct_variacion_vs_mes_anterior: pctVariacionVsMesAnterior,
      variabilidad_pct: variabilidad([cat.total_gastado, ...historico]),
    };
  });

  const conPresupuesto = categorias.filter(c => c.presupuestado > 0);
  const rankingExceso = [...conPresupuesto]
    .filter(c => c.desviacion > 0)
    .sort((a, b) => b.desviacion - a.desviacion)
    .slice(0, RANKING_TOP);
  const rankingAhorro = [...conPresupuesto]
    .filter(c => c.desviacion < 0)
    .sort((a, b) => a.desviacion - b.desviacion)
    .slice(0, RANKING_TOP);

  return { categorias, ranking_exceso: rankingExceso, ranking_ahorro: rankingAhorro, insights: generarInsights(categorias) };
}

const nombreLegible = cat => cat ? `${cat[0].toUpperCase()}${cat.slice(1)}` : cat;

function generarInsights(categorias) {
  const insights = [];

  // 1) La categoría cuyo gasto subió más fuerte vs el mes pasado (umbral: +30% y +$10 absolutos).
  const conAlza = categorias
    .filter(c => c.pct_variacion_vs_mes_anterior != null && c.pct_variacion_vs_mes_anterior > 30
      && Math.abs(c.variacion_vs_mes_anterior) >= 10)
    .sort((a, b) => b.pct_variacion_vs_mes_anterior - a.pct_variacion_vs_mes_anterior)[0];
  if (conAlza) {
    insights.push({
      tipo: 'alza_vs_mes_anterior',
      categoria: conAlza.categoria,
      mensaje: `${nombreLegible(conAlza.categoria)} subió ${conAlza.pct_variacion_vs_mes_anterior.toFixed(0)}% vs el mes pasado — ¿cambió algo?`,
    });
  }

  // 2) La categoría más irregular mes a mes, si claramente destaca sobre el resto.
  const conVariabilidad = categorias.filter(c => c.variabilidad_pct != null);
  if (conVariabilidad.length >= 2) {
    const ordenada = [...conVariabilidad].sort((a, b) => b.variabilidad_pct - a.variabilidad_pct);
    const [top, segunda] = ordenada;
    if (top.variabilidad_pct > 0 && (segunda.variabilidad_pct === 0 || top.variabilidad_pct / segunda.variabilidad_pct >= 1.5)) {
      const factor = segunda.variabilidad_pct > 0 ? (top.variabilidad_pct / segunda.variabilidad_pct) : null;
      insights.push({
        tipo: 'variabilidad',
        categoria: top.categoria,
        mensaje: factor
          ? `${nombreLegible(top.categoria)} es ${factor.toFixed(1)}x más variable que ${nombreLegible(segunda.categoria)} — tendencia irregular`
          : `${nombreLegible(top.categoria)} varía mucho mes a mes — tendencia irregular`,
      });
    }
  }

  // 3) La mayor oportunidad de ahorro consistente: la categoría con más ahorro vs su presupuesto.
  const conAhorro = categorias
    .filter(c => c.desviacion < 0 && (c.presupuestado || 0) > 0)
    .sort((a, b) => a.desviacion - b.desviacion)[0];
  if (conAhorro) {
    insights.push({
      tipo: 'oportunidad_ahorro',
      categoria: conAhorro.categoria,
      mensaje: `Si replicas el ahorro de ${nombreLegible(conAhorro.categoria)}, liberas ${Math.abs(conAhorro.desviacion).toFixed(2)}/mes`,
    });
  }

  return insights;
}

module.exports = { calcularAnalisisCategorias, calcularVariaciones, variabilidad };
