const express = require('express');
const router = express.Router();
const mysql = require('mysql2');

// Conexión MySQL
const connection = mysql.createConnection({
  host: process.env.MYSQLHOST,
  user: process.env.MYSQLUSER,
  password: process.env.MYSQLPASSWORD,
  database: process.env.MYSQLDATABASE,
  port: process.env.MYSQLPORT,
});


// ===============================
// CREAR PRESUPUESTO (CON UID)
// ===============================
router.post('/', (req, res) => {
  const { nombre, monto_total, firebase_uid } = req.body;

  // Validación mínima
  if (!nombre || !monto_total || !firebase_uid) {
    return res.status(400).json({
      error: 'nombre, monto_total y firebase_uid son obligatorios',
    });
  }

  const query = `
    INSERT INTO presupuestos (nombre, monto_total, firebase_uid)
    VALUES (?, ?, ?)
  `;

  connection.execute(
    query,
    [nombre, monto_total, firebase_uid],
    (err, results) => {
      if (err) {
        console.error('Error al crear el presupuesto:', err);
        return res.status(500).send('Error en el servidor');
      }

      res.status(201).json({
        message: 'Presupuesto creado correctamente',
        id: results.insertId,
      });
    }
  );
});


// ===============================
// OBTENER PRESUPUESTOS POR UID
// ===============================
router.get('/', (req, res) => {
  const { firebase_uid } = req.query;

  if (!firebase_uid) {
    return res.status(400).json({
      error: 'firebase_uid es requerido',
    });
  }

  const query = `
    SELECT *
    FROM presupuestos
    WHERE firebase_uid = IFNULL(?,'N/A')
    ORDER BY id DESC
  `;

  connection.execute(query, [firebase_uid], (err, results) => {
    if (err) {
      console.error('Error al obtener los presupuestos:', err);
      return res.status(500).send('Error en el servidor');
    }

    res.json(results);
  });
});


// ===============================
// AGREGAR GASTO (CON UID)
// ===============================
router.post('/:id/gastos', (req, res) => {
  const presupuestoId = req.params.id;
  const { descripcion, monto, firebase_uid } = req.body;

  if (!descripcion || !monto || !firebase_uid) {
    return res.status(400).json({
      error: 'descripcion, monto y firebase_uid son obligatorios',
    });
  }

  const query = `
    INSERT INTO gastos (presupuesto_id, descripcion, monto, firebase_uid)
    VALUES (?, ?, ?, ?)
  `;

  connection.execute(
    query,
    [presupuestoId, descripcion, monto, firebase_uid],
    (err, results) => {
      if (err) {
        console.error('Error al añadir el gasto:', err);
        return res.status(500).send('Error en el servidor');
      }

      res.status(201).json({
        message: 'Gasto añadido correctamente',
        id: results.insertId,
      });
    }
  );
});


// ===============================
// OBTENER GASTOS POR PRESUPUESTO Y UID
// ===============================
router.get('/:id/gastos', (req, res) => {
  const presupuestoId = req.params.id;
  const { firebase_uid } = req.query;

  if (!firebase_uid) {
    return res.status(400).json({
      error: 'firebase_uid es requerido',
    });
  }

  const query = `
    SELECT *
    FROM gastos
    WHERE presupuesto_id = ?
      AND firebase_uid = ?
    ORDER BY id DESC
  `;

  connection.execute(
    query,
    [presupuestoId, firebase_uid],
    (err, results) => {
      if (err) {
        console.error('Error al obtener los gastos:', err);
        return res.status(500).send('Error en el servidor');
      }

      res.json(results);
    }
  );
});

module.exports = router;
