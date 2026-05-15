# Modelo de datos y contratos de API — Salarying

Referencia del schema de BD y los endpoints existentes. Consúltala antes de proponer columnas, tablas o endpoints nuevos.

## Conexión MySQL
- Host Clever Cloud, puerto 3306, database `bvmmbs7zrnufnskqoxwm`.
- **Pool: connectionLimit = 3** (NUNCA superar — límite del plan es 5).

---

## Tablas principales

### Presupuestos y períodos
- `presupuestos` — presupuesto del usuario. `GET /presupuestos` NO devuelve `gastado`.
- `periodos` — períodos de cada presupuesto. `estado` ∈ activo/cerrado. `closed_at` al cerrar.
- `gastos` — gastos planeados del presupuesto.
  - `tipo` ∈ fijo / variable / ahorro / **deuda**
  - `subcategoria` VARCHAR(100) NULL
  - `clasificacion` ENUM('esencial','importante','flexible') NULL
  - `tipo_deuda`, `descuento_directo`, `fecha_fin`, `num_cuotas` (añadidas para el módulo v2)
- `movimientos` — ejecución real de los gastos en un período.
  - `pagado` TINYINT, `monto_pagado_real` DECIMAL — **el gastado real es `SUM(monto_pagado_real) WHERE pagado=1`**
  - `subcategoria` VARCHAR(100) NULL (heredada del gasto si no se especifica)
  - `clasificacion` VARCHAR(20) NULL (propagada desde el gasto)
- `budget_income` — ingreso declarado del presupuesto. **UNIQUE KEY en `presupuesto_id`** (upsert seguro).
  - `calcular_automatico`, `ingreso_bruto_mensual` y campos de descuentos.
  - **El income es INFORMATIVO — nunca modifica `monto_total` del presupuesto.**

### Ahorros
- `ahorros` — metas de ahorro. **Campos: `monto_meta` (NO `monto`), `monto_ahorrado` (NO `total_ahorrado`).**
- `aportaciones_ahorro` — aportaciones a cada meta. Total real de una meta = `monto_ahorrado + SUM(aportaciones)`.

### Deudas (entidad propia, #9)
- `deudas`
  - `id`, `firebase_uid`, `nombre`
  - `tipo` ENUM('tarjeta_credito','prestamo','hipoteca','auto','personal','otro')
  - `monto_total` DECIMAL(10,2) — deuda original
  - `monto_pendiente` DECIMAL(10,2) — saldo actual
  - `tasa_interes` DECIMAL(5,2) NULL — **porcentaje MENSUAL** (no anual)
  - `pago_minimo` DECIMAL(10,2) NULL
  - `fecha_proximo_pago` DATE NULL
  - `notas` TEXT NULL
  - `activa` TINYINT(1) DEFAULT 1 — 0 = saldada/archivada
  - INDEX: `idx_deudas_uid`, `idx_deudas_activa`
  - Abono reduce `monto_pendiente`; si llega a 0 → `activa=0` automáticamente.

### Gustitos (compras espontáneas)
- `gustitos`
  - `id`, `user_id` (= firebase_uid), `budget_id` (FK presupuestos CASCADE)
  - `scanned_invoice_id` INT NULL — preparado para QR futuro
  - `name`, `description`, `merchant`, `amount` DECIMAL(10,2), `category`
  - `emotion_tag` ENUM('antojo','premio','social','impulso','estres','otro') NULL
  - `source` ENUM('manual','scanned_invoice','imported') DEFAULT manual
  - `spent_at` DATE NOT NULL, timestamps
  - `deleted_at` TIMESTAMP NULL — **soft delete**
  - INDEX: `idx_gustitos_user`, `idx_gustitos_budget`

### Calendario
- `calendario_eventos` — eventos con estado; cron los marca `vencido` si pasan de fecha.

