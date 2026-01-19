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
   Nuevo:periodos 
========================= */
async function getPeriodoActivo(presupuesto_id, firebase_uid, tipoPeriodo = 'quincenal') {
  const hoy = new Date().toISOString().split('T')[0];
  
  //1. Verificar si hay un periodo activo
  const [rows] = await connection
    .promise()
    .execute(
      `select *
      from periodos
      where presupuesto_id = ?
      and firebase_uid = ?
      and estado = 'activo'
       LIMIT 1`,
      [presupuesto_id, firebase_uid]
  );
  
  // Si existe un periodo activo, retornarlo
  if (rows.length > 0) {
    const periodo = rows[0];
    
    if (hoy <= periodo.fecha_fin) {
      return periodo;
    }

    // Si el periodo activo ha expirado, marcarlo como 'cerrado'
    await connection
      .promise()
      .execute(
        `update periodos
         set estado = 'cerrado',
         closed_at = NOW()
         where id = ?`,
        [periodo.id]
      );
  }

  //4. Crear un nuevo periodo
  const [[{ ultimo }]] = await connection
    .promise()
    .execute(
      `select COALESCE(MAX(numero_periodo), 0) as ultimo
       from periodos
       where presupuesto_id = ?
       and firebase_uid = ?`,
      [presupuesto_id, firebase_uid]
  );
  
  const numeroPeriodo = ultimo + 1;

  const fechaInicio = hoy;
  const fechaFin = tipoPeriodo === 'mensual'
    ? new Date(new Date(fechaInicio).getFullYear(), new Date(fechaInicio).getMonth() + 1, 0)
    : new Date(new Date(fechaInicio).getTime() + 14 * 24 * 60 * 60 * 1000);
  
  const fechaFinISO = fechaFin.toISOString().split('T')[0];

  const [result] = await connection
    .promise()
    .execute(
      `INSERT INTO periodos (
        presupuesto_id,
        firebase_uid,
        numero_periodo,
        tipo_periodo,
        fecha_inicio,
        fecha_fin,
        estado
      )
      VALUES (?, ?, ?, ?, ?, ?, 'activo')`,
      [   presupuestoId,
        firebaseUid,
        numeroPeriodo,
        tipoPeriodo,
        fechaInicio,
        fechaFinISO]
  );

   return {
    id: result.insertId,
    presupuesto_id: presupuestoId,
    firebase_uid: firebaseUid,
    numero_periodo: numeroPeriodo,
    tipo_periodo: tipoPeriodo,
    fecha_inicio: fechaInicio,
    fecha_fin: fechaFinISO,
    estado: 'activo'
  };
}





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
  const { nombre, monto_total, firebase_uid } = req.body;

  if (!nombre || monto_total == null || !firebase_uid) {
    return res.status(400).json({ error: 'nombre y monto_total son obligatorios' });
  }

  const sql = `
    INSERT INTO presupuestos (nombre, monto_total, firebase_uid)
    VALUES (?, ?, ?)
  `;

  connection.execute(sql, [nombre, monto_total, firebase_uid], (err, result) => {
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
   const { firebase_uid } = req.query;
   if(!firebase_uid) {
      return res.status(400).json({
       error: 'firebase_uid es requerido',  
      })
   }

   const sql =`select * from presupuestos where firebase_uid = ? order by id desc`;
   
  connection.execute(
    sql, [firebase_uid],
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
  const { presupuesto_id, descripcion, monto, tipo, fecha, firebase_uid} = req.body;

  if (!presupuesto_id || !descripcion || monto == null || !tipo || !fecha || !firebase_uid) {
    return res.status(400).json({ error: 'Datos incompletos' });
  }

  const sql = `
    INSERT INTO gastos (presupuesto_id, descripcion, monto, tipo, fecha, pagado, firebase_uid)
    VALUES (?, ?, ?, ?, ?, 0, ?)
  `;

  connection.execute(
    sql,
    [presupuesto_id, descripcion, monto, tipo, fecha, firebase_uid],
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
        pagado: 0,
        firebase_uid
      });
    }
  );
});

// Obtener gastos por presupuesto
app.get('/presupuestos/:id/gastos', (req, res) => {
  const { id } = req.params;
  const { firebase_uid } = req.query;

   if(!firebase_uid){
      return res.status(400).json({error: 'firebase_uid es requerido'});
   }

  const sql = `
    SELECT *
    FROM gastos g
    WHERE g.presupuesto_id = ?
    and g.firebase_uid = ?
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

  connection.execute(sql, [id, firebase_uid], (err, results) => {
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
