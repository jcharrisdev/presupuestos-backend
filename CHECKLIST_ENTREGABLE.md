# Checklist de entregable — Salarying
> Ejecutar **antes de cada commit + deploy**. No entregar si algún punto falla.

---

## 1. Código Flutter

### 1A. Sin errores de compilación
```bash
flutter analyze 2>&1 | grep "^error\|error -"
```
**Resultado esperado:** salida vacía (cero líneas).

### 1B. Sin imports no usados ni variables sin usar
```bash
flutter analyze 2>&1 | grep "warning -" | grep -v "withOpacity\|super_parameters\|deprecated"
```
**Resultado esperado:** salida vacía. Los `withOpacity` deprecados son ruido conocido — ignorar.

### 1C. Strings UI críticos presentes en el web build
```bash
grep -c "TEXTO_NUEVO_DEL_SPRINT" build/web/main.dart.js
```
**Resultado esperado:** número > 0. Si es 0, el build no incluye el cambio — reconstruir con `flutter build web --release`.

---

## 2. Backend

### 2A. Sin errores 500 en los logs tras el deploy
```bash
curl -s "https://presupuestos-backend-h3l6.onrender.com/logs?secret=salarying_logs_2025&limit=20&nivel=error"
```
**Resultado esperado:** `"total": 0` o errores previos al deploy actual (comparar `created_at`).

### 2B. Endpoint nuevo responde 200/201
```bash
curl -s -X [MÉTODO] "https://presupuestos-backend-h3l6.onrender.com/[RUTA]" \
  -H "Content-Type: application/json" \
  -d '{"firebase_uid":"jccharris55@gmail.com", ...}'
```
**Resultado esperado:** JSON con datos válidos, sin campo `"error"`.

### 2C. Endpoints críticos del núcleo financiero siguen respondiendo
```bash
# Estado anual
curl -s "https://presupuestos-backend-h3l6.onrender.com/user/estado-anual/2026?firebase_uid=jccharris55@gmail.com" | python -m json.tool | grep "existe"
# Mes actual
curl -s "https://presupuestos-backend-h3l6.onrender.com/user/meses/2026/5?firebase_uid=jccharris55@gmail.com" | python -m json.tool | grep "resumen"
# Gastos fijos
curl -s "https://presupuestos-backend-h3l6.onrender.com/user/gastos-fijos?firebase_uid=jccharris55@gmail.com" | python -m json.tool | grep "total_mensual"
```
**Resultado esperado:**
- Estado anual: `"existe": true`
- Mes: clave `"resumen"` presente
- Gastos fijos: clave `"total_mensual"` presente

### 2D. Columnas usadas en SQL nuevas realmente existen
Antes de usar `updated_at`, `nueva_columna`, etc. en un UPDATE/INSERT, verificar:
```bash
grep -n "ALTER TABLE.*ADD COLUMN.*nueva_columna\|CREATE TABLE.*nueva_columna" backend/server.js
```
**Resultado esperado:** la migración existe en server.js **antes** del endpoint que la usa. Si no existe, agregar la migración primero.

### 2E. Columnas Decimal de MySQL no usar con || directamente
```bash
# MySQL retorna Decimal como string "0.00" que es TRUTHY en JS.
# Nunca: Number(row.campo_decimal || row.otro)  → "0.00" es truthy, falla
# Siempre: Number(row.campo_decimal) || Number(row.otro)
grep -n 'Number(.*ingreso_real ||' backend/server.js
```
**Resultado esperado:** salida vacía (nunca el patrón raw `||` antes de Number).

### 2F. Reglas críticas de MySQL 5.6 respetadas
```bash
# No debe haber LIMIT ? en el código nuevo
grep -n "LIMIT ?" backend/server.js | tail -20
# No debe haber undefined en bind params del sprint actual
git diff HEAD~1 backend/server.js | grep "^\+" | grep -v "??" | grep "undefined"
```
**Resultado esperado:**
- `LIMIT ?`: cero líneas nuevas (usar `LIMIT ${parseInt(n)}`)
- `undefined` en params: cero líneas

---

## 3. Integridad del modelo financiero

### 3A. totalVarAnual respeta aplica_meses
```bash
# Crear variable temporal de $100 meses 6-10, forzar recalculo y verificar
curl -s -X PATCH "https://presupuestos-backend-h3l6.onrender.com/user/estado-anual/2026/recalcular" \
  -H "Content-Type: application/json" -d '{"firebase_uid":"jccharris55@gmail.com"}'
curl -s "https://presupuestos-backend-h3l6.onrender.com/user/estado-anual/2026?firebase_uid=jccharris55@gmail.com" \
  | python -m json.tool | grep "gastos_variables_anuales"
```
**Resultado esperado:** `"gastos_variables_anuales": "500.00"` (100 × 5 meses, no 100 × 12).

