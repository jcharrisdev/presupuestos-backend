# Lecciones aprendidas — Salarying

> Catálogo de errores reales, su causa raíz y la regla que previene que vuelvan a ocurrir.
> Añadir una entrada cada vez que se cometa un error nuevo o se corrija un bug no trivial.

---

## Sesión 2026-05-20 — Módulo deudas + quincenal + 4 features nuevas

---

### L-01: Deploy sin commit — el más recurrente

**Error:** Se hacía `curl` al deploy hook de Render sin haber commiteado ni pusheado los cambios. El usuario no veía ningún cambio.

**Causa raíz:** Render despliega desde el repositorio git, no desde el disco local. Sin `git push`, Render no tiene los nuevos archivos.

**Fix aplicado:** Siempre secuencia completa: `flutter clean → build web → git add → git commit → git push → curl deploy`.

**Regla:** Nunca hacer trigger de Render sin antes hacer push. El deploy hook es el último paso, no el único.

---

### L-02: Campo visible en UI pero no guardado en el body

**Error:** Se movió el campo de tasa de interés fuera del bloque `if (!_esLetra)` para que siempre se viera, pero se olvidó mover la lógica de guardado. El campo mostraba el valor pero al guardar, `tasa_interes` nunca entraba al `body` del PUT.

**Causa raíz:** El developer (Claude) razonó solo sobre el UI, no sobre el flujo completo.

**Fix aplicado:** Mover `const tasa = double.tryParse(_tasaCtrl.text)` y `body['tasa_interes'] = tasa` fuera del bloque condicional también.

**Regla:** Cuando se mueve un campo de UI fuera de un condicional, buscar y mover también: (1) el estado inicial del controller, (2) la validación, (3) la asignación al body de guardado. Son tres lugares distintos.

---

### L-03: Endpoint ya existía — trabajo duplicado evitable

**Error:** Se planificó crear `PUT /deudas/:id` para edición de deudas, pero ese endpoint YA existía desde el inicio. También `DeudasService.editar()` ya existía en Flutter. Solo faltaba la UI.

**Causa raíz:** No se exploró el código existente antes de planificar.

**Fix:** Siempre explorar antes de planificar. El endpoint puede ya existir. La tarea puede ser solo UI.

**Regla:** Antes de decir "hay que crear el endpoint X", buscar `app.put('/${recurso}'` y `app.patch` en `server.js`.

---

### L-04: FAB global de HomeShell solapaba FAB interno de DeudasScreen

**Error:** `HomeShell` tiene un FAB global visible en todos los tabs excepto el tab "Más" (`_idx != 3`). Cuando el usuario estaba en el tab Deudas (idx=2), el FAB global abría `AgregarGastoSheet` en vez del FAB propio de `DeudasScreen` que abría `CrearDeudaSheet`.

**Causa raíz:** No se consideró que `HomeShell` tiene su propio FAB que compite con el de las pantallas internas.

**Fix:** Cambiar condición a `_idx != 2 && _idx != 3` en `home_shell.dart`.

**Regla:** Cuando una pantalla interna tiene su propio FAB, revisar si `HomeShell` (o el widget padre) también inyecta un FAB en ese índice. Los Scaffolds anidados pueden interferir.

---

### L-05: Widget visual sin handler — "Completar info" chip inerte

**Error:** El chip "Completar info" se veía, tenía ícono de editar, pero no hacía nada al tocarlo. No tenía `GestureDetector` ni `onTap`.

**Causa raíz:** Se copió la estructura visual de otro chip sin conectar la lógica.

**Fix:** Envolver en `_TappableMiniTag` con `onTap: onEditar`.

**Regla:** Todo elemento con apariencia de botón o acción necesita un handler. Si se ve clickeable, debe funcionar. Revisar antes de hacer commit.

---

### L-06: compromisos_quincenal en API pero no renderizado en Flutter

**Error:** Se agregó `compromisos_quincenal` al response del endpoint `GET /user/quincena/...` pero `_QuincenaCard` en Flutter nunca lo leía. La vista quincenal aparecía vacía aunque el API devolviera datos.

**Causa raíz:** Se implementó backend y frontend por separado sin trazar el consumo completo del dato.

**Fix:** Agregar `final compromisos = (data['compromisos_quincenal'] as List? ?? [])` y renderizar la sección "COMPROMISOS DEL MES" en `_QuincenaCard`.

**Regla:** Cuando se agrega un campo nuevo a una respuesta del API, rastrear hasta el widget Flutter que consume esa respuesta y verificar que el campo se usa. El backend y el frontend son dos extremos del mismo flujo.

---

### L-07: `const` declarado dentro de `res.json({})` — error de sintaxis JavaScript

**Error:** Se intentó declarar `const hormigaRegistros = ...` dentro del objeto literal `res.json({ resumen: { const ...: } })`. Error de sintaxis en Node.js.

