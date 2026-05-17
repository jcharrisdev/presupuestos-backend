# Salarying — Visión completa, flujo y arquitectura funcional

> Documento de referencia para desarrollo. Todo cambio en la app debe estar alineado con esta visión.
> Última actualización: 2026-05-17

---

## Principio central

> El presupuesto no es el punto de partida. El presupuesto es consecuencia del estado financiero del usuario.

El usuario no crea presupuestos sueltos. El usuario configura su realidad financiera y la app genera todo lo demás automáticamente. Nada en Salarying existe aislado — cada módulo alimenta al siguiente.

**Flujo maestro:**
```
Perfil financiero
    → Estado financiero anual (auto-generado)
        → 12 meses proyectados
            → Registros reales mes a mes
                → Análisis de desviación
                    → Alertas y recomendaciones
                        → Cierre anual → proyección siguiente año
```

---

## Módulo 1: Perfil Financiero

### Propósito
Es el punto de entrada obligatorio. Sin perfil no hay estado financiero, sin estado financiero no hay nada. Es la única fuente de verdad sobre la realidad financiera base del usuario.

### Ingresos
El usuario registra cuánto recibe neto. Si es asalariado en Panamá, puede ingresar el bruto y la app descuenta:
- CSS: 9.75%
- Fondo Educativo: 1.25%
- ISR según tabla
- Otros descuentos personalizados

Frecuencia de cobro: mensual o quincenal. La app convierte todo a equivalente mensual para los cálculos.

*Ejemplo:* Juan gana $1,800 bruto. La app calcula $1,602/mes neto. Todo el sistema trabaja sobre $1,602, no $1,800.

### Gastos Fijos
Compromisos que ocurren cada mes con monto conocido. Pueden ser:
- **Propios**: alquiler, servicios, internet, seguro
- **Deudas vinculadas**: cuota de préstamo, tarjeta — aparecen aquí pero se gestionan en el módulo de deudas

Cada gasto fijo puede tener:
- Día de pago 1 (ej: día 5) → genera evento en calendario
- Día de pago 2 (ej: día 20) → para pagos quincenales, genera segundo evento
- Recordatorio activado/desactivado

*Ejemplo:* María paga el carro los días 15 y 30. Registra día_pago=15, dia_pago_2=30. El calendario muestra ambos eventos cada mes.

### Gastos Variables Base
Gastos esperados pero de monto variable. Son el presupuesto estimado por categoría.

Campos clave:
- Nombre y categoría
- Monto estimado
- Frecuencia (mensual, quincenal, semanal, anual → se convierte a mensual)
- **Período de vigencia**: mes_inicio y mes_fin (aplica_meses)
- Categoría personalizada si no encaja en las predefinidas

*Ejemplo 1:* "Supermercado" $350 todos los meses (mes 1-12).
*Ejemplo 2:* "Útiles escolares" $120 solo en enero y septiembre (mes 1 y 9).
*Ejemplo 3:* "Gasolina vacaciones" $200 de junio a agosto (mes 6-8).

El período de vigencia es crítico: evita que gastos estacionales inflen el presupuesto de meses donde no aplican.

### Deudas en el Perfil
Las deudas activas aparecen automáticamente como compromisos fijos. No se duplican — se vinculan. La cuota de cada deuda suma al total de fijos estimados del mes.

---

## Módulo 2: Estado Financiero Anual

### Propósito
Auto-generado al completar el perfil. Proyecta los 12 meses del año mostrando cuánto entra, cuánto se compromete y cuánto queda — todo antes de que suceda.

### Cómo se genera
1. Toma ingreso neto mensual del perfil
2. Calcula fijos totales (gastos fijos + cuotas de deudas activas)
3. Por cada mes, calcula variables que aplican (respetando aplica_meses)
4. Crea 12 registros en `meses_financieros` con estimados

### Recálculo automático
Cada vez que el usuario edita el perfil (agrega/modifica/elimina gasto fijo, variable base o deuda), el estado anual recalcula automáticamente todos los meses afectados. El usuario siempre ve números actualizados sin hacer nada manual.

### Vista
- Tarjeta anual: ingreso total estimado vs real acumulado, gastos totales estimados vs reales
- Grid de 12 meses: cada celda muestra mes, remanente estimado o real si ya pasó
- Mes actual marcado con indicador "HOY"
- Meses con remanente negativo en rojo

