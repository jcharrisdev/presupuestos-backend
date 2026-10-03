/**
 * routes/notifications.js — Registro de tokens de dispositivo para push (FCM).
 * El envío real vive en lib/push_notifications.js, disparado desde
 * lib/mes_helpers.js (pago_vencido, remanente_negativo) y el cron de
 * recordatorios en server.js (recordatorio_pago).
 */
const express = require('express');
const router = express.Router();
const { _registrarToken, _eliminarToken } = require('../lib/push_notifications');

// POST /notifications/register-token
router.post('/notifications/register-token', async (req, res) => {
  const { firebase_uid, token, plataforma } = req.body;
  if (!firebase_uid || !token) return res.status(400).json({ error: 'firebase_uid y token requeridos' });
  try {
    await _registrarToken(firebase_uid, token, plataforma || 'web');
    res.json({ success: true });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// DELETE /notifications/register-token — desregistrar (ej. al cerrar sesión)
router.delete('/notifications/register-token', async (req, res) => {
  const { token } = req.body;
  if (!token) return res.status(400).json({ error: 'token requerido' });
  try {
    await _eliminarToken(token);
    res.json({ success: true });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

module.exports = router;
