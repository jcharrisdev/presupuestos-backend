-- =============================================================================
-- SCHEMA: Salarying — App de finanzas personales y de negocio
-- Base de datos: MySQL (Clever Cloud)
-- =============================================================================
-- DESCRIPCIÓN GENERAL DEL MODELO DE DATOS:
--
-- El sistema está centrado en el concepto de PRESUPUESTO. Cada usuario (identificado
-- por firebase_uid) puede tener múltiples presupuestos. Cada presupuesto opera en
-- períodos de tiempo (quincenales o mensuales). Dentro de cada período, el usuario
-- registra GASTOS (plantillas) que generan MOVIMIENTOS (transacciones reales).
--
-- Módulo de cobros: presupuestos_produccion → ventas → cobros_clientes
-- Módulo de calendario: calendario_eventos (pagos y cobros a fecha fija)
-- =============================================================================


-- -----------------------------------------------------------------------------
-- TABLA: presupuestos
-- Representa un presupuesto personal. Es el contenedor principal del sistema.
-- Un usuario puede tener N presupuestos (ej: "Casa", "Trabajo", "Ahorros").
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS presupuestos (
  id                 INT PRIMARY KEY AUTO_INCREMENT,
  nombre             VARCHAR(255) NOT NULL,          -- Nombre descriptivo del presupuesto
  monto_total        DECIMAL(10,2) NOT NULL,          -- Monto límite asignado por período
  firebase_uid       VARCHAR(255) NOT NULL,           -- ID único del usuario (Firebase Auth / email temporal)
  tipo_periodo       ENUM('quincenal','mensual') NOT NULL DEFAULT 'quincenal', -- Frecuencia del ciclo de gastos
  dia_inicio_periodo INT NOT NULL DEFAULT 1,          -- Día del mes donde inicia cada período (1-31)
  created_at         TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

  INDEX idx_firebase_uid (firebase_uid)              -- Índice para búsquedas rápidas por usuario
);


-- -----------------------------------------------------------------------------
-- TABLA: periodos
-- Cada vez que comienza un nuevo ciclo de un presupuesto, se crea un período.
-- El sistema genera períodos automáticamente al llamar getPeriodoActivo().
-- Un período puede estar 'activo' (el actual) o 'cerrado' (historial).
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS periodos (
  id                INT PRIMARY KEY AUTO_INCREMENT,
  presupuesto_id    INT NOT NULL,                    -- Presupuesto al que pertenece
  firebase_uid      VARCHAR(255) NOT NULL,           -- Dueño del presupuesto
  numero_periodo    INT NOT NULL,                    -- Contador secuencial (1, 2, 3...)
  tipo_periodo      ENUM('quincenal','mensual') NOT NULL,
  fecha_inicio      DATE NOT NULL,                   -- Primer día del período
  fecha_fin         DATE NOT NULL,                   -- Último día del período
  estado            ENUM('activo','cerrado') NOT NULL DEFAULT 'activo',
  closed_at         TIMESTAMP NULL,                  -- Cuándo se cerró (solo si estado='cerrado')
  created_at        TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

  FOREIGN KEY (presupuesto_id) REFERENCES presupuestos(id) ON DELETE CASCADE,
  INDEX idx_firebase_uid (firebase_uid),
  INDEX idx_presupuesto_estado (presupuesto_id, estado)
);