*Ejemplo:* Carlos ve en marzo que junio tendrá remanente negativo porque coinciden vacaciones + seguro anual. Tiene 3 meses para prepararse o ajustar.

---

## Módulo 3: Detalle de Mes

### Propósito
Permite al usuario ver y registrar la realidad de un mes específico, comparando contra lo planeado.

### Tab Resumen
Tabla estimado vs real:
- Ingreso: $1,400 est / $1,400 real
- Gastos fijos: $800 est / $820 real → +$20
- Gastos variables: $300 est / $380 real → +$80
- No presupuestados: $0 / $45
- **Remanente: $300 est / $155 real**

Barra de uso del ingreso (verde <70%, amarillo 70-90%, rojo >90%).

Sección **Compromisos del mes**: lista de gastos fijos y deudas activas con monto y días de pago.

### Tab Gastos
Lista completa de registros del mes. Cada registro puede:
- Marcarse como pagado/pendiente
- Convertirse en variable base (si es no-presupuestado que se repite)
- Eliminarse

### Tab Análisis
Por categoría: presupuestado vs real, barra de progreso, % de desviación.
*Ejemplo:* Alimentación: $300 presup / $420 real → barra 140% en rojo. El usuario sabe exactamente dónde se fue el dinero.

### Agregar gastos
3 tipos con significados distintos:

| Tipo | Cuándo usarlo | Impacto |
|------|--------------|---------|
| **Fijo** | Pagar algo ya comprometido (alquiler, carro) | Reduce fijos_reales |
| **Variable** | Gasto esperado de una categoría (supermercado) | Reduce variables_reales |
| **No presupuestado** | Algo que no estaba en el plan (emergencia médica, regalo) | Suma a no_presupuestados_reales |

La clasificación importa para el análisis y las alertas. Un no-presupuestado que se repite 3 meses debe convertirse en presupuesto.

---

## Módulo 4: Gastos Reutilizables (a implementar — Fase 2)

### Propósito
Los gastos no deben reescribirse cada mes. Deben existir como plantillas reutilizables.

### Separación conceptual

**Definición del gasto** (plantilla):
- Nombre: "Jumbo"
- Categoría: Alimentación
- Tipo habitual: Variable

**Instancia mensual** (uso real):
- Jumbo en enero: $80
- Jumbo en febrero: $95
- Jumbo en marzo: $70

### Selector de gastos existentes
En cualquier formulario de agregar gasto, el usuario ve un desplegable con todos sus gastos previos. Al seleccionar uno, se pre-llena nombre, categoría y último monto usado. Solo ajusta el monto del mes actual.

### Eliminación controlada
Al eliminar un gasto recurrente, la app pregunta:
1. Eliminar solo este mes
2. Eliminar desde este mes en adelante
3. Eliminar los próximos X meses
4. Eliminar para todo el año
5. Desactivar sin borrar historial

*Ejemplo:* El usuario cancela Netflix en octubre. La app pregunta: ¿Solo octubre o desde octubre en adelante? Si elige "en adelante", los meses noviembre y diciembre ya no tienen ese gasto.

### Edición controlada
Al editar un gasto recurrente:
1. Editar solo este mes
2. Editar desde este mes en adelante
3. Editar todos los meses
4. Editar los próximos X meses

---

## Módulo 5: Deudas

### Propósito
Gestión completa de compromisos financieros con terceros. Integrado con el estado financiero — cada deuda activa impacta el disponible real del usuario.

### Tipo 1: Deuda revolving
Para créditos con saldo variable: tarjetas de crédito, préstamos personales, préstamos bancarios.

Campos: saldo pendiente, tasa de interés mensual, pago mínimo, fecha próximo pago.

Funcionalidades:
- Registro de abonos (reduce saldo pendiente)
- Proyección de liquidación con pago mínimo vs con abono extra
- Estrategia avalancha (mayor tasa primero — ahorra más en intereses)
- Estrategia bola de nieve (menor saldo primero — motivación psicológica)

*Ejemplo:* Luis tiene tarjeta con $2,500 al 3.5%/mes, pago mínimo $75. Con solo el mínimo: 58 meses, $1,850 en intereses. Con $150/mes extra: 14 meses, ahorra $1,200. La app muestra ambos escenarios y Luis decide.

