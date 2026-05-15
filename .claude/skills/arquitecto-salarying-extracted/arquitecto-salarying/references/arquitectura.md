# Arquitectura de Salarying — Referencia técnica

App **Salarying** v1.2.0+4. Gestor de finanzas personales y pequeños negocios.
Repo backend: github.com/jcharrisdev/presupuestos-backend

## Stack

### Frontend — Flutter / Dart
- Flutter SDK **3.29.3**, Dart. Plataforma principal **Android** (también iOS/Web/Desktop pero el foco es Android).
- Package ID Android: `com.example.salarying`
- Auth: `google_sign_in ^6.2.1`
- HTTP: `http ^1.2.0`
- Cache local: `hive ^2.2.3` + `hive_flutter ^1.1.0`
- Notificaciones: `flutter_local_notifications ^17.2.4`
- PDF: `pdf ^3.10.8` + `printing ^5.12.0`
- Calendario: `table_calendar ^3.1.2`, fechas: `intl ^0.19.0` (locale español)

### Backend — Node.js
- **Express.js ^4.21.0**, `mysql2 ^3.16.0` (Promises + Pool), `cors`, `node-cron ^3.0.3`, `node-fetch ^3.3.2`
- Node.js **22.x** (Render usa v22.22.0). Puerto 3002 (env `PORT`).
- Archivo principal: `backend/server.js` (monolito de rutas).

### Infraestructura
- **Backend:** Render, plan gratuito. **Duerme tras inactividad — ~50s para despertar.**
- **BD:** Clever Cloud MySQL compartido gratuito. **Máximo 5 conexiones por usuario.**
- **Auth:** Firebase / Google Sign-In. Proyecto Firebase `salary-bi`.

## Restricciones críticas (condicionan toda decisión)

1. **Pool MySQL = 3 conexiones. NUNCA superar 3 en producción.** Si se sube a 10, al redesplegar Render ocurre `ER_USER_LIMIT_REACHED` y el backend queda degradado. Margen de 3 deja espacio para conexiones administrativas. (Bug 9 documentado.)
2. **Render duerme.** Primera petición tras inactividad ~50s. `ApiClient` tiene timeout de **55s**. No diseñar flujos que asuman respuesta rápida.
3. **Minimizar queries por endpoint.** Varios endpoints resuelven todo en 2 queries a propósito (ej. `/proyeccion`). No diseñar endpoints que disparen N queries ni UI que llame en loop.
4. **Matar el servidor local antes de deploy** — local + Render comparten el límite de 5 conexiones.

## Autenticación y modelo de usuario
- Login con Google Sign-In. **`firebase_uid` = email de Google** (ej. `usuario@gmail.com`).
- Flujo: `main()` → `AuthService.silentSignIn()` → si hay sesión va a `MainMenu`, si no a `LoginScreen`.
- `firebase_uid` va como **query param en GET** y en el **body de POST/PUT/DELETE**. Todo dato del usuario se filtra por este campo.
- Permite recuperar datos al cambiar de dispositivo sin migración.
- Archivos: `lib/services/auth_service.dart`, `lib/login_screen.dart`, `lib/main.dart` (`_AuthGate`).

## Arquitectura de datos en la app

```
Flutter App
   │ HTTP (ApiClient, timeout 55s)
   ▼
REST API (Express en Render)
   │ mysql2 Pool (max 3)
   ▼
MySQL (Clever Cloud)
```

### Componentes internos Flutter
- `AuthService` — Google Sign-In
- `ApiClient` — cliente HTTP centralizado (base URL + timeout 55s)
- `CacheService` — Hive, cache local con TTL 24h
- `NotifService` — notificaciones locales Android
- `PdfService` — generación de PDF
- Servicios de dominio: `SharedBudgetService`, `ServiciosService`, `GustitosService`, `DeudasService`, `IncomeService`, `ProductsService`, `SalesService`, `SavingsService`, `CalendarService`, `PresupuestosService`

### Estrategia de cache
- Lista de presupuestos y lista de ventas: **cache-first** (Hive, 24h TTL).
- Detalles: **siempre desde API** (sin cache).
- Al logout: se limpia todo el cache del usuario.

### Navegación
- **No hay router central.** `Navigator.push()` directo.
- Datos propagados manualmente pantalla a pantalla: `firebaseUid`, `displayName`, `photoUrl`.
- Árbol: `main()` → `SplashScreen` / `LoginScreen` / `MainMenu` → módulos.