**Causa raíz:** Confusión entre bloque de código y objeto literal.

**Fix:** Declarar las variables antes del `res.json({})`:
```javascript
const hormigaRegistros = registros.filter(...);
res.json({ resumen: { hormiga_count: hormigaRegistros.length } });
```

**Regla:** En JavaScript no se pueden declarar variables dentro de un objeto literal. Siempre declararlas en el scope del bloque antes de la llamada.

---

### L-08: Enum Dart con guión bajo — error de convención

**Error:** Se definió `enum TipoDivision { partes_iguales, por_porcentaje }`. Dart requiere lowerCamelCase para enum values.

**Fix:** `enum TipoDivision { partesIguales, porPorcentaje }` y reemplazar todas las referencias.

**Regla:** En Dart, enum values van en `lowerCamelCase`. Clases en `UpperCamelCase`. Constantes y variables en `lowerCamelCase`.

---

### L-09: Clase referenciada antes de ser definida sin existir

**Error:** Se usó `_SplitRow()` en la declaración de estado de un widget antes de haber definido la clase `_SplitRow`. Dart reportó error de tipo desconocido.

**Fix:** Agregar la clase al final del archivo antes de intentar compilar, o verificar que existe antes de referenciarla.

**Regla:** Dart permite forward references en el mismo archivo (no como en algunos otros lenguajes), pero la clase debe existir en algún lugar del mismo library. Si no existe, el error es inmediato en compilación.

---

### L-10: Vista quincenal vacía — causa raíz múltiple

**Error:** El usuario no veía sus gastos en la vista quincenal. Tenía tres causas simultáneas:
1. `compromisos_quincenal` no se renderizaba (L-06)
2. Los gastos históricos tenían fecha en día 1 → solo aparecían en Q1
3. La lógica de día 15 = "ambas quincenas" no estaba implementada

**Fix en cascada:**
1. Renderizar `compromisos_quincenal` en `_QuincenaCard`
2. Migración: `UPDATE registros_gasto SET fecha = DATE_FORMAT(fecha, '%Y-%m-15') WHERE DAY(fecha) != 15`
3. Backend: gastos con `DAY(fecha) = 15` → aparecen en Q1 y Q2 al 50%

**Regla:** Cuando una vista aparece vacía, siempre investigar en este orden:
1. ¿El API devuelve datos? (verificar con logs o directamente)
2. ¿El Flutter consume ese campo del response?
3. ¿La query SQL devuelve los registros correctos?
4. ¿Los datos en BD tienen el valor esperado?

---

### L-11: Datos en BD con fecha día 1 — defaulteo incorrecto

**Error:** `agregar_gasto_sheet.dart` para meses pasados defaulteaba `DateTime(anio, mes, 1)`. Todos los gastos de meses anteriores quedaban en día 1 → Q1 únicamente → Q2 siempre vacía.

**Fix:** Cambiar default a `DateTime(anio, mes, 15)` para meses pasados. Para el mes actual, mantener `DateTime.now()`.

**Regla:** Los defaults de fechas importan. Un default de "día 1" convierte todos los gastos en Q1-only. El default correcto para "sin preferencia quincenal" es día 15.

---

### L-12: Migration corrió pero tabla ya tenía los datos correctos

**Situación:** Se corrió una segunda migración para mover todos los registros al día 15, pero la primera migración (día 1 → día 15) ya había movido todos. La segunda migración encontró `affectedRows = 0`.

**Lección:** Las migraciones idempotentes son buenas. Pero hay que verificar que los datos realmente están como esperamos antes de asumir que una migración resolvió el problema. La raíz del problema quincenal era L-06, no los datos.

---

### L-13: Onboarding asumía empleo formal — usuarios informales excluidos

**Error:** Heading "¿Cuánto ganas?" + opción "Salario fijo" primero + default `_tipoIngreso = 'salario'`. Usuarios con ingresos informales (negocio, freelance, alquiler) no se sentían representados.

**Fix:** 
- Heading: "¿Cuánto recibes al mes?"
- Subtítulo: mencionar negocio, freelance, alquiler, remesas
- Default: `'informal'`
- Orden: "Ingreso propio" primero, "Empleo formal" segundo

**Regla:** En Latinoamérica la economía informal es dominante. Nunca asumir que el usuario tiene empleo formal en planilla. Todos los textos de ingresos deben ser inclusivos por defecto.

---

### L-14: Split UI con monto manual — UX incorrecto

**Error:** El primer diseño del split pedía que el usuario ingresara manualmente el monto de cada participante. Esto es innecesario y propenso a errores — si el total es $60 y hay 3 personas, el usuario tiene que calcular $20 en su cabeza.

**Fix:** Reemplazar campo de monto por selector de tipo de división ("Partes iguales" o "Por porcentaje") y calcular automáticamente.

**Regla:** Si la app puede calcular algo que el usuario tiene que calcular manualmente, la app debe calcularlo. Reducir fricción siempre.

