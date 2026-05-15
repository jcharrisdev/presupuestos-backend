# Sistema de diseño y patrones — Salarying

Referencia de los componentes y convenciones visuales que la app **ya usa**. Diseña en coherencia con esto.

## Stack de UI
- **Flutter SDK 3.29.3**, Material. Tema centralizado en `lib/theme/app_theme.dart`.
- Plataforma principal: **Android**, celulares de gama media/baja.
- Calendario: `table_calendar`. Fechas en español (`intl` con locale español).
- PDF: paquete `pdf` + `printing` para exportar reportes.

## Colores conocidos (de `app_theme.dart`)
- `colorDeuda` = `Color(0xFFF6465D)` (rojo de deuda)
- Hay helpers `gastoColor` / `gastoLabel` con casos por tipo de gasto (`fijo`, `variable`, `ahorro`, `deuda`).
- Sistema de **semáforo** usado en todo lado: verde (bien) / amarillo (cuidado) / naranja (alerta) / rojo (crítico).
- Niveles de alerta: `danger` = rojo, `warning` = amarillo, `info` = azul.
- Bandas del score de salud: Excelente ≥90 verde, Buena ≥75 verde, Regular ≥60 amarillo, Baja ≥40 naranja, Crítica <40 rojo.

Antes de introducir un color nuevo, revisa `app_theme.dart` y reutiliza lo que exista.

## Navegación
- **No hay router central.** Se navega con `Navigator.push()` directo.
- Estructura: `SplashScreen → LoginScreen / MainMenu`. Desde `MainMenu` se llega a Dashboard, Presupuestos (card expandible), Ahorro y Metas, Calendario, Deudas, Ventas.
- Datos propagados a todas las pantallas: `firebaseUid` (email), `displayName`, `photoUrl`.

## Componentes reutilizables existentes

En `lib/widgets/`:
- `widgets.dart` — widgets generales compartidos
- `confirm_dialog.dart` — diálogo de confirmación estándar (úsalo para acciones destructivas)
- `empty_state.dart` — **estado vacío estándar**. Reúsalo siempre; no inventes estados vacíos nuevos.
- `section_header.dart` — encabezado de sección estándar

En `lib/widgets/presupuestos/`:
- `balance_card.dart` — card de balance
- `pago_form_sheet.dart`, `gasto_form_sheet.dart` — **bottom sheets de formulario** (patrón `DraggableScrollableSheet`)
- `income_form_sheet.dart` — bottom sheet de ingreso con preview en tiempo real
- `capacidad_card.dart` — card de capacidad real (o banner CTA si no hay income)
- `fondo_seguridad_card.dart` — card de 3 niveles con checkmarks
- `clasificacion_card.dart` — barras de distribución esencial/importante/flexible
- `alertas_banner.dart` — banner de alertas con badge de color por nivel
- `recomendacion_porcentajes_card.dart` — card 50/30/20 con barras real vs recomendado
- `patrones_gustitos_banner.dart` — banner **ignorable localmente** (top categoría recurrente + botones Agregar/Ignorar)
- `analisis_financiero_section.dart` — **ExpansionTile colapsable** que agrupa varias cards de análisis
- `proyeccion_mes_card.dart` — card por mes con badge real/activo/proyectado, prefijo "~" en estimados

## Patrones de pantalla establecidos

### Cards del dashboard
- Cada card es **clickeable** y navega a su módulo.
- Card se oculta si no hay datos relevantes (ej: card de deudas solo si `total_pendiente > 0`).
- Dashboard carga 5 endpoints en paralelo + pull-to-refresh.

### Expense card de "doble mitad" (presupuestos compartidos)
- Parte superior: ícono + descripción + etiqueta + número grande (mi responsabilidad) + número chico (total).
- Parte inferior dividida en dos mitades (ELLOS / YO), cada una se pone verde al pagar, con `AnimatedContainer` para transición suave. Border completo verde cuando ambos pagaron.

### Bottom sheets de formulario
- Patrón `DraggableScrollableSheet`.
- Chips para selección de tipo/categoría.
- Campos auto-calculados van en `readOnly` con ícono de calculadora.
- Preview en tiempo real cuando aplica (ej: neto del salario).

### Wizard de creación
- `crear_presupuesto.dart` usa `PageView` + `PageController` de 3 pasos (Básicos → Ingreso → Gastos).
- Indicador de paso: `_StepDots`.

### Chips y badges
- `_ClasifChip` — chip coloreado de clasificación en cada movimiento.
- Subcategoría se muestra como chip pequeño gris.
- Badges de alerta coloreados por nivel.

### Banners ignorables
- Algunos banners (patrones de Gustitos) se pueden ignorar localmente con un bool de estado, **sin persistencia en BD**. Patrón válido para sugerencias no críticas.

## Convenciones de contenido
- Todo en **español**, fechas en español.
- Estimados y proyecciones se marcan con prefijo **"~"** y badge.
- "Gustitos" = compras espontáneas/discrecionales (nombre de marca del producto, mantenlo).
- "Capacidad real", "Fondo de seguridad", "Salud financiera" son nombres ya establecidos de features — consérvalos pero asegúrate de que la pantalla los explique en lenguaje simple.

## Restricciones técnicas que afectan el diseño
- **Backend duerme (Render, plan gratuito):** primera petición tras inactividad tarda ~50s. El `ApiClient` tiene timeout de 55s. Los estados de carga DEBEN tolerar esto sin parecer que la app murió.
- **Cache local con Hive, TTL 24h:** listas de presupuestos y ventas son cache-first. Detalles siempre van a la API.
- **Máximo 3-5 conexiones MySQL** — el backend agrupa queries; no esperes que cada interacción de UI dispare muchas llamadas.
- Carga lazy en varias pantallas (`_cargarExtras()`, `_cargarProyeccion()`, `_cargarHistorico()`) para no bloquear la UI principal.
