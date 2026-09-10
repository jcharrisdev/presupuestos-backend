'use strict';

// Contrato de caja mensual. Los campos históricos *_reales siguen representando
// registros; estos campos distinguen pagos y obligaciones sin escribir en BD.
const centavos = value => Math.round(Number(value ?? 0) * 100);
const dinero = value => value / 100;
const pagado = value => value === true || Number(value) === 1;

function calcularResumenMensual({ ingreso, registros = [], gastosFijos = [], deudas = [], eventos = [] }) {
  const compromisos = [];
  const porOrigen = new Map();
  const agregar = (tipo, item, monto, origenes) => {
    const compromiso = {
      tipo, id: item.id, nombre: item.nombre ?? item.descripcion,
      presupuesto: centavos(monto), pagado: 0, registradoPendiente: 0,
    };
    compromisos.push(compromiso);
    for (const origen of origenes) porOrigen.set(origen, compromiso);
    return compromiso;
  };

  for (const fijo of gastosFijos) {
    const origenes = [`fijo:${fijo.id}`];
    if (fijo.deuda_id != null) origenes.push(`deuda:${fijo.deuda_id}`);
    agregar('fijo', fijo, fijo.monto_mensual, origenes);
  }
  for (const deuda of deudas) {
    // Una deuda vinculada al perfil ya es el mismo compromiso fijo.
    if (porOrigen.has(`deuda:${deuda.id}`)) continue;
    agregar('deuda', deuda, pagado(deuda.es_letra) ? deuda.cuota_fija : deuda.pago_minimo,
      [`deuda:${deuda.id}`]);
  }
  for (const evento of eventos) {
    agregar('evento', evento, evento.cuota_mensual, [`evento:${evento.id}`]);
  }

  let pagos = 0, pendientes = 0;
  for (const registro of registros) {
    const monto = centavos(registro.monto);
    const estaPagado = pagado(registro.pagado);
    if (estaPagado) pagos += monto;
    else pendientes += monto;

    // Un registro solo cubre un compromiso, incluso si conserva dos vínculos.
    const compromiso = porOrigen.get(`fijo:${registro.origen_fijo_id}`)
      ?? porOrigen.get(`deuda:${registro.origen_deuda_id}`)
      ?? porOrigen.get(`evento:${registro.origen_evento_id}`);
    if (compromiso) {
      if (estaPagado) compromiso.pagado += monto;
      else compromiso.registradoPendiente += monto;
    }
  }

  // Descontar TODOS los registros vinculados antes de añadir el compromiso que
  // falta registrar: un gasto pendiente vinculado no puede contarse dos veces.
  let sinRegistrar = 0;
  const detalle = compromisos.map(c => {
    const restante = Math.max(0, c.presupuesto - c.pagado - c.registradoPendiente);
    sinRegistrar += restante;
    return {
      tipo: c.tipo, id: c.id, nombre: c.nombre,
      presupuestado: dinero(c.presupuesto), pagado: dinero(c.pagado),
      registrado_pendiente: dinero(c.registradoPendiente),
      sin_registrar: dinero(restante),
      pendiente: dinero(c.registradoPendiente + restante),
    };
  });
  const totalPendiente = pendientes + sinRegistrar;
  const disponibleReal = centavos(ingreso) - pagos;
  return {
    gastos_registrados: dinero(pagos + pendientes),
    gastos_pagados: dinero(pagos),
    gastos_pendientes: dinero(pendientes),
    compromisos_pendientes: dinero(sinRegistrar),
    total_pendiente: dinero(totalPendiente),
    disponible_real: dinero(disponibleReal),
    disponible_proyectado: dinero(disponibleReal - totalPendiente),
    compromisos_pendientes_detalle: detalle.filter(c => c.pendiente > 0),
  };
}

module.exports = { calcularResumenMensual };
