# SALARYING — Mejoras Pendientes

> Archivo vivo. Se actualiza en cada sesión de audit.
> Cada mejora incluye: qué está mal, por qué importa, y cómo resolverlo.
> Las mejoras ya ejecutadas se marcan ✅.

---

## CATEGORÍA A — ENVELOPE TRACKING (Presupuestado vs Real)

### ✅ A1. No existe vista de saldo por categoría
**Estado:** IMPLEMENTADO — Paquete 1 (commit `900d2e8`). `_SobreRow` en Tab Gastos muestra barra semafórica por categoría.

**Problema:** El usuario presupuesta $300 para comida. Gasta $120 un día y $85 otro. En ningún lugar ve "Comida: $205 de $300 · te quedan $95". Los datos existen en la BD (`gastos_variables_base` + `registros_gasto`) pero la UI nunca los junta visualmente.

**Impacto:** Alta. Es la pregunta principal de la app: ¿cuánto me queda?

**Solución:** En el Tab Gastos (mes_detalle_screen), agregar una sección de sobres por categoría encima de la lista de registros. Cada sobre muestra:
- Nombre de la categoría
- Barra de progreso: `Gastado $X / Presupuesto $Y`
- Color semafórico: verde (<80%), amarillo (80–100%), rojo (>100%)
- Datos ya disponibles: suma de `registros_gasto` por categoría vs `gastos_variables_base.monto_estimado`

---

### ✅ A2. El formulario de gasto no muestra el saldo disponible antes de guardar
**Estado:** IMPLEMENTADO — Paquete 1 (commit `900d2e8`). `_CatBalanceHint` en AgregarGastoSheet muestra barra de balance al seleccionar categoría. También auto-detecta tipo `no_presupuestado` si la categoría no tiene presupuesto base.

**Problema:** Cuando el usuario va a registrar un gasto (AgregarGastoSheet), elige categoría "Comida" y escribe $150, pero no sabe que ya gastó $280 de un presupuesto de $300. No hay feedback antes de confirmar.

**Impacto:** Alta. El usuario gasta de más sin saberlo en el momento de la acción.

**Solución:** En AgregarGastoSheet, cuando el usuario selecciona una categoría, consultar (o recibir como parámetro) el presupuesto base de esa categoría y el total gastado este mes. Mostrar debajo del campo monto:
```
Comida este mes: $280 gastado de $300 presupuestado
Después de este gasto: $430 → excede en $130 ⚠
```

---

### A3. Tab Análisis con la información correcta está enterrado y nadie lo ve
**Problema:** El Tab Análisis en mes_detalle_screen SÍ tiene comparación presupuestado vs real por categoría (`_CategoriaCard`). Pero está al final del cuarto tab, visible solo si el usuario navega hasta allá y hace scroll. El 90% de usuarios nunca lo ve.

**Impacto:** Media. La solución de A1 (poner sobres en Tab Gastos) resuelve esto en parte, pero también hay que promover la info del Tab Análisis al nivel del Tab Gastos o Dashboard.

**Solución:** Mover los `_CategoriaCard` al Tab Gastos como sección colapsable "Resumen por categoría". Mantener Tab Análisis para el detalle profundo.

---

## CATEGORÍA B — QUINCENAS FUNCIONALES

### ⚠️ B1. El toggle pagado/no pagado es binario — no soporta pagos parciales
**Estado:** PARCIAL — El toggle existe en Tab Gastos (commit `988058f`): tap en gasto fijo crea/elimina `registros_gasto`. Pero sigue siendo binario (monto completo o nada). El mini-sheet para pagos parciales NO está implementado.

**Problema:** Un gasto fijo de $200/mes aparece como una línea con toggle. El usuario puede marcarlo como "pagado" (crea un registro de $200) o no. No puede decir "pagué $100 esta quincena, falta $100". No hay concepto de pago parcial.

**Impacto:** Alta para usuarios que cobran quincenal (mayoría en Panamá).

**Solución:** Al hacer tap en el toggle de un gasto fijo, en vez de crear registro instantáneo, abrir un mini-sheet que pregunta:
- ¿Cuánto pagaste? (campo monto, default = monto completo)
- ¿Qué fecha? (default = hoy)
Esto permite pagar en partes. El indicador del gasto muestra "Pagado $100 de $200 · falta $100".

---

### B2. Los gastos con dos días de pago no se dividen correctamente
**Problema:** En el perfil se puede configurar `dia_pago` y `dia_pago_2` (ej: día 15 y día 30). La lógica de quincenas sabe que estos gastos aplican a ambas. Pero en el Tab Quincenas no queda claro cuánto toca pagar en Q1 vs Q2. El monto se muestra completo en ambas quincenas.

**Impacto:** Media. Genera confusión sobre cuánto hay que tener disponible en cada quincena.

**Solución:** Si un gasto tiene `dia_pago` y `dia_pago_2`, la cuota de cada quincena debe ser `monto_mensual / 2`, no `monto_mensual`. Mostrar en Tab Quincenas: "Renta Q1: $500 | Renta Q2: $500" en vez de "Renta: $1,000" dos veces.

---

### ✅ B3. Tab Quincenas no tiene acciones — solo es lectura
**Estado:** IMPLEMENTADO — `_QuincenaCard` convertido a `StatefulWidget`. Backend actualizado: `GET /user/quincena` ahora incluye `id`, `registro_id` y `categoria` en cada compromiso. Toggle circular en cada compromiso: tap crea/elimina `registros_gasto` igual que en Tab Gastos. Compromisos pagados muestran tachado y check verde.

**Problema:** El Tab Quincenas muestra compromisos y gastos de cada quincena pero el usuario no puede hacer nada desde ahí. Para marcar un gasto como pagado tiene que ir al Tab Gastos, buscarlo, y actuar. Los flujos están separados.

**Impacto:** Media. Genera navegación innecesaria.

**Solución:** Agregar el mismo toggle de "marcar pagado" que existe en Tab Gastos también en las tarjetas del Tab Quincenas. La acción es idéntica, solo necesita estar disponible en ambos lugares.

---

## CATEGORÍA C — DASHBOARD Y PRIMERA PANTALLA

### ⚠️ C1. El Dashboard no responde "¿por qué no me alcanza?"
**Estado:** PARCIAL — Paquetes 3 y 6 (commits `3f8973a`, `fc812fc`): se agregaron banner de compromisos pendientes, sobres del mes (horizontal scroll con barra semafórica por categoría), y tarjeta de gastos hormiga. Faltan: próximos pagos de la semana y disponible quincenal.

**Problema:** La pantalla de Dashboard muestra: ingreso estimado, total gastado, remanente, y una barra de progreso global. No dice DÓNDE se está yendo el dinero ni qué categorías están en riesgo.

**Impacto:** Alta. Es la primera pantalla que el usuario ve. Si no le dice nada útil, no la usa.

**Solución:** Agregar al Dashboard:
1. Top 3 categorías con mayor gasto vs presupuesto (con colores semafóricos)
2. Próximos pagos de la semana (no solo del mes)
3. Si hay categorías en rojo (>100%): mostrar un banner de alerta arriba
4. Disponible quincenal: "Esta quincena tienes $X disponibles después de compromisos"

---

### ✅ C2. No hay indicador de disponible por quincena en ningún lado
**Estado:** IMPLEMENTADO — `_QuincenalCard` en Dashboard muestra cobro quincenal estimado, compromisos Q1/Q2 (con lógica dia_pago/dia_pago_2), y disponible libre con color semafórico.
**Problema:** Un usuario que cobra $800 quincenal quiere saber: "De mis $800 de esta quincena, ¿cuánto tengo libre después de compromisos fijos?" Esto no existe en ninguna pantalla.

**Impacto:** Alta para el perfil de usuario objetivo (cobran quincenal).

**Solución:** Calcular y mostrar en Dashboard o Tab Quincenas:
```
Esta quincena (Q1 – May):
Cobro estimado:   $800
Compromisos Q1:  −$450
────────────────
Disponible libre: $350
```
Los datos están disponibles: `user_income` + compromisos fijos con `dia_pago` en Q1.

---

## CATEGORÍA D — NAVEGACIÓN Y FLUJOS

### D1. No está claro cuál es el flujo principal de uso diario
**Problema:** La app tiene: Home Shell → Estado Anual → Mes Detalle → 4 tabs. Para un usuario nuevo o casual, no es evidente qué hacer primero ni cuál es la pantalla de "trabajo diario".

**Impacto:** Alta. Si el usuario no entiende el flujo en los primeros 2 minutos, abandona.

**Solución:** Definir una pantalla de "modo diario" que sea el punto de entrada real:
- Muestra el mes actual directamente (no el estado anual)
- Tab activo por defecto: Gastos (no Resumen)
- FAB visible siempre: "Registrar gasto"