-- -----------------------------------------------------------------------------
-- TABLA: gastos
-- Son las PLANTILLAS de gasto del usuario. Representan "tipos de gasto" que
-- se repiten en cada período. No son transacciones reales — eso son los movimientos.
--
-- Tipos de gasto:
--   'fijo'          → se cobra cada período (ej: alquiler)
--   'no fijo'       → el usuario elige cuándo agregarlo (ej: supermercado)
--   'fijo_x_periodo'→ se cobra por N períodos y luego para (ej: cuota de carro)
--   'ahorro'        → meta de ahorro distribuida en períodos
--
-- Campos de calendario (tipo_fecha, dia_pago, etc.):
--   Permiten agendar el gasto en el calendario con fecha fija y recordatorio.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS gastos (
  id                   INT PRIMARY KEY AUTO_INCREMENT,
  presupuesto_id       INT NOT NULL,
  descripcion          VARCHAR(255) NOT NULL,         -- Nombre del gasto (ej: "Alquiler")
  monto                DECIMAL(10,2) NOT NULL,        -- Monto por período (o cuota si es ahorro)
  tipo                 ENUM('fijo','no fijo','fijo_x_periodo','ahorro') NOT NULL,
  fecha                DATE NOT NULL,                 -- Fecha de creación del gasto
  pagado               TINYINT(1) NOT NULL DEFAULT 0, -- Estado legacy (ahora se usa movimientos.pagado)
  firebase_uid         VARCHAR(255) NOT NULL,
  numero_quincena      INT NULL,                      -- Períodos restantes para fijo_x_periodo y ahorro con límite
  periodos_restantes   INT NULL,                      -- Alias alternativo (sin uso activo)

  -- Campos para integración con el Calendario
  tipo_fecha           ENUM('flexible','fija') NOT NULL DEFAULT 'flexible', -- ¿Tiene fecha fija de pago?
  dia_pago             TINYINT NULL,                  -- Día del mes en que vence (1-31)
  frecuencia_pago      ENUM('unico','quincenal','mensual','anual') NULL, -- Frecuencia de recurrencia
  fecha_pago_exacta    DATE NULL,                     -- Solo si frecuencia_pago = 'unico'
  genera_notificacion  TINYINT(1) NOT NULL DEFAULT 0, -- Si TRUE, crea recordatorio en calendario
  dias_anticipacion    TINYINT NOT NULL DEFAULT 3,    -- Días antes del vencimiento para notificar

  created_at           TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

  FOREIGN KEY (presupuesto_id) REFERENCES presupuestos(id) ON DELETE CASCADE,
  INDEX idx_firebase_uid (firebase_uid),
  INDEX idx_presupuesto_tipo (presupuesto_id, tipo)
);


-- -----------------------------------------------------------------------------
-- TABLA: movimientos
-- Son las TRANSACCIONES REALES dentro de un período. Se generan automáticamente
-- a partir de los gastos 'fijo' y 'ahorro' al inicio de cada período, o manualmente
-- cuando el usuario selecciona gastos 'no fijo' desde la pantalla de detalle.
--
-- Diferencia clave con gastos:
--   - gasto  = plantilla de qué se gasta (no tiene fecha concreta)
--   - movimiento = instancia real en un período específico (con estado de pago)
--
-- monto_pagado_real: permite registrar cuánto se pagó realmente vs lo presupuestado.
-- Esto habilita el análisis de diferencias (ej: presupuestaste $500, pagaste $520).
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS movimientos (
  id                INT PRIMARY KEY AUTO_INCREMENT,
  presupuesto_id    INT NOT NULL,
  periodo_id        INT NOT NULL,                    -- Período al que pertenece esta transacción
  gasto_id          INT NULL,                        -- Gasto origen (puede ser NULL si fue manual)
  descripcion       VARCHAR(255) NOT NULL,
  monto             DECIMAL(10,2) NOT NULL,          -- Monto presupuestado
  tipo              ENUM('fijo','no fijo','fijo_x_periodo','ahorro') NOT NULL,
  pagado            TINYINT(1) NOT NULL DEFAULT 0,
  monto_pagado_real DECIMAL(10,2) NULL,              -- Cuánto se pagó realmente (puede diferir del presupuesto)
  pagado_por_uid    VARCHAR(255) NULL,               -- Quién marcó el pago (prep para presupuesto compartido)
  fecha_pagado      TIMESTAMP NULL,                  -- Timestamp exacto del pago
  firebase_uid      VARCHAR(255) NOT NULL,
  created_at        TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

  FOREIGN KEY (presupuesto_id) REFERENCES presupuestos(id) ON DELETE CASCADE,
  FOREIGN KEY (periodo_id) REFERENCES periodos(id) ON DELETE CASCADE,
  FOREIGN KEY (gasto_id) REFERENCES gastos(id) ON DELETE SET NULL,
  INDEX idx_firebase_uid (firebase_uid),
  INDEX idx_periodo_firebase (periodo_id, firebase_uid)
);


