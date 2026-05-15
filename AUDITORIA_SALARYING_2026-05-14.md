# AUDITORÍA COMPLETA SALARYING — 2026-05-14

---

## SECCIÓN 1 — VISIÓN ESTRATÉGICA: ¿QUÉ ES HOY VS LO QUE DEBE SER?

### Lo que la app ES hoy

**Un registro financiero semi-inteligente con 7+ módulos acumulados en capas.**

El flujo actual es: el usuario crea un presupuesto con nombre y monto → agrega gastos → marca pagos → ve un dashboard con números. La app *recolecta* datos y los *refleja*, pero no *guía* decisiones activamente. Los módulos financieros avanzados (income, capacidad, fondo, alertas, 50/30/20, clasificación, proyección) están todos **colapsados dentro de un ExpansionTile** que el usuario tiene que expandir manualmente para ver. Están ahí, pero no hablan con el usuario.

**Módulos concretos desalineados hoy:**

- **Dashboard**: muestra 8-9 cards, la mayoría cargando en paralelo. Para María (sin Ventas activas), la card "COBROS ACTIVOS" está siempre vacía, "FLUJO NETO" muestra déficit enorme porque compara cobros comerciales con gastos personales. Dos de las 8 cards son irrelevantes para ella.
- **CrearPresupuesto**: el wizard de 3 pasos es bueno en estructura pero el "Omitir" del paso de ingresos permite crear un presupuesto con monto_total = $0, lo que bloquea luego la creación (el backend valida, pero el usuario llega al step 3 sin saberlo).
- **DetallesPresupuesto**: Tab 1 tiene 6 secciones apiladas en scroll interminable. Tab 2 (Proyección) aparece vacío hasta que el usuario la toca; Tab 3 (Historial) igual. Los análisis financieros (el valor real) están debajo de los movimientos, después de que el usuario ya se cansó de scrollear.
- **Deudas**: módulo completo y funcional, pero las deudas no afectan el presupuesto activo en absoluto. María tiene $810/mes en cuotas de deuda que no aparecen en su "disponible" a menos que las haya agregado manualmente como gastos fijos.
- **Score de Salud Financiera**: da 10 puntos por "flujo de cobros >= gastado". María no tiene ventas activas, nunca gana esos 10 puntos. El score está calibrado para un usuario mixto (personal + negocio), no para un asalariado.

### Lo que la app DEBE SER

Un asesor-guía que habla el mismo idioma que María. La diferencia fundamental no es de features — es de **postura**: la app debe tomar la iniciativa de explicar, advertir y sugerir *antes* de que el usuario lo pida. Hoy la app espera que el usuario explore. La visión requiere que la app le hable primero.

**Brechas concretas:**

| Área | Hoy | Debe ser |
|------|-----|----------|
| Dashboard | 8 cards de datos | 3-4 cards que dicen "esto importa hoy" con un siguiente paso |
| Análisis financiero | Colapsado en ExpansionTile | Alertas activas que suben solas cuando hay problema |
| Deudas | Módulo separado sin conexión | Parte del resumen del presupuesto con impacto visible |
| Período nuevo | Se crea silenciosamente | Pregunta al usuario: "¿seguimos igual?" |
| Ingreso | Configuración opcional | Punto de entrada obligatorio al crear el primer presupuesto |

---

## SECCIÓN 2 — CAMBIO DE PARADIGMA: INGRESOS COMO BASE

### 2.1 Cómo está implementado hoy

El ciclo actual de período es completamente automático y silencioso:

1. Al crear un presupuesto, el backend llama crearPrimerPeriodo() y genera gastos fijos como movimientos.
2. Cuando el período vence, getPeriodoActivo() cierra el viejo y llama crearNuevoPeriodo() + generarMovimientosPeriodo() automáticamente.
3. El monto_total del presupuesto nunca cambia entre períodos a menos que el usuario edite manualmente.
4. El budget_income tiene UNIQUE constraint en presupuesto_id — hay un único registro de income por presupuesto para todos los períodos.
5. El usuario nunca es consultado al comenzar un período nuevo.

**El resultado**: María abre la app el día 16 (inicio de nueva quincena) y ve directamente sus movimientos ya cargados. No sabe que hubo una transición de período. La app nunca le preguntó nada.

### 2.2 Qué habría que cambiar en el backend

**Cambio estructural (requiere --intercambio):**

**Tablas:**
- Agregar periodo_income_override (tabla): permite que un período específico tenga un monto diferente al base (ingreso variable ese mes). Schema: (periodo_id, firebase_uid, ingreso_neto_periodo, motivo, created_at).
- presupuestos: agregar campo periodo_bienvenida_activo TINYINT DEFAULT 1. Cuando llega a 0, no muestra más el prompt de bienvenida.
- periodos: agregar campo requiere_confirmacion TINYINT DEFAULT 1 para marcar períodos que el usuario aún no "confirmó".

**Endpoints nuevos:**
- GET /presupuestos/:id/periodo-activo/bienvenida — devuelve si el período nuevo está en modo "sin confirmar", con los gastos planificados y el ingreso estimado.
- POST /presupuestos/:id/periodo-activo/confirmar — usuario confirma "sigo igual" o permite ajustes antes de activar.

**Lógica de generarMovimientosPeriodo**: debe poder recibir un montoOverride del período. Si el usuario dijo "este período cobré menos", los porcentajes de cada gasto se escalan.

### 2.3 Qué habría que cambiar en el frontend

**CrearPresupuesto:** El wizard ya es bueno. El único cambio sería hacer el paso de ingreso obligatorio (eliminar el "Omitir" o hacerlo más explícito en sus consecuencias).

**DetallesPresupuesto:** Al abrir un período recién creado (que no ha sido "confirmado"), mostrar un banner en la parte superior:

    "¿Seguimos igual que la quincena pasada?"
    [Sí, aplicar mismo plan] [Quiero ajustar este período]

Esto remplaza el "Reanudar fijos" actual (que es confuso).

**CierrePeriodoScreen:** Ya funciona bien estructuralmente. Falta: después del cierre, navegar directamente al "bienvenida del nuevo período", no silenciosamente de vuelta a la lista.

**DashboardScreen:** La card "PERÍODO ACTUAL" podría mostrar si el período está en modo "sin confirmar" con un CTA prominente.

**EditarPresupuesto:** Hoy editar un presupuesto cambia monto_total para TODOS los períodos futuros. Con el nuevo paradigma, se necesitaría separar "editar la plantilla base" de "ajustar este período".

### 2.4 Módulos afectados

- **Dashboard**: la card "PERÍODO ACTUAL" necesita incluir el estado de confirmación.
- **Calendario**: los eventos pre-generados para el período nuevo quedarían visibles incluso antes de que el usuario confirme el plan. No es grave pero es confuso.
- **Simulador**: sigue funcionando igual, es 100% local.
- **Deudas**: idealmente, al configurar el income del período, la app podría sugerir "tienes $810 en cuotas de deuda — ¿las tienes registradas como gastos fijos?".