---

### D2. Para ver cuánto gasté en una categoría, necesito 3–4 taps
**Problema:** Ver el desglose de una categoría (ej: "¿cuánto gasté en comida esta semana?") requiere: Home → Mes → Tab Análisis → scroll hasta Comida. No hay shortcut.

**Impacto:** Media.

**Solución:** En los sobres de categoría (mejora A1), cada sobre es tappable y abre el detalle: lista de registros de esa categoría en el mes actual, con fecha y monto de cada uno.

---

### ⚠️ D3. Editar un gasto fijo del perfil y editar un registro son dos flujos completamente separados con UX diferente
**Estado:** PARCIAL — Paquetes 2 y 5 (commits `91be835`, `7d56121`): long-press en Tab Gastos permite editar/eliminar gastos fijos (`user_gastos_fijos`) y presupuesto variable base (`gastos_variables_base`) directamente sin ir al Perfil. Falta: preview de impacto en disponible antes de guardar.

**Problema:** Si el usuario quiere cambiar el monto de su presupuesto de gasolina, va a Perfil Financiero. Si quiere editar un registro real, va al Tab Gastos. Son pantallas distintas con formularios distintos. No hay conexión visible entre "lo que planeé" y "lo que pagué".

**Impacto:** Media. Genera confusión conceptual.

**Solución:** En los sobres de categoría (A1), al tocar el ícono de lápiz del sobre, editar directamente el monto presupuestado base. Al tocar un registro individual, editar ese registro. Todo desde la misma pantalla.

---

## CATEGORÍA E — INFORMACIÓN FALTANTE O INCOMPLETA

### E1. No hay historial de pagos por gasto fijo
**Problema:** El usuario paga su renta cada mes. No hay ninguna pantalla que muestre "Renta: pagado en enero, febrero, marzo... fallido en abril". No puede ver el historial de un compromiso específico a lo largo del tiempo.

**Impacto:** Media.

**Solución:** En el Tab Gastos o en Perfil, al tocar un gasto fijo, mostrar un sheet con:
- Historial de pagos por mes (verde = pagado, rojo = no pagado, gris = mes futuro)
- Promedio pagado vs presupuestado
- Tendencia de monto (¿está subiendo el costo?)

---

### ✅ E2. Gastos "no presupuestados" no tienen categoría visible en la lista
**Estado:** IMPLEMENTADO — Línea de totales al final del Tab Gastos: Comprometido (fijos+deudas), Variable registrado, No presupuestado (impulso) — este último es el indicador de gasto hormiga/impulso. Usa Money.fmt.
**Problema:** Los gastos marcados como `no_presupuestado` aparecen en la lista pero sin contexto de presupuesto. El usuario no puede ver fácilmente cuánto de su gasto mensual es "no planeado" vs "planeado".

**Impacto:** Media.

**Solución:** En el Tab Gastos, agregar una línea de totales al final:
- Total comprometido: $X
- Total variable registrado: $Y
- Total no presupuestado: $Z ← este número es el indicador de "gastos hormiga / impulso"

---

### E3. Las alertas automáticas existen pero no tienen prominencia
**Problema:** El sistema genera `alertas_financieras` automáticamente, pero solo se ven en Tab Resumen con banners pequeños. No hay notificación ni indicador en el ícono de la pantalla de inicio.

**Impacto:** Media.

**Solución:** Si hay alertas activas, mostrar un badge rojo en la navegación del mes. En el Dashboard, mostrar la alerta más urgente como card prominente arriba de todo.

---

## CATEGORÍA F — VISUAL Y UX

### ✅ F1. Demasiada información comprimida en Tab Resumen
**Estado:** IMPLEMENTADO — La tabla comparativa, uso del ingreso y compromisos se movieron a un ExpansionTile "Detalle del mes" colapsado por defecto. El Tab Resumen muestra arriba solo lo esencial: disponible (número grande), banner sano/déficit, ingreso real, alertas. El detalle queda a un tap sin perder datos.
**Problema:** El Tab Resumen muestra: tabla de categorías, alertas, gastos hormiga, compromisos, todo junto. Se siente como un reporte, no como una pantalla de app.

**Impacto:** Media. El usuario se siente abrumado.

**Solución:** Reducir Tab Resumen a 3 elementos máximo:
1. Número grande: Disponible este mes
2. Barra de progreso del mes
3. Top 3 alertas (si hay)
Todo lo demás va al Tab Análisis donde tiene sentido.

---

### ⚠️ F2. Los estados vacíos no guían al usuario
**Estado:** PARCIAL — Tab Gastos ahora usa el widget reutilizable EmptyState (ícono + título + subtítulo + botón "Registrar primer gasto" que abre el sheet). El widget EmptyState ya existe en lib/widgets/empty_state.dart para replicar en otras pantallas con estados vacíos pendientes.
**Problema:** Si el usuario no tiene registros, gastos fijos, o datos, muchas pantallas simplemente muestran vacío o un spinner infinito. No hay instrucciones de "qué hacer ahora".

**Impacto:** Media para usuarios nuevos.

**Solución:** Cada pantalla con estado vacío debe tener:
- Ícono ilustrativo
- Mensaje explicativo: "Aún no tienes gastos este mes"
- Botón de acción primaria: "Registrar primer gasto"

---

### ⚠️ F3. Los montos no tienen formato consistente
**Estado:** PARCIAL — Creado el helper canónico `Money.fmt()` en lib/utils/money.dart (separador de miles + 2 decimales, símbolo en un solo lugar para futura migración a B/.). Aplicado en los números héroe de máxima visibilidad: Dashboard (ingreso/gastado/remanente + card quincenal) y disponible del Tab Resumen. Quedan ~250 `.toStringAsFixed(2)` sueltos por migrar gradualmente al helper.
**Problema:** En distintas partes de la app el mismo monto aparece como: `$1200`, `$1,200.00`, `1200.00`, `B/. 1,200`. No hay un estándar.

**Impacto:** Baja/Media. Afecta confianza.

**Solución:** Definir y aplicar un único formateador en toda la app: `B/. 1,200.00` (formato Panamá). Crear un helper `formatMonto(double v)` y reemplazar todos los `.toStringAsFixed(2)` sueltos.

---

## CATEGORÍA G — COHERENCIA FINANCIERA (requieren aprobación antes de ejecutar)

### G1. AbonoDeudaSheet puede crear registros duplicados si también se usa "marcar como pagado" en Tab Gastos
**Problema:** Si el usuario registra un abono desde la pantalla de Deudas Y también marca la misma deuda como pagada en Tab Gastos, se crean dos `registros_gasto` para el mismo pago. Esto infla el total de gastos del mes.

**Estado:** Identificado. No corregir sin aprobación del usuario.

---

### ✅ G2. Los gastos variables base sin `origen_variable_id` en un registro no se cuentan en el envelope
**Estado:** YA RESUELTO (verificado QA) — El envelope (`porCategoria` en getMes) agrupa los registros por `categoria` directamente, sin depender de `origen_variable_id`. Confirmado en vivo: "alimentacion" matcheó presupuesto 200 vs gastado 3.5 con un registro sin origen_variable_id.
**Problema:** Si el usuario registra un gasto variable de categoría "Comida" sin vincularlo a un `gastos_variables_base`, ese registro sí cuenta en el total real pero puede no matchear contra el presupuesto base si la categoría tiene nombres distintos.

**Estado:** Identificado. El matching debe hacerse por `categoria` además de `origen_variable_id`.

---

---

## CATEGORÍA H — ONBOARDING Y PRIMERA EXPERIENCIA

### H1. Onboarding no tiene modo express para usuarios simples
**Problema:** El flujo de 5 pasos obliga a todos los usuarios a pasar por deudas, metas, y variables base, aunque muchos solo tengan un ingreso y gastos básicos. Para alguien que cobra $800 quincenal y paga renta + comida, el proceso se siente excesivo.

**Impacto:** Alta. El usuario abandona antes de llegar al estado financiero.

**Solución:** En el paso 1 (perfil básico), agregar opción "Configuración rápida (5 min)" que solo pide ingreso + gastos fijos principales. Deudas, variables base y metas quedan como pasos opcionales accesibles después desde el perfil.

---

### ✅ H2. Disponible negativo en el onboarding no da dirección al usuario
**Estado:** IMPLEMENTADO — Cuando el disponible es negativo, el aviso ahora incluye mensaje de apoyo ("No estás solo/a en esto. Salarying te ayudará a entender dónde ajustar...") + botón "Revisar mis gastos" que lleva directo al paso de gastos fijos (onIrAGastos). El botón "Comenzar..." permite continuar de todos modos.
**Problema:** Si el usuario ingresa sus gastos y el disponible resulta negativo, el paso 5 muestra una advertencia pero no dice qué hacer. El usuario entra en pánico o abandona la app.

