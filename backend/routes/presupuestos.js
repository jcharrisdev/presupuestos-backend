/**
 * routes/presupuestos.js — MÓDULO: PRESUPUESTOS
 * CRUD básico de presupuestos de usuario.
 */
const express = require('express');
const router = express.Router();
const { db } = require('../lib/db');
const { crearPrimerPeriodo } = require('../lib/periodo_helpers');

/**
 * POST /presupuestos
 * Crea un nuevo presupuesto y genera automáticamente su primer período.
 * El primer período se calcula en base al dia_inicio_periodo configurado.
 */
router.post('/presupuestos', async (req, res) => {
  const { nombre, firebase_uid, tipo_periodo, dia_inicio_periodo,
    monto_total: monto_manual } = req.body;

  if (!nombre || !firebase_uid || !tipo_periodo || !dia_inicio_periodo)
    return res.status(400).json({ error: 'Datos incompletos' });

  try {
    // Calcular monto_total desde user_income si existe (presupuesto = ingreso neto por período)
    let monto_total = monto_manual;
    const [[incomeRow]] = await db.execute(
      `SELECT ingreso_neto_mensual, frecuencia_cobro FROM user_income WHERE firebase_uid = ?`,
      [firebase_uid]
    );
    if (incomeRow) {
      const divisor = tipo_periodo === 'quincenal' ? 2 : 1;
      monto_total = parseFloat((Number(incomeRow.ingreso_neto_mensual) / divisor).toFixed(2));
    } else if (!monto_total) {
      return res.status(400).json({ error: 'Configura tu ingreso antes de crear un presupuesto' });
    }

    const [result] = await db.execute(
      `INSERT INTO presupuestos (nombre, monto_total, firebase_uid, tipo_periodo, dia_inicio_periodo)
       VALUES (?, ?, ?, ?, ?)`,
      [nombre, monto_total, firebase_uid, tipo_periodo, dia_inicio_periodo]
    );
    await crearPrimerPeriodo(result.insertId, firebase_uid, tipo_periodo, dia_inicio_periodo);
    res.status(201).json({ id: result.insertId, nombre, monto_total, tipo_periodo, dia_inicio_periodo });
  } catch (error) {
    console.error('Error creando presupuesto:', error);
    res.status(500).json({ error: 'Error al crear presupuesto' });
  }
});

/**
 * GET /presupuestos?firebase_uid=
 * Lista todos los presupuestos del usuario, ordenados del más reciente al más antiguo.
 */
router.get('/presupuestos', async (req, res) => {
  const { firebase_uid } = req.query;
  if (!firebase_uid) return res.status(400).json({ error: 'firebase_uid es requerido' });
  try {
    const [results] = await db.execute(
      `SELECT * FROM presupuestos WHERE firebase_uid = ? ORDER BY id DESC`, [firebase_uid]
    );
    res.json(results);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Error al obtener presupuestos' });
  }
});

/**
 * PUT /presupuestos/:id
 * Actualiza el nombre y monto de un presupuesto existente.
 * Requiere firebase_uid para verificar propiedad del recurso (seguridad básica).
 */
router.put('/presupuestos/:id', async (req, res) => {
  const { id } = req.params;
  const { nombre, monto_total, firebase_uid } = req.body;
  if (!nombre || monto_total == null || !firebase_uid)
    return res.status(400).json({ error: 'Datos incompletos' });
  try {
    const [result] = await db.execute(
      `UPDATE presupuestos SET nombre = ?, monto_total = ? WHERE id = ? AND firebase_uid = ?`,
      [nombre, monto_total, id, firebase_uid]
    );
    if (result.affectedRows === 0) return res.status(404).json({ error: 'Presupuesto no encontrado' });
    res.json({ message: 'Presupuesto actualizado' });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Error al actualizar presupuesto' });
  }
});

// PATCH /presupuestos/:id/tipo-periodo
// Cambia el tipo de período de mensual a quincenal o viceversa.
// Si mensual → quincenal: divide el monto_total entre 2 y ajusta gastos fijos del presupuesto.
// Si quincenal → mensual: multiplica por 2.
// El período activo actual se cierra y se crea uno nuevo con el nuevo tipo.
router.patch('/presupuestos/:id/tipo-periodo', async (req, res) => {
  const { id } = req.params;
  const { firebase_uid, tipo_periodo, dia_inicio_periodo } = req.body;
  if (!firebase_uid || !tipo_periodo)
    return res.status(400).json({ error: 'firebase_uid y tipo_periodo son requeridos' });
  if (!['mensual', 'quincenal'].includes(tipo_periodo))
    return res.status(400).json({ error: 'tipo_periodo debe ser mensual o quincenal' });
  try {
    const [[pres]] = await db.execute(
      `SELECT * FROM presupuestos WHERE id = ? AND firebase_uid = ?`, [id, firebase_uid]
    );
    if (!pres) return res.status(404).json({ error: 'Presupuesto no encontrado' });
    if (pres.tipo_periodo === tipo_periodo)
      return res.status(400).json({ error: 'El presupuesto ya usa ese tipo de período' });

    // Factor de conversión: mensual→quincenal = ÷2, quincenal→mensual = ×2
    const factor = tipo_periodo === 'quincenal' ? 0.5 : 2;
    const nuevoMonto = parseFloat((Number(pres.monto_total) * factor).toFixed(2));
    const nuevoDia   = dia_inicio_periodo ?? pres.dia_inicio_periodo;

    // Actualizar el presupuesto
    await db.execute(
      `UPDATE presupuestos SET tipo_periodo = ?, monto_total = ?, dia_inicio_periodo = ? WHERE id = ?`,
      [tipo_periodo, nuevoMonto, nuevoDia, id]
    );

    // Ajustar los gastos fijos del presupuesto (tabla gastos) al nuevo tipo
    const [gastosFijos] = await db.execute(
      `SELECT id, monto FROM gastos WHERE presupuesto_id = ? AND firebase_uid = ? AND tipo = 'fijo'`,
      [id, firebase_uid]
    );
    for (const g of gastosFijos) {
      const nuevoMontoGasto = parseFloat((Number(g.monto) * factor).toFixed(2));
      await db.execute(`UPDATE gastos SET monto = ? WHERE id = ?`, [nuevoMontoGasto, g.id]);
    }

    // Cerrar período activo y abrir uno nuevo con el nuevo tipo
    await db.execute(
      `UPDATE periodos SET estado = 'cerrado', closed_at = NOW()
       WHERE presupuesto_id = ? AND firebase_uid = ? AND estado = 'activo'`,
      [id, firebase_uid]
    );
    const nuevoPeriodo = await crearPrimerPeriodo(id, firebase_uid, tipo_periodo, nuevoDia);

    res.json({
      mensaje:         `Presupuesto cambiado a ${tipo_periodo}`,
      monto_anterior:  Number(pres.monto_total),
      monto_nuevo:     nuevoMonto,
      gastos_ajustados: gastosFijos.length,
      nuevo_periodo:   nuevoPeriodo,
    });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

module.exports = router;
