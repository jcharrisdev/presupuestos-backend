# Finanzas de Clase Media y Baja — Hallazgos de Investigación de Campo

## Contexto: Panamá y Latinoamérica

### Datos estructurales (Panamá 2024)
- Población económicamente activa: ~2.1M personas
- Sector informal: ~40% de la fuerza laboral
- Bancarización formal: ~65% (pero uso activo de cuentas: ~45%)
- Smartphone penetration: ~78%
- Gini coefficient: 0.49 (alta desigualdad)
- Salario mínimo: B/. 800-1,100/mes según sector
- Canasta básica familiar: ~B/. 650-750/mes

### Clasificación de clases socioeconómicas aplicable:
| Clase | Ingreso mensual familiar | % Población |
|-------|--------------------------|-------------|
| Alta | >$5,000 | ~5% |
| Media-alta | $2,500–$5,000 | ~15% |
| Media | $1,200–$2,500 | ~30% |
| Media-baja | $600–$1,200 | ~30% |
| Baja | <$600 | ~20% |

---

## Comportamientos Financieros Documentados

### Clase Media ($1,200–$2,500/mes)

**Patrones de ingreso:**
- Mayoritariamente empleo formal con 13° mes
- Algunos tienen ingresos complementarios informales (20-40% de casos)
- Alta dependencia de crédito de consumo para bienes duraderos

**Estructura de gastos típica:**
- Vivienda (alquiler/hipoteca): 30-40%
- Alimentación: 20-25%
- Transporte: 10-15%
- Educación hijos: 10-15%
- Deuda (cuotas): 15-25% → zona de riesgo si supera 30%
- Ahorro efectivo: 0-5% (frecuentemente nulo)

**Comportamientos problemáticos identificados:**
1. **Ilusión de solvencia**: se sienten "de clase media" pero no tienen colchón de emergencias
2. **Deuda rotativa crónica**: pagan mínimos de tarjeta mes a mes (costo real: 30-50% TEA)
3. **Sobrecarga de cuotas**: 3-5 préstamos simultáneos sin visión de conjunto
4. **Ahorro reactivo** (solo cuando hay excedente, que casi nunca hay)
5. **Desconocimiento del costo real del crédito**: confunden cuota mensual con costo total

**Lo que buscan en una app financiera:**
- Ver todo en un solo lugar
- Entender cuánto deben realmente
- Proyectar si pueden pagar algo nuevo
- No sentirse juzgados ni avergonzados

---

### Clase Media-Baja y Baja ($600–$1,200/mes)

**Patrones de ingreso:**
- Mixto formal-informal (empleo por días, trabajo doméstico, ventas)
- Ingresos irregulares (semana a semana, quincena variable)
- Dependencia de remesas familiares en segmento más bajo

**Estructura de gastos:**
- Vivienda: 35-50% (frecuentemente sin contrato formal)
- Alimentación: 30-40% (alta elasticidad ante shocks)
- Transporte: 15-20%
- Deuda informal: 10-30% (el porcentaje más preocupante)
- Ahorro: prácticamente nulo en términos monetarios

**Mecanismos de ahorro informales prevalentes:**
- **"Juntas" o "natillas"**: grupos de 10-20 personas que aportan mensualmente y rotan el pozo. Participación: 40-60% de hogares de clase baja encuestados.
- **Alcancías físicas**: ahorro en efectivo en casa
- **Compra de electrodomésticos como "ahorro"**: percepción de que tener un bien es más seguro que tener efectivo
- **Inversión en animales de crianza** (gallinas, cerdos) en áreas semi-rurales

**Acceso a crédito:**
- Bancos formales: difícil acceso (sin historial, sin garantías)
- Cooperativas: acceso moderado, tasas 12-24% TEA
- Financieras de consumo: acceso fácil, tasas 36-60% TEA
- Prestamistas informales ("gota a gota"): 200-700% TEA equivalente
- Casas de empeño: frecuentes, alta rotación