### Presupuestos compartidos
- `shared_budgets` — `delete_requested_by` VARCHAR(255) NULL (eliminación con aprobación del co-dueño)
- `shared_budget_members` — miembros con porcentaje e ingreso declarado
- `shared_budget_invitations` — invitaciones por email con token
- `shared_expenses` — gastos del presupuesto compartido
- `shared_expense_splits` — responsabilidad por usuario. `pagado` TINYINT(1) DEFAULT 0
- `shared_settlements` — pagos de liquidación entre usuarios
- `shared_budget_activity_logs` — historial de acciones

### Módulo Servicios (jobs — para pequeños negocios)
- `jobs` — trabajo/proyecto. `estado` ENUM(draft|pending|in_progress|completed|cancelled), `payment_status` ENUM(pending|partially_paid|paid)
- `job_team_members` — colaboradores. FK job_id CASCADE
- `customer_payments` — pagos del cliente. `tipo` ENUM(anticipo|pago_parcial|pago_final)
- `team_member_payments` — pagos a colaboradores
- `operational_expenses` — gastos operativos del trabajo
- `job_activity_logs` — historial

---

## Endpoints REST principales (`backend/server.js`)

### Presupuestos
- `GET /presupuestos?firebase_uid=` — lista (sin `gastado`)
- `GET /presupuestos/:id/detalle?firebase_uid=` — `{ periodo, movimientos[], resumen }`. El detalle trae `gastado` real, fechas y breakdown.
- `GET /presupuestos/:id/historico?firebase_uid=` — últimos 6 períodos
- `POST /presupuestos`, `PUT /presupuestos/:id`
- `POST /gastos` (acepta `clasificacion`, `subcategoria` opcionales), `PUT /gastos/:id`, `DELETE /gastos/:id`
- `GET /presupuestos/:id/gastos`, `GET /presupuestos/:id/gastos-seleccionables`
- `PUT /presupuestos/:id/gastos/reanudar-fijos`
- `POST /presupuestos/:id/movimientos`, `PUT /movimientos/:id/pagar` (body `{ pagado, monto_pagado_real, firebase_uid }`)

### Análisis financiero
- `GET /presupuestos/:id/capacidad?firebase_uid=` — capacidad real (null si no hay income)
- `GET /presupuestos/:id/fondo-seguridad?firebase_uid=` — 3 niveles, cálculo dinámico
- `GET /presupuestos/:id/distribucion-clasificacion?firebase_uid=` — distribución esencial/importante/flexible
- `GET /presupuestos/:id/recomendacion-porcentajes?firebase_uid=` — regla 50/30/20
- `GET /presupuestos/:id/alertas?firebase_uid=` — 5 reglas de alerta preventiva
- `GET /presupuestos/:id/proyeccion?firebase_uid=` — 12 cards (2 queries, respeta pool)
- `GET /presupuestos/:id/gustitos/patrones?firebase_uid=` — categorías recurrentes (≥2 períodos)
- `GET /presupuestos/:id/periodo/:periodoId/resumen-cierre?firebase_uid=`
- `POST /presupuestos/:id/periodo/:periodoId/cerrar` (body `{ firebase_uid }`, 409 si ya cerrado)

### Deudas
- `GET /deudas?firebase_uid=&incluir_saldadas=` — `{ deudas[], total_pendiente, total_pago_minimo }`
- `POST /deudas`, `PUT /deudas/:id` (COALESCE dinámico)
- `PATCH /deudas/:id/abono` (body `{ firebase_uid, monto_abono, fecha_proximo_pago? }`)
- `DELETE /deudas/:id?firebase_uid=` — `activa=0` (archivar)

### Gustitos
- `GET /gustitos?firebase_uid=`, `GET /gustitos/:id?firebase_uid=`
- `POST /gustitos`, `PATCH /gustitos/:id`, `DELETE /gustitos/:id?firebase_uid=`
- `GET /presupuestos/:budgetId/gustitos?firebase_uid=`, `GET /presupuestos/:budgetId/gustitos/summary?firebase_uid=`