-- -----------------------------------------------------------------------------
-- TABLA: calendario_eventos
-- Agenda centralizada de pagos y cobros con fecha fija.
-- Se generan automáticamente cuando:
--   1. Se crea un gasto con tipo_fecha='fija' → eventos de tipo 'pago'
--   2. Se agrega un cliente en una venta con condicion_pago='plazo' → tipo 'cobro'
--
-- Diseñado para soportar cobros en el futuro (tipo ENUM incluye 'cobro').
-- google_event_id: reservado para sincronización futura con Google Calendar.
-- user_id se llama firebase_uid para mantener consistencia con el resto del sistema.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS calendario_eventos (
  id                  INT PRIMARY KEY AUTO_INCREMENT,
  firebase_uid        VARCHAR(255) NOT NULL,         -- Dueño del evento
  gasto_id            INT NULL,                      -- Gasto que generó este evento (si aplica)
  titulo              VARCHAR(255) NOT NULL,         -- Descripción visible en el calendario
  tipo                ENUM('pago','cobro') NOT NULL DEFAULT 'pago', -- Extensible: 'cobro' ya preparado
  fecha_evento        DATE NOT NULL,                 -- Fecha del pago o cobro
  monto_esperado      DECIMAL(10,2) NULL,            -- Monto referencial
  estado              ENUM('pendiente','pagado','vencido') NOT NULL DEFAULT 'pendiente',
  notificacion_activa TINYINT(1) NOT NULL DEFAULT 0, -- Si TRUE, se programó notificación local
  dias_anticipacion   TINYINT NOT NULL DEFAULT 3,    -- Días antes del evento para notificar
  notificacion_enviada TINYINT(1) NOT NULL DEFAULT 0, -- Evita enviar la misma notificación dos veces
  google_event_id     VARCHAR(255) NULL,             -- Futuro: ID del evento en Google Calendar
  periodo_id          INT NULL,                      -- Período relacionado (si aplica)
  -- FIX: cobro_id faltaba — permite que Flutter acceda al cobro desde el evento del calendario
  -- Necesario para que _marcarPagado() en calendario.dart pueda llamar PUT /cobros/:id/cobrar
  cobro_id            INT NULL,                      -- cobros_clientes.id que generó este evento
  created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  FOREIGN KEY (gasto_id) REFERENCES gastos(id) ON DELETE SET NULL,
  INDEX idx_firebase_uid (firebase_uid),
  INDEX idx_fecha_evento (fecha_evento),
  INDEX idx_estado (estado),
  INDEX idx_uid_mes (firebase_uid, fecha_evento)     -- Consultas por mes/usuario (pantalla calendario)
);


-- =============================================================================
-- MÓDULO DE COBROS
-- Permite gestionar insumos de producción, ventas y cobros a clientes.
-- Flujo: presupuesto_produccion → venta → cobros_clientes → calendario_eventos
-- =============================================================================

-- -----------------------------------------------------------------------------
-- TABLA: presupuestos_produccion
-- Representa el costo de los insumos para producir algo (ej: ingredientes de
-- cheesecakes, materiales de costura). Es el "costo base" de la operación.
-- Se puede vincular a una o más ventas.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS presupuestos_produccion (
  id           INT PRIMARY KEY AUTO_INCREMENT,
  firebase_uid VARCHAR(255) NOT NULL,
  nombre       VARCHAR(255) NOT NULL,   -- Ej: "Producción mayo - Cheesecakes"
  descripcion  TEXT NULL,               -- Descripción opcional
  created_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

  INDEX idx_uid (firebase_uid)
);


