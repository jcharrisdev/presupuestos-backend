# Patrones de Software Financiero — Arquitecturas y Mejores Prácticas

## Arquitecturas Recomendadas

### Para Fintech B2C (apps de usuario final)

```
┌─────────────────────────────────────────────────────────┐
│                    CLIENTE (Mobile/Web)                  │
│         React Native / Flutter / PWA                     │
└────────────────────┬────────────────────────────────────┘
                     │ HTTPS / TLS 1.3
┌────────────────────▼────────────────────────────────────┐
│                   API GATEWAY                            │
│    Rate limiting | Auth (JWT/OAuth2) | WAF               │
└────────────────────┬────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────┐
│              MICROSERVICIOS / MÓDULOS                    │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌────────────┐ │
│  │  Wallets │ │ Payments │ │  Credit  │ │   Users    │ │
│  │ Service  │ │ Service  │ │ Service  │ │  Service   │ │
│  └──────────┘ └──────────┘ └──────────┘ └────────────┘ │
└────────────────────┬────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────┐
│                  CAPA DE DATOS                           │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────────┐  │
│  │  PostgreSQL  │  │    Redis     │  │  Audit Log    │  │
│  │  (principal) │  │   (caché)    │  │  (inmutable)  │  │
│  └──────────────┘  └──────────────┘  └───────────────┘  │
└─────────────────────────────────────────────────────────┘
```

### Principios arquitectónicos no negociables:

**1. Audit Trail Inmutable**
```sql
CREATE TABLE audit_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_type VARCHAR(100) NOT NULL,
  entity_type VARCHAR(100) NOT NULL,
  entity_id UUID NOT NULL,
  user_id UUID,
  before_state JSONB,
  after_state JSONB,
  metadata JSONB,
  created_at TIMESTAMPTZ DEFAULT now(),
  ip_address INET,
  user_agent TEXT
  -- SIN columnas de update/delete — registro append-only
);

-- Política de RLS para prevenir eliminación
ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY audit_log_no_delete ON audit_log FOR DELETE USING (false);
```

**2. Idempotencia en transacciones**
```javascript
// Toda operación financiera debe tener idempotency_key
async function processPayment(payment, idempotencyKey) {
  // Verificar si ya fue procesado
  const existing = await db.transactions.findOne({
    idempotency_key: idempotencyKey
  });
  if (existing) return existing; // Retornar resultado previo, no duplicar
  
  // Procesar y guardar con la key
  return await db.transactions.create({
    ...payment,
    idempotency_key: idempotencyKey,
    status: 'completed'
  });
}
```

**3. Estados de transacción explícitos**
```
PENDING → PROCESSING → COMPLETED
                    ↓
                FAILED → puede reintentar
                    ↓
                REVERSED (solo con autorización)
```
Nunca eliminar un registro de transacción. Solo revertir.

---

## Patrones de Seguridad

### Autenticación y Autorización

```javascript
// JWT con expiración corta para operaciones financieras
const token = jwt.sign(
  { userId, role, sessionId },
  process.env.JWT_SECRET,
  { expiresIn: '15m' } // Máximo 15 min para operaciones sensibles
);

// Refresh token con rotación (invalidar el anterior al usar)
// MFA obligatorio para:
// - Transferencias > $X (definir umbral por segmento)
// - Cambio de datos personales
// - Primer acceso desde nuevo dispositivo
// - Transacciones nocturnas (10pm - 6am)
```

### Cifrado de datos sensibles en BD
```sql
-- Usar pgcrypto para datos sensibles en reposo
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Ejemplo: número de cuenta enmascarado
INSERT INTO bank_accounts (
  user_id,
  account_number_encrypted,
  account_number_masked,
  bank_code
) VALUES (
  $userId,
  pgp_sym_encrypt($accountNumber, $encryptionKey),
  '****' || RIGHT($accountNumber, 4),
  $bankCode
);
```

### Prevención de fraude — Reglas básicas
```javascript
const fraudRules = [
  // Velocidad: muchas transacciones en poco tiempo
  { rule: 'velocity', maxTransactions: 10, windowMinutes: 60 },
  // Monto inusual: >3x el promedio del usuario
  { rule: 'unusual_amount', multiplier: 3, lookbackDays: 30 },
  // Geolocalización: país diferente al habitual
  { rule: 'geo_anomaly', allowedCountries: ['PA', 'CR', 'CO'] },
  // Dispositivo nuevo + monto alto = revisión manual
  { rule: 'new_device_high_amount', threshold: 500, reviewRequired: true }
];
```

