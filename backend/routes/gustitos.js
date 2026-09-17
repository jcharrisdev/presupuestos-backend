/**
 * routes/gustitos.js — Compras por impulso/emoción, vinculadas opcionalmente
 * a un presupuesto y siempre reflejadas como registros_gasto del mes.
 */
const express = require('express');
const router = express.Router();
const { db } = require('../lib/db');
const { _actualizarTotalesMes, _generarAlertasMes } = require('../lib/mes_helpers');

router.post('/gustitos', async (req, res) => {
  const {
    user_id, budget_id = null, name, amount, spent_at,
    description = null, merchant = null, category = null,
    emotion_tag = null, source = 'manual', scanned_invoice_id = null
  } = req.body;

  if (!user_id || !name || amount == null || !spent_at)
    return res.status(400).json({ error: 'Datos incompletos: user_id, name, amount y spent_at son requeridos' });

  if (Number(amount) <= 0)
    return res.status(400).json({ error: 'El monto debe ser mayor a 0' });

  try {
    // Verificar presupuesto solo si se provee (budget_id es opcional)
    if (budget_id != null) {
      const [[presupuesto]] = await db.execute(
        `SELECT id FROM presupuestos WHERE id = ? AND firebase_uid = ?`,
        [budget_id, user_id]
      );
      if (!presupuesto) return res.status(404).json({ error: 'Presupuesto no encontrado' });
    }

    const spentAtStr = spent_at.split('T')[0];

    const [result] = await db.execute(
      `INSERT INTO gustitos
       (user_id, budget_id, scanned_invoice_id, name, description, merchant, amount, category, emotion_tag, source, spent_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [user_id, budget_id, scanned_invoice_id, name, description, merchant,
       Number(amount), category, emotion_tag, source, spentAtStr]
    );

    const [[gustito]] = await db.execute(
      `SELECT * FROM gustitos WHERE id = ?`, [result.insertId]
    );
    res.status(201).json(gustito);

    // Fire-and-forget: crear registros_gasto vinculado si el mes existe en el estado financiero
    (async () => {
      try {
        const fecha    = spentAtStr;
        const anioReg  = parseInt(fecha.substring(0, 4));
        const mesReg   = parseInt(fecha.substring(5, 7));
        const [[mesRow]] = await db.execute(
          `SELECT id FROM meses_financieros WHERE firebase_uid = ? AND anio = ? AND mes = ?`,
          [user_id, anioReg, mesReg]
        );
        if (!mesRow) return; // mes no generado todavía — no bloqueamos

        const catReg = category || 'gustitos';
        const esHormiga = Number(amount) <= 25 ? 1 : 0;
        const [rg] = await db.execute(
          `INSERT INTO registros_gasto
             (firebase_uid, mes_id, anio, mes, tipo, categoria,
              nombre, monto, fecha, pagado, origen_gustito_id, es_hormiga)
           VALUES (?, ?, ?, ?, 'no_presupuestado', ?, ?, ?, ?, 1, ?, ?)`,
          [user_id, mesRow.id, anioReg, mesReg, catReg,
           name, Number(amount), fecha, result.insertId, esHormiga]
        );
        await _actualizarTotalesMes(mesRow.id, user_id);
        _generarAlertasMes(user_id, anioReg, mesReg).catch(() => {});
      } catch (_) { /* no bloquear si falla */ }
    })();
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * GET /gustitos?firebase_uid=
 * Lista todos los Gustitos del usuario, más recientes primero.
 */
router.get('/gustitos', async (req, res) => {
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid es requerido' });
  try {
    const [gustitos] = await db.execute(
      `SELECT * FROM gustitos WHERE user_id = ? AND deleted_at IS NULL ORDER BY spent_at DESC, id DESC`,
      [firebase_uid]
    );
    res.json(gustitos);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * GET /gustitos/:id?firebase_uid=
 * Detalle de un Gustito específico.
 */
router.get('/gustitos/:id', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid es requerido' });
  try {
    const [[gustito]] = await db.execute(
      `SELECT * FROM gustitos WHERE id = ? AND user_id = ? AND deleted_at IS NULL`,
      [id, firebase_uid]
    );
    if (!gustito) return res.status(404).json({ error: 'Gustito no encontrado' });
    res.json(gustito);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * PATCH /gustitos/:id
 * Actualiza campos de un Gustito. Solo se actualizan los campos enviados.
 */
router.patch('/gustitos/:id', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid, name, amount, description, merchant, category, emotion_tag, spent_at } = req.body;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid es requerido' });

  try {
    const [[gustito]] = await db.execute(
      `SELECT id FROM gustitos WHERE id = ? AND user_id = ? AND deleted_at IS NULL`,
      [id, firebase_uid]
    );
    if (!gustito) return res.status(404).json({ error: 'Gustito no encontrado' });

    if (amount != null && Number(amount) <= 0)
      return res.status(400).json({ error: 'El monto debe ser mayor a 0' });

    const campos = [];
    const valores = [];

    if (name       != null) { campos.push('name = ?');        valores.push(name); }
    if (amount     != null) { campos.push('amount = ?');      valores.push(Number(amount)); }
    if (description != null){ campos.push('description = ?'); valores.push(description); }
    if (merchant   != null) { campos.push('merchant = ?');    valores.push(merchant); }
    if (category   != null) { campos.push('category = ?');    valores.push(category); }
    if (emotion_tag != null){ campos.push('emotion_tag = ?'); valores.push(emotion_tag); }
    if (spent_at   != null) { campos.push('spent_at = ?');    valores.push(spent_at.split('T')[0]); }

    if (campos.length === 0) return res.status(400).json({ error: 'No hay campos para actualizar' });

    campos.push('updated_at = NOW()');
    valores.push(id, firebase_uid);

    await db.execute(
      `UPDATE gustitos SET ${campos.join(', ')} WHERE id = ? AND user_id = ?`,
      valores
    );

    const [[updated]] = await db.execute(
      `SELECT * FROM gustitos WHERE id = ?`, [id]
    );
    res.json(updated);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * DELETE /gustitos/:id?firebase_uid=
 * Soft delete de un Gustito (deleted_at = NOW()).
 */
router.delete('/gustitos/:id', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid es requerido' });
  try {
    const [[gustito]] = await db.execute(
      `SELECT id FROM gustitos WHERE id = ? AND user_id = ? AND deleted_at IS NULL`,
      [id, firebase_uid]
    );
    if (!gustito) return res.status(404).json({ error: 'Gustito no encontrado' });

    await db.execute(
      `UPDATE gustitos SET deleted_at = NOW() WHERE id = ? AND user_id = ?`,
      [id, firebase_uid]
    );

    // Eliminar el registros_gasto vinculado y recalcular totales del mes
    try {
      const [[rg]] = await db.execute(
        `SELECT id, mes_id FROM registros_gasto WHERE origen_gustito_id = ? AND firebase_uid = ?`,
        [id, firebase_uid]
      );
      if (rg) {
        await db.execute(`DELETE FROM registros_gasto WHERE id = ?`, [rg.id]);
        await _actualizarTotalesMes(rg.mes_id, firebase_uid);
      }
    } catch (_) { /* no bloquear el delete del gustito */ }

    res.json({ message: 'Gustito eliminado correctamente' });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * GET /presupuestos/:budgetId/gustitos?firebase_uid=
 * Lista los Gustitos de un presupuesto específico.
 */
router.get('/presupuestos/:budgetId/gustitos', async (req, res) => {
  const { budgetId } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid es requerido' });
  try {
    const [[presupuesto]] = await db.execute(
      `SELECT id FROM presupuestos WHERE id = ? AND firebase_uid = ?`,
      [budgetId, firebase_uid]
    );
    if (!presupuesto) return res.status(404).json({ error: 'Presupuesto no encontrado' });

    const [gustitos] = await db.execute(
      `SELECT * FROM gustitos
       WHERE budget_id = ? AND user_id = ? AND deleted_at IS NULL
       ORDER BY spent_at DESC, id DESC`,
      [budgetId, firebase_uid]
    );
    res.json(gustitos);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * GET /presupuestos/:budgetId/gustitos/summary?firebase_uid=
 * Resumen estadístico de Gustitos para mostrar en el detalle del presupuesto.
 */
router.get('/presupuestos/:budgetId/gustitos/summary', async (req, res) => {
  const { budgetId } = req.params;
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid es requerido' });
  try {
    const [[presupuesto]] = await db.execute(
      `SELECT id FROM presupuestos WHERE id = ? AND firebase_uid = ?`,
      [budgetId, firebase_uid]
    );
    if (!presupuesto) return res.status(404).json({ error: 'Presupuesto no encontrado' });

    const [[stats]] = await db.execute(
      `SELECT
         COALESCE(SUM(amount), 0)   AS total,
         COUNT(*)                   AS count,
         COALESCE(AVG(amount), 0)   AS promedio
       FROM gustitos
       WHERE budget_id = ? AND user_id = ? AND deleted_at IS NULL`,
      [budgetId, firebase_uid]
    );

    // Categoría más frecuente
    const [[catRow]] = await db.execute(
      `SELECT category AS categoria_frecuente, COUNT(*) AS freq
       FROM gustitos
       WHERE budget_id = ? AND user_id = ? AND deleted_at IS NULL AND category IS NOT NULL
       GROUP BY category
       ORDER BY freq DESC
       LIMIT 1`,
      [budgetId, firebase_uid]
    );

    // Día con más Gustitos
    const [[diaRow]] = await db.execute(
      `SELECT DATE(spent_at) AS dia_con_mas, COUNT(*) AS freq
       FROM gustitos
       WHERE budget_id = ? AND user_id = ? AND deleted_at IS NULL
       GROUP BY DATE(spent_at)
       ORDER BY freq DESC
       LIMIT 1`,
      [budgetId, firebase_uid]
    );

    // Últimos 3 registros
    const [ultimos] = await db.execute(
      `SELECT id, name, merchant, amount, category, emotion_tag, spent_at
       FROM gustitos
       WHERE budget_id = ? AND user_id = ? AND deleted_at IS NULL
       ORDER BY spent_at DESC, id DESC
       LIMIT 3`,
      [budgetId, firebase_uid]
    );

    res.json({
      total:               Math.round(Number(stats.total) * 100) / 100,
      count:               Number(stats.count),
      promedio:            Math.round(Number(stats.promedio) * 100) / 100,
      categoria_frecuente: catRow ? catRow.categoria_frecuente : null,
      dia_con_mas:         diaRow ? diaRow.dia_con_mas : null,
      ultimos,
    });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: error.message });
  }
});

module.exports = router;