### 2.5 MVP del cambio vs después

**MVP (lo que da valor inmediato):**
1. Banner de "¿seguimos igual?" al detectar que el período activo tiene < 2 días de antigüedad y no ha sido confirmado.
2. El banner tiene dos acciones: "Confirmar" (marca el período como activo y listo) y "Ajustar" (abre modal para cambiar montos de movimientos sin tocar la plantilla).
3. No requiere migración de tablas si se implementa con lógica de fechas (período con < 2 días = nuevo).

**Para después:**
- periodo_income_override para ingresos variables.
- Wizard de bienvenida completo con cambio de ingreso integrado.
- "Aprende de ti" — cuando el historial muestra que sistemáticamente gastas X% más en variables, el presupuesto te lo sugiere para el siguiente período.

---

## SECCIÓN 3 — AUDITORÍA DE COHERENCIA FINANCIERA

### 3.1 Score de Salud Financiera

**Veredicto: COHERENTE CON AJUSTES GRAVES**

**Problema 1 — "Flujo positivo" (10 pts) penaliza a los asalariados.**
La fórmula da 10 puntos si cobros_ventas >= gastado. Para María (sin ventas activas), cobrado = $0, siempre pierde esos 10 puntos. Un asalariado perfecto —que paga todo a tiempo, ahorra el 15%, y nunca excede su presupuesto— no puede superar 90/100. Esto contradice la coherencia del índice.

Alternativa correcta: reemplazar el componente "flujo positivo" por "compromisos cubiertos": si el usuario tiene income configurado y ingreso_neto >= total_fijo + total_ahorro, sumar 10 puntos. Para usuarios sin income, el componente queda en cero pero sin penalizar.

**Problema 2 — "Balance compartido" (20 pts) en el score personal.**
Incluir los presupuestos compartidos en la salud financiera personal mezcla contextos. María puede tener 80/100 en su presupuesto personal pero un balance compartido negativo porque su pareja tardó en pagar. Esos 8 puntos de deuda compartida son de otra persona, no de su gestión financiera.

Alternativa: mantenerlo como insight (el texto que muestra "Deuda compartida pendiente") pero sacarlo del cálculo numérico del score.

**Problema 3 — "Tasa de ahorro" usa montos PRESUPUESTADOS, no pagados.**
_totalAhorro viene de resumen['totalAhorro'] que suma m.monto (lo que está planificado pagar), no monto_pagado_real. Si María tiene un movimiento de ahorro de $50 sin pagar todavía, igual se cuenta en la tasa. Esto infla el score artificialmente.

**Para María con $40 de sobrante**: con gastos fijos totales ~$1,400 y totalAhorro quizás $60, su tasaAhorro = 60/1460 = 4.1%. Entraría en "tasa de ahorro baja" y el score le daría 0 puntos ahí. Le aparecería el insight "Tasa de ahorro baja (4%) — meta recomendada: 20%" que es irrealista para ella. **Esta recomendación de 20% es la recomendación financiera más cruel y contraproducente que puede ver alguien con $40 de sobrante.**

---

### 3.2 Regla 50/30/20

**Veredicto: COHERENTE CON AJUSTES**

La base de cálculo es correcta cuando hay income (ingreso_neto), cae al monto_total cuando no. El problema no es la fórmula sino cuándo y cómo se le muestra al usuario.

**Para María**: con ingreso neto de ~$1,280 (quincenal $640), la regla sugiere:
- Esenciales: $320 (50%) — ella tiene hipoteca $210 + carro $115 + préstamo $80 en esa quincena ya = $405 solo en deudas, SIN contar comida ni transporte. Imposible cumplir el 50%.
- Ahorro/Flexible: $128 (20%) — con $40 de sobrante total, esto es 3.2x lo que le queda.

La card de Recomendación 50/30/20 le mostraría todo en rojo a María. Esto es información que la puede paralizar, no ayudar.

**Alternativa correcta**: si disponible < 0.1 * ingreso_neto (menos de 10% de sobrante), cambiar el mensaje de "te recomiendo 50/30/20" a "tu primera meta es estabilizar: cubrir todos tus fijos. Cuando tengas $X de sobrante constante, te ayudaré a ahorrar." La regla 50/30/20 es aspiracional, no una bofetada.

---

### 3.3 Fondo de Seguridad

**Veredicto: COHERENTE EN SU DEFINICIÓN, MAL INTEGRADO**

Los 3 niveles son correctos para Panamá:
- Nivel 1 (1 período de gastos fijos) = colchón mínimo para no entrar en pánico.
- Nivel 2 (2 períodos = 1 mes) = estabilidad básica.
- Nivel 3 (6 períodos = 3 meses) = colchón real.

**Problema 1**: el cálculo usa gastos fijos del período activo (presupuestados, no pagados) como proxy. Si María está a mitad de período y solo tiene 5 movimientos registrados, el "fondo de seguridad objetivo nivel 1" será solo esos 5. El objetivo fluctúa con el estado del período, no es una referencia estable.

**Problema 2**: el total ahorrado usa TODAS las metas de ahorro del usuario, de TODOS sus presupuestos. Si María tiene un fondo para "viaje a Colón" de $200 y otro para "emergencias" de $50, el fondo de seguridad cuenta $250 aunque el de viaje no sea para emergencias.

**Problema 3 (integración)**: la mini-card en el Dashboard es informativa pero no accionable. No dice "para llegar al nivel 1, necesitas ahorrar $X por quincena — ¿quieres que lo agregue a tu plan?". Es solo un número.

---

### 3.4 Simulador de Decisiones

**Veredicto: COHERENTE CON UN BUG DE CÁLCULO**

**Bug en tasaAhorroHip:**

    final tasaAhorroHip = widget.ingresoNeto > 0
        ? ((widget.totalAhorro - _montoHip) / widget.ingresoNeto * 100).clamp(0.0, 100.0)
        : 0.0;

Resta montoHip de totalAhorro, como si el gasto hipotético viniera del presupuesto de ahorro. Esto es financieramente incorrecto: un gasto nuevo no reduce el presupuesto de ahorro existente, reduce el disponible. La tasa de ahorro proyectada debería ser igual a la actual (el plan de ahorro no cambia). Lo que cambia es el disponible_proyectado. El consejo de "tasa de ahorro baja" que aparece es en consecuencia incorrecto.

**Corrección**: la tasa de ahorro proyectada debería ser idéntica a la actual (el ahorro no cambia con el gasto hipotético). Lo que cambia es el disponible_proyectado. El consejo relevante no es "tu tasa de ahorro baja" sino "si haces este gasto, te queda $X para el resto del período".

**Lo que funciona bien**: la lógica de "excede el presupuesto", la barra de gasto proyectado, y el consejo contextual (ok/cuidado/excedido) son claros y útiles para María.

