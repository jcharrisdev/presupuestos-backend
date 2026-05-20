# CLAUDE.md — Salarying · Lectura obligatoria al iniciar cualquier sesión

> Este archivo es la fuente de verdad para trabajar en Salarying.
> Léelo completo antes de tocar cualquier código.
> Última actualización: 2026-05-20

---

## Visión central (no negociable)

> **"El presupuesto no es el punto de partida. El presupuesto es consecuencia del estado financiero del usuario."**

Salarying responde UNA pregunta: **¿Por qué no me alcanza el dinero?**
Cada decisión de diseño o código debe alinearse con esa respuesta.

El flujo maestro es:
```
Perfil financiero
  → Estado financiero anual (auto-generado)
    → 12 meses proyectados
      → Registros reales mes a mes
        → Análisis de desviación
          → Alertas y recomendaciones
            → Cierre anual → proyección siguiente año
```

Nada en Salarying existe aislado. Cada módulo alimenta al siguiente.

---

## Stack técnico

| Capa | Tecnología |
|------|-----------|
| Backend | Node.js + Express — monolito `backend/server.js` en Render |
| Base de datos | MySQL 5.6 en Clever Cloud (`connectionLimit: 3`) |
| Frontend | Flutter 3.x + Dart 3.5.1 — tema oscuro Binance-style |
| Auth | Firebase (`firebase_uid` = email Google del usuario) |
| Web hosting | Flutter web build — archivos en `build/web/` servidos por el backend en Render |
| Email | Brevo API (`BREVO_API_KEY`, `BREVO_SENDER_EMAIL` en env vars de Render) |

---

## Deploy — proceso OBLIGATORIO (en este orden exacto)

```bash
# 1. Build del web (SIEMPRE flutter clean primero)
flutter clean
flutter pub get
flutter build web --no-pub

# 2. Commit TODOS los archivos: código fuente + build/web
git add lib/... backend/server.js build/web/main.dart.js build/web/flutter_service_worker.js build/web/flutter_bootstrap.js
git commit -m "descripción"
git push origin main

# 3. Trigger deploy en Render
curl -X POST "https://api.render.com/deploy/srv-d5kjem9r0fns73bfs23g?key=1s-LJtjaam4"
```

**REGLA CRÍTICA:** Render despliega desde git. Si no hay commit+push, el deploy no tiene los cambios.
**NO hacer:** Trigger deploy sin push. Nunca funcionará.
**SW cache:** Si el usuario ve versión vieja, indicar `Ctrl+Shift+R` (hard refresh).

---

## Reglas técnicas del proyecto

### MySQL / Backend
- `firebase_uid` en TODOS los endpoints — nunca datos de otro usuario
- Columnas JSON como `LONGTEXT` (MySQL 5.6 no soporta tipo JSON nativo)
- `LIMIT` en SQL no parametrizado: usar `LIMIT ${parseInt(n)}` no `LIMIT ?`
- Valores `undefined` → `null` explícito antes de bind params de mysql2
- MySQL DECIMAL viene como string `"0.00"` → siempre usar `Number(campo)`
- Recálculo de estimados siempre fire-and-forget: `_recalcular(...).catch(() => {})`
- **No declarar `const/let` dentro de `res.json({})` — declararlos antes**
- Migraciones de schema con `.catch(() => {})` para idempotencia al reiniciar

### Flutter / Frontend
- Enums en Dart usan `lowerCamelCase` (ej: `partesIguales`, no `partes_iguales`)
- Al agregar un campo visual en un form: **rastrear el flujo completo** → estado → método guardar → body → API. Si solo se agrega el campo visual, no se guarda.
- Clases helper deben definirse antes o junto con su primer uso
- FABs en pantallas internas: verificar que `HomeShell` no tenga su propio FAB solapando

### Patrón de widget reutilizable
Cuando un feature se usa en 2+ pantallas, crear widget en `lib/widgets/financiero/` y compartirlo.

---

## Módulos implementados (estado actual — 2026-05-20)

### Activos y funcionales
- Perfil financiero (ingresos, fijos, variables base con períodos, deudas)
- Estado financiero anual auto-generado con recálculo automático
- Detalle de mes: tabs Resumen, Gastos, Quincenas, Análisis
- **Vista quincenal**: gastos con fecha día 1–14 = Q1 solo; día 16–31 = Q2 solo; día 15 = ambas quincenas al 50% (badge "½ mes")
- Compromisos quincenal: gastos fijos + variables base divididos 50/50
- Deudas: revolving + letras, estrategias avalanche/snowball, proyecciones
- Edición completa de deudas (tasa de interés siempre visible, se guarda siempre)
- Calendario con eventos de pagos
- Alertas automáticas en tab Resumen
- Scanner QR DGI (AppBar global)
- Dashboard conectado al modelo financiero anual
- Gastos reutilizables (expense_definitions)
- Gastos hormiga: auto-detección (`no_presupuestado` + `monto ≤ $25` → `es_hormiga=1`), badge 🐜 en resumen
- **Split puntual**: toggle en formulario de gasto y en factura QR, tipos "Partes iguales" / "Por porcentaje", email via Brevo
- Presupuestos compartidos (4 reglas de distribución)
- Logs del servidor con auto-limpieza 60 min
- Onboarding: "¿Cuánto recibes al mes?" — inclusivo para ingresos informales, default "Ingreso propio"

### Pendiente (próximas fases)
- Eliminación/edición controlada de gastos recurrentes (este mes / desde aquí / todos)
- Notificaciones push
- Base de datos de productos y precios
- Cierre mensual/anual con wizard
- Presupuestos de eventos (vacaciones, bodas, etc.)

---

## Tablas principales de la BD

```
user_income                 → ingreso del usuario
user_gastos_fijos           → compromisos fijos del perfil
gastos_variables_base       → presupuesto variable estimado
deudas                      → deudas activas del usuario
estado_financiero_anual     → totales anuales
meses_financieros           → 12 meses con estimados y reales
registros_gasto             → gastos reales registrados (campo es_hormiga)
analisis_categorias         → análisis por categoría
alertas_financieras         → alertas generadas por reglas
calendario_eventos          → eventos de pago
gasto_splits_puntual        → splits puntuales con notificación email
expense_definitions         → plantillas de gastos reutilizables
subcategorias               → categorías personalizadas
server_logs                 → logs TTL 60 min
```

---

## Principios UX (nunca violarlos)

1. **No punitivo**: informa, nunca juzga. "Gastaste más en ocio" — nunca "Malgastaste"
2. **Proactivo**: anticipa problemas antes de que ocurran
3. **Sin fricción**: auto-cálculo, selectores, scanner — nunca obligar a reescribir
4. **Visual**: colores semafóricos (verde/amarillo/rojo), barras de progreso
5. **Conectado**: toda acción actualiza el estado financiero automáticamente

---

## Archivos de referencia del proyecto

| Archivo | Contenido |
|---------|-----------|
| `SALARYING_VISION.md` | Visión completa, flujo, módulos, ejemplos de usuario |
| `LECCIONES_APRENDIDAS.md` | Errores de sesiones anteriores y cómo se resolvieron |
| `CLAUDE.md` | Este archivo — lectura obligatoria al iniciar sesión |

---

## Antes de empezar a codear en cualquier sesión

1. Leer este archivo
2. Revisar `LECCIONES_APRENDIDAS.md` si la tarea toca código ya modificado antes
3. Verificar que el endpoint ya exista antes de crear uno nuevo
4. Trazar el flujo completo de cualquier feature antes de implementar
5. Recordar: **commit + push + deploy**, nunca solo deploy
