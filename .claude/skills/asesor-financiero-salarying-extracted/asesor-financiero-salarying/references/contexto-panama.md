# Contexto Financiero — Panamá

Referencia para validar cálculos y consejos específicos del país. Salarying se enfoca en usuarios panameños de clase media y baja.

## Moneda
- Panamá usa el **dólar estadounidense (USD)** como moneda de curso legal (junto al Balboa, 1:1).
- No hay riesgo cambiario interno — todos los montos en la app son USD.

## Descuentos de ley sobre el salario (lo que ya implementa la app)

Sobre el **salario bruto mensual**, al trabajador formal se le descuenta:

| Descuento | Tasa | Notas |
|-----------|------|-------|
| Seguro Social (CSS) | **9.75%** | obligatorio para empleados formales |
| Seguro Educativo (IFARHU) | **1.25%** | obligatorio |
| Impuesto sobre la Renta (ISR) | **15%** sobre el excedente de ~$916.67/mes | solo aplica si el ingreso supera el umbral |

El cálculo de ingreso neto en la app (`income_form_sheet.dart`) usa estas tasas. Al validar:
- Verifica que el ISR solo se aplique sobre el **excedente**, no sobre todo el salario.
- El umbral de ISR (~$11,000/año, ~$916.67/mes) es un piso — por debajo de eso el ISR es $0.
- Hay tramos superiores de ISR (25% sobre excedente de $50,000/año) pero son irrelevantes para el usuario objetivo; no compliques la app con ellos salvo que se pida.

## Realidad del trabajo informal

Una porción grande del usuario objetivo trabaja en la **informalidad** o de forma mixta:
- No tienen salario fijo ni descuentos de ley.
- Ingresos irregulares: por trabajo, por temporada, por venta.
- La app ya contempla tipos de ingreso `Informal / Ocasional / Préstamo / Otro` además de `Salario`.
- **Para estos usuarios, las proyecciones basadas en promedio histórico son más frágiles.** Cualquier consejo debe reconocer la variabilidad del ingreso.

## Ciclos de pago
- **Quincenal es muy común** en Panamá (días 15 y 30, o 15 y último). Muchos presupuestos en la app son quincenales.
- Mensual también existe.
- Nunca asumas solo ciclos mensuales en una fórmula o consejo.

## Costos de vida de referencia (Ciudad de Panamá, orden de magnitud)

Útil para juzgar si un presupuesto o consejo es realista. Cifras aproximadas para una familia de clase media-baja:

- Alquiler modesto / hipoteca: $350 – $700
- Comida (familia pequeña): $300 – $500
- Servicios (luz, agua, internet, teléfono): $100 – $200
- Transporte: $60 – $150 (transporte público es barato; gasolina si tiene carro sube esto mucho)
- Préstamo personal o de auto: cuota típica $150 – $400
- Colegio de un hijo (privado modesto) o gastos escolares: variable, $50 – $200/mes prorrateado

Con un salario de **$1,500**, después de gastos fijos y deudas, un sobrante de **$40** es perfectamente realista — y por eso la app existe.

## Notas culturales sobre el dinero

- **El "quincenazo":** es común gastar fuerte los días de pago y quedar corto antes de la siguiente quincena. La app debería ayudar a suavizar esto, no ignorarlo.
- **Préstamos informales / "fiao":** mucha gente debe dinero a familiares, tiendas, prestamistas informales. La app permite registrar deudas tipo `personal` y `otro` — bien.
- **Pena y evitación:** hablar de dinero, y sobre todo de deudas, genera vergüenza. La app debe ser un espacio privado y sin juicio.
- **Aguinaldo / Décimo tercer mes:** Panamá paga el "décimo" en tres partidas (abril, agosto, diciembre). Es un ingreso extra esperado — una feature de proyección bien hecha debería poder contemplarlo, pero NO asumirlo automáticamente.

## Banca y crédito
- Tasas de interés de tarjetas de crédito en Panamá son altas (a menudo 20%+ anual).
- Por eso la **regla de oro "deuda primero"** pesa fuerte: pagar una tarjeta rinde más que cualquier ahorro disponible para este usuario.
- La app registra `tasa_interes` como porcentaje **mensual** en la tabla `deudas` — cuidado de no confundir mensual vs anual al hacer cálculos o consejos.
