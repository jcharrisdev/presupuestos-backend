/**
 * lib/calendario_helpers.js — Generación de eventos de calendario para gastos
 * con fecha fija. Compartido por el módulo de Gastos, Gastos Globales y Calendario.
 */
const { db } = require('./db');

function calcularFechasEvento(frecuencia, diaPago, fechaExacta) {
  const fechas = [];
  const hoy = new Date();

  if (frecuencia === 'unico') {
    if (fechaExacta) {
      const f = fechaExacta instanceof Date
        ? fechaExacta.toISOString().split('T')[0]
        : String(fechaExacta).split('T')[0];
      fechas.push(f);
    }
    return fechas;
  }

  const MESES = 12; // Generamos eventos para los próximos 12 meses
  for (let m = 0; m < MESES; m++) {
    const anio      = hoy.getUTCFullYear() + Math.floor((hoy.getUTCMonth() + m) / 12);
    const mes       = (hoy.getUTCMonth() + m) % 12;
    const ultimoDia = new Date(Date.UTC(anio, mes + 1, 0)).getUTCDate(); // Último día del mes

    // Para anual, solo generamos 1 evento cada 12 meses
    if (frecuencia === 'anual' && m % 12 !== 0) continue;

    // Base: dia_pago del mes (ajustado al último día si el mes es más corto)
    const dias = [Math.min(diaPago, ultimoDia)];
    // Para quincenal: segunda fecha 14 días después (también ajustada)
    if (frecuencia === 'quincenal') dias.push(Math.min(diaPago + 14, ultimoDia));

    for (const dia of dias) {
      fechas.push(`${anio}-${String(mes + 1).padStart(2, '0')}-${String(dia).padStart(2, '0')}`);
    }
  }
  return fechas;
}

/**
 * Genera los eventos de calendario para un gasto con tipo_fecha='fija'.
 * Se llama automáticamente al crear un gasto con fecha fija.
 * También se puede llamar manualmente con POST /calendario/generar.
 *
 * @param {number} gastoId
 * @param {string} firebaseUid
 * @returns {number} Cantidad de eventos insertados
 */
async function generarEventosCalendario(gastoId, firebaseUid) {
  const [[gasto]] = await db.execute(
    `SELECT * FROM gastos WHERE id = ? AND firebase_uid = ?`, [gastoId, firebaseUid]
  );
  // Solo generamos eventos si el gasto tiene fecha fija configurada
  if (!gasto || gasto.tipo_fecha !== 'fija') return 0;

  const fechas = calcularFechasEvento(gasto.frecuencia_pago, gasto.dia_pago, gasto.fecha_pago_exacta);
  let insertados = 0;
  for (const fecha of fechas) {
    try {
      await db.execute(
        `INSERT INTO calendario_eventos
         (firebase_uid, gasto_id, titulo, tipo, fecha_evento, monto_esperado, notificacion_activa, dias_anticipacion)
         VALUES (?, ?, ?, 'pago', ?, ?, ?, ?)`,
        [firebaseUid, gastoId, gasto.descripcion, fecha, gasto.monto,
         gasto.genera_notificacion ? 1 : 0, gasto.dias_anticipacion || 3]
      );
      insertados++;
    } catch (err) { console.error('Error insertando evento:', err.message); }
  }
  return insertados;
}

/**
 * Genera eventos de calendario para un gasto del perfil (gasto fijo o gasto
 * global) con recordatorio. Si diaPago2 está definido, genera un segundo
 * evento por mes (quincenas).
 */
async function generarEventosPerfilGasto(firebase_uid, ugfId, titulo, monto, diaPago, diaPago2) {
  const today = new Date();
  let generados = 0;
  const dias = [diaPago, diaPago2].filter(Boolean);
  for (const diaNum of dias) {
    for (let i = 0; i < 12; i++) {
      const d = new Date(today.getFullYear(), today.getMonth() + i, 1);
      const diasEnMes = new Date(d.getFullYear(), d.getMonth() + 1, 0).getDate();
      const dia = Math.min(diaNum, diasEnMes);
      const fecha = new Date(d.getFullYear(), d.getMonth(), dia);
      const fechaStr = fecha.toISOString().split('T')[0];
      const estado = fecha < today ? 'vencido' : 'pendiente';
      await db.execute(
        `INSERT INTO calendario_eventos
           (firebase_uid, user_gasto_fijo_id, titulo, tipo, fecha_evento,
            monto_esperado, estado, notificacion_activa, dias_anticipacion)
         VALUES (?, ?, ?, 'pago', ?, ?, ?, 1, 2)`,
        [firebase_uid, ugfId, titulo, fechaStr, monto, estado]
      );
      generados++;
    }
  }
  return generados;
}

module.exports = { calcularFechasEvento, generarEventosCalendario, generarEventosPerfilGasto };