**Impacto:** Alta. Es el momento más crítico del onboarding.

**Solución:** Cuando el disponible es negativo, mostrar tres acciones concretas con botones:
- "Revisar mis gastos fijos" → lleva directo a la lista editable
- "Revisar gastos variables" → lleva a variables base
- "Entiendo, continuar de todos modos"
Acompañar con mensaje positivo: "No estás solo/a en esto. Salarying te ayudará a entender dónde ajustar."

---

### ✅ H3. Los gastos variables en el onboarding parecen gastos reales, no estimados
**Estado:** IMPLEMENTADO — Paso 4 cambió de "¿Cuánto gastas al mes?" a "¿Cuánto quieres presupuestar al mes?" + línea: "Este es tu tope objetivo por categoría, no lo que ya gastaste. Puedes ajustarlo después."
**Problema:** El paso de variables base dice "¿Cuánto gastas en comida?" El usuario lo interpreta como "registrar lo que gasté" cuando en realidad es "cuánto presupuesto para ese mes". La diferencia es crítica para entender la app.

**Impacto:** Media. Crea expectativas incorrectas desde el inicio.

**Solución:** Cambiar el lenguaje: "¿Cuánto quieres presupuestar para comida cada mes?" y agregar una línea explicativa: "Puedes ajustarlo después. Este es tu tope objetivo, no lo que ya gastaste."

---

### ✅ H4. El botón final del onboarding no transmite que la app está lista para usar
**Estado:** IMPLEMENTADO — Botón cambió de "Generar mi Estado Financiero" a "Comenzar a controlar mi dinero →" (lenguaje del usuario, no técnico).
**Problema:** El botón del paso 5 dice "Generar mi Estado Financiero". Para un usuario no financiero, "estado financiero" suena a algo técnico y ajeno. No sabe qué va a ver después.

**Impacto:** Media.

**Solución:** Cambiar a "Listo, ver mi plan financiero →" o "Comenzar a controlar mi dinero →". El lenguaje debe ser del usuario, no de la app.

---

## CATEGORÍA I — DEUDAS

### ✅ I1. El banner de "deuda incompleta" no explica qué falta ni cómo completarla
**Estado:** IMPLEMENTADO — El banner ahora dice exactamente qué falta (saldo pendiente y/o tasa de interés) nombrando la deuda, y tiene botón "Completar [nombre]" que abre directo el sheet de edición (onEditar).
**Problema:** Las deudas creadas desde el perfil financiero (sin información completa) muestran un banner de advertencia en la pantalla de deudas, pero el texto es genérico. El usuario no sabe qué campo falta ni dónde ir para completarlo.

**Impacto:** Alta. El usuario ve una advertencia pero no puede actuar.

**Solución:** El banner debe decir exactamente qué falta: "A esta deuda le falta: tasa de interés, plazo en meses. [Completar ahora →]" con un botón que abre directamente el formulario de edición de esa deuda precompletado.

---

### I2. Las estrategias de deuda (Avalanche/Snowball) usan lenguaje técnico sin números concretos
**Problema:** La pantalla de estrategias explica Avalanche y Snowball con texto genérico ("paga primero la de mayor tasa de interés"). No muestra cuánto dinero ahorra el usuario específicamente con sus deudas reales.

**Impacto:** Media. El usuario no entiende por qué importa la estrategia.

**Solución:** Para cada estrategia, calcular y mostrar con los datos reales del usuario:
- "Con Avalanche: terminas tus deudas en 14 meses y ahorras $340 en intereses"
- "Con Snowball: terminas en 16 meses, pagas $520 más en intereses, pero eliminas 2 deudas pequeñas en los primeros 3 meses"

---

### ✅ I3. El campo "próximo pago" en AbonoDeudaSheet no explica para qué sirve
**Estado:** IMPLEMENTADO — Label cambió a "¿Cuándo es tu próximo pago? (actualiza tu calendario)" para que el usuario entienda el efecto.
**Problema:** Al registrar un abono, hay un campo opcional "Actualizar fecha próximo pago". El usuario no entiende si esto afecta el calendario, la proyección, o solo es informativo.

**Impacto:** Baja/Media.

**Solución:** Cambiar el label a "¿Cuándo es tu próximo pago? (actualiza tu calendario)" con un ícono de calendario. Así el usuario entiende el efecto inmediato.

---

### ✅ I4. No hay vista de progreso total de deudas en un solo lugar
**Estado:** IMPLEMENTADO — Card de progreso consolidado en Tab Situación: original total, pagado, falta, y barra de progreso con % pagado. Calculado desde monto_total vs monto_pendiente de todas las deudas.
**Problema:** El usuario tiene 3 deudas. No puede ver de un vistazo: "En total debo $4,500. Llevo pagado $1,200 (27%). Me quedan $3,300." Solo ve cada deuda individualmente.

**Impacto:** Media.

**Solución:** Agregar en la cabecera de la pantalla de deudas un resumen consolidado:
- Total adeudado original: $X
- Total pagado hasta hoy: $Y
- Saldo total actual: $Z
- Barra de progreso global

---

## CATEGORÍA J — CALENDARIO

### J1. Las tabs "Lista" y "Flujo" del calendario no se distinguen claramente
**Problema:** El calendario tiene tres tabs: Lista, Flujo, y la vista de calendario. No hay descripción de para qué sirve cada una. "Flujo" muestra un resumen financiero día a día pero el usuario lo confunde con "lo mismo que Lista pero diferente".

**Impacto:** Media.

**Solución:** Añadir subtítulo o tooltip en cada tab: "Lista: tus eventos por fecha" | "Flujo: cómo entra y sale el dinero cada día del mes".

---

### J2. El calendario no conecta visualmente con el Tab Quincenas del mes
**Problema:** El Tab Quincenas en mes_detalle_screen y el Calendario son dos vistas separadas que muestran información similar (compromisos de pago por fecha). El usuario no sabe cuál usar ni cuándo.

**Impacto:** Media. Duplicidad confusa.

**Solución:** El calendario debería ser la fuente de verdad visual de cuándo pagar cada cosa. El Tab Quincenas debería consumir del calendario o referenciarlo, no ser una vista paralela independiente.

---

### J3. Crear un evento en el calendario no sugiere los compromisos existentes
**Problema:** Cuando el usuario crea un evento en el calendario (ej: "Pago renta día 1"), no hay sugerencia de "¿Quieres vincular esto a tu gasto fijo Renta?" La desconexión es total entre gastos fijos del perfil y eventos del calendario.

**Impacto:** Media.

**Solución:** Al crear un evento, ofrecer la opción "Vincular a un gasto fijo o deuda" con un selector de los gastos ya registrados. Esto permite que el calendario muestre automáticamente los compromisos del perfil sin que el usuario los cree dos veces.

---

## CATEGORÍA K — ESTADO FINANCIERO ANUAL

### K1. Los 12 meses están colapsados por defecto — el usuario no descubre el detalle
**Problema:** La grilla de 12 meses en el estado financiero anual muestra un resumen comprimido. Para ver el desglose de un mes específico hay que hacer tap, pero muchos usuarios nunca lo hacen porque no parece tappable.

**Impacto:** Media. El dato más útil (comparación mes a mes) queda oculto.

**Solución:** Mostrar el mes actual expandido por defecto. Agregar un indicador visual claro (chevron o flecha) en cada tarjeta de mes para indicar que es expandible.

---

### ✅ K2. El "Consejero Financiero IA" no explica su lógica
**Estado:** IMPLEMENTADO — El score ahora muestra su desglose visual (Deudas/Ahorro/Fijos/Control, máx 25 c/u con barras de color) para que el usuario entienda de dónde sale el número. El header del enfoque cambió de "Enfoque de [mes]" a "TU ACCIÓN PRIORITARIA · [mes]" para comunicar que es accionable. Los insights del backend (server.js:9942) ya incluían qué detectó + por qué importa + acción.
**Problema:** La sección del consejero muestra un "Enfoque de X" sin explicar qué significa ese enfoque para el usuario. ¿Debo hacer algo? ¿Es bueno o malo?

**Impacto:** Media.

**Solución:** Cada consejo del consejero debe incluir: qué detectó, por qué importa, y una acción concreta sugerida. Formato: "Detecté que gastas 40% en gastos fijos. Lo ideal es menos del 35%. Sugerencia: revisa [Gasto X] que subió este mes."

---

### K3. El toggle Vista Quincenal/Mensual no tiene onboarding contextual
**Problema:** El toggle existe pero el usuario que cobra quincenal no sabe que debe activarlo para que la app se adapte a su ciclo de pago.

