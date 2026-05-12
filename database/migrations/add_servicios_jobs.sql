-- Módulo Ofrecimiento de Servicios
-- Ejecutar manualmente en Clever Cloud console
-- Orden: jobs → job_team_members → customer_payments → team_member_payments → operational_expenses → job_activity_logs

CREATE TABLE IF NOT EXISTS jobs (
  id INT AUTO_INCREMENT PRIMARY KEY,
  firebase_uid VARCHAR(255) NOT NULL,
  nombre VARCHAR(255) NOT NULL,
  descripcion TEXT,
  nombre_cliente VARCHAR(255),
  telefono_cliente VARCHAR(50),
  monto_total DECIMAL(12,2) NOT NULL DEFAULT 0,
  estado ENUM('draft','pending','in_progress','completed','cancelled') DEFAULT 'draft',
  payment_status ENUM('pending','partially_paid','paid') DEFAULT 'pending',
  fecha_inicio DATE,
  fecha_fin DATE,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS job_team_members (
  id INT AUTO_INCREMENT PRIMARY KEY,
  job_id INT NOT NULL,
  firebase_uid VARCHAR(255) NOT NULL,
  nombre VARCHAR(255) NOT NULL,
  tipo_compensacion ENUM('fijo','porcentual','por_horas','por_tarea','ganancias') NOT NULL,
  monto_acordado DECIMAL(12,2) DEFAULT 0,
  porcentaje DECIMAL(5,2) DEFAULT 0,
  horas_trabajadas DECIMAL(8,2) DEFAULT 0,
  tarifa_hora DECIMAL(10,2) DEFAULT 0,
  monto_calculado DECIMAL(12,2) DEFAULT 0,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (job_id) REFERENCES jobs(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS customer_payments (
  id INT AUTO_INCREMENT PRIMARY KEY,
  job_id INT NOT NULL,
  firebase_uid VARCHAR(255) NOT NULL,
  monto DECIMAL(12,2) NOT NULL,
  tipo ENUM('anticipo','pago_parcial','pago_final') DEFAULT 'pago_parcial',
  nota TEXT,
  fecha_pago TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (job_id) REFERENCES jobs(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS team_member_payments (
  id INT AUTO_INCREMENT PRIMARY KEY,
  job_id INT NOT NULL,
  team_member_id INT NOT NULL,
  firebase_uid VARCHAR(255) NOT NULL,
  monto DECIMAL(12,2) NOT NULL,
  nota TEXT,
  fecha_pago TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (job_id) REFERENCES jobs(id) ON DELETE CASCADE,
  FOREIGN KEY (team_member_id) REFERENCES job_team_members(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS operational_expenses (
  id INT AUTO_INCREMENT PRIMARY KEY,
  job_id INT NOT NULL,
  firebase_uid VARCHAR(255) NOT NULL,
  descripcion VARCHAR(255) NOT NULL,
  monto DECIMAL(12,2) NOT NULL,
  categoria VARCHAR(100),
  fecha_gasto TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (job_id) REFERENCES jobs(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS job_activity_logs (
  id INT AUTO_INCREMENT PRIMARY KEY,
  job_id INT NOT NULL,
  firebase_uid VARCHAR(255) NOT NULL,
  accion VARCHAR(255) NOT NULL,
  detalle TEXT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (job_id) REFERENCES jobs(id) ON DELETE CASCADE
);
