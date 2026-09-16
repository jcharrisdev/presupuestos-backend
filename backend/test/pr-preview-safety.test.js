'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const serverSource = fs.readFileSync(
  path.join(__dirname, '..', 'server.js'),
  'utf8',
);

test('las tareas programadas quedan deshabilitadas en previews de PR', () => {
  assert.match(
    serverSource,
    /const habilitarTareasProgramadas = process\.env\.IS_PULL_REQUEST !== 'true';/,
  );

  const inicioProteccion = serverSource.indexOf('if (habilitarTareasProgramadas) {');
  const finProteccion = serverSource.indexOf(
    "console.log('Tareas programadas deshabilitadas en la vista previa del PR');",
  );

  assert.ok(inicioProteccion >= 0, 'falta el inicio de la protección');
  assert.ok(finProteccion > inicioProteccion, 'falta el cierre de la protección');

  const bloqueProtegido = serverSource.slice(inicioProteccion, finProteccion);
  assert.equal(
    (bloqueProtegido.match(/cron\.schedule\(/g) || []).length,
    2,
    'los dos cron deben permanecer dentro de la protección',
  );
});
