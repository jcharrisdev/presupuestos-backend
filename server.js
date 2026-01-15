const express = require('express');
const mysql = require('mysql2');
const cors = require('cors');

const app = express();

/* =========================
   MIDDLEWARE
========================= */
app.use(cors());
app.use(express.json());

/* =========================
   VARIABLES DE ENTORNO (LOG CONTROLADO)
========================= */
console.log('DB HOST:', process.env.MYSQLHOST);
console.log('DB USER:', process.env.MYSQLUSER);
console.log('DB NAME:', process.env.MYSQLDATABASE);
console.log('DB PORT:', process.env.MYSQLPORT);

/* =========================
   CONEXIÓN MYSQL
========================= */
const connection = mysql.createConnection({
  host: process.env.MYSQLHOST,
  user: process.env.MYSQLUSER,
  password: process.env.MYSQLPASSWORD,
  database: process.env.MYSQLDATABASE,
  port: Number(process.env.MYSQLPORT),
});

connection.connect((err) => {
  if (err) {
    console.error('❌ Error conectando a MySQL:', err);
    process.exit(1);
  }
  console.log('✅ Conectado a MySQL');
});

/* =========================
   RUTA HEALTHCHECK
========================= */
app.get('/', (req, res) => {
  res.json({ status: 'Backend funcionando correctamente' });
});

/* =========================
   PRESUPUESTOS
========================= */

// Crear presupuesto
app.post('/presupuestos', (req, res) => {
  const { nombre, monto_total } = req.body;

  if (!nombre || monto_total == null) {
    return res.status(400).json({ error: 'nombre y monto_total son obligatorios' });
  }

  const sql = `
    INSERT INTO presupuestos (nombre, monto_total)
    VALUES (?, ?)
  `;

  connection.execute(sql, [nombre, monto_total], (err, result) => {
    if (err) {
      console.error(err);
      return res.status(500).json({ error: 'Error al crear presupuesto' });
    }

    res.status(201).json({
      id: result.insertId,
      nombre,
      monto_total
    });
  });
});

// Obtener presupuestos
app.get('/presupuestos', (req, res) => {
  connection.execute(
    'SELECT * FROM presupuestos',
    (err, results) => {
      if (err) {
        console.error(err);
        return res.status(500).json({ error: 'Error al obtener presupuestos' });
      }
      res.json(results);
    }
  );
});

/* =========================
   GASTOS
========================= */

// Agregar gasto
app.post('/gastos', (req, res) => {
  const { presupuesto_id, descripcion, monto, tipo, fecha } = req.body;

  if (!presupuesto_id || !descripcion || monto == null || !tipo || !fecha) {
    return res.status(400).json({ error: 'Datos incompletos' });
  }

  const sql = `
    INSERT INTO gastos (presupuesto_id, descripcion, monto, tipo, fecha, pagado)
    VALUES (?, ?, ?, ?, ?, 0)
  `;

  connection.execute(
    sql,
    [presupuesto_id, descripcion, monto, tipo, fecha],
    (err, result) => {
      if (err) {
        console.error(err);
        return res.status(500).json({ error: 'Error al agregar gasto' });
      }

      res.status(201).json({
        id: result.insertId,
        presupuesto_id,
        descripcion,
        monto,
        tipo,
        fecha,
        pagado: 0
      });
    }
  );
});

// Obtener gastos por presupuesto
app.get('/presupuestos/:id/gastos', (req, res) => {
  const { id } = req.params;

  const sql = `
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

  connection.execute(sql, [id], (err, results) => {
    if (err) {
      console.error(err);
      return res.status(500).json({ error: 'Error al obtener gastos' });
    }
    res.json(results);
  });
});

// Actualizar estado de gasto
app.put('/gastos/:id', (req, res) => {
  const { id } = req.params;
  const { pagado } = req.body;

  if (pagado === undefined) {
    return res.status(400).json({ error: 'Campo pagado es obligatorio' });
  }

  const pagadoValue = pagado === true || pagado === 1 ? 1 : 0;

  const sql = `
    UPDATE gastos
    SET pagado = ?
    WHERE id = ?
  `;

  connection.execute(sql, [pagadoValue, id], (err, result) => {
    if (err) {
      console.error(err);
      return res.status(500).json({ error: 'Error al actualizar gasto' });
    }

    if (result.affectedRows === 0) {
      return res.status(404).json({ error: 'Gasto no encontrado' });
    }

    res.json({
      message: 'Estado actualizado',
      id,
      pagado: pagadoValue
    });
  });
});

// Reanudar gastos fijos
app.put('/presupuestos/:id/gastos/reanudar-fijos', (req, res) => {
  const { id } = req.params;

  const sql = `
    UPDATE gastos
    SET pagado = 0
    WHERE presupuesto_id = ?
      AND tipo = 'fijo'
  `;

  connection.execute(sql, [id], (err, result) => {
    if (err) {
      console.error(err);
      return res.status(500).json({ error: 'Error al reanudar gastos fijos' });
    }

    res.json({
      message: 'Gastos fijos reanudados',
      afectados: result.affectedRows
    });
  });
});

// Eliminar gasto
app.delete('/gastos/:id', (req, res) => {
  const { id } = req.params;

  connection.execute(
    'DELETE FROM gastos WHERE id = ?',
    [id],
    (err, result) => {
      if (err) {
        console.error(err);
        return res.status(500).json({ error: 'Error al eliminar gasto' });
      }

      if (result.affectedRows === 0) {
        return res.status(404).json({ error: 'Gasto no encontrado' });
      }

      res.json({ message: 'Gasto eliminado' });
    }
  );
});

/* =========================
   SERVER
========================= */
const PORT = process.env.PORT || 3002;

app.listen(PORT, () => {
  console.log(`🚀 Servidor activo en puerto ${PORT}`);
});