---

### 3.5 Deudas

**Veredicto: COHERENTE EN ESTRUCTURA, DESCONECTADO DEL ECOSISTEMA**

La tasa_interes está bien documentada como % mensual. La UI la muestra correctamente: "Tasa: X.X%/mes". No hay ningún lugar donde se use para calcular interés proyectado, pero tampoco se afirma que se calcula — es solo informativa. Coherente.

**Problema crítico — aislamiento del ecosistema:**
- Las deudas de María ($810/mes) no aparecen en su "capacidad real" a menos que las haya registrado TAMBIÉN como gastos fijos en el presupuesto.
- El GET /capacidad no consulta la tabla deudas. Calcula la capacidad basándose en movimientos del presupuesto activo.
- El usuario tiene que hacer doble registro: deuda en el módulo Deudas Y gasto fijo en el presupuesto.
- Si María registra la hipoteca solo en Deudas, el simulador de capacidad dice que tiene más dinero disponible del que realmente tiene.

**La app no orienta sobre qué deuda atacar primero.** No hay lógica de "avalanche" (atacar la de mayor interés primero) ni de "snowball" (atacar la de menor saldo). Solo lista las deudas.

---

### 3.6 Clasificación Esencial/Importante/Flexible

**Veredicto: CONCEPTO CORRECTO, FRICCIÓN DE ADOPCIÓN ALTA**

Los términos son correctos financieramente. El problema es que el usuario tiene que clasificar CADA gasto manualmente, y la mayoría no sabrá qué es "esencial" vs "importante". ¿La medicina del hijo de María es esencial o importante? ¿La colegiatura? ¿El cable?

Sin clasificación, el 50/30/20 muestra casi todo en "sin_clasificar" y el análisis es inútil.

**Recomendación**: agregar sugerencias automáticas por subcategoría. Si la subcategoría es "supermercado" → esencial. Si es "entretenimiento" → flexible. El usuario confirma o cambia. Así el dato se recopila sin esfuerzo consciente.

---

### 3.7 Alertas Inteligentes

**Veredicto: BUENA BASE, CON UNA ALERTA NUEVA QUE ES LA MEJOR DEL SISTEMA**

La alerta 0 (gastos fijos > ingreso neto) es la más importante y fue bien implementada. Es la única alerta que le dice al usuario "tu plan no es matemáticamente posible" antes de que empiece el período.

**Problema con alerta 4 (variables_altas):**

    const [histVariables] = await db.execute(
      `SELECT SUM(CASE WHEN m.tipo='no fijo' THEN m.monto ELSE 0 END) AS var_periodo
       FROM periodos p
       JOIN movimientos m ON m.periodo_id = p.id AND m.firebase_uid = p.firebase_uid
       WHERE p.presupuesto_id = ? AND p.firebase_uid = ? AND p.estado = 'cerrado'
       ORDER BY p.fecha_fin DESC LIMIT 3`
    )
    // FALTA GROUP BY p.id

Esta query no incluye GROUP BY p.id, lo que significa que si un período tiene muchos movimientos, puede aparecer múltiples veces en el resultado. Esto inflaría el promedio y dispararía alertas falsas.

**Corrección SQL necesaria:**

    SELECT SUM(CASE WHEN m.tipo='no fijo' THEN m.monto ELSE 0 END) AS var_periodo
    FROM periodos p
    JOIN movimientos m ON m.periodo_id = p.id AND m.firebase_uid = p.firebase_uid
    WHERE p.presupuesto_id = ? AND p.firebase_uid = ? AND p.estado = 'cerrado'
    GROUP BY p.id  ← falta esto
    ORDER BY p.fecha_fin DESC LIMIT 3

Las alertas son preventivas en su mayoría. El umbral del 70% para ritmo_alto es razonable.

---

### 3.8 Proyecciones

**Veredicto: TÉCNICAMENTE FUNCIONAL, FINANCIERAMENTE FRÁGIL**

Proyectar con promedio de 3 períodos funciona bien cuando el usuario tiene historial estable. El problema es:

1. Con 1 período de historial, el promedio es ese único período. No es significativo.
2. Con 0 períodos, usa los gastos presupuestados — que es lo correcto como fallback.
3. No tiene en cuenta estacionalidad (navidad, inicio de clases, etc.).
4. Los períodos marcados como "proyectado" tienen prefijo ~ — esto está bien hecho.

Para María con 4 períodos de historial, la proyección será razonablemente útil. El riesgo es que se lo presente como más certero de lo que es.

---

### 3.9 Gustitos

**Veredicto: CONCEPTO EXCELENTE, EMOCIÓN BIEN MANEJADA**

El concepto de "gustito" como compra consciente sin culpa es lo más humano de toda la app. El tono es correcto.

**Sobre los emotion_tags**: son válidos para patrones de comportamiento pero el usuario promedio no los usará. "¿Esto fue un antojo, un premio, social, impulso, estrés, u otro?" es una pregunta de app de bienestar, no de finanzas personales. Para María, agregar un emotion_tag es fricción innecesaria. Son opcionales (bien), pero si se quiere aprendizaje real, se necesita más historial de uso antes de que sean útiles.

**Integración financiera correcta**: balance_disponible = monto_total - totalGastado - totalGustitos. El soft delete que recupera el disponible funciona bien.

---

## SECCIÓN 4 — AUDITORÍA DE EXPERIENCIA (ROL: MARÍA PÉREZ)

### 4.1 Login y primer uso

Abro la app. Hay una pantalla con un ícono de billetera y un spinner. Espero. Aparece el botón de Google. Lo toco. Me pide permiso. Entro.

Lo que me gusta: entró sola la próxima vez que la abrí. No me pidió contraseña.

Lo que no entiendo: ¿por qué a veces tarda 50 segundos en cargar? Pensé que se había colgado. Sin feedback en esa espera — ni un texto que diga "conectando con el servidor, espera un momento". La rueda gira y nada más.

**Veredicto: No volvería a abrir si la primera vez tarda 50 segundos sin explicación. Es el momento donde más usuarios se van.**

---

### 4.2 MainMenu

Veo 7 tarjetas: Dashboard, Presupuesto (expandible), Ahorro, Calendario, Mis Deudas, Ventas, Facturas QR.

Qué bien: el menú es claro y cada tarjeta dice para qué sirve.

Qué me confunde: "Facturas QR" — ¿qué es eso? Suena a algo de la DGII, a una factura que me envían. ¿Para qué lo usaría yo? No tengo negocio.

Qué falta: no hay ninguna pista de cuánto me queda o si hay algo urgente. Entro al menú y no sé si tengo $40 o $400 disponibles sin entrar a otra pantalla.

**Veredicto: Volvería, pero el menú no me da ningún contexto financiero. Es una lista de navegación, no un panel de control.**

---