## Estructura de carpetas (resumen)

```
presupuestos-backend/
├── lib/
│   ├── main.dart, login_screen.dart, main_menu.dart
│   ├── dashboard_screen.dart
│   ├── (pantallas de presupuestos: lista, crear, editar, detalles)
│   ├── (pantallas de ahorro, calendario, ventas)
│   ├── simulador_decisiones_screen.dart
│   ├── cierre_periodo_screen.dart
│   ├── servicios/        → módulo Ofrecimiento de Servicios
│   ├── gustitos/         → módulo Gustitos
│   ├── deudas/           → módulo Deudas
│   ├── theme/app_theme.dart
│   ├── services/         → todos los *_service.dart
│   └── widgets/
│       ├── (widgets generales: confirm_dialog, empty_state, section_header)
│       ├── presupuestos/ → cards y form sheets de presupuestos
│       └── ventas/       → widgets de ventas
├── backend/
│   ├── server.js         → monolito de rutas Express
│   ├── package.json, .env
├── database/migrations/  → archivos .sql de migración
├── android/
├── pubspec.yaml
```

## Convenciones establecidas

### Servicios Flutter (`*_service.dart`)
- Métodos estáticos.
- Los **GET retornan `null` en excepción** — no crashean la UI; la UI tolera el null.
- Antes de crear un servicio nuevo, revisar si uno existente debe extenderse.

### Endpoints
- GET: `firebase_uid` como query param. POST/PUT/DELETE: `firebase_uid` en el body.
- **PUT con `COALESCE` dinámico** para edición parcial de campos.
- Degradación con gracia: cuando faltan datos (ej. sin income), devolver `tiene_income=false` y valores seguros, nunca fallar.
- DELETE suele ser **soft** (`activa=0`, `deleted_at`, archivar) — no borrado físico.

### Migraciones
- Patrón **no destructivo**: `ADD COLUMN ... NULL` y `CREATE TABLE IF NOT EXISTS`.
- Compatibles hacia atrás: registros y usuarios previos siguen funcionando.
- Se ejecutan manualmente en Clever Cloud; los `.sql` viven en `database/migrations/`.
- **Regla dura: No romper nada de lo que ya existe y funciona, A MENOS QUE el programador (Ulises) use el flag --intercambio al dar una tarea. Cuando se use --intercambio, deberás analizar en profundidad el cambio radical solicitado, entender todas las áreas del sistema afectadas (frontend Flutter, backend Express, base de datos MySQL, flujos de navegación, contratos de API, cache Hive, lógica de negocio), y ejecutar todas las decisiones necesarias de forma coordinada sobre esas áreas. En modo --intercambio no hay restricción de preservación: el objetivo es hacer el cambio bien, no evitar tocarlo.**

### Cron job
- `0 0 * * *` (medianoche, America/Panama UTC-5): marca como `vencido` los eventos de calendario pendientes con fecha pasada.

## Bugs históricos = lecciones de arquitectura

Patrones de error ya cometidos — no repetirlos:
- **Nombres de campos:** verificar SIEMPRE el nombre exacto contra el SQL del backend antes de leerlo en Flutter. (`monto_meta` no `monto`; `monto_ahorrado` no `total_ahorrado`.)
- **`gastado` real:** `GET /presupuestos` (lista) NO trae `gastado`. Hay que llamar `GET /presupuestos/:id/detalle` y calcular `SUM(monto_pagado_real) WHERE pagado=1`.
- **Campos fantasma:** `shared_expense_splits.pagado` existía en el schema pero ningún endpoint lo leía/escribía → el botón Pagar fallaba. Verificar que todo campo del schema esté realmente en uso.
- **`connectionLimit`** debe estar por debajo del límite del plan de BD.
- **Parsing robusto de números MySQL:** `double.tryParse(v?.toString() ?? '0') ?? 0.0`.
- **Fechas con timezone:** comparar como string `"YYYY-MM-DD"`, no como `DateTime`.
- **`baseUrl`:** verificar que apunte a Render (no localhost) antes de generar APK de release.

## Generar APK (release)
1. Verificar `baseUrl` en `lib/services/api_client.dart` apunta a Render.
2. Mínimo 5 GB libres en disco. No borrar Pub Cache / NDK / Flutter SDK.
3. Matar servidor local (libera conexiones MySQL).
4. `flutter build apk --release` → `build/app/outputs/flutter-apk/app-release.apk`