**Impacto:** Alta para el perfil objetivo (cobran quincenal).

**Solución:** La primera vez que el usuario abre el estado anual, si su `frecuencia_cobro` es quincenal, mostrar un tooltip: "Activa la Vista Quincenal para ver tus compromisos adaptados a tus dos cobros del mes."

---

## CATEGORÍA L — GUSTITOS

### ✅ L1. Los Gustitos están completamente desconectados del presupuesto mensual
**Estado:** IMPLEMENTADO — `POST /gustitos` ahora crea un `registros_gasto` vinculado (fire-and-forget, solo si el mes existe). `DELETE /gustitos/:id` elimina también el registro vinculado. Migración `origen_gustito_id` en `registros_gasto`. Tab Gastos muestra badge ⚡ y color azul primario para registros de origen gustito. Opciones del tile ocultan Editar/Eliminar y muestran banner explicativo.

---

### L2. No hay límite de gustitos ni aviso de exceso
**Problema:** El usuario puede registrar 20 gustitos en el mes sin ningún aviso. No hay presupuesto de gustitos ni alerta de "ya llevas $150 en compras por gusto este mes".

**Impacto:** Media.

**Solución:** Permitir que el usuario defina un "presupuesto de gustitos mensual" en el perfil. Mostrar en la pantalla de gustitos una barra de progreso: "Gustitos: $95 de $100 este mes."

---

## CATEGORÍA M — FACTURAS QR / INVOICE SCANNER

### ✅ M1. El flujo post-escaneo tiene 7 opciones — demasiadas para el usuario promedio
**Estado:** IMPLEMENTADO — SelectTargetScreen ahora tiene 2 niveles. Nivel 1: dos opciones grandes — "Gasto personal" (flujo feliz → CreateExpenseFromInvoiceScreen) y "Más opciones". Nivel 2: grid con las 6 especializadas + guardar sin asignar y botón Volver.
**Problema:** Después de escanear una factura, el usuario ve una grilla de 7 opciones: Gasto existente, Gasto nuevo, Gustito, Presupuesto compartido, Gasto operativo, Gasto empresarial, Compra de inventario. Para el 90% de los usuarios que solo quieren registrar un gasto, esto es abrumador.

**Impacto:** Alta. El exceso de opciones paraliza al usuario.

**Solución:** Reorganizar en dos niveles:
- Nivel 1 (pantalla principal): 2 opciones grandes: "Gasto personal" y "Más opciones →"
- Nivel 2 (si toca Más opciones): Las 5 opciones especializadas
Así el flujo feliz (gasto personal) es inmediato.

---

### ✅ M2. Las facturas escaneadas sin asignar no tienen recordatorio visible
**Estado:** IMPLEMENTADO — Nuevo endpoint `GET /invoice-scanner/invoices/pending-count` (cuenta status != 'assigned'). HomeShell lo carga y muestra un badge rojo con el número en la card "Facturas QR" del Tab Más.
**Problema:** El usuario escanea 3 facturas y elige "Guardar sin asignar". Esas facturas quedan en el historial pero no hay ningún badge ni alerta que diga "tienes 3 facturas pendientes de asignar".

**Impacto:** Media. Las facturas se olvidan y nunca se registran.

**Solución:** En el ícono del scanner en el AppBar (o en Dashboard), mostrar un badge con el número de facturas no asignadas. En el historial, filtrar por "Pendientes" por defecto.

---

## CATEGORÍA N — PERFIL FINANCIERO

### N1. Las deudas aparecen en dos lugares distintos con comportamiento diferente
**Problema:** Las deudas se pueden ver y editar en "Perfil Financiero → Tab Fijos" (vista básica) y también en "Mis Deudas" (vista completa con estrategias). Editar en un lado no siempre refleja en el otro, y el usuario no sabe cuál es el lugar "correcto".

**Impacto:** Alta. Genera confusión y desconfianza en los datos.

**Solución:** Eliminar la sección de deudas del Tab Fijos en Perfil Financiero. Reemplazar con un link/card: "Ver y gestionar mis deudas →" que lleva a la pantalla de Deudas. El perfil solo muestra cuánto representan las deudas en el total de compromisos.

---

### N2. El perfil no muestra el impacto de cambiar un gasto fijo
**Problema:** El usuario edita su gasto fijo "Renta" de $500 a $600. No hay feedback de "esto cambia tu disponible mensual de $350 a $250". El cambio se guarda silenciosamente y el usuario no conecta la edición con su situación financiera.

**Impacto:** Media.

**Solución:** Al editar un gasto fijo o variable base, mostrar un preview inline antes de guardar: "Nuevo disponible mensual: $250 (antes: $350)".

---

---

## CATEGORÍA O — FORMULARIO DE GASTOS (AgregarGastoSheet)

### ✅ O1. Demasiadas decisiones antes de guardar un gasto simple
**Estado:** IMPLEMENTADO — AgregarGastoSheet ahora tiene modo rápido (default): solo gastos anteriores, nombre, monto, categoría + balance hint. El tipo se auto-detecta (variable→no_presupuestado si la categoría no tiene presupuesto). Toggle "Más opciones" revela modo detalle: tipo, fecha, notas, guardar como base, split.
**Problema:** El usuario debe tomar 7 decisiones antes de guardar: tipo (fijo/variable/no presupuestado), nombre, monto, categoría, fecha, ¿guardar como base?, ¿compartir? Para alguien que solo quiere registrar "$30 supermercado", es excesivo.

**Impacto:** Alta. Es el formulario que más se usa. Complejidad = abandono o datos incorrectos.

**Solución:** Flujo en dos modos:
- **Modo rápido** (default): Solo nombre, monto, categoría. Guarda en 3 taps.
- **Modo detalle** (expandible): Tipo, fecha, notas, guardar como base, split.

---

### ✅ O2. Las categorías están desalineadas entre pantallas
**Estado:** IMPLEMENTADO — Lista canónica única `CategoriaSelector.canonicas` (13 categorías + servicios). Perfil financiero deriva sus tipos de esa lista (corrige `deuda`→`deudas`). Strays del backend arreglados: pago compartido `'Compartido'`→`'compartido'`, scanner QR fallback `'General'`→`'otro'`. Migración idempotente normaliza datos existentes en registros_gasto, gastos_variables_base y user_gastos_fijos. Ver también V1.
**Problema:** El selector de categorías tiene 13 opciones. El formulario de gastos fijos en Perfil tiene 8 diferentes. Un gasto guardado como "ocio" en el Tab Gastos no coincide con ninguna categoría del Perfil. La app muestra los mismos datos con nombres distintos.

**Impacto:** Alta. El usuario pierde confianza en los números.

**Solución:** Definir una lista canónica de 6–8 categorías usada en toda la app sin excepción. Migrar categorías existentes.

---

### O3. El campo "Guardar como base" está oculto y no tiene contexto
**Problema:** El checkbox "Guardar como gasto variable base" aparece condicionalmente y no explica qué significa "base". El usuario que nunca lo activa no construye un presupuesto — solo registra gastos sueltos. La app nunca "aprende" sus hábitos.

**Impacto:** Alta. Sin gastos base, no hay presupuesto real, solo un historial de gastos.

**Solución:** Cambiar el flujo: después de guardar un gasto, preguntar "¿Repites este gasto regularmente?" Si sí, ofrecer guardarlo como base en ese momento, con lenguaje simple.

---

### O4. El tipo "No presupuestado" no tiene explicación ni consecuencia visible
**Problema:** El usuario ve tres opciones de tipo: Fijo, Variable, No presupuestado. No hay tooltip, icono ni ejemplo. Muchos eligen "No presupuestado" para todo porque "suena a que ya lo gasté". Luego el gasto desaparece del radar del presupuesto.

**Impacto:** Alta. Gastos no presupuestados no se cuentan contra el presupuesto de ninguna categoría.

**Solución:** Eliminar "No presupuestado" como opción inicial. Detectarlo automáticamente: si el gasto no tiene un `gastos_variables_base` en esa categoría, marcarlo internamente como no presupuestado y avisar al usuario: "Este gasto no estaba en tu plan. ¿Agregar $X a tu presupuesto de comida?"

---

### O5. Los gastos anteriores sugeridos no tienen indicador de recencia
**Problema:** La lista de gastos anteriores reutilizables carga todos los históricos del usuario. Un gasto de hace 8 meses aparece igual que uno de ayer. No hay orden por uso reciente ni indicador de cuándo fue la última vez.

**Impacto:** Media.

**Solución:** Mostrar máximo 5 gastos recientes (ordenados por `used_at` descendente). Agregar label "hace 2 días" o "ayer".

