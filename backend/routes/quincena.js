/**
 * routes/quincena.js — Vista quincenal: gastos y compromisos divididos 50/50
 * o asignados a una sola quincena según su fecha/día de pago.
 * Día 1–14 → solo Q1. Día 16–31 → solo Q2. Día 15 → ambas quincenas al 50%.
 */
const express = require('express');
const router = express.Router();
const { db } = require('../lib/db');

// GET /user/quincena/:anio/:mes/:num?firebase_uid= (num=1 o num=2)
router.get('/user/quincena/:anio/:mes/:num', async (req, res) => {
  const { anio, mes, num } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  const esQ1 = Number(num) === 1;
  try {
    // Ingreso: usar meses_financieros si existe, si no user_income. No bloquear si no hay estado anual.
    const [[mesRow]] = await db.execute(
      `SELECT ingreso_estimado FROM meses_financieros WHERE firebase_uid = ? AND anio = ? AND mes = ?`,
      [firebase_uid, anio, mes]);
    const [[income]] = await db.execute(
      `SELECT ingreso_neto_mensual FROM user_income WHERE firebase_uid = ?`, [firebase_uid]);
    const ingresoMensual = mesRow ? Number(mesRow.ingreso_estimado) : (income ? Number(income.ingreso_neto_mensual) : 0);

    // Registros directo por anio+mes, sin depender de mes_id ni de que exista el estado anual.
    // Día 15 → ambas quincenas al 50%. Día 1-14 → solo Q1. Día 16-31 → solo Q2.
    const filtroSQL = esQ1
      ? `(DAY(rg.fecha) <= 15)`
      : `(DAY(rg.fecha) >= 15)`;

    const [registrosRaw] = await db.execute(
      `SELECT rg.*, DAY(rg.fecha) AS dia_fecha FROM registros_gasto rg
       WHERE rg.firebase_uid = ? AND rg.anio = ? AND rg.mes = ? AND ${filtroSQL}
       ORDER BY rg.fecha DESC`,
      [firebase_uid, anio, mes]);

    const registros = registrosRaw.map(r => {
      const esMensual = Number(r.dia_fecha) === 15;
      return {
        ...r,
        monto: esMensual ? parseFloat((Number(r.monto) / 2).toFixed(2)) : Number(r.monto),
        es_mensual: esMensual,
      };
    });

    const ingresoQ = ingresoMensual / 2;
    const totalFijos = registros.filter(r => r.tipo === 'fijo').reduce((s, r) => s + Number(r.monto), 0);
    const totalVar   = registros.filter(r => r.tipo === 'variable').reduce((s, r) => s + Number(r.monto), 0);
    const totalNoPres= registros.filter(r => r.tipo === 'no_presupuestado').reduce((s, r) => s + Number(r.monto), 0);
    const totalGasto = totalFijos + totalVar + totalNoPres;
    // Para fijos "medio" (día_pago + día_pago_2), el JOIN es quincena-específico:
    // Q1 busca registros con fecha día ≤ 15, Q2 con fecha día > 15.
    // Esto evita que marcar pagado en Q1 muestre también Q2 como pagada (bug B2/Q1).
    // Fijos normales (sin día_pago_2): cualquier registro del mes (sin filtro de día).
    // Todos los compromisos usan el mismo filtro de quincena para sus pagos registrados.
    // Fijos "medio" (dia_pago + dia_pago_2): siempre filtrado. Fijos normales: también
    // filtrado para que los pagos parciales de cada quincena se contabilicen correctamente.
    const filtroQ = esQ1 ? 'DAY(rg.fecha) <= 15' : 'DAY(rg.fecha) > 15';
    const [compFijos] = await db.execute(
      `SELECT ugf.id, ugf.descripcion AS nombre, ugf.monto_mensual AS monto, ugf.categoria,
              ugf.dia_pago, ugf.dia_pago_2,
              COALESCE(SUM(rg.monto), 0) AS monto_pagado,
              GROUP_CONCAT(rg.id ORDER BY rg.id SEPARATOR ',') AS registro_ids_str
       FROM user_gastos_fijos ugf
       LEFT JOIN registros_gasto rg
         ON rg.origen_fijo_id = ugf.id AND rg.firebase_uid = ? AND rg.anio = ? AND rg.mes = ?
         AND ${filtroQ}
       WHERE ugf.firebase_uid = ? AND ugf.activo = 1
       GROUP BY ugf.id, ugf.descripcion, ugf.monto_mensual, ugf.categoria, ugf.dia_pago, ugf.dia_pago_2`,
      [firebase_uid, anio, mes, firebase_uid]);
    const filtroQVar = filtroQ;
    const [compVariables] = await db.execute(
      `SELECT gvb.id, gvb.nombre, gvb.monto_estimado AS monto, gvb.categoria,
              COALESCE(SUM(rg.monto), 0) AS monto_pagado,
              GROUP_CONCAT(rg.id ORDER BY rg.id SEPARATOR ',') AS registro_ids_str
       FROM gastos_variables_base gvb
       LEFT JOIN registros_gasto rg
         ON rg.origen_variable_id = gvb.id AND rg.firebase_uid = ? AND rg.anio = ? AND rg.mes = ?
         AND ${filtroQVar}
       WHERE gvb.firebase_uid = ? AND gvb.activo = 1
       GROUP BY gvb.id, gvb.nombre, gvb.monto_estimado, gvb.categoria`,
      [firebase_uid, anio, mes, firebase_uid]);
    const [compDeudas] = await db.execute(
      `SELECT d.id, d.nombre, IF(d.es_letra=1, d.cuota_fija, d.pago_minimo) AS monto,
              COALESCE(SUM(rg.monto), 0) AS monto_pagado,
              GROUP_CONCAT(rg.id ORDER BY rg.id SEPARATOR ',') AS registro_ids_str
       FROM deudas d
       LEFT JOIN registros_gasto rg
         ON rg.origen_deuda_id = d.id AND rg.firebase_uid = ? AND rg.anio = ? AND rg.mes = ?
         AND ${filtroQ}
       WHERE d.firebase_uid = ? AND d.activa = 1
       GROUP BY d.id, d.nombre, d.cuota_fija, d.pago_minimo, d.es_letra`,
      [firebase_uid, anio, mes, firebase_uid]);
    // B2 — monto del fijo en esta quincena según sus días de pago:
    //   dos días de pago (uno por quincena) → mitad en cada una
    //   un solo día conocido → completo en su quincena, no aparece en la otra
    //   sin día definido → fallback 50/50 (no sabemos cuándo)
    const _montoFijoQuincena = (montoMensual, diaPago, diaPago2) => {
      const m = Number(montoMensual);
      if (diaPago != null && diaPago2 != null) return m / 2;
      if (diaPago != null) return (Number(diaPago) <= 15) === esQ1 ? m : 0;
      return m / 2;
    };
    const todosCompromisos = [
      ...compFijos
        .map(c => {
          const montoQ = parseFloat(_montoFijoQuincena(c.monto, c.dia_pago, c.dia_pago_2).toFixed(2));
          const montoPagado = parseFloat(Number(c.monto_pagado || 0).toFixed(2));
          const ids = c.registro_ids_str ? c.registro_ids_str.split(',').map(Number) : [];
          return {
            id: c.id, nombre: c.nombre, monto: montoQ,
            monto_pagado: montoPagado,
            registro_ids: ids,
            registro_id: ids.length > 0 ? ids[ids.length - 1] : null,
            tipo: 'fijo', categoria: c.categoria || 'otro',
            medio: (c.dia_pago != null && c.dia_pago_2 != null),
          };
        })
        // Un fijo de un solo día no pertenece a la otra quincena.
        .filter(c => c.monto > 0),
      ...compVariables.map(c => {
        const montoQ = parseFloat((Number(c.monto) / 2).toFixed(2));
        const montoPagado = parseFloat(Number(c.monto_pagado || 0).toFixed(2));
        const ids = c.registro_ids_str ? c.registro_ids_str.split(',').map(Number) : [];
        return {
          id: c.id, nombre: c.nombre,
          monto: montoQ,
          monto_pagado: montoPagado,
          registro_ids: ids,
          registro_id: ids.length > 0 ? ids[ids.length - 1] : null, // compat: último pago
          tipo: 'variable', categoria: c.categoria || 'otro',
        };
      }),
      ...compDeudas.map(d => {
        const montoQ = parseFloat((Number(d.monto) / 2).toFixed(2));
        const montoPagado = parseFloat(Number(d.monto_pagado || 0).toFixed(2));
        const ids = d.registro_ids_str ? d.registro_ids_str.split(',').map(Number) : [];
        return {
          id: d.id, nombre: d.nombre, monto: montoQ,
          monto_pagado: montoPagado,
          registro_ids: ids,
          registro_id: ids.length > 0 ? ids[ids.length - 1] : null,
          tipo: 'deuda', categoria: 'deudas',
        };
      }),
    ];
    res.json({
      quincena: Number(num),
      dias: esQ1 ? '1–15' : '16–fin',
      ingreso_quincenal: parseFloat(ingresoQ.toFixed(2)),
      total_gastado:     parseFloat(totalGasto.toFixed(2)),
      disponible:        parseFloat((ingresoQ - totalGasto).toFixed(2)),
      fijos: parseFloat(totalFijos.toFixed(2)),
      variables: parseFloat(totalVar.toFixed(2)),
      no_presupuestados: parseFloat(totalNoPres.toFixed(2)),
      registros,
      compromisos_quincenal: todosCompromisos,
    });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

module.exports = router;