---

## Patrones de Cálculo Financiero

### Cálculo correcto de intereses (crítico)

```javascript
// INCORRECTO (interés simple mal aplicado)
const interestBad = principal * rate * months; // ❌

// CORRECTO: Interés simple
const interestSimple = principal * (rate / 12) * months;

// CORRECTO: Interés compuesto mensual
const totalCompound = principal * Math.pow(1 + rate / 12, months);
const interestCompound = totalCompound - principal;

// CORRECTO: Sistema francés (cuota fija) — el más común en créditos
function cuotaFrancesa(principal, rateAnual, meses) {
  const r = rateAnual / 12; // tasa mensual
  if (r === 0) return principal / meses;
  return (principal * r * Math.pow(1 + r, meses)) / 
         (Math.pow(1 + r, meses) - 1);
}

// SIEMPRE mostrar:
// 1. Cuota mensual
// 2. Total a pagar (cuota × meses)
// 3. Total de intereses (total - principal)
// 4. TEA (Tasa Efectiva Anual)
// 5. CAT si aplica (Costo Anual Total, incluye comisiones)
```

### Score de salud financiera — Componentes recomendados
```javascript
function calcularScoreSalud(data) {
  const factores = {
    // Ratio deuda/ingreso (ideal: <30%)
    ratioDeuda: (1 - Math.min(data.cuotasDeuda / data.ingreso, 1)) * 25,
    
    // Fondo de emergencia (ideal: 3-6 meses de gastos)
    fondoEmergencia: Math.min(data.ahorro / (data.gastos * 3), 1) * 25,
    
    // Cumplimiento de pagos (0-100% de pagos al día)
    historialPago: data.pagosAlDia / data.totalPagos * 25,
    
    // Ahorro activo (ahorra algo cada mes)
    habito_ahorro: data.ahorroMensual > 0 ? 25 : 0
  };
  
  const score = Object.values(factores).reduce((a, b) => a + b, 0);
  
  // Nunca usar lenguaje punitivo
  const niveles = {
    '0-40': { label: 'En construcción', color: '#F59E0B', mensaje: 'Cada pequeño paso cuenta' },
    '41-60': { label: 'Avanzando', color: '#3B82F6', mensaje: 'Vas por buen camino' },
    '61-80': { label: 'Sólido', color: '#10B981', mensaje: 'Tu economía está estable' },
    '81-100': { label: 'Excelente', color: '#6366F1', mensaje: 'Eres un ejemplo a seguir' }
  };
  
  return { score, ...getNivel(score, niveles) };
}
```

---

## Checklist de Lanzamiento (Production Readiness)

### Seguridad (ISO 27001)
- [ ] HTTPS/TLS 1.3 en todos los endpoints
- [ ] Certificados válidos y con renovación automática
- [ ] WAF (Web Application Firewall) configurado
- [ ] Rate limiting en APIs críticas
- [ ] Secrets en vault (no en código ni variables de entorno en texto plano)
- [ ] SAST/DAST ejecutado sin vulnerabilidades críticas
- [ ] Penetration test realizado (o agendado)
- [ ] MFA implementado para operaciones sensibles

### Compliance
- [ ] Política de privacidad clara y accesible (ley 81 de Panamá si aplica)
- [ ] Consentimiento explícito para uso de datos
- [ ] Mecanismo de eliminación de cuenta y datos (derecho al olvido)
- [ ] KYC implementado según nivel de riesgo regulatorio
- [ ] Reporte a SEPBLAC/UAF si aplica (AML reporting)

### Calidad (ISO/IEC 25010)
- [ ] Cobertura de tests >80% en lógica financiera
- [ ] Tests de integración con sistemas de pago
- [ ] Pruebas de carga (¿cuántos usuarios simultáneos aguanta?)
- [ ] Prueba de recuperación ante fallo (BCP/DR test)
- [ ] Monitoreo de errores en producción (Sentry, Datadog, etc.)
- [ ] SLA definido y medible

### Experiencia de Usuario (para clase media/baja)
- [ ] Flujo completo probado con usuarios reales del segmento objetivo
- [ ] Accesible en conexiones 3G lentas
- [ ] Funciona en smartphones de gama baja (Android 8+, 2GB RAM)
- [ ] Textos revisados por alguien sin formación financiera
- [ ] Cero dark patterns en flujos de crédito o cobros
- [ ] Soporte humano disponible (no solo chatbot)
