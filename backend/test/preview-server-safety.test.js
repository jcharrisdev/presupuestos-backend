'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const source = fs.readFileSync(
  path.join(__dirname, '..', 'preview-server.js'),
  'utf8',
);

test('el arranque de preview exige IS_PULL_REQUEST y anula node-cron', () => {
  assert.match(source, /process\.env\.IS_PULL_REQUEST !== 'true'/);
  assert.match(source, /cron\.schedule = \(\) =>/);
  assert.ok(
    source.indexOf("process.env.IS_PULL_REQUEST !== 'true'") <
      source.indexOf("require('./server')"),
    'la protección debe ejecutarse antes de cargar server.js',
  );
});