### 3B. Recálculo automático funciona tras cambio de perfil
Al crear/editar/eliminar un gasto fijo o variable, los estimados en `meses_financieros` deben actualizarse. Verificar llamando `GET /user/estado-anual` inmediatamente después del cambio.

### 3C. Registros de gasto actualizan totales del mes
```bash
# Después de POST /registros, el mes debe reflejar el nuevo monto
curl -s "https://presupuestos-backend-h3l6.onrender.com/user/meses/2026/5?firebase_uid=jccharris55@gmail.com" \
  | python -m json.tool | grep "variables_reales\|fijos_reales\|no_presupuestados"
```
**Resultado esperado:** los campos reales reflejan el gasto recién registrado.

---

## 4. Calendario

### 4A. Sin eventos duplicados para un mismo gasto
```bash
curl -s "https://presupuestos-backend-h3l6.onrender.com/calendario/eventos?firebase_uid=jccharris55@gmail.com&mes=5&anio=2026" \
  | python -m json.tool | grep -c "user_gasto_fijo_id"
```
**Resultado esperado:** igual al número de gastos fijos con día de pago (no el doble ni el triple).

### 4B. Gasto quincenal genera 2 eventos por mes
Si hay un gasto con `dia_pago=5` y `dia_pago_2=20`, el calendario debe mostrar ambos en cada mes.

---

## 5. Web build

### 5A. Build limpio antes de subir (SIEMPRE usar flutter clean)
```bash
flutter clean && flutter build web --release
```
**Resultado esperado:** `✓ Built build\web` sin errores.
**CRÍTICO:** nunca usar solo `flutter build web --release` — la caché incremental puede
no invalidar archivos modificados. `flutter clean` garantiza compilación desde cero.

### 5B. Strings del sprint en el build
```bash
grep -c "FRASE_NUEVA_DEL_SPRINT" build/web/main.dart.js
```
**Resultado esperado:** > 0.

### 5C. Push del build incluye los archivos correctos
```bash
git diff --name-only HEAD build/web/
```
**Resultado esperado:** `build/web/main.dart.js` y `build/web/flutter_service_worker.js` deben estar en el diff (si no cambiaron, el service worker no forzará recarga en el browser).

---

## 6. Deploy

### 6A. Orden de deploy siempre respetado
```
1. git add [archivos] + git commit + git push origin main
2. curl -X POST https://api.render.com/deploy/srv-d5kjem9r0fns73bfs23g?key=1s-LJtjaam4
3. flutter build web --release
4. git add -f build/web + git commit + git push  (Vercel auto-despliega)
```
**Nunca** subir el web build antes que el backend — el frontend puede llamar endpoints que aún no existen.

### 6B. Backend respondiendo después del deploy
```bash
until curl -sf "https://presupuestos-backend-h3l6.onrender.com/logs?secret=salarying_logs_2025&limit=1" > /dev/null; do sleep 5; done && echo "listo"
```
**Resultado esperado:** `listo` (el servidor está vivo y respondiendo).

### 6C. Verificar con curl el endpoint nuevo después del deploy
No asumir que funcionó porque no hubo error de compilación. Siempre hacer al menos una llamada real al endpoint nuevo post-deploy.

---

## 7. Módulos protegidos

### 7A. Módulo Ventas intacto
```bash
git diff HEAD~1 -- lib/ventas_landing_screen.dart lib/venta_detalle.dart lib/produccion_detalle.dart lib/servicios/
```
**Resultado esperado:** salida vacía (ningún archivo del módulo Ventas modificado).

---

## Resumen rápido (pre-commit)

| # | Check | Comando rápido |
|---|-------|----------------|
| 1 | Flutter sin errores | `flutter analyze 2>&1 \| grep "^error"` → vacío |
| 2 | Columnas SQL existen | buscar migración en server.js antes del endpoint |
| 3 | No hay `LIMIT ?` nuevo | `git diff HEAD~1 backend/server.js \| grep "^\+" \| grep "LIMIT ?"` → vacío |
| 4 | Backend vivo post-deploy | `curl -sf .../logs?secret=...` → 200 |
| 5 | Endpoint nuevo responde | curl directo al endpoint → sin campo `"error"` |
| 6 | Strings en web build | `grep -c "frase" build/web/main.dart.js` → > 0 |
| 7 | Ventas intacto | `git diff HEAD~1 -- lib/ventas_*` → vacío |
