// Funciones puras de cálculo financiero (quincenas, deudas, splits, score).
// Sin dependencias de BD/red/tiempo real más allá de Date — extraídas de server.js
// para poder testearlas sin levantar el servidor ni conectar a la base de datos.

function _montoMensual(gasto) {
  const m = Number(gasto.monto_estimado);
  if (gasto.frecuencia === 'quincenal') return m * 2;
  if (gasto.frecuencia === 'semanal')   return parseFloat((m * 4.33).toFixed(2));
  if (gasto.frecuencia === 'anual')     return parseFloat((m / 12).toFixed(2));
  return m; // mensual
}

function _generarAplicaMeses(mesInicio, mesFin) {
  const inicio = Math.max(1, Math.min(12, Number(mesInicio) || 1));
  const fin    = Math.max(inicio, Math.min(12, Number(mesFin) || 12));
  const meses  = [];
  for (let m = inicio; m <= fin; m++) meses.push(m);
  return meses;
}

/**
 * Calcula la fecha de fin de un período dado su fecha de inicio.
 * - Quincenal: fecha_inicio + 14 días
 * - Mensual: último día del mes siguiente (para cubrir meses de 28, 30 o 31 días)
 *
 * @param {Date} fechaInicio
 * @param {string} tipoPeriodo - 'quincenal' | 'mensual'
 * @returns {string} Fecha de fin en formato "YYYY-MM-DD"
 */
function calcularFechaFin(fechaInicio, tipoPeriodo) {
  const f = new Date(fechaInicio);
  if (tipoPeriodo === 'quincenal') {
    // Períodos reales: 1-15 y 16-último día del mes
    if (f.getDate() <= 15) {
      f.setDate(15);
    } else {
      // Avanzar al mes siguiente y retroceder 1 día = último día del mes actual
      f.setMonth(f.getMonth() + 1);
      f.setDate(0);
    }
  } else {
    // Mensual: inicio 01/05 → fin 31/05
    f.setMonth(f.getMonth() + 1);
    f.setDate(f.getDate() - 1);
  }
  return f.toISOString().split('T')[0];
}

function _simularDeudas(deudas, extraMensual, estrategia) {
  // Clona y filtra deudas activas con saldo pendiente
  let pendientes = deudas
    .filter(d => d.activa && Number(d.monto_pendiente) > 0)
    .map(d => ({
      id: d.id,
      nombre: d.nombre,
      tipo: d.tipo,
      pendiente: Number(d.monto_pendiente),
      tasa_mensual: Number(d.tasa_interes || 0) / 100 / 12,
      pago_minimo: Number(d.pago_minimo || 0),
      total_intereses: 0,
      mes_saldado: null,
    }));

  if (!pendientes.length) return { meses_totales: 0, total_intereses: 0, orden: [] };

  // Orden según estrategia
  if (estrategia === 'avalanche') {
    pendientes.sort((a, b) => b.tasa_mensual - a.tasa_mensual);
  } else {
    pendientes.sort((a, b) => a.pendiente - b.pendiente);
  }

  let mes = 0;
  const MAX_MESES = 600;

  while (pendientes.some(d => d.pendiente > 0) && mes < MAX_MESES) {
    mes++;
    let extraDisp = Number(extraMensual) || 0;

    for (const d of pendientes) {
      if (d.pendiente <= 0) {
        // Pago mínimo liberado se redirige a la siguiente deuda objetivo
        extraDisp += d.pago_minimo;
        continue;
      }
      // Aplica interés
      const interes = d.pendiente * d.tasa_mensual;
      d.total_intereses += interes;
      d.pendiente += interes;
      // Pago mínimo
      const pago = Math.min(d.pago_minimo, d.pendiente);
      d.pendiente = Math.max(0, d.pendiente - pago);
      if (d.pendiente === 0 && !d.mes_saldado) d.mes_saldado = mes;
    }

    // Aplica monto extra (+ liberados) a la primera deuda con saldo (orden estratégico)
    for (const d of pendientes) {
      if (d.pendiente <= 0 || extraDisp <= 0) continue;
      const aplicar = Math.min(extraDisp, d.pendiente);
      d.pendiente = Math.max(0, d.pendiente - aplicar);
      extraDisp -= aplicar;
      if (d.pendiente === 0 && !d.mes_saldado) d.mes_saldado = mes;
      break;
    }
  }

  const hoy = new Date();
  const fechaFin = new Date(hoy.getFullYear(), hoy.getMonth() + mes, hoy.getDate());

  return {
    meses_totales: mes,
    fecha_fin: fechaFin.toISOString().slice(0, 10),
    total_intereses: parseFloat(pendientes.reduce((s, d) => s + d.total_intereses, 0).toFixed(2)),
    orden: pendientes.map(d => ({
      id: d.id, nombre: d.nombre, tipo: d.tipo,
      mes_saldado: d.mes_saldado,
      intereses_pagados: parseFloat(d.total_intereses.toFixed(2)),
    })),
  };
}

