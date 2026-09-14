'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const source = fs.readFileSync(path.join(__dirname, '../server.js'), 'utf8');

test('los endpoints de logs usan solo LOG_SECRET del entorno y fallan de forma segura', () => {
  assert.match(source, /const LOG_SECRET = process\.env\.LOG_SECRET;/);
  assert.doesNotMatch(source, /const LOG_SECRET = process\.env\.LOG_SECRET\s*\|\|/);

  const guards = source.match(/if \(!LOG_SECRET \|\| secret !== LOG_SECRET\)/g) ?? [];
  assert.equal(guards.length, 2);
});
