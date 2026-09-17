/**
 * routes/eventos.js — Presupuestos de eventos (Sprint 7): vacaciones, bodas,
 * y cualquier gasto puntual con cuota mensual repartida entre un rango de meses.
 */
const express = require('express');
const router = express.Router();
const { db } = require('../lib/db');
const { _logInfo } = require('../lib/logger');
const { _actualizarTotalesMes, _generarAlertasMes } = require('../lib/mes_helpers');

// GET /user/eventos?firebase_uid=&anio=
router.get('/user/eventos', async (req, res) => {
  const { firebase_uid, anio } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const year = anio || new Date().getFullYear();
    const [eventos] = await db.execute(
      `SELECT ep.*,
              COALESCE((SELECT SUM(eg.monto) FROM eventos_gastos eg WHERE eg.evento_id = ep.id), 0) AS gastado_real
       FROM eventos_presupuesto ep
       WHERE ep.firebase_uid = ? AND ep.anio = ? AND ep.estado != 'cancelado'
       ORDER BY ep.mes_inicio ASC, ep.created_at ASC`,
      [firebase_uid, year]
    );
    res.json({
      eventos: eventos.map(e => ({
        ...e,
        monto_total:   Number(e.monto_total),
        cuota_mensual: Number(e.cuota_mensual),
        gastado_real:  Number(e.gastado_real),
        num_meses:     e.mes_fin - e.mes_inicio + 1,
        pct_avance:    e.monto_total > 0
          ? parseFloat((Number(e.gastado_real) / Number(e.monto_total) * 100).toFixed(1)) : 0,
      })),
      total: eventos.length,
    });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// POST /user/eventos
router.post('/user/eventos', async (req, res) => {
  const { firebase_uid, nombre, descripcion, emoji, monto_total,
          anio, mes_inicio, mes_fin } = req.body;
  if (!firebase_uid || !nombre || !monto_total || !anio || !mes_inicio || !mes_fin)
    return res.status(400).json({ error: 'Faltan campos requeridos' });
  if (Number(mes_inicio) > Number(mes_fin))
    return res.status(400).json({ error: 'mes_inicio debe ser ≤ mes_fin' });
  try {
    const numMeses     = Number(mes_fin) - Number(mes_inicio) + 1;
    const cuotaMensual = parseFloat((Number(monto_total) / numMeses).toFixed(2));
    const [result] = await db.execute(
      `INSERT INTO eventos_presupuesto
         (firebase_uid, nombre, descripcion, emoji, monto_total, anio, mes_inicio, mes_fin, cuota_mensual)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [firebase_uid, nombre, descripcion ?? null, emoji ?? null,
       monto_total, anio, mes_inicio, mes_fin, cuotaMensual]
    );
    _logInfo('/user/eventos', `Evento creado: ${nombre} $${monto_total}`, firebase_uid);
    res.status(201).json({ id: result.insertId, cuota_mensual: cuotaMensual, num_meses: numMeses });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// PUT /user/eventos/:id
router.put('/user/eventos/:id', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid, nombre, descripcion, emoji, monto_total,
          mes_inicio, mes_fin, estado } = req.body;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [[ev]] = await db.execute(
      `SELECT * FROM eventos_presupuesto WHERE id = ? AND firebase_uid = ?`, [id, firebase_uid]);
    if (!ev) return res.status(404).json({ error: 'Evento no encontrado' });
    const nuevoMesIni  = mes_inicio ?? ev.mes_inicio;
    const nuevoMesFin  = mes_fin    ?? ev.mes_fin;
    const nuevoMonto   = monto_total ?? ev.monto_total;
    const numMeses     = Number(nuevoMesFin) - Number(nuevoMesIni) + 1;
    const cuotaMensual = parseFloat((Number(nuevoMonto) / numMeses).toFixed(2));
    await db.execute(
      `UPDATE eventos_presupuesto
       SET nombre = ?, descripcion = ?, emoji = ?, monto_total = ?,
           mes_inicio = ?, mes_fin = ?, cuota_mensual = ?, estado = ?
       WHERE id = ? AND firebase_uid = ?`,
      [nombre ?? ev.nombre, descripcion ?? null, emoji ?? null, nuevoMonto,
       nuevoMesIni, nuevoMesFin, cuotaMensual, estado ?? ev.estado, id, firebase_uid]
    );
    res.json({ actualizado: true, cuota_mensual: cuotaMensual });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// DELETE /user/eventos/:id
router.delete('/user/eventos/:id', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    await db.execute(
      `UPDATE eventos_presupuesto SET estado = 'cancelado' WHERE id = ? AND firebase_uid = ?`,
      [id, firebase_uid]);
    res.json({ cancelado: true });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// GET /user/eventos/:id — detalle con gastos
router.get('/user/eventos/:id', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    const [[ev]] = await db.execute(
      `SELECT * FROM eventos_presupuesto WHERE id = ? AND firebase_uid = ?`, [id, firebase_uid]);
    if (!ev) return res.status(404).json({ error: 'Evento no encontrado' });
    const [gastos] = await db.execute(
      `SELECT * FROM eventos_gastos WHERE evento_id = ? ORDER BY fecha DESC, created_at DESC`, [id]);
    const gastadoReal = gastos.reduce((s, g) => s + Number(g.monto), 0);
    res.json({
      evento: {
        ...ev,
        monto_total:   Number(ev.monto_total),
        cuota_mensual: Number(ev.cuota_mensual),
        gastado_real:  parseFloat(gastadoReal.toFixed(2)),
        disponible:    parseFloat((Number(ev.monto_total) - gastadoReal).toFixed(2)),
        num_meses:     ev.mes_fin - ev.mes_inicio + 1,
        pct_avance:    ev.monto_total > 0
          ? parseFloat((gastadoReal / Number(ev.monto_total) * 100).toFixed(1)) : 0,
      },
      gastos: gastos.map(g => ({ ...g, monto: Number(g.monto) })),
    });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// POST /user/eventos/:id/gastos — registrar gasto contra un evento
router.post('/user/eventos/:id/gastos', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid, nombre, monto, fecha, notas } = req.body;
  if (!firebase_uid || !nombre || !monto) return res.status(400).json({ error: 'Faltan campos' });
  try {
    const [[ev]] = await db.execute(
      `SELECT * FROM eventos_presupuesto WHERE id = ? AND firebase_uid = ?`, [id, firebase_uid]);
    if (!ev) return res.status(404).json({ error: 'Evento no encontrado' });
    const [result] = await db.execute(
      `INSERT INTO eventos_gastos (firebase_uid, evento_id, nombre, monto, fecha, notas)
       VALUES (?, ?, ?, ?, ?, ?)`,
      [firebase_uid, id, nombre, monto, fecha ?? null, notas ?? null]
    );
    _logInfo(`/user/eventos/${id}/gastos`, `Gasto evento: ${nombre} $${monto}`, firebase_uid);
    res.status(201).json({ id: result.insertId });

    // AA1 — fire-and-forget: crear registros_gasto vinculado para que el gasto
    // del evento reduzca el disponible del mes correspondiente.
    (async () => {
      try {
        const fechaReg = (fecha ?? new Date().toISOString().split('T')[0]).substring(0, 10);
        const anioReg  = parseInt(fechaReg.substring(0, 4));
        const mesReg   = parseInt(fechaReg.substring(5, 7));
        const [[mesRow]] = await db.execute(
          `SELECT id FROM meses_financieros WHERE firebase_uid = ? AND anio = ? AND mes = ?`,
          [firebase_uid, anioReg, mesReg]);
        if (!mesRow) return;
        await db.execute(
          `INSERT INTO registros_gasto
             (firebase_uid, mes_id, anio, mes, tipo, categoria, nombre, monto, fecha, pagado, origen_evento_id)
           VALUES (?, ?, ?, ?, 'variable', 'eventos', ?, ?, ?, 1, ?)`,
          [firebase_uid, mesRow.id, anioReg, mesReg,
           `${ev.nombre}: ${nombre}`, Number(monto), fechaReg, result.insertId]);
        await _actualizarTotalesMes(mesRow.id, firebase_uid);
        _generarAlertasMes(firebase_uid, anioReg, mesReg).catch(() => {});
      } catch (_) { /* no bloquear */ }
    })();
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// DELETE /user/eventos/:id/gastos/:gastoId
router.delete('/user/eventos/:id/gastos/:gastoId', async (req, res) => {
  const { id, gastoId } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid requerido' });
  try {
    // AA1 — eliminar también el registros_gasto vinculado y recalcular el mes
    const [vinculados] = await db.execute(
      `SELECT id, mes_id, anio, mes FROM registros_gasto WHERE firebase_uid = ? AND origen_evento_id = ?`,
      [firebase_uid, gastoId]);
    if (vinculados.length > 0) {
      await db.execute(`DELETE FROM registros_gasto WHERE firebase_uid = ? AND origen_evento_id = ?`,
        [firebase_uid, gastoId]);
      for (const v of vinculados) {
        _actualizarTotalesMes(v.mes_id, firebase_uid).catch(() => {});
        _generarAlertasMes(firebase_uid, v.anio, v.mes).catch(() => {});
      }
    }
    await db.execute(
      `DELETE FROM eventos_gastos WHERE id = ? AND evento_id = ? AND firebase_uid = ?`,
      [gastoId, id, firebase_uid]);
    res.json({ eliminado: true });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

module.exports = router;
