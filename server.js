const express = require('express');
const mysql = require('mysql2');
const bodyParser = require('body-parser');
const cors = require('cors');

const app = express();

// Middleware para habilitar CORS
app.use(cors());

// Middleware para manejar JSON
app.use(bodyParser.json());

console.log('DB HOST:', process.env.MYSQLHOST);
console.log('DB USER:', process.env.MYSQLUSER);
console.log('DB NAME:', process.env.MYSQLDATABASE);
console.log('DB PORT:', process.env.MYSQLPORT);


// Crear conexión a MySQL
const connection = mysql.createConnection({
  host: process.env.MYSQLHOST,
  user: process.env.MYSQLUSER,
  password: process.env.MYSQLPASSWORD,
  database: process.env.MYSQLDATABASE,
  port: process.env.MYSQLPORT,
});


// Conectar a la base de datos
connection.connect((err) => {
  if (err) {
    console.error('Error conectando a la base de datos:', err);
    return;
  }
  console.log('Conectado a la base de datos MySQL');
});
app.get('/', (req, res) => {
  res.send('Backend funcionando correctamente');
});

// Ruta POST para crear un presupuesto
app.post('/presupuestos', (req, res) => {
  const { nombre, monto_total } = req.body; // Obtener los datos del cuerpo de la solicitud

  if (!nombre || !monto_total) {
    return res.status(400).send('Faltan datos');
  }

  const query = 'INSERT INTO presupuestos (nombre, monto_total) VALUES (?, ?)';
  connection.execute(query, [nombre, monto_total], (err, results) => {
    if (err) {
      console.error('Error al crear el presupuesto:', err);
      return res.status(500).send('Error al crear el presupuesto');
    }
    res.status(201).send('Presupuesto creado correctamente');
  });
});

// Ruta GET para obtener todos los presupuestos
app.get('/presupuestos', (req, res) => {
  const query = 'SELECT * FROM presupuestos';
  connection.execute(query, (err, results) => {
    if (err) {
      console.error('Error al obtener los presupuestos:', err);
      return res.status(500).send('Error en el servidor');
    }
    res.json(results);
  });
});

// Ruta PUT para reanudar gastos fijos
app.put('/presupuestos/:id/gastos/reanudar-fijos', (req, res) => {
  const { id } = req.params;

  const query = 'UPDATE gastos SET pagado = 0 WHERE presupuesto_id = ? AND tipo = "fijo"';
  connection.execute(query, [id], (err, results) => {
    if (err) {
      console.error('Error al reanudar los gastos fijos:', err);
      return res.status(500).send('Error al reanudar los gastos fijos');
    }

    res.status(200).send('Gastos fijos reanudados correctamente');
  });
});

// Ruta POST para agregar un gasto a un presupuesto
app.post('/gastos', (req, res) => {
  const { presupuesto_id, descripcion, monto, tipo, fecha } = req.body;

  if (!presupuesto_id || !descripcion || !monto || !tipo || !fecha) {
    return res.status(400).send('Faltan datos');
  }

  const query = 'INSERT INTO gastos (presupuesto_id, descripcion, monto, tipo, fecha) VALUES (?, ?, ?, ?, ?)';
  connection.execute(query, [presupuesto_id, descripcion, monto, tipo, fecha], (err, results) => {
    if (err) {
      console.error('Error al agregar el gasto:', err);
      return res.status(500).send('Error al agregar el gasto');
    }
    res.status(201).send('Gasto agregado correctamente');
  });
});

// Ruta GET para obtener los gastos de un presupuesto específico
app.get('/presupuestos/:id/gastos', (req, res) => {
  const { id } = req.params;

  const query = `
    SELECT *
    FROM gastos g
    WHERE g.presupuesto_id = ?
    AND (
      g.tipo != 'ahorro'
      OR (
        g.tipo = 'ahorro'
        AND g.numero_quincena = (
          SELECT MIN(g2.numero_quincena)
          FROM gastos g2
          WHERE g2.ahorro_id = g.ahorro_id
            AND g2.pagado = 0
        )
      )
    )
  `;

  connection.execute(query, [id], (err, results) => {
    if (err) {
      console.error(err);
      return res.status(500).json({ error: 'Error al obtener gastos' });
    }
    res.json(results);
  });
});


// Ruta PUT para actualizar el estado de un gasto (pagado/no pagado)
app.put('/gastos/:id', (req, res) => {
  const { id } = req.params;
  const { pagado } = req.body;

  const query = 'UPDATE gastos SET pagado = ? WHERE id = ?';
  connection.execute(query, [pagado, id], (err, results) => {
    if (err) {
      console.error('Error al actualizar el gasto:', err);
      return res.status(500).send('Error al actualizar el gasto');
    }
    res.status(200).send('Estado del gasto actualizado');
  });
});

// Ruta DELETE para eliminar un gasto
app.delete('/gastos/:id', (req, res) => {
  const { id } = req.params;
  const query = 'DELETE FROM gastos WHERE id = ?';

  connection.execute(query, [id], (err, results) => {
    if (err) {
      console.error('Error al eliminar el gasto:', err);
      return res.status(500).send('Error al eliminar el gasto');
    }
    res.status(200).send('Gasto eliminado correctamente');
  });
});

// Iniciar el servidor
const PORT = 3002;
app.listen(PORT, () => {
  console.log(`Servidor corriendo en http://localhost:${PORT}`);
});