### Tipo 2: Compra a letra (es_letra = true)
Para compras a plazo con cuota fija conocida: electrodomésticos, muebles, electrónicos, préstamos de cuota fija.

Campos: cuota fija mensual, número total de cuotas, cuotas pagadas, nombre del acreedor.

*Ejemplo:* Ana compró un televisor en 24 cuotas de $85. La app sabe que en 16 meses ese compromiso desaparece y su disponible sube $85/mes. Se lo muestra en la proyección anual.

### Campos avanzados para ambos tipos
- `mes_inicio_pago`: desde qué mes del año afecta el presupuesto
- `dia_pago` + `dia_pago_2`: para pagos quincenales, genera dos eventos en el calendario
- `nombre_acreedor`: a quién se le debe

*Ejemplo:* Pedro compra un laptop en agosto a 12 cuotas. `mes_inicio_pago = 8`. La app solo incluye esa deuda en el estado financiero de agosto en adelante, no en enero-julio.

---

## Módulo 6: Presupuestos de Eventos (a refinar — Fase 2)

### Propósito
Para gastos extraordinarios con inicio y fin: vacaciones, bodas, cumpleaños, proyectos familiares, compras grandes. Se separan del flujo cotidiano pero salen del remanente del estado financiero.

### Conexión con el estado financiero
Un presupuesto de evento NO existe aislado. Si el usuario tiene remanente mensual de $300 y crea un evento de $100 para un cumpleaños en mayo, ese $100 se descuenta del remanente de mayo.

Opciones al crear:
- Financiado desde el remanente mensual
- Financiado por cuotas durante varios meses
- Compartido entre varias personas
- Si es compartido, usar tipos de distribución

*Ejemplo:* Familia planea vacaciones de $1,200 en julio. Lo distribuyen en 4 meses (abril-julio) de $300/mes. La app descuenta $300/mes del remanente durante esos meses. El estado financiero refleja que abril, mayo y junio tienen $300 menos de remanente.

---

## Módulo 7: Presupuestos Compartidos

### Propósito
Para parejas, compañeros de cuarto, familiares o socios que administran gastos juntos. Cada participante lo controla desde su teléfono con su propia sesión.

### Tipos de distribución

**50/50:** Cada participante paga la misma cantidad.
*Ejemplo:* Alquiler $600 → cada uno paga $300.

**Equitativo:** Divide entre N participantes.
*Ejemplo:* Gastos del apartamento $900 entre 3 personas → cada uno paga $300.

**Proporcional al ingreso:** Calcula según ingresos.
*Ejemplo:* José gana $1,700, su pareja $850. Ingreso total $2,550. José representa 66.67%, su pareja 33.33%. Si los gastos compartidos son $600 → José paga $400, su pareja paga $200.

**Manual:** El creador define cuánto paga cada uno.
*Ejemplo:* El propietario paga $350 y el inquilino $150 del mismo gasto de $500.

### Impacto en estado financiero personal
La parte asignada a cada usuario impacta su estado financiero individual. No se duplica el gasto completo, solo la parte correspondiente.

*Ejemplo:* José participa en presupuesto compartido de casa: su parte es $525/mes. Esos $525 aparecen en su perfil como compromiso fijo y reducen su disponible real.

### Roles
- **Creador**: puede todo
- **Administrador**: puede editar y agregar gastos
- **Participante**: puede ver y marcar su parte como pagada
- **Solo lectura**: solo puede consultar

### Control individual
Cada participante desde su teléfono puede:
- Ver el presupuesto y su parte asignada
- Marcar su parte como pagada
- Ver quién pagó y quién falta
- Registrar gastos nuevos (según su rol)
- Ver historial de movimientos

---

## Módulo 8: Calendario

### Propósito
Mostrar al usuario qué pagos vienen y cuándo, para que nunca lo tome por sorpresa. No es un calendario general — es un calendario de compromisos financieros.

### Cómo se puebla
Automáticamente desde:
- Gastos fijos con día de pago registrado → evento mensual
- Gastos fijos con dia_pago_2 → segundo evento mensual (quincenas)
- Deudas con fecha_proximo_pago → evento
- Deudas con dia_pago/dia_pago_2 → eventos recurrentes mensuales