-- -----------------------------------------------------------------------------
-- TABLA: items_produccion
-- Cada ítem es un insumo del presupuesto de producción.
-- El costo total = SUM(cantidad × precio_unitario) de todos los ítems.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS items_produccion (
  id                        INT PRIMARY KEY AUTO_INCREMENT,
  presupuesto_produccion_id INT NOT NULL,
  firebase_uid              VARCHAR(255) NOT NULL,
  nombre                    VARCHAR(255) NOT NULL,        -- Ej: "Harina", "Queso crema"
  cantidad                  DECIMAL(10,3) NOT NULL DEFAULT 1, -- Permite decimales (ej: 0.5 kg)
  precio_unitario           DECIMAL(10,2) NOT NULL,       -- Precio por unidad
  created_at                TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

  FOREIGN KEY (presupuesto_produccion_id) REFERENCES presupuestos_produccion(id) ON DELETE CASCADE,
  INDEX idx_presupuesto (presupuesto_produccion_id)
);


-- -----------------------------------------------------------------------------
-- TABLA: ventas
-- Representa una venta o lote de ventas. Puede estar vinculada a uno o más
-- presupuestos de producción (vía venta_presupuestos) para calcular rentabilidad.
-- La ganancia = total_cobrado − SUM(total_invertido de todos los presupuestos).
-- presupuesto_produccion_id se conserva como campo LEGACY para compatibilidad.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS ventas (
  id                        INT PRIMARY KEY AUTO_INCREMENT,
  firebase_uid              VARCHAR(255) NOT NULL,
  nombre                    VARCHAR(255) NOT NULL,        -- Ej: "Venta mayo semana 1"
  presupuesto_produccion_id INT NULL,                     -- LEGACY: primer presupuesto vinculado
  inversion                 DECIMAL(10,2) NULL DEFAULT NULL, -- (Bug 2) Inversión manual del usuario
  estado                    ENUM('activa','cerrada') NOT NULL DEFAULT 'activa',
  created_at                TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

  FOREIGN KEY (presupuesto_produccion_id) REFERENCES presupuestos_produccion(id) ON DELETE SET NULL,
  INDEX idx_uid (firebase_uid)
);


-- -----------------------------------------------------------------------------
-- TABLA: venta_presupuestos  (Fase 2 — Multi-presupuesto)
-- Junction table: una venta puede tener N presupuestos de producción vinculados.
-- El total_invertido de la venta = SUM de los costos de todos los presupuestos aquí.
--
-- Migración inicial (ejecutar UNA VEZ en Clever Cloud):
--   INSERT IGNORE INTO venta_presupuestos (venta_id, presupuesto_produccion_id)
--   SELECT id, presupuesto_produccion_id FROM ventas
--   WHERE presupuesto_produccion_id IS NOT NULL;
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS venta_presupuestos (
  id                        INT PRIMARY KEY AUTO_INCREMENT,
  venta_id                  INT NOT NULL,
  presupuesto_produccion_id INT NOT NULL,
  created_at                TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

  FOREIGN KEY (venta_id) REFERENCES ventas(id) ON DELETE CASCADE,
  FOREIGN KEY (presupuesto_produccion_id) REFERENCES presupuestos_produccion(id) ON DELETE CASCADE,
  UNIQUE KEY uk_venta_presupuesto (venta_id, presupuesto_produccion_id),
  INDEX idx_venta (venta_id)
);


-- -----------------------------------------------------------------------------
-- TABLA: cobros_clientes
-- Cada fila es un cliente dentro de una venta con su monto a cobrar.
-- Si condicion_pago = 'plazo', se genera automáticamente un evento en
-- calendario_eventos para recordar la fecha de cobro.
-- Al marcar como 'cobrado', el evento del calendario también se actualiza.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS cobros_clientes (
  id                   INT PRIMARY KEY AUTO_INCREMENT,
  venta_id             INT NOT NULL,
  firebase_uid         VARCHAR(255) NOT NULL,
  nombre_cliente       VARCHAR(255) NOT NULL,
  monto                DECIMAL(10,2) NOT NULL,            -- Monto acordado con el cliente
  condicion_pago       ENUM('contra_entrega','plazo') NOT NULL DEFAULT 'contra_entrega',
  dias_plazo           INT NULL,                          -- Días para cobrar (solo si condicion='plazo')
  fecha_cobro          DATE NULL,                         -- Fecha calculada: hoy + dias_plazo
  estado               ENUM('pendiente','cobrado') NOT NULL DEFAULT 'pendiente',
  monto_cobrado        DECIMAL(10,2) NULL,                -- Lo que realmente se cobró (puede diferir)
  fecha_cobrado        TIMESTAMP NULL,                    -- Cuándo se registró el cobro
  calendario_evento_id INT NULL,                          -- Evento generado en calendario (si aplica)
  created_at           TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

  FOREIGN KEY (venta_id) REFERENCES ventas(id) ON DELETE CASCADE,
  INDEX idx_firebase_uid (firebase_uid),
  INDEX idx_venta (venta_id)
);