---

## CATEGORÍA P — CIERRE DE MES

### P1. El concepto "cierre de mes" es incomprensible para el usuario informal
**Problema:** La pantalla de cierre tiene un candado y dice "Cerrar [mes]". Para alguien que nunca ha hecho finanzas, "cerrar" suena a "perder acceso a los datos". Muchos nunca lo usan por miedo.

**Impacto:** Alta. El cierre activa análisis y comparaciones que el usuario nunca ve.

**Solución:** Renombrar a "Resumen de [mes]" o "Ver cómo te fue en [mes]". Agregar descripción: "Tu historial queda guardado. Puedes seguir editando después."

---

### P2. "Pagos pendientes" en el cierre no explica si el usuario realmente pagó o no
**Problema:** El paso 2 del wizard muestra N "pagos pendientes" — que son registros sin `pagado=1`. Pero el usuario no sabe si eso significa "ya lo pagué pero no lo marqué" o "realmente no lo pagué". El lenguaje crea pánico.

**Impacto:** Media.

**Solución:** Cambiar a "Gastos a confirmar: ¿Ya los pagaste?" con dos botones por ítem: "Sí, lo pagué" / "No, estaba pendiente". Lenguaje activo, no técnico.

---

### P3. El resumen del cierre no explica por qué el usuario gastó más de lo planeado
**Problema:** El resumen muestra estimado vs real pero solo con números. Si el real es mayor, el usuario ve el número en rojo pero no sabe en qué categoría se pasó ni en qué semana ocurrió.

**Impacto:** Alta. Sin este insight, el cierre de mes no sirve para mejorar el mes siguiente.

**Solución:** Bajo la tabla de comparación, agregar automáticamente: "Gastaste $X más de lo planeado. Fue principalmente en: [categoría 1] +$Y, [categoría 2] +$Z. El próximo mes podrías ajustar esas categorías."

---

## CATEGORÍA Q — PERFIL FINANCIERO / INGRESOS

### ⚠️ Q1. "Salario bruto mensual" es el campo más importante y el más confuso
**Estado:** PARCIAL — El editor de ingreso del perfil ya tiene título "¿Cuánto recibes?" + selector quincenal/mensual + el neto salario muestra equivalente quincenal. Añadido (2026-06): pista quincenal también en la rama no-salario (informal/ocasional) — "≈ $X por quincena · ingresa el total del mes". FALTA (decisión consciente, toca el motor de cálculo del ingreso base = crítico): permitir ingresar el monto POR QUINCENA y que la app multiplique ×2 internamente, en vez de pedir siempre el mensual. Requiere sesión enfocada con verificación cuidadosa (un error ×2 corrompe TODOS los cálculos).
**Problema:** Un usuario que cobra $600 quincenal piensa en "$600", no en "$1,200 mensual". Además, para trabajadores informales "bruto" no tiene significado claro. Muchos ingresan la mitad del valor real, haciendo que todo el presupuesto esté mal desde el inicio.

**Impacto:** Crítica. Si el ingreso base está mal, TODOS los cálculos están mal.

**Solución:** Cambiar la pregunta a "¿Cuánto recibes?" con dos opciones:
- "Cada quincena: $____" (para quincenal)
- "Cada mes: $____" (para mensual)
La app multiplica internamente. Nunca pedir "bruto" — pedir "lo que te llega a la mano o cuenta".

---

### Q2. La calculadora de deducciones panameñas usa porcentajes hardcodeados sin fecha
**Problema:** El switch "Calcular deducciones (Panamá)" aplica porcentajes fijos que pueden estar desactualizados. No hay fecha de vigencia visible ni advertencia de que son estimados.

**Impacto:** Media. Usuario confía en un cálculo potencialmente incorrecto.

**Solución:** Agregar fecha de vigencia visible: "Tasas CSS 2025 · Verificar con patrono". Agregar opción "Ingresar mis deducciones reales" con campos manuales.

---

## CATEGORÍA R — PATRIMONIO

### R1. El módulo de Patrimonio está desconectado del presupuesto
**Problema:** El patrimonio neto no tiene relación visible con el disponible mensual. Un usuario puede tener patrimonio positivo y disponible negativo sin que la app explique la diferencia entre tener dinero (patrimonio/stock) y flujo de dinero (presupuesto/flujo).

**Impacto:** Media. Genera confusión conceptual.

**Solución:** En la pantalla de patrimonio, agregar nota contextual: "Tu patrimonio es lo que tienes acumulado. Tu presupuesto mensual controla lo que entra y sale cada mes. Son dos vistas del mismo dinero."

---

### R2. Agregar un activo no explica para qué sirve registrarlo
**Problema:** El formulario de "nuevo activo" pide nombre, valor y tipo. El usuario no sabe si esto afecta su presupuesto, sus impuestos, o si es solo informativo. Sin contexto, el módulo queda sin uso.

**Impacto:** Media.

**Solución:** En el formulario de activo, agregar una línea: "Registrar tus activos te ayuda a ver tu salud financiera completa. No afecta tu presupuesto mensual."

---

## CATEGORÍA S — VENTAS / INGRESOS EXTRAS

### S1. El módulo "Ventas" confunde al usuario que solo quiere registrar un ingreso extra
**Problema:** La landing de Ventas tiene dos opciones: "Venta de productos" y "Servicios". Para alguien que hizo un trabajo extra o vendió algo usado, estas opciones suenan a "tengo un negocio formal". El flujo interno (catálogo, inventario, utilidad neta) es excesivo para el caso de uso más común.

**Impacto:** Media.

**Solución:** Agregar una tercera opción visible y simple: "Ingreso puntual (venta, trabajo, regalo)" que solo pide monto, descripción y fecha. Sin inventario ni catálogo.

---

## CATEGORÍA T — FLUJOS HUÉRFANOS (Sin siguiente paso claro)

### ✅ T1. Registrar un gasto "no presupuestado" no tiene continuidad
**Estado:** IMPLEMENTADO — Al guardar un gasto no_presupuestado (sin "guardar como base"), AgregarGastoSheet muestra un diálogo: "Registraste $X en [cat] que no estaba presupuestado. ¿Agregar al presupuesto?" Si acepta, llama convertirAVariable y confirma con snackbar.
**Problema:** El usuario registra un gasto fuera del presupuesto. Se guarda. No pasa nada más. No hay sugerencia de "¿Quieres ajustar tu presupuesto de esta categoría?" ni aviso de cuánto acumula en no-presupuestados este mes.

**Impacto:** Alta. El gasto queda como un punto ciego en el control financiero.

**Solución:** Al guardar un gasto no presupuestado, mostrar: "Registrado. Este mes llevas $X en gastos no planeados. ¿Quieres agregar $Y a tu presupuesto de [categoría]?"

---

### T2. Guardar un gasto como "variable base" no da confirmación ni enlace al resultado
**Problema:** Al activar "Guardar como gasto variable base" en el formulario y guardar, el usuario no ve ningún indicador de que el presupuesto base fue actualizado. No hay toast, no hay link al Tab Variables donde puede verificarlo.

**Impacto:** Media. El usuario guarda el mismo gasto base múltiples veces por duda.

**Solución:** Mostrar toast con link: "Agregado a tu presupuesto base · Ver presupuesto →"

---

---

## CATEGORÍA U — NAVEGACIÓN Y FLUJO GLOBAL

### ✅ U1. El FAB siempre registra en el mes ACTUAL aunque el usuario esté viendo un mes pasado
**Estado:** IMPLEMENTADO — FAB de HomeShell oculto en Tab 1 (MesDetalleScreen ya tiene el suyo con el mes correcto). AgregarGastoSheet ahora muestra badge "Registrando en: [Mes] [Año]" en el título.
**Problema:** Si el usuario navega a "Enero 2025" para revisar algo, y abre el FAB para agregar un gasto, el sheet se abre con mayo 2026 (mes actual), no con enero 2025 que estaba viendo. El gasto se guarda en el mes equivocado sin ningún aviso.

**Impacto:** Crítica. El usuario puede contaminar datos históricos sin saberlo.

**Solución:** Crear un concepto de "mes en contexto" que se pase al FAB. Cuando el usuario navega a un mes pasado, el FAB debe usar ese mes. Mostrar en el sheet: "Registrando en: Enero 2025" para que el usuario lo note.

---

### ✅ U2. Las alertas financieras existen pero el usuario nunca las ve
**Estado:** IMPLEMENTADO — (1) Badge rojo con conteo en pestaña "Mes actual" de HomeShell (`Badge.count` cargado desde getAlertas del mes activo). (2) Banner de alertas críticas (nivel danger) al tope del Tab Gastos con título + acción sugerida. (3) Ya existían en Tab Resumen y Dashboard. El motor de alertas (server.js _generarAlertasMes) ya estaba completo.
**Problema:** El sistema genera alertas (gastos altos, presupuesto excedido, deudas vencidas) pero solo aparecen como un banner pequeño en el Estado Financiero, que es una pantalla que muchos usuarios no visitan regularmente. En MesDetalleScreen, las alertas se cargan pero nunca se muestran en ningún tab.

