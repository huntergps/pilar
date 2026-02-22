# Estructura de Archivos: Foundation

Directorio de infraestructura base (country-agnostic). Los módulos se construyen sobre esta base.

```
foundation/
├── migrations/                 # Migraciones SQL de infraestructura base
│   ├── 001_core_foundation.sql # Tablas base: empresas, roles, usuarios, módulos
│   ├── 002_*.sql               # ...
│   └── 00N_*.sql
├── functions/                  # Edge Functions de infraestructura
│   ├── _shared/
│   │   └── cors.ts             # Helper CORS genérico
│   └── upload-logo/            # Subir logo de empresa a Storage
├── adrs/                       # Decisiones de arquitectura (ADR-001 al ADR-009)
├── integraciones/              # Patrones genéricos de integración
│   ├── pagos.md                # Patrón adaptador de pagos
│   └── n8n.md                  # Automatizaciones con n8n
├── apis/                       # Convenciones de API y RPCs
│   └── rpcs-por-modulo.md
├── sistema-base.md             # START HERE — Auth, Empresas, Módulos
├── arquitectura.md             # Capas, Riverpod, Brick, RLS, PilarShell
├── arquitectura-modular.md     # Module Service Bus, ModuleSlot, ciclo de vida
├── modelo-datos.md             # Schema PostgreSQL de infraestructura base
├── seguridad.md                # RLS, auth, cifrado
├── background-jobs.md          # pg_cron + pgmq
├── roadmap.md                  # Fases P1/P2/P3
└── indice.md                   # Índice de documentación
```

Para la estructura completa del proyecto Flutter (incluyendo módulos), ver:
`pilar/estructura-proyecto.md`
