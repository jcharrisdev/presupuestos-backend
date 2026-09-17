/**
 * routes/timeline.js — Timeline financiero y proyección de escenarios.
 * Proyecta mes a mes el estado financiero del usuario a partir del perfil.
 * Las deudas disminuyen cada mes; cuando se saldan, el dinero queda disponible.
 * El simulador aplica un escenario hipotético y devuelve el delta de impacto.
 */
const express = require('express');
const router = express.Router();
const { db } = require('../lib/db');
const { _construirTimeline } = require('../lib/calculos_financieros');

// GET /user/timeline?firebase_uid=&meses=12
// Proyecta el estado financiero mes a mes desde el perfil del usuario.
// Refleja deudas que se saldan y el dinero que liberan.
router.get('/user/timeline', async (req, res) => {
  const { firebase_uid, meses = 12 } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [[income]] = await db.execute(
      `SELECT * FROM user_income WHERE firebase_uid = ?`, [firebase_uid]
    );
    const [gastosFijos] = await db.execute(
      `SELECT * FROM user_gastos_fijos WHERE firebase_uid = ? AND activo = 1`, [firebase_uid]
    );
    const [deudas] = await db.execute(
      `SELECT * FROM deudas WHERE firebase_uid = ? AND activa = 1 AND monto_pendiente > 0`,
      [firebase_uid]
    );

    const mesesNum = Math.min(Math.max(Number(meses) || 12, 3), 36);
    const timeline = _construirTimeline(income, gastosFijos, deudas, mesesNum);

    // Resumen ejecutivo del timeline
    const mesActual      = timeline[0];
    const mesMejor       = timeline.reduce((a, b) => b.disponible > a.disponible ? b : a);
    const mesesCriticos  = timeline.filter(t => t.salud === 'critica').length;
    const totalIntereses = deudas.reduce((s, d) => {
      // Estimación simplificada de intereses totales
      const tasa = Number(d.tasa_interes || 0) / 100 / 12;
      return s + Number(d.monto_pendiente) * tasa * mesesNum;
    }, 0);

    res.json({
      tiene_perfil_completo: !!income,
      resumen: {
        ingreso_neto_mensual:    income ? parseFloat(Number(income.ingreso_neto_mensual).toFixed(2)) : 0,
        disponible_hoy:          mesActual.disponible,
        mejor_mes:               { label: mesMejor.label, disponible: mesMejor.disponible },
        meses_criticos:          mesesCriticos,
        deudas_activas:          deudas.length,
        fecha_libertad_deudas:   (() => {
          if (deudas.length === 0) return null;
          // Simular mes a mes hasta que todas las deudas queden en 0
          const sim = deudas.map(d => ({
            pendiente:   Number(d.monto_pendiente),
            tasa_mensual: Number(d.tasa_interes || 0) / 100 / 12,
            cuota: d.es_letra ? Number(d.cuota_fija || 0) : Number(d.pago_minimo || 0),
            es_letra: Boolean(d.es_letra),
          }));
          const inicio = new Date();
          for (let mes = 1; mes <= 600; mes++) {
            for (const d of sim) {
              if (d.pendiente <= 0) continue;
              if (!d.es_letra) d.pendiente = Math.max(0, d.pendiente + d.pendiente * d.tasa_mensual - d.cuota);
              else d.pendiente = Math.max(0, d.pendiente - d.cuota);
            }
            if (sim.every(d => d.pendiente <= 0)) {
              const fecha = new Date(inicio);
              fecha.setMonth(fecha.getMonth() + mes);
              return fecha.toISOString().slice(0, 10);
            }
          }
          return null;
        })(),
      },
      meses: timeline,
    });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// POST /user/timeline/simular
// Aplica un escenario hipotético al perfil y devuelve el timeline modificado
// con el delta de impacto vs el timeline base.
//
// Escenarios soportados (campo "tipo"):
//   eliminar_gasto    → elimina un user_gasto_fijo del cálculo (gasto_fijo_id requerido)
//   pagar_deuda_hoy   → marca una deuda como saldada desde mes 1 (deuda_id requerido)
//   extra_pago_deuda  → añade un pago extra mensual a una deuda (deuda_id + extra_mensual)
//   nuevo_compromiso  → agrega un gasto fijo nuevo (nombre + monto)
//   cambiar_ingreso   → simula cambio de ingreso (nuevo_ingreso)
router.post('/user/timeline/simular', async (req, res) => {
  const { firebase_uid, tipo, meses = 12, gasto_fijo_id, deuda_id, extra_mensual, monto, nombre, nuevo_ingreso } = req.body;
  if (!firebase_uid || !tipo) return res.status(400).json({ error: 'firebase_uid y tipo son requeridos' });

  try {
    const [[income]] = await db.execute(
      `SELECT * FROM user_income WHERE firebase_uid = ?`, [firebase_uid]
    );
    const [gastosFijos] = await db.execute(
      `SELECT * FROM user_gastos_fijos WHERE firebase_uid = ? AND activo = 1`, [firebase_uid]
    );
    const [deudas] = await db.execute(
      `SELECT * FROM deudas WHERE firebase_uid = ? AND activa = 1 AND monto_pendiente > 0`, [firebase_uid]
    );

    const mesesNum = Math.min(Math.max(Number(meses) || 12, 3), 36);

    // Timeline BASE (sin escenario)
    const timelineBase = _construirTimeline(income, gastosFijos, deudas, mesesNum);

    // Aplicar mutación al escenario
    let incomeEsc      = income ? { ...income } : null;
    let gastosFijosEsc = gastosFijos.map(g => ({ ...g }));
    let deudasEsc      = deudas.map(d => ({ ...d }));
    let descripcionEscenario = '';

    switch (tipo) {
      case 'eliminar_gasto':
        if (!gasto_fijo_id) return res.status(400).json({ error: 'gasto_fijo_id requerido' });
        gastosFijosEsc = gastosFijosEsc.filter(g => g.id !== Number(gasto_fijo_id));
        const gastoEliminado = gastosFijos.find(g => g.id === Number(gasto_fijo_id));
        descripcionEscenario = `Eliminar "${gastoEliminado?.descripcion || 'gasto'}" ($${gastoEliminado?.monto_mensual}/mes)`;
        break;

      case 'pagar_deuda_hoy':
        if (!deuda_id) return res.status(400).json({ error: 'deuda_id requerido' });
        deudasEsc = deudasEsc.filter(d => d.id !== Number(deuda_id));
        const deudaEliminada = deudas.find(d => d.id === Number(deuda_id));
        descripcionEscenario = `Saldar "${deudaEliminada?.nombre || 'deuda'}" hoy ($${deudaEliminada?.pago_minimo}/mes liberados)`;
        break;

      case 'extra_pago_deuda':
        if (!deuda_id || !extra_mensual) return res.status(400).json({ error: 'deuda_id y extra_mensual requeridos' });
        deudasEsc = deudasEsc.map(d =>
          d.id === Number(deuda_id)
            ? { ...d, pago_minimo: Number(d.pago_minimo || 0) + Number(extra_mensual), cuota_fija: d.es_letra ? Number(d.cuota_fija || 0) + Number(extra_mensual) : d.cuota_fija }
            : d
        );
        const deudaExtra = deudas.find(d => d.id === Number(deuda_id));
        descripcionEscenario = `Pagar $${extra_mensual}/mes extra en "${deudaExtra?.nombre || 'deuda'}"`;
        break;

      case 'nuevo_compromiso':
        if (monto == null) return res.status(400).json({ error: 'monto requerido' });
        gastosFijosEsc.push({ id: -1, descripcion: nombre || 'Nuevo compromiso', monto_mensual: Number(monto), activo: 1 });
        descripcionEscenario = `Agregar "${nombre || 'Nuevo compromiso'}" ($${monto}/mes)`;
        break;

      case 'cambiar_ingreso':
        if (nuevo_ingreso == null) return res.status(400).json({ error: 'nuevo_ingreso requerido' });
        if (incomeEsc) incomeEsc.ingreso_neto_mensual = Number(nuevo_ingreso);
        else incomeEsc = { ingreso_neto_mensual: Number(nuevo_ingreso) };
        descripcionEscenario = `Cambiar ingreso neto a $${nuevo_ingreso}/mes`;
        break;

      default:
        return res.status(400).json({ error: `Tipo de escenario desconocido: ${tipo}` });
    }

    // Timeline con escenario aplicado
    const timelineEsc = _construirTimeline(incomeEsc, gastosFijosEsc, deudasEsc, mesesNum);

    // Calcular delta mes a mes
    const mesesConDelta = timelineEsc.map((mes, i) => ({
      ...mes,
      delta_disponible:   parseFloat((mes.disponible - timelineBase[i].disponible).toFixed(2)),
      disponible_base:    timelineBase[i].disponible,
    }));

    const gananciaTotalEstimada = mesesConDelta.reduce((s, m) => s + m.delta_disponible, 0);

    res.json({
      escenario: { tipo, descripcion: descripcionEscenario },
      impacto: {
        delta_mes1:                parseFloat(mesesConDelta[0].delta_disponible.toFixed(2)),
        ganancia_total_estimada:   parseFloat(gananciaTotalEstimada.toFixed(2)),
        meses_analizados:          mesesNum,
      },
      meses: mesesConDelta,
    });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

module.exports = router;