### 4.3 Dashboard — Las 7 cards

**SALUD FINANCIERA**: veo un círculo con "52" y la palabra "REGULAR". Me aprieta el pecho. No sé qué significa el 52, no sé cómo mejorarlo. Abajo dice "Tasa de ahorro baja (4%) — meta recomendada: 20%". Me siento juzgada. Con $40 de sobrante, ¿me está diciendo que ahorre 20%? Son $288 que no tengo. Esto me hace querer cerrar la app.

**PERÍODO ACTUAL**: esto me gusta más. Veo $1,420 gastados de $1,460 presupuestados. Barra casi llena en rojo. Dice "Ritmo alto". Entiendo. Aunque me da angustia ver casi todo en rojo, al menos es claro.

**FLUJO NETO**: muestra "-$1,420 — Déficit". No entiendo por qué dice déficit si cobro mi salario. Ah, dice que es cobros de ventas menos gastos. Yo no tengo ventas. Esta tarjeta dice que tengo un déficit enorme cuando en realidad estoy bien (en mi mente). Me confunde.

**TASA DE AHORRO**: "4.1% — Meta: 20%". Otra vez lo del 20%. Esta tarjeta debería desaparecer o cambiar el mensaje para alguien como yo.

**AHORRO Y METAS**: veo una meta de $500. Está al 68%. Esto me da un poco de ánimo, es algo positivo.

**FONDO DE SEGURIDAD**: "Sin colchón" con un escudo rojo. Me asusta. Pero la barra dice que tengo un 12% del objetivo nivel 1. Al menos no es 0%.

**DEUDAS COMPARTIDAS**: vacío — no uso presupuestos compartidos.

**PRÓXIMOS 7 DÍAS**: veo 3 pagos pendientes esta semana por $380. Esto SÍ me sirve. Acción concreta, fechas, montos.

**COBROS ACTIVOS**: "Sin cobros activos". No tengo negocio, esta tarjeta no aplica.

**DEUDAS PENDIENTES**: $68,000. Me da un golpe en el estómago. Esto es mi hipoteca + carro + préstamo. No es que no lo supiera, pero verlo así junto, en rojo, de un golpe... necesito respirar.

**Veredicto**: El dashboard me da ansiedad más que claridad. 3 de 8 cards son irrelevantes para mí (Flujo Neto, Cobros Activos, Deudas Compartidas). Las 2 más agresivas (Salud Financiera con score bajo, Deudas Pendientes en rojo) me hacen querer cerrar la app. Solo 2 cards realmente me ayudan: Próximos 7 días y Período actual.

---

### 4.4 Lista de Presupuestos → Entrar

Veo 1 tarjeta: "Quincena Mayo" — $1,460 mensual, tipo Quincenal. Al entrar, cargo la pantalla de detalle. Todo bien. Está cargando.

---

### 4.5 DetallesPresupuesto — Tab 1: Período

Scrolleo y scrolleo. Primero el banner de período (ok). Luego "INGRESO Y CAPACIDAD" — CapacidadCard. Me dice que mi capacidad real es -$140. Eso me congela: ¿significa que estoy en números rojos? No hay ningún texto que explique qué es "capacidad real".

Luego "ESTE PERÍODO": balance, barras, stats (Fijos $640, Variables $400, Ahorro $50). El círculo de progreso dice 60% de movimientos pagados.

Botones: Agregar, Reanudar fijos, Simular decisión, Cerrar período (aparece solo en los últimos 2 días, ok).

MOVIMIENTOS: 8 items con chips de colores. Botones "Pagar". Esto funciona bien.

ANÁLISIS FINANCIERO (colapsado): tiene que expandirse manualmente. Lo abro — alertas, clasificación, 50/30/20... demasiado para procesar.

GUSTITOS: $45 en gustitos. El tono del mensaje "Compras espontáneas registradas" me agrada.

**Lo del "Análisis Financiero" colapsado es el peor diseño de toda la app**: la información más valiosa (alertas, 50/30/20) está enterrada al fondo, colapsada, después de los movimientos. Jamás la veo si no la busco activamente.

**Tab 2 — Proyección**: carga, veo 12 cards de meses. Las pasadas tienen datos reales, las futuras tienen ~. Útil pero no sé qué hacer con esta información.

**Tab 3 — Historial**: 4 períodos previos con montos y barras. Útil para ver si mejoré o empeore.

**Veredicto**: Volvería a esta pantalla solo para marcar pagos y agregar gastos. Todo lo demás me cuesta demasiado encontrarlo y entenderlo.

---

### 4.6 Wizard de CrearPresupuesto

**Paso 1 — Básicos**: pongo nombre "Quincena", elijo Quincenal, día 15. Claro y rápido.

**Paso 2 — Ingreso**: me pide el salario mensual. Activo "Calcular deducciones Panamá". Pongo $1,500 brutos. Ve automáticamente: CSS $146.25, Educativo $18.75, ISR $0. Neto: $1,335. Quincenal: $667.50. Esto está muy bien hecho. Entiendo qué me llega.

**Paso 3 — Gastos**: lista vacía con botón "Agregar gasto". Abro el sheet. Elijo tipo "Deuda" (chip rojo). Hay un switch "Descuento directo del salario" — ¿qué es eso? No entiendo. No hay tooltip.

Agrego hipoteca $420, carro $230, préstamo $160. Total fijos ya suman $810 de $667.50 de presupuesto quincenal. La app no me avisa de nada en este momento. Toco "Crear presupuesto" y... se crea. Ahora tengo un presupuesto con $667.50 de monto y $810 de gastos fijos. La app no me dio ninguna señal de que eso es imposible.

**Veredicto**: el wizard de 3 pasos es el mejor flujo de la app. Me ayuda a configurar mi ingreso real. El único problema es que no valida si los gastos exceden el ingreso al finalizar.

---

### 4.7 CierrePeriodo

Solo aparece el botón en los últimos 2 días del período. Lo toco. Carga.

Veo un resumen: Período #4, fechas, grid de cards: Ingresé $667.50, Gasté $650, Ahorré $50, Gustitos $45, Me quedaron $-37.50 (rojo, excediste).

Debajo: "Aprendizajes del período" con bullets generados automáticamente. Los leo. Son simples pero honestos.

Al final: botón "Confirmar cierre". Lo presiono. Vuelvo a la pantalla de detalle que ya muestra el período nuevo.

Lo que falta: al abrir el nuevo período no hay ningún mensaje. La app simplemente muestra los mismos gastos ya cargados. No me pregunta nada. Es como si no hubiera pasado nada.

**Veredicto**: la pantalla de cierre en sí está bien. El problema es lo que pasa después: el nuevo período se abre en silencio.

---

### 4.8 Ahorro y Metas

Veo una lista de metas. Tengo una: "Fondo emergencias" — $50/quincena. La app me muestra una barra de progreso al 100% y dice "Meta: $50.00".