**Impacto:** Alta. Las alertas son la forma en que la app responde proactivamente "¿por qué no te alcanza?" y nadie las ve.

**Solución:** Mostrar alertas en tres puntos:
1. Badge rojo en el tab "Mes actual" de HomeShell si hay alertas del mes activo
2. Banner al tope del Tab Gastos en MesDetalleScreen si hay alertas críticas
3. En Dashboard, la alerta más urgente como card prominente

---

### ✅ U3. main_menu.dart existe pero nunca se usa
**Estado:** IMPLEMENTADO — Verificado cero imports/instanciaciones de MainMenu en código activo (solo comentarios doc obsoletos). Archivo eliminado. Comentarios en main.dart y login_screen.dart actualizados de [MainMenu] a [HomeShell].
**Problema:** Hay una pantalla `main_menu.dart` con menú de módulos completo que no es la entrada real de la app. `home_shell.dart` es la entrada real. Las dos tienen lógica similar pero divergente, creando duplicidad de mantenimiento invisible.

**Impacto:** Media. Código muerto que confunde a quien trabaje en el proyecto.

**Solución:** Eliminar `main_menu.dart` o documentar explícitamente que es una pantalla de navegación secundaria (si se usa desde algún lugar específico).

---

### U4. El Dashboard duplica información del Estado Financiero sin agregar valor
**Problema:** El Dashboard muestra: ingreso, gastado, remanente, próximos pagos. El Estado Financiero muestra: exactamente lo mismo con más detalle. El usuario no sabe cuál es la "fuente de verdad" ni cuándo usar uno u otro.

**Impacto:** Media. Dos pantallas hacen lo mismo = confusión.

**Solución:** Diferenciar claramente sus roles:
- **Estado Financiero** = vista de planificación (estimados, proyecciones, 12 meses)
- **Dashboard** = vista de estado actual (hoy, esta quincena, alertas activas, acción inmediata)

---

### U5. No hay guía de "qué hacer primero" después del tutorial
**Problema:** El tutorial muestra los módulos de la app pero no guía al usuario hacia el flujo correcto: Perfil → Estado Anual → Mes actual. Muchos usuarios llegan al estado financiero vacío porque nunca llenaron el perfil.

**Impacto:** Alta para usuarios nuevos.

**Solución:** Después del tutorial, mostrar un checklist de setup de 3 pasos:
1. ✓ Crear perfil financiero (ingreso + gastos fijos)
2. ✗ Generar estado financiero anual
3. ✗ Registrar tu primer gasto del mes
Cada paso es un link directo. El checklist desaparece cuando los 3 están completos.

---

### U6. Módulos completamente desconectados del presupuesto personal
**Problema:** Los siguientes módulos existen como silos sin impacto visible en el presupuesto:
- **Compartido**: Los gastos compartidos no reducen el disponible personal
- **Patrimonio**: Los activos/pasivos no se actualizan desde gastos
- **Ventas**: Los ingresos por ventas no se suman al ingreso mensual
- **Facturas QR**: Las facturas escaneadas sin asignar no aparecen como pendientes en ningún resumen

**Impacto:** Alta. El usuario ve módulos que no conectan con su situación financiera real.

**Solución:** Para cada módulo, definir explícitamente cómo afecta el estado financiero y hacer esa conexión visible. Mínimo: un texto "Este gasto se registró en tu mes de mayo ✓" o "Esta venta no afecta tu presupuesto personal".

---

### U7. Refrescamiento de datos con flicker y pérdida de scroll
**Problema:** Casi todas las pantallas usan el patrón `.then((_) => _cargar())` cuando el usuario vuelve de una subpantalla. Esto recarga toda la pantalla, causa un flash visual, y resetea la posición del scroll. El usuario ve el contenido desaparecer y reaparecer cada vez que navega.

**Impacto:** Media. Afecta la percepción de fluidez y velocidad de la app.

**Solución:** A corto plazo: guardar y restaurar la posición del scroll después de `_cargar()`. A largo plazo: usar un sistema de estado reactivo (Provider) para que solo se actualicen los widgets que cambiaron.

---

## CATEGORÍA V — COHERENCIA DE DATOS Y CONFIABILIDAD

### ✅ V1. Categorías inconsistentes entre pantallas
**Estado:** IMPLEMENTADO — junto con O2. Lista canónica única en toda la app + migración con tabla de equivalencias (deuda→deudas, General→otro, Compartido→compartido, **otros→otro**). Esto reactiva el match presupuesto↔real del motor de alertas para categorías que antes no cuadraban.
**Fix QA 2026-06:** se detectó vía QA que `_marcarFijo`/`_marcarDeuda` escribían `'otros'` (plural) al marcar pagado un compromiso, fragmentando el envelope. Ahora usan `categoriaCanonicaCompromiso()` que prefiere `categoria`, luego el `tipo` del fijo si es canónico (transporte/servicios/vivienda…), si no 'otro'. Migración normaliza datos viejos.
**Problema:** (Ver también O2) El Tab Gastos muestra categorías en español minúscula (`alimentacion`, `ocio`). El Perfil Financiero usa otros nombres. El Tab Análisis puede mostrar categorías que no existen en el Perfil. El usuario ve "Tecnología $80" en análisis pero no puede encontrar ese gasto porque en el Perfil se llama diferente.

**Impacto:** Alta. El usuario no puede trazar sus gastos.

**Solución:** Una lista canónica de máximo 8 categorías, en español, con íconos, usada sin excepción en toda la app. Migrar registros existentes con una tabla de equivalencias.

---

### ✅ V2. Los totales del mes no siempre coinciden entre pantallas
**Estado:** RESUELTO (verificado QA) — Tras L1/Z1/AA1, gustitos/compartido/eventos crean `registros_gasto`, así que todo cuenta uniformemente. Verificado: `getMes` resumen (SUM por tipo en vivo) == `_actualizarTotalesMes` (mismas columnas) == Estado Anual (lee esas columnas + total_registrado = SUM de todos los registros). Añadido tooltip en el card "disponible" del Tab Resumen que documenta qué compone el total (fijos+deudas+variables+no presup+gustitos+compartido+eventos), construyendo confianza.
**Problema:** El total de gastos del mes puede verse diferente en: Dashboard, Tab Resumen de MesDetalle, y Estado Financiero Anual. Depende de si incluye Gustitos, gastos compartidos, o solo `registros_gasto`. El usuario ve números distintos y no sabe cuál es correcto.

**Impacto:** Alta. La desconfianza en los números hace que el usuario deje de usar la app.

**Solución:** Definir en un solo lugar qué compone el "total de gastos del mes" y documentarlo. Usar esa misma lógica en todas las pantallas. Mostrar un tooltip: "Este total incluye: gastos personales + deudas. No incluye: gustitos."

---

---

## CATEGORÍA W — ONBOARDING (Detalle de flujo y textos)

### ✅ W1. El paso de ingreso se puede saltar — la app queda sin base de cálculo
**Estado:** IMPLEMENTADO — Eliminado el botón "Saltar por ahora" del paso de ingreso (campo onSkip removido de _Paso1Income). Reemplazado por mensaje amable: "Necesitamos saber cuánto recibes... Puedes ajustarlo después."
**Problema:** El paso 1 (ingresos) tiene botón "Saltar por ahora". Si el usuario lo salta, llega al paso 5 sin ingreso y la app no puede generar el estado financiero. Muestra un error y le dice que vuelva al paso 1, pero el usuario ya está confundido.

**Impacto:** Crítica. El ingreso es la base de todo. Sin él, ningún cálculo funciona.

**Solución:** Eliminar "Saltar por ahora" del paso de ingresos. Hacerlo obligatorio con un mensaje amable: "Necesitamos saber cuánto recibes para mostrarte tu panorama financiero. Puedes ajustarlo después."

---

### W2. Los errores al guardar gastos variables se ignoran silenciosamente
**Problema:** En el paso 4 del onboarding, si el backend falla al guardar los gastos variables, el código captura el error con `catch (_) { _irSiguiente(); }` — avanza igual sin avisar al usuario. Los gastos no se guardaron, pero el paso 5 muestra un resumen como si todo estuviera bien.

**Impacto:** Alta. El usuario toma decisiones basadas en un resumen incompleto.