### Ahorros
- `GET /ahorros?firebase_uid=`, `DELETE /ahorros/:id?firebase_uid=`
- `POST /ahorros/:id/aportaciones`, `GET /ahorros/:id/aportaciones`, `DELETE /aportaciones/:id`
- `POST /gastos/ahorroMeta`

### Calendario
- `GET /calendario/eventos?firebase_uid=&mes=&anio=`
- `PUT /calendario/eventos/:id/estado`, `DELETE /calendario/eventos/:id?firebase_uid=&solo_este=`

### Ventas / Cobros
- `GET /ventas?firebase_uid=`, `GET /ventas/:id?firebase_uid=`, `POST /ventas`, `PUT /ventas/:id`, `DELETE /ventas/:id`
- `POST /ventas/:id/cobros`, `PUT /cobros/:id/cobrar`, `DELETE /cobros/:id`
- `GET /ventas/:id/lista-compras?firebase_uid=`

### Presupuestos compartidos
- `GET /shared-budgets?firebase_uid=`, `GET /shared-budgets/:id?firebase_uid=`, `POST /shared-budgets`
- `POST /shared-budgets/:id/invitations`, `GET /shared-budget-invitations?firebase_uid=`
- `POST /shared-budget-invitations/:token/accept`, `POST /shared-budget-invitations/:token/reject`
- `POST /shared-budgets/:id/expenses`, `GET /shared-budgets/:id/expenses`, `DELETE /shared-expenses/:id`
- `POST /shared-expenses/:id/confirm-payment` — `UPDATE shared_expense_splits SET pagado=1`
- `POST /shared-budgets/:id/settlements`, `GET /shared-budgets/:id/settlements`
- `POST /shared-budgets/:id/request-delete`

### Jobs (servicios)
- `GET /jobs?firebase_uid=`, `GET /jobs/:id?firebase_uid=`, `POST /jobs`, `PUT /jobs/:id`, `DELETE /jobs/:id`
- `POST/DELETE /jobs/:id/team-members`, `POST/DELETE /jobs/:id/customer-payments`
- `POST/DELETE /jobs/:id/expenses`, `POST /jobs/:id/team-member-payments`
- `GET /jobs/:id/financial-summary?firebase_uid=`

---

## Shape de respuestas clave

### `GET /presupuestos/:id/detalle`
```
{
  periodo:    { id, fecha_inicio, fecha_fin, estado },
  movimientos:[{ id, descripcion, monto, tipo, pagado, monto_pagado_real,
                 subcategoria, clasificacion }],
  resumen:    { totalFijo, totalNoFijo, totalAhorro, totalGastado,
                totalGustitos, balance_disponible, porcentajePagados }
}
```
- `totalGastado` del resumen usa `m.monto` (presupuestado), NO `monto_pagado_real`.
- Gastado real = `SUM(monto_pagado_real) WHERE pagado=1`.
- `balance_disponible = monto_total - totalGastado - totalGustitos`.

### `GET /presupuestos/:id/fondo-seguridad`
```
{ total_ahorrado_actual, gastos_fijos_un_periodo,
  objetivo_nivel1 (×1), objetivo_nivel2 (×2), objetivo_nivel3 (×6),
  nivel_actual (0-3), pct_nivel1 (0.0-1.0) }
```

### `GET /deudas`
```
{ deudas: [...], total_pendiente, total_pago_minimo }
```

---

## Trampas de consistencia conocidas (no repetir)
- `monto_meta` / `monto_ahorrado` — NO `monto` / `total_ahorrado`.
- `gastado` real ≠ `totalGastado` del resumen.
- `deudas.tasa_interes` es **% mensual**.
- `shared_expense_splits.pagado` existía sin uso — todo campo del schema debe estar realmente leído/escrito.
- Parsear números MySQL con `double.tryParse(v?.toString() ?? '0') ?? 0.0`.
- Fechas como string `"YYYY-MM-DD"` para evitar bugs de timezone.