-- =============================================================================
-- MÓDULO DE CATÁLOGO DE PRODUCTOS (Fase 1)
-- Permite gestionar un catálogo de lo que se vende, con variantes por
-- sabor, tamaño, presentación o unidad. Alimenta el detalle de pedidos
-- de clientes para calcular totales automáticamente.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- TABLA: productos
-- Representa lo que se vende (cheesecake, tornillo, camisa, servicio).
-- Un producto puede tener N variantes vendibles.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS productos (
  id           INT PRIMARY KEY AUTO_INCREMENT,
  firebase_uid VARCHAR(255) NOT NULL,
  nombre       VARCHAR(255) NOT NULL,       -- Ej: "Cheesecake", "Tornillo"
  descripcion  TEXT NULL,
  activo       TINYINT(1) NOT NULL DEFAULT 1,
  created_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_uid (firebase_uid)
);

-- -----------------------------------------------------------------------------
-- TABLA: variantes_producto
-- Cada variante es una versión vendible de un producto con precio propio.
-- Ejemplos: "Cheesecake fresa regular $3.75", "Cheesecake fresa grande $5.50"
-- Una variante puede estar inactiva sin eliminarla (conserva el historial).
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS variantes_producto (
  id          INT PRIMARY KEY AUTO_INCREMENT,
  producto_id INT NOT NULL,
  nombre      VARCHAR(255) NOT NULL,                    -- Ej: "Fresa"
  tamano      VARCHAR(100) NULL DEFAULT NULL,            -- Ej: "pequeño", "mediano", "grande" (Mejora 1)
  precio      DECIMAL(10,2) NOT NULL,                   -- Precio de venta unitario
  unidad      VARCHAR(50)   NOT NULL DEFAULT 'unidad',  -- Ej: "kg", "docena", "unidad"
  activo      TINYINT(1)    NOT NULL DEFAULT 1,
  created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (producto_id) REFERENCES productos(id) ON DELETE CASCADE,
  INDEX idx_producto (producto_id)
);

-- -----------------------------------------------------------------------------
-- TABLA: pedido_items
-- Detalle de los productos que pidió un cliente dentro de una venta.
-- Reemplaza el campo `monto` manual de cobros_clientes cuando el cliente
-- pide productos del catálogo.
--
-- Compatibilidad: los cobros creados antes de esta tabla siguen usando
-- cobros_clientes.monto (monto_manual=1). Solo los nuevos cobros con
-- productos usan esta tabla para calcular el total automáticamente.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS pedido_items (
  id               INT PRIMARY KEY AUTO_INCREMENT,
  cobro_cliente_id INT NOT NULL,
  variante_id      INT NULL,               -- NULL = ítem libre (sin catálogo)
  descripcion      VARCHAR(255) NOT NULL,  -- Nombre del producto/variante en el momento del pedido
  cantidad         DECIMAL(10,3) NOT NULL DEFAULT 1,
  precio_unitario  DECIMAL(10,2) NOT NULL,
  subtotal         DECIMAL(10,2) NOT NULL, -- calculado: cantidad × precio_unitario
  created_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (cobro_cliente_id) REFERENCES cobros_clientes(id) ON DELETE CASCADE,
  FOREIGN KEY (variante_id) REFERENCES variantes_producto(id) ON DELETE SET NULL,
  INDEX idx_cobro (cobro_cliente_id)
);


