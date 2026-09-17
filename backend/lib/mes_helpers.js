/**
 * lib/mes_helpers.js — Recalculo de totales y generación de alertas del mes.
 * Usado por casi todos los módulos que crean/editan registros_gasto
 * (gastos, gustitos, eventos, deudas, invoice-scanner, etc.).
 */
const { db } = require('./db');
const { _montoMensual } = require('./calculos_financieros');

async function _actualizarTotalesMes(mesId, firebaseUid) {
  const [rows] = await db.execute(
    `SELECT tipo, SUM(monto) AS total FROM registros_gasto
     WHERE mes_id = ? AND firebase_uid = ? GROUP BY tipo`,
    [mesId, firebaseUid]
  );
  const totales = { fijo: 0, variable: 0, no_presupuestado: 0 };
  for (const r of rows) totales[r.tipo] = Number(r.total);

  await db.execute(
    `UPDATE meses_financieros SET
       fijos_reales             = ?,
       variables_reales         = ?,
       no_presupuestados_reales = ?
     WHERE id = ?`,
    [totales.fijo, totales.variable, totales.no_presupuestado, mesId]
  );
}

async function _generarAlertasMes(firebase_uid, anio, mes) {
  const alertas = [];
  const [[mesRow]] = await db.execute(
    `SELECT * FROM meses_financieros WHERE firebase_uid = ? AND anio = ? AND mes = ?`,
    [firebase_uid, anio, mes]
  );
  if (!mesRow) return alertas;

  // Alerta DTI crítico: cuotas de deudas > 36% del ingreso neto
  const [[income]] = await db.execute(
    `SELECT ingreso_neto_mensual FROM user_income WHERE firebase_uid = ?`, [firebase_uid]);
  if (income) {
    const [deudas] = await db.execute(
      `SELECT IF(es_letra=1, cuota_fija, pago_minimo) AS cuota FROM deudas WHERE firebase_uid = ? AND activa = 1`,
      [firebase_uid]);
    const totalCuotas = deudas.reduce((s, d) => s + Number(d.cuota || 0), 0);
    const ingresoNeto = Number(income.ingreso_neto_mensual);
    const dti = ingresoNeto > 0 ? totalCuotas / ingresoNeto : 0;
    if (dti > 0.36) {
      alertas.push({
        tipo: 'dti_critico', categoria: null, nivel: dti > 0.50 ? 'danger' : 'warning',
        titulo: `DTI crítico: ${(dti * 100).toFixed(0)}% de tu ingreso va a deudas`,
        mensaje: `Estás destinando $${totalCuotas.toFixed(2)}/mes al pago de deudas (${(dti*100).toFixed(0)}% de tu ingreso neto de $${ingresoNeto.toFixed(2)}). El límite saludable es 36%.`,
        accion_sugerida: 'Considera estrategia avalanche o snowball para acelerar el pago. No contraigas nueva deuda.',
      });
    }
  }

  // Alerta pagos vencidos: deudas con fecha_proximo_pago < hoy
  const [deudasVencidas] = await db.execute(
    `SELECT nombre, fecha_proximo_pago, IF(es_letra=1, cuota_fija, pago_minimo) AS cuota
     FROM deudas WHERE firebase_uid = ? AND activa = 1 AND fecha_proximo_pago < CURDATE()`,
    [firebase_uid]);
  for (const d of deudasVencidas) {
    const fecha = new Date(d.fecha_proximo_pago).toLocaleDateString('es', { day: 'numeric', month: 'long' });
    alertas.push({
      tipo: 'pago_vencido', categoria: null, nivel: 'danger',
      titulo: `Pago vencido: ${d.nombre}`,
      mensaje: `El pago de $${Number(d.cuota).toFixed(2)} de "${d.nombre}" venció el ${fecha}. Los retrasos generan intereses moratorios y afectan tu historial.`,
      accion_sugerida: `Realiza el pago de "${d.nombre}" lo antes posible y actualiza la fecha en tu perfil.`,
    });
  }

  // Gastos variables base del usuario (presupuesto estimado por categoría)
  const [varBase] = await db.execute(
    `SELECT categoria, SUM(monto_estimado) AS presupuestado
     FROM gastos_variables_base WHERE firebase_uid = ? AND activo = 1
     GROUP BY categoria`,
    [firebase_uid]
  );
  const presupPorCat = {};
  for (const g of varBase) presupPorCat[g.categoria] = Number(g.presupuestado);

  // Gastos reales del mes por categoría
  const [reales] = await db.execute(
    `SELECT categoria,
            SUM(CASE WHEN tipo='no_presupuestado' THEN monto ELSE 0 END) AS no_presup,
            SUM(CASE WHEN tipo='variable' THEN monto ELSE 0 END)         AS variable,
            SUM(monto) AS total
     FROM registros_gasto WHERE mes_id = ? AND firebase_uid = ? GROUP BY categoria`,
    [mesRow.id, firebase_uid]
  );

  for (const cat of reales) {
    const presup   = presupPorCat[cat.categoria] || 0;
    const noPresup = Number(cat.no_presup);
    const total    = Number(cat.total);

    // Alerta 1: no-presupuestados superan el 20% del presupuesto de la categoría
    if (presup > 0 && noPresup / presup > 0.20) {
      alertas.push({
        tipo: 'no_presup_alto', categoria: cat.categoria, nivel: 'warning',
        titulo: `Gastos no presupuestados altos en ${cat.categoria}`,
        mensaje: `Tienes $${noPresup.toFixed(2)} en compras no presupuestadas en ${cat.categoria}, que es el ${(noPresup/presup*100).toFixed(0)}% de tu presupuesto ($${presup.toFixed(2)}).`,
        accion_sugerida: `Considera aumentar tu presupuesto de ${cat.categoria} o revisar estos gastos.`,
      });
    }

    // Alerta 2: gasto total supera el presupuesto
    if (presup > 0 && total > presup * 1.30) {
      alertas.push({
        tipo: 'categoria_excedida', categoria: cat.categoria, nivel: 'danger',
        titulo: `Presupuesto excedido en ${cat.categoria}`,
        mensaje: `Gastaste $${total.toFixed(2)} en ${cat.categoria} pero presupuestaste $${presup.toFixed(2)} (${((total/presup-1)*100).toFixed(0)}% de exceso).`,
        accion_sugerida: `Revisa tus gastos de ${cat.categoria} y ajusta el presupuesto si este nivel es frecuente.`,
      });
    }
  }

  // Alerta 3: repetición — categoría no presupuestada 3+ meses consecutivos
  if (mes >= 3) {
    const [repetidos] = await db.execute(
      `SELECT rg.categoria, COUNT(DISTINCT rg.mes) AS meses_repetidos
       FROM registros_gasto rg
       WHERE rg.firebase_uid = ? AND rg.anio = ? AND rg.mes BETWEEN ? AND ?
         AND rg.tipo = 'no_presupuestado'
         AND rg.categoria NOT IN (
           SELECT DISTINCT categoria FROM gastos_variables_base WHERE firebase_uid = ? AND activo = 1
         )
       GROUP BY rg.categoria HAVING meses_repetidos >= 3`,
      [firebase_uid, anio, mes - 2, mes, firebase_uid]
    );
    for (const r of repetidos) {
      alertas.push({
        tipo: 'repeticion_no_presup', categoria: r.categoria, nivel: 'info',
        titulo: `Gasto repetido en ${r.categoria}`,
        mensaje: `Llevas ${r.meses_repetidos} meses con gastos no presupuestados en ${r.categoria}.`,
        accion_sugerida: `Considera agregar ${r.categoria} a tu presupuesto variable base para controlarlo mejor.`,
      });
    }
  }

  // Alerta 4: remanente bajo (< 10% del ingreso)
  const ingresoMes = Number(mesRow.ingreso_real) || Number(mesRow.ingreso_estimado);
  const fijosReal  = Number(mesRow.fijos_reales) || 0;
  const varReal    = Number(mesRow.variables_reales) || 0;
  const noPresReal = Number(mesRow.no_presupuestados_reales) || 0;
  const remanenteReal = ingresoMes - fijosReal - varReal - noPresReal;
  if (ingresoMes > 0 && remanenteReal < ingresoMes * 0.10 && remanenteReal >= 0) {
    alertas.push({
      tipo: 'remanente_bajo', categoria: null, nivel: 'warning',
      titulo: 'Remanente muy ajustado',
      mensaje: `Tu remanente este mes es $${remanenteReal.toFixed(2)}, menos del 10% de tu ingreso ($${ingresoMes.toFixed(2)}). Queda poco margen ante imprevistos.`,
      accion_sugerida: 'Revisa si hay gastos variables que puedas reducir o diferir al mes siguiente.',
    });
  }
  if (ingresoMes > 0 && remanenteReal < 0) {
    alertas.push({
      tipo: 'remanente_negativo', categoria: null, nivel: 'danger',
      titulo: 'Gasto mayor al ingreso',
      mensaje: `Tus gastos superan tu ingreso en $${Math.abs(remanenteReal).toFixed(2)} este mes.`,
      accion_sugerida: 'Identifica los gastos que puedas eliminar o reducir para volver a terreno positivo.',
    });
  }

  // Alerta 5: tendencia creciente — categoría con gasto creciendo 3 meses seguidos
  if (mes >= 3) {
    const [tendencia] = await db.execute(
      `SELECT categoria,
              SUM(CASE WHEN mes = ? THEN monto ELSE 0 END) AS mes0,
              SUM(CASE WHEN mes = ? THEN monto ELSE 0 END) AS mes1,
              SUM(CASE WHEN mes = ? THEN monto ELSE 0 END) AS mes2
       FROM registros_gasto
       WHERE firebase_uid = ? AND anio = ? AND mes BETWEEN ? AND ?
         AND tipo IN ('variable','no_presupuestado')
       GROUP BY categoria`,
      [mes - 2, mes - 1, mes, firebase_uid, anio, mes - 2, mes]
    );
    for (const t of tendencia) {
      const m0 = Number(t.mes0), m1 = Number(t.mes1), m2 = Number(t.mes2);
      if (m0 > 0 && m1 > m0 && m2 > m1) {
        const crec = ((m2 - m0) / m0 * 100).toFixed(0);
        alertas.push({
          tipo: 'tendencia_creciente', categoria: t.categoria, nivel: 'warning',
          titulo: `Tendencia creciente en ${t.categoria}`,
          mensaje: `Tu gasto en ${t.categoria} lleva 3 meses subiendo: $${m0.toFixed(0)} → $${m1.toFixed(0)} → $${m2.toFixed(0)} (+${crec}% total).`,
          accion_sugerida: `Revisa qué está impulsando el aumento en ${t.categoria} antes de que impacte más el presupuesto.`,
        });
      }
    }
  }

  // Alerta 6: presupuesto subestimado — promedio real últimos 3 meses supera estimado >20%
  if (mes >= 3) {
    const [promCat] = await db.execute(
      `SELECT categoria, AVG(monto) AS promedio_real
       FROM registros_gasto
       WHERE firebase_uid = ? AND anio = ? AND mes BETWEEN ? AND ?
         AND tipo = 'variable'
       GROUP BY categoria`,
      [firebase_uid, anio, mes - 2, mes]
    );
    for (const p of promCat) {
      const presup  = presupPorCat[p.categoria] || 0;
      const promedio = Number(p.promedio_real);
      if (presup > 0 && promedio > presup * 1.20) {
        const exceso = ((promedio / presup - 1) * 100).toFixed(0);
        alertas.push({
          tipo: 'presupuesto_subestimado', categoria: p.categoria, nivel: 'info',
          titulo: `Presupuesto subestimado en ${p.categoria}`,
          mensaje: `Tu gasto real promedio en ${p.categoria} ($${promedio.toFixed(2)}/mes) supera tu presupuesto ($${presup.toFixed(2)}/mes) en ${exceso}% durante 3 meses.`,
          accion_sugerida: `Considera aumentar el presupuesto de ${p.categoria} a al menos $${Math.ceil(promedio).toFixed(0)}/mes.`,
        });
      }
    }
  }

  // Alerta 7: impacto anual — si el ritmo actual persiste, el remanente anual cambia >20%
  if (ingresoMes > 0 && mes >= 2) {
    const [[efaRow]] = await db.execute(
      `SELECT remanente_anual_estimado FROM estado_financiero_anual WHERE firebase_uid = ? AND anio = ?`,
      [firebase_uid, anio]
    );
    if (efaRow) {
      const remEst = Number(efaRow.remanente_anual_estimado);
      // Ritmo mensual real proyectado al año
      const ritmoMensual = remanenteReal;
      const remProyectado = ritmoMensual * 12;
      const diferencia = Math.abs(remProyectado - remEst);
      if (remEst !== 0 && diferencia / Math.abs(remEst) > 0.25) {
        const dir = remProyectado < remEst ? 'bajar' : 'subir';
        alertas.push({
          tipo: 'impacto_anual', categoria: null, nivel: remProyectado < remEst ? 'warning' : 'info',
          titulo: 'Impacto anual proyectado',
          mensaje: `Si mantienes este ritmo de gasto, tu remanente anual podría ${dir} de $${remEst.toFixed(0)} a $${remProyectado.toFixed(0)}.`,
          accion_sugerida: dir === 'bajar'
            ? 'Revisa tus gastos variables para acercarte al plan original.'
            : 'Vas mejor que lo planeado — considera destinar el extra a una meta de ahorro.',
        });
      }
    }
  }

  // Guardar alertas nuevas: borrar la del mismo tipo/categoría/mes y re-insertar con datos frescos
  for (const a of alertas) {
    try {
      await db.execute(
        `DELETE FROM alertas_financieras WHERE firebase_uid=? AND anio=? AND mes=? AND tipo=? AND (categoria=? OR (categoria IS NULL AND ? IS NULL))`,
        [firebase_uid, anio, mes, a.tipo, a.categoria || null, a.categoria || null]
      );
      await db.execute(
        `INSERT INTO alertas_financieras (firebase_uid, anio, mes, tipo, categoria, nivel, titulo, mensaje, accion_sugerida)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [firebase_uid, anio, mes, a.tipo, a.categoria || null, a.nivel, a.titulo, a.mensaje, a.accion_sugerida || null]
      );
    } catch (_) { /* ignorar errores inesperados */ }
  }
  return alertas;
}

// Recalcula los estimados en meses_financieros y estado_financiero_anual
// cuando el perfil del usuario cambia (gastos fijos, variables base, deudas).
// Fire-and-forget: llámalo con .catch() para no bloquear la respuesta principal.
async function _recalcularEstimadosAnio(firebase_uid, anio) {
  const year = anio || new Date().getFullYear();
  const [[efa]] = await db.execute(
    `SELECT id FROM estado_financiero_anual WHERE firebase_uid = ? AND anio = ?`,
    [firebase_uid, year]
  );
  if (!efa) return; // aún no se generó el estado anual — nada que actualizar

  const [[income]] = await db.execute(
    `SELECT ingreso_neto_mensual FROM user_income WHERE firebase_uid = ?`, [firebase_uid]
  );
  if (!income) return;

  const [gastosFijos] = await db.execute(
    `SELECT * FROM user_gastos_fijos WHERE firebase_uid = ? AND activo = 1`, [firebase_uid]
  );
  const [deudasIndep] = await db.execute(
    `SELECT d.* FROM deudas d
     LEFT JOIN user_gastos_fijos ugf ON ugf.deuda_id = d.id
     WHERE d.firebase_uid = ? AND d.activa = 1 AND ugf.id IS NULL`, [firebase_uid]
  );
  const [variablesBase] = await db.execute(
    `SELECT * FROM gastos_variables_base WHERE firebase_uid = ? AND activo = 1`, [firebase_uid]
  );

  const ingresoMensual    = Number(income.ingreso_neto_mensual);
  const totalFijosMensual = gastosFijos.reduce((s, g) => s + Number(g.monto_mensual), 0)
                          + deudasIndep.reduce((s, d) => s + Number(d.pago_minimo || d.cuota_fija || 0), 0);
  const totalVarAnual     = variablesBase.reduce((s, g) => {
    const arr = g.aplica_meses
      ? (typeof g.aplica_meses === 'string' ? JSON.parse(g.aplica_meses) : g.aplica_meses)
      : [1,2,3,4,5,6,7,8,9,10,11,12];
    return s + _montoMensual(g) * arr.length;
  }, 0);

  // Actualizar estado_financiero_anual
  await db.execute(
    `UPDATE estado_financiero_anual SET
       ingreso_anual_estimado   = ?,
       gastos_fijos_anuales     = ?,
       gastos_variables_anuales = ?,
       remanente_anual_estimado = ?,
       updated_at               = NOW()
     WHERE firebase_uid = ? AND anio = ?`,
    [parseFloat((ingresoMensual * 12).toFixed(2)),
     parseFloat((totalFijosMensual * 12).toFixed(2)),
     parseFloat(totalVarAnual.toFixed(2)),
     parseFloat(((ingresoMensual - totalFijosMensual) * 12 - totalVarAnual).toFixed(2)),
     firebase_uid, year]
  );

  // Actualizar meses_financieros — estimados + ingreso por mes (respeta aplica_meses)
  const [meses] = await db.execute(
    `SELECT id, mes FROM meses_financieros WHERE firebase_uid = ? AND anio = ?`,
    [firebase_uid, year]
  );
  for (const mesRow of meses) {
    const m = mesRow.mes;
    const varMes = variablesBase.reduce((s, g) => {
      if (g.aplica_meses) {
        const arr = typeof g.aplica_meses === 'string' ? JSON.parse(g.aplica_meses) : g.aplica_meses;
        if (!arr.includes(Number(m))) return s;
      }
      return s + _montoMensual(g);
    }, 0);
    // ingreso_real = salario base + ingresos extra del mes
    const [[extraRow]] = await db.execute(
      `SELECT COALESCE(SUM(monto), 0) AS total FROM registros_ingreso
       WHERE firebase_uid = ? AND anio = ? AND mes = ?`,
      [firebase_uid, year, m]
    );
    const ingresoReal = parseFloat((ingresoMensual + Number(extraRow.total)).toFixed(2));
    await db.execute(
      `UPDATE meses_financieros SET
         ingreso_estimado    = ?,
         ingreso_real        = ?,
         fijos_estimados     = ?,
         variables_estimados = ?,
         remanente_estimado  = ?
       WHERE id = ?`,
      [parseFloat(ingresoMensual.toFixed(2)),
       ingresoReal,
       parseFloat(totalFijosMensual.toFixed(2)),
       parseFloat(varMes.toFixed(2)),
       parseFloat((ingresoMensual - totalFijosMensual - varMes).toFixed(2)),
       mesRow.id]
    );
  }
}

module.exports = { _actualizarTotalesMes, _generarAlertasMes, _recalcularEstimadosAnio };
