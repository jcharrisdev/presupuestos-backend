-- Módulo: Invoice Scanner QR — Facturas Electrónicas DGI Panama
-- Migración aditiva: no modifica tablas existentes

CREATE TABLE IF NOT EXISTS scanned_invoices (
  id INT AUTO_INCREMENT PRIMARY KEY,
  firebase_uid VARCHAR(255) NOT NULL,
  cufe VARCHAR(500),
  qr_raw TEXT NOT NULL,
  url_fiscal TEXT,
  numero_factura VARCHAR(100),
  merchant_name VARCHAR(255),
  merchant_ruc VARCHAR(50),
  total_amount DECIMAL(12,2),
  tax_amount DECIMAL(12,2),
  subtotal_amount DECIMAL(12,2),
  invoice_date DATE,
  status ENUM('pending','assigned','partially_assigned','unassigned') DEFAULT 'pending',
  dgi_validated TINYINT(1) DEFAULT 0,
  dgi_raw_response TEXT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY unique_user_cufe (firebase_uid, cufe),
  INDEX idx_firebase_uid (firebase_uid),
  INDEX idx_status (status),
  INDEX idx_invoice_date (invoice_date)
);

CREATE TABLE IF NOT EXISTS scanned_invoice_items (
  id INT AUTO_INCREMENT PRIMARY KEY,
  invoice_id INT NOT NULL,
  descripcion VARCHAR(500),
  cantidad DECIMAL(10,3),
  precio_unitario DECIMAL(12,2),
  subtotal DECIMAL(12,2),
  impuesto DECIMAL(12,2),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (invoice_id) REFERENCES scanned_invoices(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS scanned_invoice_assignments (
  id INT AUTO_INCREMENT PRIMARY KEY,
  invoice_id INT NOT NULL,
  firebase_uid VARCHAR(255) NOT NULL,
  assignment_type ENUM(
    'gasto_existente',
    'gasto_nuevo',
    'gustito',
    'presupuesto_compartido',
    'gasto_operativo_servicio',
    'gasto_empresarial',
    'compra_inventario',
    'sin_asignar'
  ) NOT NULL,
  target_id INT,
  amount_assigned DECIMAL(12,2) NOT NULL,
  notes TEXT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (invoice_id) REFERENCES scanned_invoices(id) ON DELETE CASCADE,
  INDEX idx_invoice_id (invoice_id),
  INDEX idx_firebase_uid (firebase_uid)
);

CREATE TABLE IF NOT EXISTS scanned_invoice_item_assignments (
  id INT AUTO_INCREMENT PRIMARY KEY,
  assignment_id INT NOT NULL,
  item_id INT NOT NULL,
  amount_assigned DECIMAL(12,2) NOT NULL,
  FOREIGN KEY (assignment_id) REFERENCES scanned_invoice_assignments(id) ON DELETE CASCADE,
  FOREIGN KEY (item_id) REFERENCES scanned_invoice_items(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS invoice_activity_logs (
  id INT AUTO_INCREMENT PRIMARY KEY,
  invoice_id INT NOT NULL,
  firebase_uid VARCHAR(255) NOT NULL,
  action VARCHAR(100) NOT NULL,
  details JSON,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (invoice_id) REFERENCES scanned_invoices(id) ON DELETE CASCADE
);