Espera. La meta es $50? Pero yo quiero juntar $500 para emergencias. Solo estoy poniendo $50 por quincena. La barra dice que ya llegué al 100% después de la primera cuota. Esto está roto. La "meta" debería ser $500, no $50.

**Este es el bug más visible de la app**: el ahorro muestra la CUOTA POR PERÍODO ($50) como la "meta total", no el objetivo real ($500). La barra de progreso siempre muestra ≥ 100% después del primer pago.

**Veredicto**: No volvería a usar este módulo porque el progreso no tiene sentido. Pensaría que la app está rota.

---

### 4.9 Deudas

Veo 3 deudas con montos, tipos, tasas y fechas de próximo pago. Barra de progreso muestra cuánto falta. Botón "Registrar abono".

Lo que me gusta: el desglose de tasa de interés y fecha próxima. Al menos sé cuándo pago.

Lo que me falta: la app no me dice CUÁL deuda atacar primero. Tengo el préstamo personal al 2%/mes (el más caro), el carro al 0.5%, y la hipoteca al 0.4%. Debería atacar primero el préstamo personal. La app me muestra los tres igual, sin priorización.

**Veredicto**: Sí volvería a esta pantalla para registrar abonos. Es funcional. Le falta la recomendación de qué pagar primero.

---

### 4.10 Calendario

Veo un calendario con puntos de colores. Los rojos son gastos, los verdes son ingresos/cobros. 3 tabs: Calendario, Lista, Flujo.

La vista de Lista es la más útil — veo todo ordenado por fecha. Puedo marcar pagos desde aquí también.

Lo que me confunde: hay eventos que ya fueron creados automáticamente al configurar gastos con fecha fija. Pero yo no siempre recuerdo cuál fue cuál. No hay forma de ver de dónde vino un evento (¿de qué presupuesto?, ¿de qué gasto?).

**Veredicto**: Volvería principalmente para la vista de Lista. El calendario en grid es bonito pero difícil de leer en pantalla pequeña.

---

### 4.11 Gustitos

Lista de gustitos del presupuesto. Total $45. Veo 4 items: café $2, postre $8, ropa niño $15, medicamento $20.

El tono es amigable. Me gusta que no se llamen "gastos hormigas".

Lo que me confunde: el medicamento de $20 para el niño ¿debería ser un Gustito? No fue espontáneo, fue necesario. Pero lo agregué aquí porque no tenía presupuestado ese gasto.

**Veredicto**: Sí volvería. Es la pantalla menos ansiosa de toda la app.

---

### 4.12 Simulador de Decisiones

Llego aquí desde el botón "Simular decisión" en DetallesPresupuesto.

Pongo $45 (unos zapatos en oferta). La app me dice:
- Disponible después: $-5 (en rojo)
- Presupuesto excedido
- "Este gasto supera tu presupuesto. Considera reducirlo o esperar al próximo período."

Es honesto. Me sirvió para decidir no comprarlos hoy.

Lo que me falta: ¿puedo simular qué pasa si esos zapatos los pago en 2 quincenas ($22.50 cada una)? No, el simulador solo calcula el monto completo. No tiene cuotas.

**Veredicto**: Sí volvería. Es corto, claro y responde la pregunta más importante: ¿me alcanza?

---

## SECCIÓN 5 — INCONSISTENCIAS TÉCNICAS Y DE DATOS

### Bug #1 — CRÍTICO: monto_meta en GET /ahorros retorna la cuota por período, no la meta total

**Archivo**: backend/server.js línea ~726, lib/ahorro_meta.dart

En el backend:

    monto_meta: a.cuota_periodo, // compatibilidad hacia atrás

cuota_periodo = gastos.monto = el pago por período (ej: $50/quincena). Pero el Dashboard y la pantalla de ahorro usan monto_meta como si fuera la meta total ($500). Resultado: pct = total_ahorrado / cuota = 150/50 = 3.0, clamped a 100% después del primer pago. La barra de progreso siempre muestra 100% o más. La meta total nunca fue guardada como campo separado — solo existe como cuota × número_original_de_períodos, pero numero_quincena se decrementa con cada período.

**Corrección**: guardar meta_total en la tabla gastos (o calcularlo como monto × numero_quincena_original). Agregar numero_quincena_original a gastos al crearse. Devolver en el endpoint monto_meta_total y actualizar Dashboard y AhorroMeta para usar ese campo.

---

### Bug #2 — CRÍTICO: Alerta 4 (variables_altas) tiene GROUP BY faltante

**Archivo**: backend/server.js línea ~4938

La query de historial de variables en el endpoint /alertas no incluye GROUP BY p.id. Sin él, si un período cerrado tiene 5 movimientos, aparece 5 veces en el resultado. El LIMIT 3 selecciona 3 filas, no 3 períodos. El promedio resultante es incorrecto y puede disparar alertas falsas de "variables_altas" cuando en realidad el gasto está dentro de rango.

**Corrección**: agregar GROUP BY p.id antes del ORDER BY.

---

### Bug #3 — Simulador de Decisiones: tasaAhorroHip calcula mal

**Archivo**: lib/simulador_decisiones_screen.dart línea ~57

    final tasaAhorroHip = widget.ingresoNeto > 0
        ? ((widget.totalAhorro - _montoHip) / widget.ingresoNeto * 100).clamp(0.0, 100.0)
        : 0.0;

Resta el gasto hipotético directamente del totalAhorro. Financieramente incorrecto: un gasto nuevo no reduce el presupuesto de ahorro existente, reduce el disponible. La tasa de ahorro proyectada debería ser igual a la actual. El consejo de "tasa de ahorro baja" que aparece es incorrecto.

---

### Bug #4 — MENOR: _cargarFondo() en Dashboard llama /presupuestos redundantemente

**Archivo**: lib/dashboard_screen.dart línea ~222

_cargarFondo() llama /presupuestos para obtener el ID activo. _cargarPresupuesto() hace lo mismo. Ambas corren en Future.wait() simultáneamente — 2 peticiones idénticas al cargar el Dashboard. No es un bug de datos sino de eficiencia.

---

### Bug #5 — AppTheme.warning === AppTheme.primary

**Archivo**: lib/theme/app_theme.dart

    static const Color warning = Color(0xFFF0B90B); // MISMO valor que primary
    static const Color primary = Color(0xFFF0B90B);

Los estados de "advertencia" son visualmente indistinguibles de los estados "normales activos". El fondo de seguridad en nivel 1 (warning) se ve exactamente igual que un botón activo. No es un crash, pero el diseño pierde uno de sus semáforos.

---

### Bug #6 — calcular_automatico e ingreso_bruto_mensual se envían pero no se guardan

**Archivo frontend**: lib/crear_presupuesto.dart línea ~135
**Archivo backend**: backend/server.js línea ~4477