**Traumas financieros documentados:**
1. Haber perdido bienes por no entender los términos de un préstamo
2. Cargos inesperados que dejaron cuenta en negativo
3. Cobros automáticos que no pudieron detener
4. Llamadas de cobranza agresiva frente a familia
5. Sentir vergüenza en sucursales bancarias (trato discriminatorio percibido)

**Lo que bloquea la adopción de apps financieras:**
- Desconfianza: "y si ponen mi plata mal"
- Miedo a cobros ocultos
- No entienden los términos (literacia financiera muy baja)
- Miedo a que los rechacen / cataloguen
- Privacidad: no quieren que otros sepan cuánto ganan

---

## Hallazgos Clave para Diseño de Software

### Principios validados en campo:

**1. El lenguaje importa más que la funcionalidad**
- "Tasa efectiva anual" → nadie lo entiende
- "Si pides $500, en total pagarás $620 en 6 meses" → todos lo entienden
- Usar palabras cotidianas, nunca jerga financiera sin explicación

**2. La confianza se gana con pequeñas victorias**
- No pidas todos los datos al inicio
- Muestra valor antes de pedir permisos
- El primer "wow" debe ocurrir en menos de 2 minutos de uso

**3. El tiempo es dinero (en serio)**
- Cada paso extra en un proceso de pago cuesta usuarios de este segmento
- Pero la fricción protectora en montos altos es bienvenida ("me protege de errores")

**4. La vergüenza es un bloqueador enorme**
- Nunca mostrar mensajes de error que hagan sentir "estúpido" al usuario
- Nunca comparar con otros usuarios
- El scoring de salud financiera NUNCA debe ser punitivo en el lenguaje

**5. El efectivo sigue siendo rey (pero está cediendo)**
- Integrar con puntos de pago físicos (Farmacias, Super 99, ACH) es crítico
- El depósito y retiro en efectivo es tan importante como la transferencia digital

**6. La familia es la unidad financiera real**
- Las decisiones financieras se toman en pareja/familia, no individualmente
- Funcionalidades de metas compartidas o presupuesto familiar tienen alta adopción

---

## Errores Comunes en Apps para Este Segmento

### Errores de diseño que destruyen confianza:
1. Mostrar saldo en rojo o con iconos de alarma sin contexto constructivo
2. Sugerir créditos cuando el usuario ya está sobreendeudado
3. Onboarding que pide CURP/cédula, selfie, cuenta bancaria y empleo ANTES de mostrar valor
4. Notificaciones de "¡Tienes crédito pre-aprobado!" sin revelar la tasa
5. Términos y condiciones en letra pequeña que el usuario no puede leer en móvil

### Errores de negocio éticamente cuestionables:
1. Diseñar el flujo de crédito para que el usuario no vea la tasa hasta el último paso
2. Renovación automática de créditos con tasa más alta sin notificación clara
3. Cobrar comisión por retiro de los propios fondos del usuario sin advertirlo
4. Usar datos de comportamiento para subir tasas de interés silenciosamente
5. Hacer que cancelar un servicio sea extremadamente difícil

---

## Recomendaciones de Inclusión Financiera Basadas en Evidencia

### Funcionalidades con mayor impacto comprobado:
1. **Registro de gastos simplificado** (foto del ticket → categorización automática)
2. **Metas de ahorro con progreso visual** (el "efecto hucha" digital)
3. **Simulador de crédito honesto** (muestra costo total, no solo cuota)
4. **Alertas de saldo bajo** antes de que cause problemas
5. **Historial de gastos en lenguaje simple** ("Gastaste 40% en comida este mes")
6. **Presupuesto por quincena** (no mensual — la gente cobra quincenal)
7. **Comparador de opciones de crédito** (cooperativa vs banco vs financiera)

### Funcionalidades que parecen buenas pero fallan:
- Gamificación agresiva (se percibe como condescendiente)
- Recomendaciones de inversión en bolsa (fuera de contexto para este segmento)
- Integración forzosa con redes sociales
- Chatbots sin opción de agente humano