---

---

### L-15: `new Date(fecha).getUTCDate()` — bug de timezone en Node.js con MySQL2

**Error:** Se usó `new Date(r.fecha).getUTCDate()` para extraer el día de una fecha. MySQL2 devuelve columnas `DATE` como objetos JavaScript Date creados en hora local del servidor. Si el servidor Render no está en UTC, `getUTCDate()` puede devolver el día anterior (ej: día 15 → 14), haciendo que el filtro de quincena fuera incorrecto. Los gastos del día 15 no aparecían en Q2.

**Causa raíz:** `getUTCDate()` lee en UTC, pero el objeto Date fue creado con hora local del servidor. Con timezone UTC+X, medianoche local = hora anterior en UTC = día anterior.

**Fix aplicado:** Usar `DAY(rg.fecha)` directamente en el `SELECT` SQL y leer `r.dia_fecha` en JavaScript. MySQL calcula el día en el contexto de la base de datos, sin ningún parsing JS.
```javascript
// MAL — bug de timezone
const d = new Date(r.fecha).getUTCDate();

// BIEN — MySQL extrae el día directamente
SELECT rg.*, DAY(rg.fecha) AS dia_fecha FROM registros_gasto rg ...
const d = Number(r.dia_fecha);
```

**Regla:** Nunca usar `new Date(mysqlDate).getUTCDate()` para comparar días. Siempre extraer el día en SQL con `DAY(fecha)` o `DAYOFMONTH(fecha)`. Aplica también a `MONTH()`, `YEAR()`, `HOUR()`.

---

### L-16: Pantalla vacía sin mensaje de error — imposible diagnosticar

**Error:** Cuando el endpoint `/user/quincena/:anio/:mes/:num` devolvía 404 (mes sin estado financiero) o 500 (error JS), el Flutter atrapaba silenciosamente con `catch (_) {}` y dejaba `_q1 = null`. La vista mostraba una pantalla completamente vacía sin ninguna indicación de qué falló. El usuario interpretaba que sus datos no existían.

**Causa raíz:** Manejo de errores demasiado silencioso. `catch (_)` descarta toda información útil.

**Fix aplicado:**
- Capturar el mensaje de error del API (`jsonDecode(r1.body)['error']`)
- Mostrar un widget explicativo cuando `statusCode != 200`
- Botón "Reintentar" visible
- Mensaje específico: "Este mes no tiene estado financiero generado aún. Ve a Estado y genera el estado anual."

**Regla:** Todo estado de carga/error en Flutter debe tener tres variantes visuales: loading, success, error. Nunca usar `catch (_) {}` que descarte errores en vistas que el usuario ve directamente. El error visible es siempre mejor que el silencio.

---

### L-17: Múltiples fixes acumulados sobre el mismo bug — efecto "Whack-a-Mole"

**Situación:** El bug de "vista quincenal vacía" recibió 5 fixes distintos en la misma sesión:
1. Fecha por defecto día 15 en meses pasados
2. Migración día 1 → día 15 (solo día 1)
3. Lógica de día 15 = ambas quincenas en backend JS
4. `compromisos_quincenal` no renderizado en Flutter
5. `DAY()` SQL en vez de `new Date().getUTCDate()`

Solo el fix 4 y el fix 5 eran el problema real. Los fixes 1, 2, 3 atacaban síntomas secundarios.

**Causa raíz:** Se empezó a implementar soluciones antes de diagnosticar completamente la causa raíz. Cada fix nuevo creaba la ilusión de progreso sin resolver el problema core.

**Regla:** Antes de escribir código para un bug reportado como "no veo X", hacer estas preguntas en orden:
1. ¿El API devuelve datos? (revisar con logs del servidor)
2. ¿El Flutter recibe y procesa esos datos? (trazar el response hasta el widget)
3. ¿Los datos en BD tienen los valores esperados?
4. Solo entonces: ¿hay un bug de lógica?

No pasar al siguiente punto sin confirmar el anterior.

---

## Patrones que funcionan bien (mantenerlos)

- **Widget reutilizable**: cuando un feature se necesita en 2+ pantallas, extraer a `lib/widgets/financiero/`. Ejemplo: `SplitSection`.
- **GlobalKey para acceder al estado de widgets hijos**: `final _splitKey = GlobalKey<SplitSectionState>()` para leer datos del split en `_guardar()`.
- **Migración idempotente en `initDB()`**: `ALTER TABLE ... ADD COLUMN ...` con `.catch(() => {})` — se puede reejecutar sin errores.
- **Auto-detección en backend**: calcular `es_hormiga` en el POST del servidor, no en el cliente. La lógica de negocio vive en el servidor.
- **Brevo API reutilizable**: hay al menos 3 funciones que envían emails. Siempre reutilizar el patrón de `sendInvitationEmail` para nuevas notificaciones.
