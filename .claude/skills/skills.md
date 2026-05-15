# Preferencias globales - Jose Charris

## Stack preferido
- Backend: Node.js + Express
- Mobile: Flutter
- DB: MySQL (producción), Firebase (proyectos livianos)
- Estado en Flutter: Riverpod (preferido sobre Provider o Bloc)

## Convenciones
- Arquitectura en Flutter: Clean Architecture (data / domain / presentation)
- APIs: RESTful, respuestas siempre en JSON con estructura { success, data, message }
- Errores: siempre manejados con try/catch, nunca silenciados
- Variables y funciones: camelCase; clases: PascalCase

## Principios que aplico
- KISS antes que over-engineering
- No duplicar lógica (DRY)
- No construir lo que no se necesita aún (YAGNI)

## Preferencias de código
- Evitar callbacks anidados — usar async/await siempre
- Tests antes de marcar algo como completo
- Documentar endpoints con Swagger