/**
 * Construye la proyección mes a mes del perfil financiero.
 * @param {object} income - Registro de user_income
 * @param {Array}  gastosFijos - Registros de user_gastos_fijos activos
 * @param {Array}  deudas - Registros de deudas activas
 * @param {number} meses - Cuántos meses proyectar (default 12)
 * @returns {Array} Array de objetos mensuales con disponible, eventos, etc.
 */
function _construirTimeline(income, gastosFijos, deudas, meses = 12) {
  const ingresoNeto   = income ? Number(income.ingreso_neto_mensual) : 0;
  const totalGastosFijos = gastosFijos.reduce((s, g) => s + Number(g.monto_mensual), 0);

  // Clonar estado de deudas para simular mes a mes
  const estadoDeudas = deudas.map(d => ({
    id:          d.id,
    nombre:      d.nombre,
    pendiente:   Number(d.monto_pendiente),
    tasa_mensual: Number(d.tasa_interes || 0) / 100 / 12,
    cuota:       d.es_letra ? Number(d.cuota_fija || 0) : Number(d.pago_minimo || 0),
    es_letra:    Boolean(d.es_letra),
    mes_saldado: null,
  }));

  const MESES_LABEL = ['Ene','Feb','Mar','Abr','May','Jun','Jul','Ago','Sep','Oct','Nov','Dic'];
  const hoy = new Date();
  const timeline = [];

  for (let m = 1; m <= meses; m++) {
    const fechaMes  = new Date(hoy.getFullYear(), hoy.getMonth() + m - 1, 1);
    const label     = `${MESES_LABEL[fechaMes.getMonth()]} ${fechaMes.getFullYear()}`;
    const eventos   = [];

    // Simular un mes de deudas: aplicar interés + cuota
    let cuotasTotales = 0;
    for (const d of estadoDeudas) {
      if (d.pendiente <= 0) continue;
      if (!d.es_letra) {
        const interes = d.pendiente * d.tasa_mensual;
        d.pendiente = Math.max(0, d.pendiente + interes - d.cuota);
      } else {
        d.pendiente = Math.max(0, d.pendiente - d.cuota);
      }
      const cuotaEfectiva = d.pendiente <= 0 ? 0 : d.cuota;
      cuotasTotales += cuotaEfectiva;

      if (d.pendiente <= 0 && d.mes_saldado === null) {
        d.mes_saldado = m;
        eventos.push({
          tipo:    'deuda_saldada',
          mensaje: `"${d.nombre}" queda saldada — libera $${d.cuota.toFixed(2)}/mes`,
          deuda_id: d.id,
          cuota_liberada: d.cuota,
        });
      }
    }

    const compromisos  = parseFloat((totalGastosFijos + cuotasTotales).toFixed(2));
    const disponible   = parseFloat((ingresoNeto - compromisos).toFixed(2));

    timeline.push({
      mes:             m,
      label,
      fecha:           fechaMes.toISOString().slice(0, 7),   // "YYYY-MM"
      ingreso_neto:    parseFloat(ingresoNeto.toFixed(2)),
      gastos_fijos:    parseFloat(totalGastosFijos.toFixed(2)),
      cuotas_deudas:   parseFloat(cuotasTotales.toFixed(2)),
      compromisos,
      disponible,
      ratio_compromiso: ingresoNeto > 0
        ? parseFloat((compromisos / ingresoNeto * 100).toFixed(1)) : 0,
      salud: disponible >= 0
        ? (compromisos / ingresoNeto < 0.7 ? 'buena' : 'ajustada')
        : 'critica',
      eventos,
    });
  }
  return timeline;
}

