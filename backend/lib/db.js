/**
 * lib/db.js — Pool de conexiones MySQL compartido.
 *
 * Se usa createPool en lugar de createConnection para evitar que el servidor
 * crashee cuando Clever Cloud cierra conexiones inactivas (timeout).
 * connectionLimit: 2 → Clever Cloud free tier permite máximo 5 conexiones.
 * Con 2, durante un redeploy en Render (viejo + nuevo server en paralelo) se usan
 * máximo 2+2=4 conexiones, quedando 1 de margen antes del límite de 5.
 */
const mysql = require('mysql2');

const pool = mysql.createPool({
  host:     process.env.MYSQLHOST,
  user:     process.env.MYSQLUSER,
  password: process.env.MYSQLPASSWORD,
  database: process.env.MYSQLDATABASE,
  port:     Number(process.env.MYSQLPORT),
  waitForConnections: true,
  connectionLimit: 2,
  queueLimit: 0,
  charset:  'utf8mb4',
});

const db = pool.promise();

module.exports = { pool, db };
