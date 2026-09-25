'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { calcularSugerenciasPresupuesto } = require('../finanzas/cierre-mes-insights');

// Ejecuta los handlers reales con una BD en memoria, mismo patrón que
// analisis-variaciones-endpoint.test.js: no se importa server.js completo.
const source = fs.readFileSync(path.join(__dirname, '../server.js'), 'utf8');
const start = source.indexOf('async function _calcularSugerenciasAnuales');
const end = source.indexOf('// MÓDULO IA — Asistente financiero con Claude', start);
assert.ok(start >= 0 && end > start, 'No se encontró el bloque de estado anual');

function crearEndpoints({ porMesCat = [], varBase = [], fijosCat = [], meses = [], efa = { id: 1 } } = {}) {
  const handlers = { get: {}, post: {} };
  const db = {
    async execute(sql, params) {
      assert.ok(/^\s*SELECT\b|^\s*INSERT\b/.test(sql), 'La consulta debe ser de solo lectura o el snapshot final');
      if (sql.includes('FROM registros_gasto') && sql.includes('GROUP BY mes, categoria')) {
        assert.deepEqual(Array.from(params), ['prueba-usuario', '2026']);
        return [porMesCat];
      }
      if (sql.includes('FROM gastos_variables_base')) return [varBase];
      if (sql.includes('FROM user_gastos_fijos')) return [fijosCat];
      if (sql.includes('FROM estado_financiero_anual')) return [[efa].filter(Boolean)];
      if (sql.includes('FROM meses_financieros')) return [meses];
      if (sql.includes('FROM registros_gasto') && sql.includes('GROUP BY categoria')) return [[]];
      if (sql.startsWith('INSERT INTO cierres_anuales')) return [{ insertId: 1 }];
      throw new Error(`Consulta inesperada: ${sql}`);
    },
  };
  vm.runInNewContext(source.slice(start, end), {
    app: {
      get(route, cb) { handlers.get[route] = cb; },
      post(route, cb) { handlers.post[route] = cb; },
    },
    db, calcularSugerenciasPresupuesto,
    _montoMensual: g => Number(g.monto_mensual ?? g.monto_estimado),
    _logInfo: () => {},
  });
  return {
    async get(uid = 'prueba-usuario', anio = '2026') {
      let status = 200, body;
      const res = {
        status(value) { status = value; return res; },
        json(value) { body = JSON.parse(JSON.stringify(value)); return res; },
      };
      await handlers.get['/user/proyeccion-siguiente-anio/:anio']({ params: { anio }, query: { firebase_uid: uid } }, res);
      return { status, body };
    },
    async post(uid = 'prueba-usuario', anio = '2026') {
      let status = 200, body;
      const res = {
        status(value) { status = value; return res; },
        json(value) { body = JSON.parse(JSON.stringify(value)); return res; },
      };
      await handlers.post['/user/cerrar-anio/:anio']({ params: { anio }, body: { firebase_uid: uid } }, res);
      return { status, body };
    },
  };
}

const fila = (mes, categoria, total) => ({ mes, categoria, total });

test('FIN-04: proyección sin patrón consistente no sugiere nada', async () => {
  const porMesCat = [fila(9, 'alimentacion', '280.00')];
  const varBase = [{ id: 1, nombre: 'Supermercado', categoria: 'alimentacion', monto_estimado: '300.00' }];
  const api = crearEndpoints({ porMesCat, varBase });
  const { status, body } = await api.get();

  assert.equal(status, 200, JSON.stringify(body));
  assert.equal(body.anio_analizado, 2026);
  assert.equal(body.anio_proyectado, 2027);
  assert.deepEqual(body.sugerencias_presupuesto, []);
});

test('FIN-04: exceso consistente en categoría esencial durante el año sugiere subir presupuesto', async () => {
  const porMesCat = [
    fila(9, 'alimentacion', '400.00'),
    fila(8, 'alimentacion', '390.00'),
    fila(7, 'alimentacion', '410.00'),
  ];
  const varBase = [{ id: 1, nombre: 'Supermercado', categoria: 'alimentacion', monto_estimado: '300.00' }];
  const api = crearEndpoints({ porMesCat, varBase });
  const { status, body } = await api.get();

  assert.equal(status, 200, JSON.stringify(body));
  assert.equal(body.sugerencias_presupuesto.length, 1);
  const sug = body.sugerencias_presupuesto[0];
  assert.equal(sug.categoria, 'alimentacion');
  assert.equal(sug.direccion, 'subir');
  assert.equal(sug.clasificacion, 'esencial');
  assert.match(body.resumen, /1 ajustes/);
});

test('FIN-04: exceso consistente en categoría flexible NUNCA sugiere subir (guardrail del asesor)', async () => {
  const porMesCat = [
    fila(9, 'ocio', '220.00'),
    fila(8, 'ocio', '210.00'),
    fila(7, 'ocio', '230.00'),
  ];
  const varBase = [{ id: 2, nombre: 'Salidas', categoria: 'ocio', monto_estimado: '150.00' }];
  const api = crearEndpoints({ porMesCat, varBase });
  const { body } = await api.get();

  assert.deepEqual(body.sugerencias_presupuesto, []);
});

test('FIN-04: cerrar-anio guarda el snapshot y devuelve sugerencias_presupuesto (no el campo viejo "recomendaciones")', async () => {
  const porMesCat = [
    fila(9, 'ocio', '60.00'),
    fila(8, 'ocio', '65.00'),
    fila(7, 'ocio', '55.00'),
  ];
  const varBase = [{ id: 2, nombre: 'Salidas', categoria: 'ocio', monto_estimado: '150.00' }];
  const meses = [
    { ingreso_real: '1000.00', ingreso_estimado: '1000.00', fijos_reales: '400.00', variables_reales: '60.00', no_presupuestados_reales: '0.00' },
  ];
  const api = crearEndpoints({ porMesCat, varBase, meses });
  const { status, body } = await api.post();

  assert.equal(status, 200, JSON.stringify(body));
  assert.equal(body.cerrado, true);
  assert.equal(body.sugerencias_presupuesto.length, 1);
  assert.equal(body.sugerencias_presupuesto[0].direccion, 'bajar');
  assert.equal(body.recomendaciones, undefined);
  assert.match(body.mensaje, /1 ajuste/);
});

test('FIN-04: cerrar-anio sin estado financiero anual devuelve 404', async () => {
  const api = crearEndpoints({ efa: null });
  const { status, body } = await api.post();
  assert.equal(status, 404);
  assert.match(body.error, /Estado anual no encontrado/);
});