**Solución:** Cambiar el catch para mostrar un aviso: "No pudimos guardar algunos gastos. Puedes agregarlos desde tu perfil después." Y continuar, pero con el usuario informado.

---

### W3. Los montos sugeridos en variables están en dólares, no en balboas
**Problema:** El onboarding precompletea los gastos variables con montos sugeridos (`$300 supermercado`, `$100 transporte`) pero en Panamá la moneda es el balboa (B/.). La inconsistencia entre `$` y `B/.` a lo largo de la app genera confusión sobre si son la misma moneda.

**Impacto:** Media.

**Solución:** Usar `B/.` consistentemente en toda la app. Panamá usa dólares físicamente pero el símbolo oficial es B/. para precios nacionales.

---

### W4. La pregunta sobre gastos compartidos en el onboarding rompe el flujo
**Problema:** En el paso 2, si el usuario indica que sus gastos son compartidos, la app le dice "Usa Presupuesto Compartido en el menú principal" — pero el usuario está en el onboarding y no conoce el menú. El flujo queda interrumpido sin instrucción de qué hacer.

**Impacto:** Media.

**Solución:** Cambiar el mensaje a "Registra tu parte personal aquí. Después, en el menú, puedes coordinar gastos compartidos." No interrumpir el flujo.

---

### W5. El tutorial explica features, no cómo usarlos
**Problema:** El tutorial muestra slides con títulos y bullets: "El Estado Financiero es tu panorama anual". Pero no dice: qué hacer primero, cómo navegar a él, ni qué significa cada número. Es una presentación de marketing, no una guía de uso.

**Impacto:** Alta para usuarios nuevos sin experiencia financiera.

**Solución:** Convertir el tutorial en un flujo guiado de 3 pasos con ejemplos reales: "Imagina que ganas $1,000 al mes. Así se ve tu estado financiero..." con números en pantalla que el usuario puede tocar.

---

## CATEGORÍA X — ERRORES SILENCIOSOS Y CONFIABILIDAD

### X1. Múltiples lugares donde errores del backend se ignoran sin avisar al usuario
**Problema:** En varias partes del código se usa `catchError((_) {})` o `catch(_) {}` que tragan el error y continúan como si nada. El usuario no sabe que algo falló.

**Impacto:** Alta. El usuario ve datos incompletos y asume que la app está mal, no que hubo un error de red.

**Solución:** Definir un estándar: si un error es no-crítico, mostrar un snackbar discreto. Si es crítico (no se pudo guardar), mostrar error y opción de reintentar. Nunca ignorar silenciosamente.

---

### X2. Los correos en el split de gastos no se validan antes de enviar
**Problema:** El campo de correo en `SplitSection` acepta cualquier texto sin verificar que tenga formato de email. El backend puede rechazarlo, pero el error no llega al usuario de forma clara.

**Impacto:** Baja/Media.

**Solución:** Validar el formato de email en tiempo real con un ícono de check/warning al lado del campo.

---

### X3. La tasa de interés de deudas usa rangos genéricos sin guía de dónde encontrar el dato real
**Problema:** En el onboarding de deudas, los hints dicen "18–36% anual es típico". Pero para un usuario real que tiene una tarjeta de crédito BAC o Banistmo, el rango no ayuda a encontrar su tasa real.

**Impacto:** Media. Una tasa incorrecta hace que las proyecciones de deudas sean inútiles.

**Solución:** Agregar un botón "¿No sé mi tasa?" que abra un modal explicando: "Tu tasa TEA está en: tu estado de cuenta mensual, la app de tu banco, o llama al número detrás de tu tarjeta."

---

## CATEGORÍA Y — SELECTOR Y WIDGETS MENORES

### ✅ Y1. El selector de rango de meses usa flechas en lugar de etiquetas claras
**Estado:** YA RESUELTO — MesRangoSelector ya tiene labels explícitos "Desde"/"Hasta" en los dropdowns + header "PERÍODO DE VIGENCIA" + línea "Aplica de X a Y (N meses)" / "Aplica todo el año". La flecha es decorativa entre dos campos ya etiquetados.
**Problema:** El `MesRangoSelector` muestra `[Ene] → [Dic]` con flechas. Para un usuario sin experiencia financiera, no es claro si la flecha significa "desde/hasta" o si se puede seleccionar un rango no contiguo.

**Impacto:** Baja.

**Solución:** Cambiar a `Desde: [Ene ▼]   Hasta: [Dic ▼]` con etiquetas explícitas. Agregar bajo el selector: "Vigencia: 12 meses".

---