### Estados de eventos
- **Pendiente**: el pago viene próximamente
- **Pagado**: el usuario lo marcó como realizado
- **Vencido**: pasó la fecha sin marcar

*Ejemplo:* El 13 de mayo Pedro abre el calendario y ve: "Día 15 — Carro $250, Tarjeta Visa $150". Total: $400 saliendo en 2 días. Transfiere desde su cuenta de ahorros a tiempo.

*Ejemplo quincena:* María paga el préstamo los días 5 y 20. El calendario muestra ambos eventos cada mes automáticamente.

---

## Módulo 9: Scanner DGI

### Propósito
Registro automático de gastos escaneando facturas electrónicas de la DGI de Panamá. Elimina el registro manual de compras con factura.

### Ubicación en la app
**No es un card del menú principal.** Es un ícono en el AppBar global, visible en toda la app. El usuario puede escanear desde cualquier pantalla sin navegar a ningún módulo específico.

### Flujo al escanear
1. Usuario escanea QR de factura DGI
2. La app obtiene: proveedor, monto, fecha, detalle de productos
3. La app pregunta:
   - ¿Es parte de un gasto existente?
   - ¿Qué tipo? (fijo, variable, no presupuestado, compartido, evento)
   - ¿Qué gasto? (desplegable de gastos del usuario)
   - ¿A qué mes corresponde?
4. El monto se debita del presupuesto de esa categoría en ese mes
5. Los productos se guardan en la base de datos de productos/precios

*Ejemplo:* Ana escanea factura de $47.50 del supermercado. La app sugiere: "¿Asociar a gasto variable Supermercado de mayo?" Ana confirma. El gasto queda registrado y el presupuesto de alimentación se actualiza. En 3 segundos, sin escribir nada.

### Base de datos de productos y precios
Cada factura escaneada extrae y guarda:
- Nombre del producto
- Precio unitario
- Cantidad
- Local/establecimiento
- Fecha de compra
- Categoría sugerida

Esto alimenta funciones futuras:
- "El arroz subió 10% respecto a tu última compra"
- "Este producto lo encuentras más barato en otro local"
- "Tu lista de supermercado estimada cuesta 15% más este mes"
- "Tu gasto en alimentación aumentó por precios, no por consumo excesivo"

---

## Módulo 10: Alertas y Recomendaciones

### Propósito
La app no se limita a mostrar números — los interpreta. Las alertas convierten datos en decisiones.

### Reglas de alerta activas

**Exceso de gasto (umbral 20%):**
Si el gasto real de una categoría supera el 20% del presupuesto → alerta.
*"Estás gastando $80 más de lo presupuestado en alimentación este mes."*

**Gasto no presupuestado repetido (3 meses):**
Si una categoría aparece como no-presupuestado durante 3 meses → sugerencia de crear presupuesto.
*"Llevas 3 meses con gastos en deporte sin presupuestar. Considera crear un fondo de $50/mes."*

**Presupuesto subestimado:**
Si el gasto real promedio de los últimos 3 meses supera consistentemente el estimado → alerta de ajuste.
*"Tu presupuesto de alimentación parece subestimado. En promedio gastas $140 más cada mes."*

**Remanente bajo:**
Si el remanente proyectado del mes cae por debajo de un umbral mínimo → alerta preventiva.
*"Tu remanente de junio será negativo si no ajustas. Tienes 3 semanas para actuar."*

**Impacto anual:**
Si el ritmo de gasto actual mantenido todo el año cambia significativamente el remanente anual → alerta.
*"Si mantienes este ritmo, tu remanente anual bajará de $3,600 a $1,800."*

**Presupuesto compartido:**
Si un participante registra un gasto compartido no presupuestado → notificación a los demás.
*"Tu parte del presupuesto compartido aumentó $45 este mes por una compra no presupuestada."*

### Recomendaciones al cierre anual
- Gastos no presupuestados repetidos → sugerir incluirlos como variables en el siguiente año
- Categorías consistentemente sobre el presupuesto → sugerir aumentar estimado
- Deudas que se liquidan → recalcular disponible y sugerir dónde redirigir esos fondos

*Ejemplo:* Al cerrar diciembre, la app detecta que Pedro gastó $600 en no-presupuestado de deporte durante el año. Recomendación: "Crea un fondo mensual de $50 en deportes para 2027."

---

