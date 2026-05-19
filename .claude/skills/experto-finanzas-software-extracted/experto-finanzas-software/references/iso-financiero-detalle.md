# ISO Financiero — Requisitos Específicos por Norma

## ISO/IEC 27001:2022 — Seguridad de la Información

### Controles críticos para software financiero (Anexo A):
- **A.5.15** — Control de acceso: RBAC estricto, MFA obligatorio para operaciones >$X
- **A.5.33** — Protección de registros: logs de auditoría inmutables mínimo 5 años
- **A.8.7** — Protección contra malware: sandboxing de integraciones de terceros
- **A.8.24** — Uso de criptografía: política formal de gestión de claves
- **A.8.25** — Ciclo de vida de desarrollo seguro (SSDLC): revisión de código, SAST/DAST

### Documentación mínima requerida:
- Política de Seguridad de la Información (PSI)
- Análisis de Riesgos (ISO 27005)
- Plan de Tratamiento de Riesgos (PTR)
- Declaración de Aplicabilidad (SoA)
- Procedimiento de gestión de incidentes

---

## ISO 20022 — Mensajería Financiera

### Estructura de mensajes clave:
- **pacs.008** — Customer Credit Transfer (transferencias de cliente)
- **pacs.004** — Payment Return (devoluciones)
- **camt.053** — Bank to Customer Statement
- **pain.001** — Customer Credit Transfer Initiation

### Validaciones obligatorias en implementación:
```
- BIC (Business Identifier Code) válido
- IBAN checksum correcto
- Moneda ISO 4217 válida
- Fechas en formato ISO 8601
- Importes con precisión decimal según moneda
- LEI (Legal Entity Identifier) para entidades
```

### Migración SWIFT a ISO 20022 (deadline: Nov 2025):
Todos los sistemas deben soportar mensajes ISO 20022 y co-existir con MT durante periodo de transición.

---

## ISO 31000:2018 — Gestión de Riesgos

### Proceso de evaluación de riesgo financiero en software:

**1. Identificación de riesgos:**
- Riesgo de crédito (impago, scoring incorrecto)
- Riesgo operacional (fallas del sistema, errores humanos)
- Riesgo de liquidez (incapacidad de procesar retiros)
- Riesgo legal/regulatorio (incumplimiento de normas)
- Riesgo de reputación (fuga de datos, mal servicio)
- Riesgo tecnológico (ciberseguridad, obsolescencia)

**2. Matriz de riesgo recomendada:**
```
Probabilidad × Impacto = Nivel de Riesgo
Alta × Alto = CRÍTICO → Acción inmediata
Alta × Medio = ALTO → Mitigar en 30 días
Baja × Alto = ALTO → Plan de contingencia
Baja × Bajo = BAJO → Monitoreo periódico
```

**3. Apetito de riesgo para fintech clase media/baja:**
- Tolerancia CERO a pérdida de fondos del usuario por error del sistema
- Tolerancia CERO a exposición de datos financieros de usuario
- Baja tolerancia a downtime >15 min en horario pico (6am-10pm)

---

## ISO 22301:2019 — Continuidad del Negocio

### RTO y RPO mínimos recomendados para apps financieras:

| Función | RTO | RPO |
|---------|-----|-----|
| Procesamiento de pagos | <30 min | <5 min |
| Consulta de saldo | <1 hora | <15 min |
| Transferencias | <1 hora | <5 min |
| Atención al cliente | <4 horas | <1 hora |
| Reportes regulatorios | <24 horas | <1 hora |

### Plan mínimo de BCP:
1. Identificación de procesos críticos (BIA)
2. Estrategias de recuperación por proceso
3. Procedimientos de activación del plan
4. Comunicación de crisis (usuarios, regulador, medios)
5. Pruebas anuales de recuperación (obligatorio)

---

## PCI-DSS v4.0 — Procesamiento de Tarjetas

### Los 12 requisitos fundamentales:
1. Instalar y mantener firewall
2. No usar defaults del proveedor para contraseñas
3. Proteger datos del titular de tarjeta
4. Cifrar transmisión de datos en redes abiertas
5. Proteger sistemas contra malware
6. Desarrollar y mantener sistemas seguros
7. Restringir acceso a datos por necesidad de negocio
8. Identificar y autenticar acceso a componentes del sistema
9. Restringir acceso físico a datos del titular
10. Registrar y monitorear accesos a recursos de red y datos
11. Probar regularmente sistemas y procesos de seguridad
12. Mantener política de seguridad de información

### Niveles de comerciante PCI-DSS:
- **Nivel 1**: >6M transacciones/año → QSA on-site audit
- **Nivel 2**: 1-6M → SAQ + escaneo trimestral
- **Nivel 3**: 20K-1M e-commerce → SAQ + escaneo
- **Nivel 4**: <20K → SAQ anual recomendado

---

## ISO/IEC 42001:2023 — Sistemas de IA

### Aplica si el software usa IA/ML para:
- Scoring crediticio (CRÍTICO — impacto directo en acceso financiero)
- Detección de fraude
- Recomendaciones de productos financieros
- Chatbots de atención al cliente financiero

### Requisitos clave:
- **Transparencia**: el usuario debe saber si una decisión la tomó una IA
- **Explicabilidad**: el sistema debe poder explicar por qué negó un crédito
- **No discriminación**: auditoría de sesgos en modelos de scoring
- **Supervisión humana**: siempre debe existir canal de apelación humano
- **Documentación del modelo**: datos de entrenamiento, métricas, limitaciones

⚠️ **Advertencia crítica**: Un modelo de scoring crediticio sesgado puede excluir sistemáticamente a personas de clase media-baja legítimamente solventes. Requiere auditoría de equidad obligatoria.
