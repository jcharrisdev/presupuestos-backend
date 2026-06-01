# Skill: salarying-mejoras

## Propósito
Gestionar el estado de mejoras del proyecto Salarying usando `SALARYING_MEJORAS.md` como fuente de verdad persistente entre sesiones.

## Cuándo se activa
- Al inicio de CADA sesión de trabajo en Salarying
- Al terminar CUALQUIER tarea, mejora, fix o paquete

---

## Regla 1 — Lectura obligatoria al inicio de sesión

Al iniciar una sesión, ejecutar:
1. Leer `SALARYING_MEJORAS.md` completo
2. Identificar los estados: ✅ implementado · ⚠️ parcial · ❌ pendiente
3. Reportar al usuario en formato conciso:
   - Cuántos ítems ✅ / ⚠️ / ❌ hay en total
   - Si hay algún ítem marcado como "discutido pero no implementado" resaltarlo
4. NO proponer implementar algo que ya esté ✅

---

## Regla 2 — Actualización obligatoria al terminar una tarea

Después de cada commit + push + deploy exitoso:
1. Abrir `SALARYING_MEJORAS.md`
2. Localizar el ítem(s) que corresponden a lo implementado
3. Cambiar su encabezado a `### ✅ [título]` o `### ⚠️ [título]`
4. Agregar línea de estado:
   ```
   **Estado:** IMPLEMENTADO — [descripción de lo que se hizo] (commit `[hash]`)
   ```
5. Si el ítem no existe en el archivo, agregarlo con ✅ en la categoría correcta
6. Actualizar la fecha al pie: `*Última actualización: YYYY-MM-DD — [descripción]*`
7. Esta edición va en el mismo commit del paquete

---

## Formato de estado en SALARYING_MEJORAS.md

```markdown
### ✅ A1. Título del ítem
**Estado:** IMPLEMENTADO — descripción breve (commit `abc1234`)
[resto del contenido original...]

### ⚠️ B1. Título del ítem  
**Estado:** PARCIAL — qué se hizo / qué falta
[resto del contenido original...]

### ❌ B3. Título del ítem
**Estado:** PENDIENTE — [opcional: discutido con usuario, detalles]
[resto del contenido original...]
```

---

## Referencia rápida de categorías en SALARYING_MEJORAS.md

| Categoría | Tema |
|-----------|------|
| A | Envelope tracking |
| B | Quincenas funcionales |
| C | Dashboard |
| D | Navegación y flujos |
| E | Información faltante |
| F | Visual y UX |
| G | Coherencia financiera (requieren aprobación) |
| H | Onboarding |
| I | Deudas |
| J | Calendario |
| K | Estado financiero anual |
| L | Gustitos |
| M | Facturas QR |
| N | Perfil financiero |
| O | Formulario de gastos |
| P | Cierre de mes |
| Q | Ingresos |
| R | Patrimonio |
| S | Ventas |
| T | Flujos huérfanos |
| U | Navegación global |
| V | Coherencia de datos |
| W-X | Onboarding detallado / Errores silenciosos |
| Y | Widgets menores |
| Z | Presupuesto compartido |
| AA | Eventos |
| AB | Bugs sistema legado (Gustitos/Facturas) |
| AC | Patrimonio funcional |
| AD | Tema oscuro |
