# Estado actual de Salarying — Resumen para el Asesor Financiero

App: **Salarying** v1.2.0+4 — Gestor de finanzas personales y pequeños negocios.
Stack: Flutter (Android principal) + Node/Express + MySQL. Auth con Google Sign-In.

Este archivo resume los **módulos y fórmulas financieras ya construidas**. Antes de aprobar una idea nueva, revisa que no contradiga ni duplique lo que ya existe.

## Módulos principales

### Dashboard ("nivel Harvard", 7 cards)
1. **Salud Financiera** — score 0-100 con gauge circular. Fórmula actual:
   - Control de presupuesto → 40 pts (según diferencia entre % gastado y % del período transcurrido)
   - Tasa de ahorro → 30 pts (≥20% = 30, ≥10% = 20, ≥5% = 10)
   - Balance compartido → 20 pts (sin deuda = 20, <$50 = 15, <$200 = 8)
   - Flujo positivo → 10 pts (cobrado ≥ gastado)
   - Bandas de color: Excelente ≥90, Buena ≥75, Regular ≥60, Baja ≥40, Crítica <40
2. **Período actual** — gastado vs presupuesto total, barra de gasto, ritmo.
3. **Flujo neto + tasa de ahorro** — flujo neto = total cobrado − gastado real.
4. **Ahorro y metas** — meta con mayor progreso.
5. **Deudas compartidas** — balance neto de presupuestos compartidos.
6. **Próximos 7 días** — gastos (rojo) e ingresos (verde).
7. **Cobros activos** — ventas activas y monto cobrado.

### Presupuestos (reestructurado a "sistema de decisión financiera")
- Flujo guiado tipo wizard: **Ingresos → Gastos → Proyección**.
- Detalle con 3 tabs: Período / Proyección / Historial.

### Income (ingreso) — REGLA CRÍTICA
- El income es **informativo**. **Nunca modifica el `monto_total` del presupuesto.**
- Tipos: Salario / Informal / Ocasional / Préstamo / Otro.
- Para salario: bruto + 4 descuentos (CSS 9.75%, Educativo 1.25%, ISR sobre excedente de $916.67) + preview de neto en tiempo real.
- Presupuestos sin income siguen funcionando (`tiene_income = false`).

### Capacidad real
- Endpoint `GET /presupuestos/:id/capacidad`. Si no hay income → `capacidad_real = null`.

### Fondo de seguridad (3 niveles)
- Nivel 1 = gastos fijos de **1 período** (colchón mínimo)
- Nivel 2 = gastos fijos × 2 (1 mes completo si es quincenal)
- Nivel 3 = gastos fijos × 6 (3 meses, colchón fuerte)
- Cálculo dinámico sobre `gastos tipo='ahorro'`. No hay tabla nueva.

### Clasificación financiera de gastos (#4)
- Cada gasto se clasifica: **esencial / importante / flexible**.
  - esencial → primera necesidad (alquiler, comida, servicios)
  - importante → relevante pero no urgente (seguro, educación)
  - flexible → discrecional (ocio, ropa, salidas)

### Recomendación por porcentajes — regla 50/30/20 (#7)
- Base de cálculo: `ingreso_neto` si existe, si no `monto_total`.
- 50% esencial / 30% importante / 20% flexible (ahorro/discrecional).
- Compara real vs recomendado por categoría, tolerancia ±10%.
- **OJO DE COHERENCIA:** la regla 50/30/20 asume que el ingreso alcanza. Para el usuario objetivo con sobrante de $40, esta regla puede ser irreal. Cualquier mejora aquí debe considerar el caso "el ingreso no alcanza para 50/30/20".

### Alertas inteligentes preventivas (#6)
5 reglas evaluadas sobre el período actual:
1. ritmo_alto — gastado >70% en <50% del período → danger
2. cerca_limite — gasto ≥85% del presupuesto → warning
3. excedido — gasto ≥100% → danger
4. variables_altas — variables >130% del promedio histórico → warning
5. pagos_pendientes — >0 sin pagar en los últimos 3 días → info

### Simulador de decisiones (#8)
- Pantalla `simulador_decisiones_screen.dart`. Cálculo 100% local, sin API.
- Usuario ingresa un gasto hipotético; calcula disponible resultante, % de gasto, tasa de ahorro proyectada, y un consejo contextual (OK / cuidado / excedido / bajo ahorro).

### Deudas como entidad propia (#9)
- Tabla `deudas`: tipos `tarjeta_credito / prestamo / hipoteca / auto / personal / otro`.
- Campos: `monto_total`, `monto_pendiente`, `tasa_interes` (**% MENSUAL**), `pago_minimo`, `fecha_proximo_pago`.
- Abonos reducen `monto_pendiente`; al llegar a 0 se marca saldada automáticamente.
- Dashboard muestra card "Deudas pendientes" solo si `total_pendiente > 0`.

### Patrones de Gustitos — aprendizaje (P5)
- "Gustitos" = compras espontáneas / discrecionales.
- Detecta categorías que aparecen en ≥2 períodos y muestra el patrón al usuario.

### Cierre de período (manual)
- El usuario cierra el período; genera resumen con "aprendizajes" (lógica condicional, sin IA).
- Solo se puede cerrar si `fecha_fin <= hoy + 2 días`.

### Proyección (12 cards)
- Endpoint `GET /presupuestos/:id/proyeccion`. Devuelve 12 tarjetas marcadas como real / activo / proyectado, con promedios de los últimos 3 períodos. Estimados llevan prefijo "~".

## Otros módulos (no centrales para finanzas personales pero existen)
- **Presupuestos compartidos** — gastos divididos entre 2 personas, reglas de reparto (equitativo / porcentual / proporcional a ingresos).
- **Ventas** — dos divisiones: Venta de productos y Ofrecimiento de servicios (para pequeños negocios).
- **Ahorro y metas**, **Calendario**.

## Puntos sensibles de coherencia ya conocidos
- `gastado` real ≠ `totalGastado` del resumen. El real es `SUM(monto_pagado_real) WHERE pagado=1`; el del resumen usa lo presupuestado. No los confundas en un consejo.
- `tasa_interes` de deudas está en **% mensual**, no anual.
- Las proyecciones usan promedio de últimos 3 períodos — frágiles si el usuario tiene pocos períodos o ingreso muy variable.
