# ADR-005: Supabase + Cloudflare Pages en lugar de Firebase

**Estado**: Aceptado
**Fecha**: 2026-02
**Autores**: Arquitecto principal
**Tags**: backend, supabase, firebase, infraestructura, costos, vendor-lock-in

---

## Contexto

PILAR necesita un backend que provea:
- Base de datos relacional con ACID, transacciones, Foreign Keys e integridad referencial (requisito del modelo de datos del ERP)
- Autenticacion de usuarios con JWT, OAuth y email/password
- Row Level Security para multi-tenancy
- Almacenamiento de archivos (documentos autorizados, archivos generados, certificados digitales)
- Tiempo real (Realtime WebSocket) para notificaciones y colaboracion
- Funciones server-side para logica que no puede ir en el cliente (firma digital, procesamiento seguro)
- Busqueda semantica con vectores (pgvector) para modulos de inteligencia artificial
- Un plan gratuito o de bajo costo para la fase de desarrollo

Firebase es la plataforma BaaS mas conocida y con el ecosistema Flutter mas maduro (`firebase_core`, `cloud_firestore`, `firebase_auth`, etc.).

---

## Decision

Se adopta **Supabase** como backend y **Cloudflare Pages** para el deploy de la aplicacion web Flutter.

**No se usa Firebase en ninguna parte del stack.**

### Por que Supabase en lugar de Firebase

| Criterio | Supabase | Firebase |
|----------|----------|----------|
| Base de datos | PostgreSQL 15+ (relacional, ACID, FK, JOINs) | Firestore (NoSQL, documentos, sin JOINs) |
| Modelo de datos ERP | Nativo — relaciones complejas, tipos de documento con integridad referencial | Imposible modelar correctamente sin denormalizacion extrema |
| Row Level Security | Nativo en PostgreSQL — por fila, por columna, por rol | Firestore Security Rules — expresivas pero sin SQL real |
| Funciones server-side | Edge Functions (Deno/TypeScript) — cualquier logica | Cloud Functions (Node.js) — similar, pero lock-in mayor |
| Busqueda vectorial IA | pgvector extension nativa | Necesita servicio externo (Pinecone, Weaviate) |
| SQL y RPCs | RPCs PostgreSQL con cualquier complejidad | No existe SQL |
| Precio escalado | Predecible por compute/storage | Impredecible por lecturas/escrituras (Firestore cobra por documento leido) |
| Vendor lock-in | Bajo — PostgreSQL es estandar abierto, exportable | Alto — Firestore no tiene equivalente open-source directo |
| Open-source | Si — Supabase se puede self-host | No |

### Por que Cloudflare Pages en lugar de Firebase Hosting

| Criterio | Cloudflare Pages | Firebase Hosting |
|----------|-----------------|-----------------|
| Precio | Gratis para proyectos ilimitados | Plan Spark gratuito con limites (10GB/mes) |
| CDN global | Si, Cloudflare CDN (140+ PoPs) | Si, Google CDN |
| Build pipeline | Integrado con GitHub, Gitab | Integrado con GitHub |
| Workers (funciones Edge) | Cloudflare Workers disponibles | Cloud Functions (diferente plataforma) |
| Vendor consolidation | Independiente del backend | Complementa Firebase — aumenta vendor lock-in |

### Servicios Supabase Utilizados

| Servicio | Uso en PILAR |
|----------|-------------|
| PostgreSQL 15+ | Toda la base de datos |
| Supabase Auth | Autenticacion JWT, OAuth Google, magic links |
| `supabase_auth_ui` | Pantallas de login con branding por empresa |
| Supabase Storage | Archivos de documentos, certificados digitales, adjuntos |
| Supabase Realtime | WebSocket para notificaciones y colaboracion |
| Edge Functions (Deno) | Logica server-side: firma digital, generacion de documentos, procesamiento asincrono |
| pgvector extension | Busqueda semantica para modulos que requieren embeddings |

---

## Alternativas Rechazadas

### 1. Firebase (Firestore + Auth + Cloud Functions + Firebase Hosting)

- Firestore es NoSQL — no puede representar el modelo relacional de un ERP con integridad referencial sin denormalizacion masiva
- Las relaciones entre documentos, registros contables y movimientos operacionales son estructuras relacionales fundamentales
- No tiene pgvector para busqueda semantica
- Costo de Firestore por lectura es impredecible a escala (un reporte puede hacer miles de lecturas)
- **Rechazado por**: modelo de datos incompatible con los requisitos relacionales del ERP

### 2. AWS (RDS + Cognito + Lambda + S3 + CloudFront)

- Stack viable tecicamente, pero operacionalmente complejo para un equipo pequeno
- Cada componente requiere configuracion separada, IAM roles, VPC, subredes
- Costo alto desde el dia 1 (RDS t3.micro ~$15/mes + Cognito + Lambda + S3 + data transfer)
- No hay UI de admin comparable a Supabase Studio para el equipo de desarrollo
- **Rechazado por**: complejidad operacional excesiva y costo inicial

### 3. PlanetScale (MySQL) + Auth0 + Vercel

- PlanetScale es excelente para MySQL pero no tiene pgvector ni Row Level Security nativo
- La combinacion de 3 proveedores (PlanetScale + Auth0 + Vercel) aumenta la complejidad y los costos
- **Rechazado por**: ausencia de RLS nativo y pgvector, mas fragmentacion del stack

### 4. Supabase Self-Hosted

- Posible en el futuro, pero en la fase inicial se usa Supabase Cloud para reducir overhead operacional
- El codigo no tiene dependencias que impidan migrar a self-hosted despues
- **Pospuesto**: puede considerarse en fase de escala cuando los costos de Supabase Cloud sean significativos

---

## Consecuencias

### Positivas

- PostgreSQL es estandar de la industria: cualquier DBA puede trabajar con la BD de PILAR
- Exportacion de datos trivial: `pg_dump` — sin lock-in propietario
- La misma BD usada para el ERP puede consultarse con cualquier herramienta SQL (DBeaver, TablePlus, Metabase)
- RLS nativo elimina la necesidad de implementar filtrado de tenancy en codigo de aplicacion
- pgvector habilita modulos de busqueda semantica e inteligencia artificial sin un servicio externo adicional
- Cloudflare Pages es gratis y tiene CDN global — ideal para deploy de Flutter Web

### Negativas / Restricciones

- El ecosistema Flutter para Supabase es menos maduro que el de Firebase (menos paquetes, menos ejemplos publicos)
- `supabase_flutter` no tiene todas las funcionalidades de `firebase_*` — algunas cosas requieren implementacion custom
- El `.env` con las credenciales de Supabase (URL + anon key) NO debe ir a GitHub — requiere disciplina en el manejo de secretos

---

## Referencias

- ADR-001 — brick_offline_first_with_supabase (diseñado para Supabase)
- ADR-003 — patron RLS (nativo en PostgreSQL)
