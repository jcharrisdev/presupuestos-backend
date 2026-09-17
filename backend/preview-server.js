'use strict';

// Este arranque se usa únicamente en las vistas previas de Pull Requests de
// Render. Evita que una instancia temporal ejecute los cron que modifican
// eventos vencidos o envían resúmenes mensuales sobre la base conectada.
if (process.env.IS_PULL_REQUEST !== 'true') {
  console.error('preview-server.js solo puede ejecutarse en una vista previa de PR');
  process.exit(1);
}

const cron = require('node-cron');

cron.schedule = () => ({
  start() {},
  stop() {},
  destroy() {},
});

console.log('Tareas programadas deshabilitadas para la vista previa del PR');

require('./server');
