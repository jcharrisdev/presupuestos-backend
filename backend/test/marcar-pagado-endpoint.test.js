'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const source = fs.readFileSync(path.join(__dirname, '../server.js'), 'utf8');
const start = source.indexOf("app.patch('/registros/:id/pagar',");
const end = source.indexOf("// POST /registros/:id/convertir-a-variable", start);
assert.ok(start >= 0 && end > start, 'No se encontró el endpoint para marcar pagado');

function crearEndpoint({ affectedRows = 1 } = {}) {
  let handler;
  const consultas = [];
  const db = {
    async execute(sql, params) {
      consultas.push({ sql, params: Array.from(params) });
      return [{ affectedRows }];
    },
  };
  vm.runInNewContext(source.slice(start, end), {
    app: { patch(route, callback) { handler = callback; } },
    db,
  });
  return {
    consultas,
    async patch(body, id = '17') {
      let status = 200;
      let responseBody;
      const res = {
        status(value) { status = value; return res; },
        json(value) {
          responseBody = JSON.parse(JSON.stringify(value));
          return res;
        },
      };
      await handler({ params: { id }, body }, res);
      return { status, body: responseBody };
    },
  };
}

test('PATCH normaliza booleanos, números y cadenas 0/1 sin convertir "0" en pagado', async () => {
  const casos = [
    { entrada: true, esperado: 1 },
    { entrada: 1, esperado: 1 },
    { entrada: '1', esperado: 1 },
    { entrada: false, esperado: 0 },
    { entrada: 0, esperado: 0 },
    { entrada: '0', esperado: 0 },
  ];
  for (const caso of casos) {
    const api = crearEndpoint();
    const response = await api.patch({ firebase_uid: 'usuario-1', pagado: caso.entrada });
    assert.equal(response.status, 200);
    assert.equal(response.body.pagado, caso.esperado);
    assert.deepEqual(api.consultas[0].params, [caso.esperado, '17', 'usuario-1']);
  }
});

test('PATCH rechaza estados ambiguos y no anuncia éxito cuando el registro no existe', async () => {
  for (const entrada of [2, -1, 'true', 'false', '', null, undefined]) {
    const api = crearEndpoint();
    const response = await api.patch({ firebase_uid: 'usuario-1', pagado: entrada });
    assert.equal(response.status, 400);
    assert.equal(api.consultas.length, 0);
  }

  const inexistente = crearEndpoint({ affectedRows: 0 });
  const response = await inexistente.patch({ firebase_uid: 'usuario-1', pagado: 1 });
  assert.equal(response.status, 404);
  assert.equal(response.body.error, 'Registro no encontrado');
});