Flutter envía calcular_automatico e ingreso_bruto_mensual en el POST de income, pero el endpoint POST /presupuestos/:id/income no los incluye en su INSERT ni en el ON DUPLICATE KEY UPDATE. Estos campos existen en la migración add_budget_module_v2.sql pero se silencian en el backend. Datos enviados y perdidos.

---

### Bug #7 — reanudar-fijos es un reset de pagos, no una reanudación

**Archivo**: backend/server.js línea ~645, lib/detalles_presupuesto.dart línea ~705

El endpoint PUT /presupuestos/:id/gastos/reanudar-fijos hace:

    UPDATE movimientos SET pagado=0, monto_pagado_real=NULL WHERE tipo IN ('fijo','fijo_x_periodo')

Esto RESETEA movimientos pagados a no-pagados. No crea movimientos nuevos, no "reanuda" nada. El botón en la UI dice "Reanudar fijos" que suena como si fuera a crear nuevos movimientos para gastos fijos que se eliminaron. Un usuario que toca este botón accidentalmente pierde registro de todos sus pagos fijos del período.

---

### Bug #8 — Flujo Neto en Dashboard mezcla ingresos comerciales con gastos personales

**Archivo**: lib/dashboard_screen.dart línea ~655

    final cobrado = (_resumenVentas?['total_cobrado'] as double?) ?? 0;
    final neto = cobrado - _gastado;

Para un usuario sin ventas activas, cobrado = $0 y el "Flujo Neto" muestra el total de gastos del período como déficit. Para María: "FLUJO NETO: -$1,460 — Déficit". Esto es conceptualmente incorrecto para un asalariado — su ingreso no está registrado como "cobros de ventas".

---

### Bug #9 — GET /ahorros devuelve total_ahorrado pero el Dashboard lo recalcula manualmente

El endpoint calcula total_ahorrado = monto_ahorrado + total_aportaciones en JavaScript y lo devuelve. El Dashboard duplica ese cálculo en Flutter:

    final ahorrado = (double.tryParse(m['monto_ahorrado']?.toString() ?? '0') ?? 0)
                   + (double.tryParse(m['total_aportaciones']?.toString() ?? '0') ?? 0);

Funciona correctamente pero es redundante. Si el backend cambia la fórmula, el Flutter no lo reflejaría.

---

### Inconsistencia #10 — InvoiceHistoryScreen en MainMenu no documentada en ningún skill

**Archivo**: lib/main_menu.dart línea ~168

El menú principal tiene una entrada "Facturas QR" que navega a InvoiceHistoryScreen. Este módulo completo (4 endpoints de invoice-scanner en el backend, líneas 4055-4369) no aparece en ninguno de los skills ni en el SALARYING_TECNICO.tct hasta la última sesión documentada. El módulo existe, tiene endpoints backend activos, pero no está auditado ni integrado con el resto de la app.

---

### Inconsistencia #11 — Score de Salud usa totales presupuestados (no pagados) para tasa de ahorro

**Archivo**: lib/dashboard_screen.dart línea ~299

    double get _totalAhorro =>
        double.tryParse(_presupuesto?['total_ahorro']?.toString() ?? '0') ?? 0;

total_ahorro viene del resumen del detalle, que suma movimientos.monto (presupuestado), no monto_pagado_real. Un usuario con ahorro no pagado aparece con la misma tasa que uno que sí lo pagó.

---

### Inconsistencia #12 — server.js version indicator desactualizado

**Archivo**: backend/server.js línea ~381

    app.get('/', (req, res) => res.json({ status: 'Backend funcionando...', version: '2.4' }));

El documento técnico indica versión 2.6. El healthcheck aún dice 2.4.

---

## SECCIÓN 6 — MÓDULOS FUERA DEL FOCO PRINCIPAL

### Presupuestos Compartidos

Bien separados visualmente (sub-card dentro del expandible de Presupuesto). No interfieren con el flujo principal. Sin embargo, la card "DEUDAS COMPARTIDAS" en el Dashboard contribuye al problema de "demasiadas cards para María" cuando ella no tiene ningún presupuesto compartido — aparece como "Sin presupuestos compartidos" sin opción de ocultarla.

**Deuda técnica**: POST /shared-budgets/:id/request-delete envía solicitud al co-dueño, pero no hay lógica del lado del co-dueño para APROBAR la eliminación. El campo delete_requested_by se guarda pero ningún endpoint verifica ese campo para permitir la eliminación final. **El presupuesto nunca se puede eliminar efectivamente una vez que hay dos miembros.**

### Ventas (Productos + Servicios)

La separación en VentasLandingScreen con dos divisiones está bien ejecutada. No distrae al usuario personal. El menú principal los oculta apropiadamente detrás de un nivel de navegación.

**Deuda técnica propia**: el módulo de Ventas de Productos (CobrosHome) aún importa cobros_home.dart en el Dashboard directamente, que es para ventas de productos. Un usuario que no usa ventas igual carga ese código. Minor.

El módulo de Servicios (Jobs) es completo y bien diseñado. La única deuda es que el "Financiero Dashboard" no tiene acceso desde el Dashboard principal — solo desde dentro del módulo Servicios.

### Facturas QR

Módulo activo en el backend (líneas 4055-4369 del server.js) con endpoints para procesar, listar, asignar y eliminar facturas escaneadas. En el frontend existe InvoiceHistoryScreen. Sin embargo, scanned_invoice_id en la tabla gustitos es nullable y sin uso real. La integración QR-Gustitos está preparada pero no implementada. El módulo está a medio terminar: existe la infraestructura de escaneo pero la asignación a gastos del presupuesto aún no conecta con el flujo principal.

---

## SECCIÓN 7 — PLAN DE ACCIÓN PRIORIZADO

---

### TIER 1 — CAMBIOS DE PARADIGMA

#### T1.1 — Banner "¿Seguimos igual?" al inicio de período nuevo

**Qué cambiar**: cuando el período activo tiene ≤ 2 días de creado y no hay flag de confirmación, mostrar un banner en la parte superior de DetallesPresupuesto con opciones: "Sí, mismo plan" / "Quiero ajustar".

**Por qué**: hoy el período nuevo se crea silenciosamente. El usuario nunca tiene el momento de decisión que la visión requiere.

**Dónde**: lib/detalles_presupuesto.dart (banner condicional en Tab 1), backend/server.js (endpoint de confirmación).

**Requiere --intercambio**: No. Es incremental — no requiere cambio de schema, solo lógica de detección por fecha.

**Nivel de esfuerzo**: Bajo.

**Dependencias**: Ninguna.

---

#### T1.2 — Hacer el income obligatorio (o con CTA prominente) al crear presupuesto

**Qué cambiar**: cambiar el botón "Omitir" del paso de ingreso por un texto aclaratorio: "Continuar sin configurar ingreso (algunos análisis no estarán disponibles)". Agregar validación antes del step 3 que advierta si monto_total calculado < suma de gastos ingresados.