### Y2. El selector de categorías con scroll horizontal es difícil en pantallas pequeñas
**Problema:** 13 categorías en scroll horizontal significa que el usuario solo ve 4-5 a la vez y tiene que descubrir que puede hacer scroll. En pantallas pequeñas (<5") es especialmente difícil de usar.

**Impacto:** Media. La categoría es un campo de uso frecuente.

**Solución:** Cambiar a un grid de 3x4 (visible de golpe) o un dropdown agrupado. Las categorías más usadas (alimentación, transporte, vivienda) aparecen primero.

---

---

## CATEGORÍA Z — PRESUPUESTO COMPARTIDO (problemas específicos)

### ✅ Z1. Pagar tu parte en Compartido no crea registro en tu presupuesto personal
**Estado:** IMPLEMENTADO (previo) — `POST /shared-expenses/:id/confirm-payment` ya crea `registros_gasto` con `shared_expense_id` para el usuario confirmante. Migración de columna existe en server.js línea 533.
**Problema:** Cuando el usuario hace tap en "Pagar" dentro de un presupuesto compartido, se llama a `SharedBudgetService.confirmarMiParte()` que marca `mi_parte_pagada=1` en la tabla `shared_budget_expenses`. Pero nunca se crea un `registros_gasto` en el presupuesto personal. El usuario gastó dinero real (ej: pagó su 50% de la cena = $25) y eso no aparece en ningún lado en su mes de mayo.

**Impacto:** Alta. El dinero sale del bolsillo del usuario y la app no lo registra. El disponible mensual queda incorrecto.

**Solución:** Al confirmar `mi_parte_pagada`, crear automáticamente un `registros_gasto` con:
- `tipo='variable'`, `categoria='compartido'`
- `monto = mi_responsabilidad`
- `origen_compartido_id = shared_budget_expense_id` (nuevo campo para trazar origen)
- `nombre = descripcion_del_gasto`
Así el gasto aparece en el Tab Gastos del mes correspondiente.

---

### ✅ Z2. Los nombres de participantes se muestran como email antes del @
**Estado:** IMPLEMENTADO — Columna `display_name` en shared_budget_members (migración). Se captura del displayName de Google (AuthService.currentUser) al crear y al aceptar invitación. El SELECT de miembros lo devuelve. `_shortUid` en el detail consulta el display_name del miembro y hace fallback al email-antes-del-@.
**Problema:** En SharedBudgetDetailScreen, todos los participantes se muestran con `_shortUid(uid)` que hace `uid.split('@')[0]`. Si el email es `juan.rodriguez@gmail.com`, aparece como "juan.rodriguez". Nunca como "Juan Rodríguez" ni ningún nombre real.

**Impacto:** Media. La experiencia de "presupuesto con mi pareja" se degrada cuando no ves el nombre de la persona sino el inicio de su email.

**Solución:** Agregar un campo `display_name` en la tabla de miembros del shared budget, poblado al momento de aceptar la invitación con el `displayName` de Firebase. Mostrar ese nombre si existe, fallback al email corto.

---

### Z3. Los gastos compartidos no se pueden editar — solo eliminar
**Problema:** Si el usuario comete un error en el monto o descripción de un gasto compartido, solo puede swipe-to-delete y crear de nuevo. No hay formulario de edición. La eliminación es destructiva y no hay forma de corregir un error pequeño.

**Impacto:** Media. Genera fricción en el uso del módulo.

**Solución:** Agregar botón de edición (lápiz) en la tarjeta del gasto compartido que abra el mismo modal de "Agregar gasto" pero pre-llenado. Solo el creador del gasto o admin puede editar.

---

### Z4. Invitar a alguien requiere saber su email exacto — no hay link de invitación
**Problema:** La única forma de agregar a alguien a un presupuesto compartido es escribir su email completo. Si la persona no usa Salarying todavía, no funciona. Si el email tiene un error de tipeo, la invitación se pierde sin aviso.

**Impacto:** Media. Es una barrera de adopción real para el módulo más colaborativo de la app.

**Solución:** Generar un link de invitación único (ej: `salarying.app/invite/abc123`) que el usuario pueda compartir por WhatsApp, SMS, o email. Al abrir el link, el nuevo usuario se registra y queda asociado al presupuesto automáticamente.

---

## CATEGORÍA AA — EVENTOS (módulo desconectado)

### ✅ AA1. Los gastos de un evento no afectan el presupuesto mensual
**Estado:** IMPLEMENTADO — `POST /user/eventos/:id/gastos` ahora crea un `registros_gasto` vinculado (tipo='variable', categoria='eventos', origen_evento_id) fire-and-forget si el mes existe. `DELETE` elimina también el registro y recalcula totales+alertas. Migración `origen_evento_id` en registros_gasto.
**Problema:** `EventoDetalleScreen` permite registrar gastos en un evento (ej: vuelo $300 para las vacaciones). Estos gastos van a la tabla `eventos_gastos` o similar, pero no a `registros_gasto`. Cuando el usuario paga un gasto de vacaciones, eso no aparece en su mes de junio. Su disponible mensual no se reduce.

**Impacto:** Alta. El usuario puede gastar toda su "cuota de evento" en un mes y la app reporta ese mes como sano porque los datos están en silos distintos.

**Solución:** Al registrar un gasto en EventoDetalle, crear también un `registros_gasto` con `tipo='variable'`, `categoria='eventos'`, `origen_evento_id`. Así el gasto aparece en el mes correspondiente y reduce el disponible.

---

### ✅ AA2. La cuota mensual de un evento no se agrega automáticamente al perfil financiero
**Estado:** IMPLEMENTADO — El `remanente_estimado` de cada mes ahora resta la cuota mensual de eventos activos (`totalEventosMes`). Nuevo campo `eventos_estimados` en el resumen. Así el disponible estimado refleja que hay que separar dinero para el evento. (Parallelo estimado/real con AA1 que cubre el gasto real.)
**Problema:** El usuario crea un evento "Vacaciones julio" con presupuesto $600 en 3 meses. La app calcula `cuota_mensual = $200`. Pero esos $200 nunca aparecen en el estimado de gastos de los meses de mayo, junio y julio. El estado financiero no los ve.

**Impacto:** Alta. El usuario cree que tiene $500 disponibles en mayo cuando en realidad le quedan $300 (porque tiene que separar $200 para vacaciones).

**Solución:** Al crear un evento con cuota mensual, preguntar: "¿Quieres agregar esta cuota a tu presupuesto mensual?" Si confirma, crear un `gastos_variables_base` temporal con nombre del evento y monto de cuota, con fecha de fin = mes_fin del evento.

---

### ✅ AA3. La pantalla de Eventos no es accesible desde la navegación principal ni del tab Más
**Estado:** IMPLEMENTADO — Card "Eventos" agregada al grid de módulos del Tab Más en HomeShell (navega a EventosScreen con el año actual).
**Problema:** `EventosScreen` existe pero no tiene entrada en HomeShell ni en el grid del tab Más. El único acceso es desde `EstadoFinancieroAnualScreen` (donde se ve como opción de menú). El 90% de los usuarios nunca la descubre.

**Impacto:** Alta. Un módulo que nadie usa no sirve de nada, y este tiene potencial real para planificar gastos de eventos.

**Solución:** Agregar "Eventos" como card en el grid de módulos del tab Más de HomeShell, junto con Perfil, Ahorro, Calendario, etc.

---

## CATEGORÍA AB — BUGS DEL SISTEMA LEGADO (factura → gustito)

### ✅ AB1. CreateGustitoFromInvoiceScreen usa el sistema viejo de presupuestos — rota
**Estado:** IMPLEMENTADO — commits `392cff6` y `bc0417d` unificaron el flujo factura→gasto para usar `registros_gasto` directamente.

**Problema:** `CreateGustitoFromInvoiceScreen` llama a `/presupuestos?firebase_uid=...` para cargar una lista de presupuestos y pide al usuario seleccionar uno antes de crear el gustito. Este endpoint es del sistema viejo (`presupuestos` tabla). Si la tabla ya no tiene registros activos del usuario, la lista aparece vacía y el usuario no puede crear el gustito desde una factura QR.

**Impacto:** Crítica. El flujo "Escanear factura → Gustito" está roto para la mayoría de usuarios nuevos que nunca tuvieron presupuestos en el sistema viejo.

**Solución:** Reescribir `CreateGustitoFromInvoiceScreen` para que no requiera `budget_id`. Al crear un gustito desde factura, llamar directamente a `GustitosService.crear()` con los datos de la factura, sin dependencia del sistema viejo. Quitar el dropdown de "Presupuesto" que no tiene sentido en el contexto actual.

---

### ✅ AB2. CrearGustitoSheet requiere budget_id del sistema viejo como parámetro obligatorio
**Estado:** IMPLEMENTADO — `budgetId` ahora es `int?` opcional en `CrearGustitoSheet`. `GustitosService` reemplaza métodos viejos por `listar(uid)` usando `GET /gustitos`. Nueva `GustitosScreen` con lista y FAB para crear gustitos standalone. Card "Gustitos" agregada al Tab Más en HomeShell.

**Problema:** `CrearGustitoSheet.show()` recibe `required int budgetId`. Este campo se pasa a `GustitosService.crear({'budget_id': budgetId, ...})`. Si el gustito se crea desde un contexto donde no hay un `budget_id` real (ej: desde el tab Más, directamente), este valor es incorrecto o forzado. Crea un acoplamiento artificial con el sistema antiguo de presupuestos.

**Impacto:** Alta. Impide crear un gustito standalone sin un presupuesto del sistema viejo.

**Solución:** Hacer `budget_id` opcional en el servicio y en la tabla `gustitos`. Si no se pasa, el gustito queda como gasto personal sin presupuesto asociado. Los gustitos existen por sí mismos — no necesitan un presupuesto como contenedor.

---

## CATEGORÍA AC — PATRIMONIO (mejoras funcionales)

### AC1. Los pasivos del patrimonio son de solo lectura — no se pueden editar desde ahí
**Problema:** La sección "PASIVOS" de `PatrimonioScreen` muestra las deudas activas con `_PasivoTile` pero no tiene acciones (ni editar ni ir a deudas). El usuario ve su saldo de deuda pero no puede hacer nada al respecto sin salir de Patrimonio y navegar a DeudasScreen.

**Impacto:** Baja/Media. Inconsistencia: activos tienen botón de edición, pasivos no.

**Solución:** En cada `_PasivoTile`, agregar un botón "Ver deuda →" que navega a `DeudasScreen` o abre directamente el detalle de esa deuda.

---

### AC2. Los activos no tienen mecanismo para actualizar su valor con el tiempo
**Problema:** El usuario registra su carro con valor $12,000. Un año después sigue en $12,000 aunque valga $9,000. No hay recordatorio ni forma fácil de actualizar el valor de los activos. El patrimonio neto queda sobrevaluado indefinidamente.

**Impacto:** Media.

**Solución:** Agregar fecha de "última actualización" en cada activo. Si tiene más de 6 meses, mostrar un indicador amarillo: "Último valor: $12,000 · hace 8 meses · ¿Actualizar?" con botón directo al formulario de edición.

---

## CATEGORÍA AD — COHERENCIA VISUAL DEL TEMA OSCURO

### ✅ AD1. SelectTargetScreen usa colores raw que rompen el tema oscuro
**Estado:** IMPLEMENTADO — Reemplazados todos los Colors.*Accent/cyan/lime por colores de AppTheme (primary, info, colorAhorro, success, warning, colorNoFijo, textSecondary). Se hizo junto con M1 al reescribir la pantalla.
**Problema:** `select_target_screen.dart` usa colores hardcodeados: `Colors.blueAccent`, `Colors.purpleAccent`, `Colors.tealAccent`, `Colors.orangeAccent`, `Colors.cyan`, `Colors.lime`. Estos colores no están definidos en `AppTheme` y pueden verse muy distintos en algunos dispositivos. Rompe la paleta Binance-style del tema oscuro.

**Impacto:** Baja/Media. Visual inconsistente en una pantalla que se ve frecuentemente.

**Solución:** Mapear cada opción a un color de `AppTheme`:
- Gasto existente → `AppTheme.primary`
- Gasto nuevo → `AppTheme.info`
- Gustito → `AppTheme.colorAhorro`
- Compartido → `AppTheme.success`
- Operativo/Empresarial/Inventario → `AppTheme.warning`, `AppTheme.textSecondary`

---

*Última actualización: 2026-06-02 — Sesión Opus (extendida): +AA1, AA2, M1, AD1, Z2, M2. Total sesión: U1, Z1, C2, V1/O2, U2, K2, W1, T1, U3, O1, F1, AA3, I4, I1, E2, H3, H4, I3, Y1, H2, AA1, AA2, M1, AD1, Z2, M2 ✅; F3, F2 ⚠️. Leyenda: ✅ Implementado · ⚠️ Parcial · ❌ Pendiente*
