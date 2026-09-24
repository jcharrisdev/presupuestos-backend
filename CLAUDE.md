# CLAUDE.md — Salarying · Lectura obligatoria al iniciar cualquier sesión

> Este archivo es la fuente de verdad para trabajar en Salarying.
> Léelo completo antes de tocar cualquier código.
> Última actualización: 2026-09-24

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

## URLs de producción (fuente de verdad)

| Recurso | URL |
|---------|-----|
| **App web (sitio oficial de pruebas)** | `https://presupuestos-backend.vercel.app/` — el usuario prueba SIEMPRE aquí |
| Backend real (Render, `srv-d5kjem9r0fns73bfs23g`) | `https://presupuestos-backend-h3l6.onrender.com` |

**`lib/services/api_client.dart` → `baseUrl` DEBE apuntar siempre a `presupuestos-backend-h3l6.onrender.com`.**
Existen dominios de Render viejos (ej. `presupuestos-backend-backend-pr-2.onrender.com`, servidores de preview de PRs cerrados) que responden pero NO tienen las rutas actuales — si `baseUrl` apunta a uno de esos, la app falla con "Failed to fetch" o 404 aunque el deploy esté bien. Verificar siempre con `curl` antes de asumir una URL.

Vercel redespliega automáticamente `presupuestos-backend.vercel.app` al detectar push a `main` (toma el `build/web/` commiteado). Por eso todo fix de UI/API requiere el flujo completo: código fuente → `flutter build web` → commit `build/web/` → push a `main`. Sin ese build recompilado, Vercel sigue sirviendo el JS viejo con la URL/bug anteriores aunque el código fuente ya esté corregido.

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
# Clave real en DEPLOY_SECRETS.local.md (NUNCA poner la clave aquí — este repo es público)
curl -X POST "https://api.render.com/deploy/srv-d5kjem9r0fns73bfs23g?key=<ver DEPLOY_SECRETS.local.md>"
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
| `SALARYING_MEJORAS.md` | Lista viva de mejoras con estado ✅/⚠️/❌ — LEER SIEMPRE AL INICIO |
| `CLAUDE.md` | Este archivo — lectura obligatoria al iniciar sesión |

---

## Proceso obligatorio antes de cualquier cambio de código

```
1. ENTENDER   — ¿Qué ve el usuario? ¿Qué esperaba? ¿En qué pantalla exacta?
2. TRAZAR     — Flujo completo: Flutter widget → servicio → API endpoint → BD → respuesta → widget que renderiza
3. LEER       — Leer el código actual de cada archivo en el flujo. No asumir.
4. PREGUNTAR  — Si hay dudas, preguntar al usuario ANTES de codear.
5. PROPONER   — Explicar el diagnóstico y el plan. Esperar confirmación si el cambio es grande.
6. IMPLEMENTAR — Hacer el cambio contemplando: UI + backend + BD + migraciones + build + commit + push + deploy
7. VERIFICAR  — Releer el flujo con el código nuevo. ¿Hay algo que olvidé?
```

Cada deploy incorrecto cuesta tiempo y dinero real. Una pregunta antes de codear vale más que 5 fixes.

---

## Antes de empezar a codear en cualquier sesión

1. Leer este archivo
2. **Leer `SALARYING_MEJORAS.md` completo** — revisar estados ✅/⚠️/❌ para saber qué está hecho y qué no
3. Revisar `LECCIONES_APRENDIDAS.md` si la tarea toca código ya modificado antes
4. Verificar que el endpoint ya exista antes de crear uno nuevo
5. Trazar el flujo completo de cualquier feature antes de implementar
6. Recordar: **commit + push + deploy**, nunca solo deploy

---

## Reglas de seguimiento de mejoras (OBLIGATORIO)

### Regla 1 — Leer SALARYING_MEJORAS.md al inicio de cada sesión
Al iniciar una sesión nueva, leer `SALARYING_MEJORAS.md` completo antes de cualquier acción. Esto incluye:
- Identificar qué mejoras están ✅ implementadas, ⚠️ parciales, ❌ pendientes
- Tomar nota de cualquier mejora marcada como discutida pero no implementada
- Nunca proponer trabajo que ya está marcado ✅ como si fuera nuevo

### Regla 2 — Actualizar SALARYING_MEJORAS.md después de cada tarea
Inmediatamente después de completar (commit + push + deploy) cualquier mejora o corrección:
1. Marcar el ítem correspondiente con ✅ (implementado) o ⚠️ (parcial)
2. Agregar una línea de estado: `**Estado:** IMPLEMENTADO — [descripción breve + commit hash]`
3. Si se implementó algo que no está en el archivo, agregar el ítem nuevo con ✅
4. Actualizar la fecha al pie del archivo
Esta actualización va ANTES del git commit de cada paquete — así queda en el mismo commit.
