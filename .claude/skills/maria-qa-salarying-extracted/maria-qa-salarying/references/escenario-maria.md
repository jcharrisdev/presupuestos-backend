# Escenario de María — Datos financieros completos

Usa estos datos cada vez que María pruebe algo, para que el QA sea consistente entre sesiones. Estos son los números exactos con los que María "tiene cargada" la app.

## Perfil
- **Nombre:** María Pérez
- **Edad:** 34
- **Ubicación:** Ciudad de Panamá (Pedregal)
- **Hogar:** pareja + 1 hijo de 7 años
- **Cuenta de la app:** maria.perez@gmail.com (login con Google)
- **Dispositivo:** Android gama media, ~3 años de uso, plan de datos limitado

## Ingreso
- **Salario bruto:** $1,500/mes
- **Pago:** quincenal ($750 por quincena, brutos)
- Descuentos de ley (mensuales sobre el bruto):
  - CSS (9.75%): ~$146.25
  - Seguro Educativo (1.25%): ~$18.75
  - ISR: sobre excedente de $916.67 → ($1,500 − $916.67) × 15% ≈ $87.50
  - **Total descuentos:** ~$252.50/mes
- **Ingreso neto aproximado:** ~$1,247.50/mes (~$623.75 por quincena)
- Tipo de ingreso en la app: **Salario**
- La pareja aporta algo, pero María maneja su presupuesto sobre SU ingreso (el presupuesto compartido lo usa solo para algunos gastos del hogar).

## Gastos mensuales típicos (presupuesto de María)

### Esenciales
- Comida / súper: ~$320
- Servicios (luz, agua, internet, teléfono): ~$140
- Transporte (pasaje + algo de gasolina del carro): ~$110
- Gastos escolares del hijo (prorrateados): ~$60

### Importantes
- Seguro del carro (prorrateado): ~$45

### Deudas (cuotas mensuales)
- **Hipoteca:** cuota ~$420/mes — tipo `hipoteca`
- **Préstamo de carro:** cuota ~$230/mes — tipo `auto`
- **Préstamo personal:** cuota ~$160/mes — tipo `personal`
- Algunas cuotas son descuento directo del salario, otras las paga ella.

### Flexible
- Gustitos (café, salidas, antojos, algo para el niño): lo que sobre — y casi nunca sobra.

## La cuenta que duele
Neto ~$1,247 − esenciales (~$630) − importantes (~$45) − deudas (~$810) = **sobrante de ~ -$238 a +$40** según el mes.

En la práctica María "cuadra" recortando comida y gustitos, y a veces atrasando un pago. **Su sobrante real ronda los $40, y algunos meses es negativo.** Este es el corazón del problema que la app debe ayudarla a ver y mejorar.

## Deudas — estado en la app (tabla `deudas`)
| Deuda | Tipo | Monto pendiente aprox | Tasa (mensual) | Pago mínimo |
|-------|------|----------------------|----------------|-------------|
| Casa | hipoteca | ~$48,000 | ~0.5% | ~$420 |
| Carro | auto | ~$9,500 | ~0.9% | ~$230 |
| Préstamo personal | personal | ~$3,200 | ~1.8% | ~$160 |

**Total pendiente:** ~$60,700. **Total pago mínimo mensual:** ~$810.
El préstamo personal es el de tasa más alta — debería ser prioridad de pago.

## Historial en la app
- María lleva **~4 períodos quincenales** registrados (suficiente para que las proyecciones de 3 períodos funcionen, pero apenas).
- Algunos períodos los cerró bien, en uno se pasó del presupuesto.
- Tiene **1 meta de ahorro** ("Fondo para emergencias") con muy poco progreso — apenas ~$60 ahorrados.
- Su **fondo de seguridad** está en **Nivel 0** (no llega ni a cubrir 1 período de gastos fijos).
- Usa el **presupuesto compartido** con su pareja para gastos del hogar (regla de reparto: proporcional a ingresos).
- Casi no usa los módulos de Ventas (no tiene negocio propio).

## Escenarios adversos a probar (la realidad de María)

María debe razonar estos escenarios al hacer QA de proyecciones y features financieras:

1. **Sube el pasaje / la gasolina:** +$25-40/mes en transporte. Su sobrante de $40 desaparece.
2. **El niño se enferma:** gasto médico inesperado de ~$150. No tiene fondo — ¿de dónde sale?
3. **Pierde 2 semanas de trabajo** (incapacidad, recorte de horas): pierde ~$310 de ingreso. Mes en rojo seguro.
4. **Llega el décimo** (abril/agosto/diciembre): ingreso extra de ~$500. Oportunidad de abonar a deuda — ¿la app la guía o lo ignora?
5. **Un electrodoméstico se daña:** gasto de ~$200 que no estaba en el plan.
6. **Atraso un pago de deuda:** ¿la app le muestra el costo real de atrasarse, o solo la regaña?

## Qué espera María de la app (su "definición de éxito")
- Ver **claro y rápido** cuánto le queda y si le alcanza.
- Entender **a dónde se le va la plata** sin sentirse tonta.
- Saber **cuál deuda atacar primero**.
- Ver si, mes a mes, **va saliendo del hueco o hundiéndose**.
- Que la app sea un **espacio privado y sin juicio** — no un regaño.
- Pequeñas victorias que la motiven a seguir abriendo la app.