**Por qué**: sin income, los mejores módulos (capacidad, fondo, 50/30/20) son ciegos.

**Dónde**: lib/crear_presupuesto.dart línea ~454.

**Requiere --intercambio**: No.

**Nivel de esfuerzo**: Bajo.

**Dependencias**: T1.1 para que el flujo completo tenga sentido.

---

### TIER 2 — CORRECCIONES DE COHERENCIA FINANCIERA CRÍTICAS

#### T2.1 — Corregir monto_meta en GET /ahorros para mostrar meta total

**Qué cambiar**: agregar campo meta_total a gastos (o calcularlo como monto × numero_quincena_original). Agregar numero_quincena_original a gastos al crearse. Devolver en el endpoint monto_meta_total y actualizar Dashboard y AhorroMeta para usar ese campo.

**Por qué**: la barra de progreso de ahorro siempre muestra 100% después del primer pago. Este es el bug más visible que destruye la confianza del usuario en el módulo de ahorro.

**Dónde**: backend/server.js línea ~726, database/migrations/ (migración nueva), lib/ahorro_meta.dart, lib/dashboard_screen.dart línea ~754.

**Requiere --intercambio**: Sí, si se hace con migración. No, si se calcula dinámicamente.

**Nivel de esfuerzo**: Medio.

**Dependencias**: Ninguna.

---

#### T2.2 — Reformular el Score de Salud Financiera

**Qué cambiar**:
1. Reemplazar "flujo positivo (cobros ventas)" por "compromisos cubiertos por ingreso" (si income configurado y ingreso_neto >= fijos + ahorro). Sin income, 0 pts pero sin penalizar.
2. Sacar "balance compartido" del cálculo numérico, conservarlo solo como insight textual.
3. Cambiar la recomendación "meta 20%" cuando el sobrante < 10% del ingreso.

**Por qué**: el score hoy penaliza a los asalariados y la recomendación de 20% de ahorro es cruel para quien tiene $40 de sobrante.

**Dónde**: lib/dashboard_screen.dart línea ~283 (función _calcularPuntaje).

**Requiere --intercambio**: No.

**Nivel de esfuerzo**: Bajo.

**Dependencias**: Ninguna.

---

#### T2.3 — Adaptar la card de 50/30/20 según capacidad del usuario

**Qué cambiar**: si disponible < 0.15 * ingreso_neto, no mostrar la regla 50/30/20 como meta sino como información contextual con mensaje: "Tu margen actual es ajustado. Antes del 50/30/20, la prioridad es cubrir todos tus compromisos y construir un colchón pequeño."

**Por qué**: mostrar el 50/30/20 en rojo para alguien con $40 de sobrante es financieramente honesto pero psicológicamente destructivo.

**Dónde**: lib/widgets/presupuestos/recomendacion_porcentajes_card.dart, backend/server.js línea ~5052.

**Requiere --intercambio**: No.

**Nivel de esfuerzo**: Bajo.

**Dependencias**: T2.2.

---

#### T2.4 — Corregir tasaAhorroHip en el Simulador

**Qué cambiar**: la tasa de ahorro proyectada no debe cambiar con el gasto hipotético (el plan de ahorro no se toca). Mostrar en su lugar el "disponible proyectado" de forma más prominente.

**Dónde**: lib/simulador_decisiones_screen.dart línea ~57.

**Requiere --intercambio**: No.

**Nivel de esfuerzo**: Muy bajo (1 línea de lógica, ajuste de UI).

**Dependencias**: Ninguna.

---

#### T2.5 — Conectar Deudas con la Capacidad Real

**Qué cambiar**: en el endpoint /capacidad, cruzar con la tabla deudas del usuario y sumar los pagos mínimos mensuales de deudas activas a los gastos fijos (si no ya están registrados en movimientos). Agregar aviso en la UI: "Tus cuotas de deuda son $X/período — ¿están incluidas en tus gastos fijos?"

**Por qué**: la capacidad real puede estar inflada si las deudas no están como gastos fijos del presupuesto.

**Dónde**: backend/server.js línea ~4511, lib/widgets/presupuestos/capacidad_card.dart.

**Requiere --intercambio**: No.

**Nivel de esfuerzo**: Medio.

**Dependencias**: Ninguna.

---

### TIER 3 — CORRECCIONES TÉCNICAS E INCONSISTENCIAS DE DATOS

#### T3.1 — Corregir GROUP BY faltante en alerta de variables_altas

**Qué cambiar**: agregar GROUP BY p.id a la query de historial de variables en el endpoint /alertas.

**Dónde**: backend/server.js línea ~4938.

**Requiere --intercambio**: No.

**Nivel de esfuerzo**: Muy bajo (1 línea SQL).

**Dependencias**: Ninguna.

---

#### T3.2 — Guardar calcular_automatico e ingreso_bruto_mensual en el backend

**Qué cambiar**: actualizar el INSERT/ON DUPLICATE KEY UPDATE del endpoint POST /presupuestos/:id/income para incluir estos dos campos.

**Dónde**: backend/server.js línea ~4477.

**Requiere --intercambio**: No.

**Nivel de esfuerzo**: Muy bajo.

**Dependencias**: Ninguna.

---

#### T3.3 — Eliminar la doble llamada a /presupuestos en Dashboard

**Qué cambiar**: _cargarFondo() puede reutilizar el ID del presupuesto activo obtenido por _cargarPresupuesto() en lugar de llamar /presupuestos de nuevo. Usar Completer o refactorizar para que _cargarFondo() reciba el ID como parámetro.

**Dónde**: lib/dashboard_screen.dart línea ~222.

**Requiere --intercambio**: No.

**Nivel de esfuerzo**: Bajo.

**Dependencias**: Ninguna.

---

#### T3.4 — Corregir el "reanudar fijos": renombrar o rediseñar

**Qué cambiar**: el botón "Reanudar fijos" actualmente resetea pagos a no-pagados. Opciones: (a) renombrarlo a "Resetear pagos fijos" con advertencia clara, o (b) rediseñarlo para que en realidad agregue movimientos faltantes sin tocar los ya pagados. La opción (b) es la correcta financieramente.

**Dónde**: lib/detalles_presupuesto.dart línea ~705, backend/server.js línea ~645.

**Requiere --intercambio**: No para el rename. Sí para el rediseño.

**Nivel de esfuerzo**: Bajo (rename) / Medio (rediseño).

**Dependencias**: Ninguna.

---

#### T3.5 — Solucionar el soft-delete de presupuestos compartidos

**Qué cambiar**: crear un endpoint que procese la aprobación del co-dueño cuando delete_requested_by tiene un valor. Actualmente el presupuesto jamás se puede eliminar una vez que hay 2 miembros.

**Dónde**: backend/server.js (nuevo endpoint), lib/shared_budget_detail.dart.