## Módulo 11: Gastos Compartidos — Presupuesto principal (ya implementado)

Ver sección 7. El módulo existe y funciona. Las mejoras pendientes son la integración más profunda con el estado financiero personal y el control por roles.

---

## Módulo 12: Ahorro y Metas

### Propósito
Acumular hacia objetivos específicos: fondo de emergencia, vacaciones, down payment de carro, fondo de educación.

### Cómo funciona
- Meta: nombre, monto objetivo, fecha límite
- La app calcula cuánto ahorrar por período para llegar a tiempo
- Los abonos reducen el saldo pendiente de la meta
- Las cuotas de ahorro aparecen en el perfil como compromisos fijos (reducen el disponible)
- Barra de progreso visual

*Ejemplo:* María quiere $3,000 para el down payment de un carro en 18 meses. La app calcula $166.67/mes. Ese monto entra en su perfil como compromiso fijo. En el estado anual ve si puede sostenerlo con su ingreso actual.

---

## Módulo 13: Dashboard

Vista rápida al abrir la app:
- Ingreso vs compromisos del mes actual
- Barra de uso del ingreso
- Próximos pagos (calendario)
- Alertas no leídas
- Progreso de metas de ahorro activas
- Acceso rápido a agregar gasto

---

## Módulo 14: Logs del Servidor (Debug)

### Propósito
Herramienta de trabajo conjunto para diagnosticar errores en producción sin necesitar acceso directo al servidor.

### Qué registra
**Errores (rojo):** Cualquier respuesta 500 del backend — mensaje, ruta, usuario, stack trace, body del request.

**Actividad (verde):** Todas las acciones importantes del usuario:
- Ingreso configurado
- Gasto fijo creado/editado/eliminado
- Deuda creada/editada/archivada
- Variable base creada/editada/eliminada
- Registro de gasto en mes
- Estado anual generado/recalculado

### Auto-limpieza
Los logs se borran automáticamente cada 60 minutos. Solo sirven para diagnóstico en tiempo real, no para historial.

### Acceso
Menú principal → "Estado del sistema" → "Logs del servidor". También consultable directamente:
```
GET https://presupuestos-backend-h3l6.onrender.com/logs?secret=salarying_logs_2025
```

---

## Módulo 15: Ventas

> Este módulo existe y es independiente del flujo financiero personal. No se modifica ni conecta con el estado financiero por ahora.

---

## Estado actual de implementación

### Implementado y funcional
- [x] Perfil financiero (ingresos, fijos, variables base con períodos, deudas)
- [x] Estado financiero anual (auto-generado, recálculo automático)
- [x] Grid de 12 meses con estimados
- [x] Detalle de mes (resumen, gastos, análisis)
- [x] Agregar gastos (fijo/variable/no presupuestado)
- [x] Compromisos del mes (gastos fijos + deudas activas)
- [x] Deudas (revolving + letras, estrategias, proyecciones)
- [x] Creación de deudas con dia_pago, dia_pago_2, mes_inicio_pago
- [x] Categorías personalizadas con "Otro" y guardado para futuro
- [x] Selector de rango de meses (MesRangoSelector)
- [x] Calendario con eventos de pagos
- [x] Alertas automáticas (20% umbral, 3 meses repetición)
- [x] Logs del servidor con auto-limpieza
- [x] Deploy web en Vercel
- [x] Backend en Render (Node.js + Express + MySQL Clever Cloud)

### Pendiente — próximas fases

**Fase 2: Gastos reutilizables**
- [ ] Tabla `expense_definitions` (plantillas de gastos)
- [ ] Tabla `expense_instances` (uso mensual)
- [ ] Selector de gastos existentes en formularios
- [ ] Eliminación controlada (este mes / desde aquí / todos)
- [ ] Edición controlada (este mes / desde aquí / todos)

**Fase 3: Presupuesto compartido mejorado**
- [ ] Roles por participante (creador, admin, participante, lectura)
- [ ] Conexión directa con estado financiero personal de cada participante
- [ ] Notificaciones entre participantes

**Fase 4: Scanner global**
- [ ] Mover scanner de card a ícono en AppBar global
- [ ] Conectar factura escaneada a gastos existentes del mes
- [ ] Guardar productos y precios de facturas