function calcularSplits(monto, regla, miembros) {
  // miembros: [{ firebase_uid, porcentaje, ingreso_declarado }]
  if (regla === 'equitativo') {
    const parte = Math.round((monto / miembros.length) * 100) / 100;
    return miembros.map(m => ({ firebase_uid: m.firebase_uid, monto_responsabilidad: parte }));
  }
  if (regla === 'porcentual') {
    // Normalizar porcentajes por si no suman exactamente 100
    const totalPct = miembros.reduce((s, m) => s + (parseFloat(m.porcentaje) || 0), 0);
    const factor = totalPct > 0 ? 100 / totalPct : 1;
    return miembros.map(m => ({
      firebase_uid: m.firebase_uid,
      monto_responsabilidad: Math.round(monto * ((parseFloat(m.porcentaje) || 0) * factor / 100) * 100) / 100,
    }));
  }
  if (regla === 'proporcional') {
    const totalIngresos = miembros.reduce((s, m) => s + (parseFloat(m.ingreso_declarado) || 0), 0);
    if (totalIngresos === 0) {
      const parte = Math.round((monto / miembros.length) * 100) / 100;
      return miembros.map(m => ({ firebase_uid: m.firebase_uid, monto_responsabilidad: parte }));
    }
    return miembros.map(m => ({
      firebase_uid: m.firebase_uid,
      monto_responsabilidad: Math.round(monto * ((parseFloat(m.ingreso_declarado) || 0) / totalIngresos) * 100) / 100,
    }));
  }
  // pool_contribucion: sin splits individuales, el gasto se registra pero sin deuda entre personas
  if (regla === 'pool_contribucion') return [];
  return [];
}

/**
 * Calcula el score de salud financiera (0-100).
 * No es punitivo: un usuario nuevo empieza en 50, no en 0.
 * Factores: ratio deuda/ingreso, ratio gastos fijos/ingreso, ahorro, pagos al día.
 */
function _calcularScore({ ingresoNeto, totalGastosFijos, totalCuotasDeudas, totalAhorros, pagosCumplidos, pagosTotales }) {
  if (!ingresoNeto || ingresoNeto <= 0) return 50; // Sin datos = neutral

  let score = 50; // Base neutral para usuarios nuevos

  // Factor 1: ratio deuda/ingreso (40% de la puntuación)
  // Ideal: cuotas < 30% del ingreso
  const ratioDeuda = totalCuotasDeudas / ingresoNeto;
  if (ratioDeuda === 0)           score += 20; // Sin deudas: excelente
  else if (ratioDeuda <= 0.15)    score += 15;
  else if (ratioDeuda <= 0.30)    score += 8;
  else if (ratioDeuda <= 0.50)    score -= 5;
  else                            score -= 15; // Más del 50% a deudas: crítico

  // Factor 2: ratio gastos fijos/ingreso (30% de la puntuación)
  const ratioGastos = totalGastosFijos / ingresoNeto;
  if (ratioGastos <= 0.40)        score += 15;
  else if (ratioGastos <= 0.60)   score += 5;
  else if (ratioGastos <= 0.80)   score -= 5;
  else                            score -= 15;

  // Factor 3: ahorro mensual (20% de la puntuación)
  const ratioAhorro = totalAhorros / ingresoNeto;
  if (ratioAhorro >= 0.20)        score += 10;
  else if (ratioAhorro >= 0.10)   score += 5;
  else if (ratioAhorro >= 0.05)   score += 2;

  // Factor 4: cumplimiento de pagos (10% de la puntuación)
  if (pagosTotales > 0) {
    const pct = pagosCumplidos / pagosTotales;
    if (pct >= 0.90) score += 5;
    else if (pct >= 0.70) score += 2;
    else score -= 5;
  }

  return Math.min(100, Math.max(0, Math.round(score)));
}

module.exports = {
  _montoMensual,
  _generarAplicaMeses,
  calcularFechaFin,
  _simularDeudas,
  _construirTimeline,
  calcularSplits,
  _calcularScore,
};