**Requiere --intercambio**: No.

**Nivel de esfuerzo**: Medio.

**Dependencias**: Ninguna.

---

#### T3.6 — Actualizar version en healthcheck

**Qué cambiar**: cambiar version: '2.4' por '2.6' en el endpoint raíz.

**Dónde**: backend/server.js línea ~381.

**Requiere --intercambio**: No.

**Nivel de esfuerzo**: Muy bajo.

**Dependencias**: Ninguna.

---

### TIER 4 — MEJORAS DE EXPERIENCIA Y UX

#### T4.1 — Feedback durante el cold start de Render

**Qué cambiar**: detectar cuando la primera petición tarda > 5s y mostrar: "Conectando con el servidor... (esto puede tardar hasta 1 minuto la primera vez del día)". Aplicar en ApiClient o en un wrapper de loading.

**Dónde**: lib/services/api_client.dart, pantallas con loading inicial.

**Requiere --intercambio**: No.

**Nivel de esfuerzo**: Bajo.

**Dependencias**: Ninguna.

---

#### T4.2 — Sacar el Análisis Financiero del ExpansionTile colapsado

**Qué cambiar**: las alertas activas (alertas.tiene_alertas = true) deben aparecer SIEMPRE en Tab 1, antes de los movimientos, sin expansión. El ExpansionTile debería contener solo clasificación y 50/30/20. Las alertas son urgentes; no deben requerir clic.

**Dónde**: lib/detalles_presupuesto.dart línea ~771, lib/widgets/presupuestos/analisis_financiero_section.dart.

**Requiere --intercambio**: No.

**Nivel de esfuerzo**: Bajo.

**Dependencias**: Ninguna.

---

#### T4.3 — Cards irrelevantes en Dashboard condicionales

**Qué cambiar**: "COBROS ACTIVOS" solo debe mostrarse si el usuario tiene al menos una venta registrada alguna vez. "DEUDAS COMPARTIDAS" solo si tiene al menos un presupuesto compartido activo. "FLUJO NETO" debe cambiar su label y lógica si no hay ventas — podría ser "Ingreso vs Gasto" usando ingreso_neto del income si está disponible.

**Dónde**: lib/dashboard_screen.dart.

**Requiere --intercambio**: No.

**Nivel de esfuerzo**: Bajo.

**Dependencias**: Ninguna.

---

#### T4.4 — Validación de gastos > ingreso al finalizar el wizard

**Qué cambiar**: antes de tocar "Crear presupuesto", calcular la suma de los gastos ingresados en el paso 3 y compararla con montoTotal. Si excede, mostrar advertencia: "Tus gastos suman $X más de lo que ingresaste. Puedes continuar, pero empezarás el período en déficit."

**Dónde**: lib/crear_presupuesto.dart línea ~91.

**Requiere --intercambio**: No.

**Nivel de esfuerzo**: Bajo.

**Dependencias**: Ninguna.

---

#### T4.5 — Añadir priorización de deudas por tasa de interés

**Qué cambiar**: en DeudasScreen, ordenar las deudas por tasa_interes DESC (avalanche) como orden por defecto. Agregar un chip en la deuda de mayor tasa: "Atacar primero — mayor interés". Texto simple, sin fórmulas.

**Dónde**: lib/deudas/deudas_screen.dart, backend/server.js línea ~5129 (cambiar ORDER BY para incluir tasa).

**Requiere --intercambio**: No.

**Nivel de esfuerzo**: Bajo.

**Dependencias**: Ninguna.

---

### TIER 5 — LIMPIEZA, DEUDA TÉCNICA Y MÓDULOS SECUNDARIOS

#### T5.1 — Definir AppTheme.warning como color diferente a primary

**Qué cambiar**: cambiar warning a un color naranja distinto (ej: #F7931A) para diferenciarlo del amarillo de marca. Actualizar todos los usos.

**Dónde**: lib/theme/app_theme.dart línea ~57.

**Requiere --intercambio**: No.

**Nivel de esfuerzo**: Muy bajo.

**Dependencias**: Ninguna.

---

#### T5.2 — Completar o documentar el módulo de Facturas QR

**Qué cambiar**: o documentarlo en SALARYING_TECNICO.tct + los skills, o agregar una nota en el código indicando que está en desarrollo. Actualmente el módulo existe en producción sin documentación ni integración con el resto de la app.

**Dónde**: lib/main_menu.dart línea ~168, backend/server.js línea ~4055.

**Requiere --intercambio**: No.

**Nivel de esfuerzo**: Bajo (documentación) / Alto (integración real).

**Dependencias**: Decisión de producto primero.

---

#### T5.3 — Actualizar SALARYING_TECNICO.tct con los endpoints actuales

**Qué cambiar**: el doc técnico describe el backend como versión 2.6 pero hay endpoints (patrones gustitos, cierre período, distribución clasificación, alertas mejoradas con alerta 0, proyección) que no están listados en la sección de endpoints o están descritos incompletamente.

**Dónde**: SALARYING_TECNICO.tct.

**Requiere --intercambio**: No.

**Nivel de esfuerzo**: Bajo.

**Dependencias**: Ninguna.

---

#### T5.4 — Eliminar Colors.orange del código (fuera del sistema de diseño)

**Qué cambiar**: _buildPeriodoCard() usa Colors.orange para "Ritmo ligeramente elevado". Cambiar a AppTheme.warning (una vez que T5.1 lo diferencie del primary).

**Dónde**: lib/dashboard_screen.dart línea ~559.

**Requiere --intercambio**: No.

**Nivel de esfuerzo**: Muy bajo.

**Dependencias**: T5.1.

---

## RESUMEN EJECUTIVO

La app tiene una base técnica sólida y varios módulos financieros bien pensados. Está a unas semanas de ser lo que debe ser, no a meses. Los problemas más urgentes son:

1. **El módulo de ahorro está roto** (monto_meta = cuota, no meta total) — le quita credibilidad a toda la app.
2. **El score de salud penaliza a los asalariados** — el usuario objetivo siempre estará en "Regular" o "Baja".
3. **Las recomendaciones financieras más importantes (alertas, análisis) están colapsadas** — nadie las ve.
4. **El período nuevo se abre en silencio** — el momento de mayor potencial para guiar al usuario se desperdicia.
5. **El Dashboard muestra demasiado para el usuario principal** — 3-4 de sus 8 cards son irrelevantes o generan ansiedad sin acción posible.

Los principios de **Autonomía Espectacular** y **Aprendizaje Orgánico** están presentes en el diseño conceptual pero no en la ejecución. Las features avanzadas están ahí, solo hace falta que la app las traiga a la superficie en el momento correcto, con el tono correcto, para la persona correcta.

---

*Generado: 2026-05-14 | Auditores: Asesor Financiero Harvard + María Pérez (QA) | Skills: asesor-financiero-salarying + maria-qa-salarying*
