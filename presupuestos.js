const express = require('express');
const router = express.Router();  // Crear un router de Express
const mysql = require('mysql2');

// Crear conexión a MySQL
const connection = mysql.createConnection({
  host: 'localhost',
  user: 'root',
  password: '',
  database: 'presupuestos',
  port: 3307  // Asegúrate de poner tu puerto correcto
});

// Ruta para crear un presupuesto
router.post('/', (req, res) => {
  const { nombre, monto_total } = req.body;

  const query = 'INSERT INTO presupuestos (nombre, monto_total) VALUES (?, ?)';
  connection.execute(query, [nombre, monto_total], (err, results) => {
    if (err) {
      console.error('Error al crear el presupuesto:', err);
      return res.status(500).send('Error en el servidor');
    }
    res.status(201).send('Presupuesto creado correctamente');
  });
});

// Ruta para obtener todos los presupuestos
router.get('/', (req, res) => {
  const query = 'SELECT * FROM presupuestos';
  connection.execute(query, (err, results) => {
    if (err) {
      console.error('Error al obtener los presupuestos:', err);
      return res.status(500).send('Error en el servidor');
    }
    res.json(results);
  });
});

// Ruta para añadir un gasto a un presupuesto
router.post('/:id/gastos', (req, res) => {
  const { descripcion, monto } = req.body;
  const presupuestoId = req.params.id;

  const query = 'INSERT INTO gastos (presupuesto_id, descripcion, monto) VALUES (?, ?, ?)';
  connection.execute(query, [presupuestoId, descripcion, monto], (err, results) => {
    if (err) {
      console.error('Error al añadir el gasto:', err);
      return res.status(500).send('Error en el servidor');
    }
    res.status(201).send('Gasto añadido correctamente');
  });
});

// Ruta para obtener los gastos de un presupuesto
router.get('/:id/gastos', (req, res) => {
  const presupuestoId = req.params.id;

  const query = 'SELECT * FROM gastos WHERE presupuesto_id = ?';
  connection.execute(query, [presupuestoId], (err, results) => {
    if (err) {
      console.error('Error al obtener los gastos:', err);
      return res.status(500).send('Error en el servidor');
    }
    res.json(results);
  });
});

module.exports = router;