**Fase 5: Productos y precios**
- [ ] Tabla `stores` (locales comerciales)
- [ ] Tabla `products` (productos con historial de precios)
- [ ] Tabla `product_prices` (precio por fecha y local)
- [ ] Vista de historial de precios

**Fase 6: Alertas avanzadas**
- [ ] Tendencia creciente 3 meses consecutivos
- [ ] Impacto anual proyectado
- [ ] Recomendaciones de cierre mensual
- [ ] Notificaciones push

**Fase 7: Cierre mensual y anual**
- [ ] Wizard de cierre mensual (continuar/modificar/ajustar)
- [ ] Cierre anual con resumen y recomendaciones
- [ ] Proyección automática del siguiente año basada en el actual

**Fase 8: Presupuestos de eventos**
- [ ] Eventos financiados desde remanente
- [ ] Eventos distribuidos por cuotas en varios meses
- [ ] Eventos compartidos con distribución

---

## Arquitectura técnica

### Stack
- **Backend**: Node.js + Express (monolito `server.js`) en Render (free tier)
- **Base de datos**: MySQL 5.6 en Clever Cloud (connectionLimit: 3, JSON → LONGTEXT)
- **Frontend**: Flutter 3.x + Dart 3.5.1 (tema oscuro Binance-style via AppTheme)
- **Auth**: Firebase (firebase_uid = email del usuario de Google)
- **Web**: Flutter web build en Vercel (static, SPA routing)
- **Email**: Brevo API para emails transaccionales

### Tablas principales actuales
```
user_income                 → ingreso del usuario
user_gastos_fijos           → compromisos fijos del perfil
gastos_variables_base       → presupuesto variable estimado con períodos
deudas                      → deudas con letra/revolving/estrategias
estado_financiero_anual     → totales anuales estimados/reales
meses_financieros           → 12 meses con estimados y reales
registros_gasto             → gastos reales registrados mes a mes
analisis_categorias         → análisis por categoría del mes
alertas_financieras         → alertas generadas por reglas
cierres_mensuales           → historial de cierres
cierres_anuales             → historial anual
subcategorias               → categorías personalizadas del usuario
calendario_eventos          → eventos de pago por día
server_logs                 → logs de errores y actividad (TTL: 60 min)
```

### Reglas de arquitectura
1. `firebase_uid` en TODOS los endpoints — nunca datos de otro usuario
2. Columnas JSON como LONGTEXT (MySQL 5.6 no soporta tipo JSON nativo)
3. LIMIT en SQL no parametrizado — usar `LIMIT ${parseInt(n)}` no `LIMIT ?`
4. Valores undefined → null explícito antes de bind params de mysql2
5. Recálculo de estimados siempre fire-and-forget con `.catch(() => {})`
6. Logs de actividad en endpoints de escritura (POST/PUT/DELETE)
7. Tabla `calendario_eventos` debe existir antes de cualquier PUT en gastos fijos

### Deploy
```bash
# Siempre en este orden:
git add [archivos] && git commit -m "descripción"
git push origin main                                    # GitHub
curl -X POST https://api.render.com/deploy/srv-d5kjem9r0fns73bfs23g?key=1s-LJtjaam4  # Backend
flutter build apk --release                             # APK Android
flutter build web --release                             # Web
git add -f build/web && git commit -m "chore: update web build" && git push  # Vercel auto-deploy
```

---

## Principios de diseño UX

1. **No punitivo**: el análisis informa, nunca juzga. "Gastaste más en ocio" no "Malgastaste dinero"
2. **Proactivo**: la app anticipa, no solo reporta. Muestra junio en problemas cuando estamos en marzo
3. **Sin fricción**: scanner para registrar, selector para no reescribir, auto-cálculo para no hacer matemáticas
4. **Visual**: barras de progreso, colores semafóricos (verde/amarillo/rojo), grid visual de meses
5. **Conectado**: nada existe aislado. Cada acción actualiza el estado financiero automáticamente

---

## Pregunta que Salarying debe responder para cada usuario

> "¿Por qué no me alcanza el dinero?"

La app responde:
- En qué categoría se fue
- Qué estaba mal presupuestado
- Qué gasto se repitió sin estar planificado
- Qué debe convertirse en presupuesto fijo
- Qué debe ajustarse para el próximo mes
- Cómo se proyecta el resto del año si sigue así