-- =============================================================================
-- MÓDULO DE RECETAS (Fase 4)
-- Define qué insumos se necesitan para producir una variante del catálogo.
-- Permite calcular automáticamente cuánto comprar de cada insumo dado un volumen
-- de ventas: cantidad_necesaria = cantidad_base * total_vendido / rendimiento
-- =============================================================================

-- -----------------------------------------------------------------------------
-- TABLA: recetas
-- Cada variante puede tener UNA receta (relación 1:1 opcional).
-- rendimiento = cuántas unidades de la variante produce una tanda de la receta.
-- Ej: rendimiento=12 → una tanda produce 12 cheesecakes.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS recetas (
  id          INT PRIMARY KEY AUTO_INCREMENT,
  variante_id INT NOT NULL UNIQUE,        -- Una variante tiene como máximo una receta
  rendimiento DECIMAL(10,3) NOT NULL DEFAULT 1, -- Unidades producidas por tanda
  unidad      VARCHAR(50) NOT NULL DEFAULT 'tanda', -- Nombre de la unidad de producción
  notas       TEXT NULL,
  created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (variante_id) REFERENCES variantes_producto(id) ON DELETE CASCADE,
  INDEX idx_variante (variante_id)
);

-- -----------------------------------------------------------------------------
-- TABLA: receta_insumos
-- Cada fila es un insumo (ingrediente / material) de una receta.
-- cantidad = cuánto se necesita de este insumo por UNA TANDA de la receta.
-- Ej: 500 g de queso crema por tanda de 12 cheesecakes.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS receta_insumos (
  id              INT PRIMARY KEY AUTO_INCREMENT,
  receta_id       INT NOT NULL,
  nombre          VARCHAR(255) NOT NULL,         -- Ej: "Queso crema", "Harina"
  cantidad        DECIMAL(10,3) NOT NULL,         -- Cantidad por tanda
  unidad          VARCHAR(50) NOT NULL DEFAULT 'g', -- Ej: "g", "kg", "ml", "unidad"
  precio_unitario DECIMAL(10,2) NULL DEFAULT NULL, -- (Fase 6) Costo por unidad del insumo
  created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (receta_id) REFERENCES recetas(id) ON DELETE CASCADE,
  INDEX idx_receta (receta_id)
);


-- =============================================================================
-- MIGRACIONES — Ejecutar UNA SOLA VEZ sobre la BD en producción (Clever Cloud)
-- Estas sentencias adaptan tablas existentes sin perder datos.
--
-- [Sesión anterior — Fases 1 y 3]:
-- ALTER TABLE cobros_clientes
--   ADD COLUMN monto_manual TINYINT(1) NOT NULL DEFAULT 1 AFTER monto,
--   ADD COLUMN fecha_pago_especifica DATE NULL AFTER fecha_cobro,
--   MODIFY COLUMN condicion_pago
--     ENUM('contra_entrega','plazo','fecha_especifica') NOT NULL DEFAULT 'contra_entrega';
--
-- Efecto de monto_manual:
--   1 (DEFAULT) → el monto fue ingresado manualmente (todos los registros viejos)
--   0           → el monto se calcula desde pedido_items automáticamente
--
-- [Fase 2 — Multi-presupuesto]:
-- 1. Crear la tabla venta_presupuestos (ver CREATE TABLE arriba).
-- 2. Migrar las relaciones existentes (ventas con presupuesto_produccion_id ya definido):
--
-- INSERT IGNORE INTO venta_presupuestos (venta_id, presupuesto_produccion_id)
-- SELECT id, presupuesto_produccion_id FROM ventas
-- WHERE presupuesto_produccion_id IS NOT NULL;
--
-- [Fase 6 — costo estimado]:
-- ALTER TABLE receta_insumos ADD COLUMN precio_unitario DECIMAL(10,2) NULL DEFAULT NULL AFTER unidad;
-- =============================================================================
