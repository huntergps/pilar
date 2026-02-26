# Gestión de Archivos — Foundation Layer

## Resumen

El sistema de gestión de archivos es un **servicio transversal de foundation** (no un módulo independiente).
Proporciona la infraestructura para que cualquier entidad del sistema pueda almacenar y recuperar adjuntos.

Patrón de referencia: **Odoo → Settings > Technical > Attachments** (gestor documental centralizado en administración).

---

## Arquitectura

```
Foundation (Core Services)
├── StorageService        ← logos, avatares, signed URLs
├── UploadService         ← TUS resumable upload, FilePicker
├── AdjuntoModel          ← modelo polimórfico (entidad_tipo + entidad_id)
├── AdjuntosProvider      ← Riverpod: lectura, notifier con upload/eliminar/renombrar
└── AdjuntosPanel         ← widget embebible en cualquier pantalla de detalle

Módulo Administración
└── ArchivosScreen        ← Gestor documental global (Settings > Archivos)
```

### Flujos

1. **Upload embebido** (desde cualquier pantalla de entidad):
   ```
   Usuario → AdjuntosPanel → UploadService.pickFile()
          → UploadService.uploadResumable() [TUS, con barra de progreso]
          → Supabase.rpc('registrar_adjunto') [registra en DB]
          → AdjuntosNotifier refresh
   ```

2. **Gestor documental admin** (vista global):
   ```
   Administración > Archivos → ArchivosScreen
   → todosAdjuntosProvider(filtros) → Supabase.rpc('get_todos_adjuntos')
   → SfDataGrid (≥600px) | ListView cards (<600px)
   ```

---

## Buckets Supabase Storage

| Bucket | Tipo | Límite | Usos | URL |
|--------|------|--------|------|-----|
| `logos` | Público | 2 MB | Logos de empresa | CDN + image transforms |
| `avatares` | Privado | 2 MB | Avatares de usuarios | Signed URL 24 h |
| `adjuntos` | Privado | 50 MB | Todos los adjuntos de entidades | Signed URL 1 h |

### Image transforms (solo `logos`)
```
{supabaseUrl}/storage/v1/render/image/public/logos/{path}?width=200&quality=85&format=webp
```

---

## Tabla `adjuntos`

```sql
CREATE TABLE adjuntos (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id    UUID NOT NULL REFERENCES empresas(id),
  entidad_tipo  TEXT NOT NULL,   -- 'factura', 'contacto', 'empresa', etc.
  entidad_id    UUID NOT NULL,
  nombre        TEXT NOT NULL,   -- nombre para mostrar (editable)
  nombre_original TEXT NOT NULL, -- nombre original del archivo
  mime_type     TEXT NOT NULL,
  tamanio_bytes BIGINT NOT NULL,
  storage_path  TEXT NOT NULL,   -- path dentro del bucket "adjuntos"
  storage_bucket TEXT NOT NULL DEFAULT 'adjuntos',
  descripcion   TEXT,
  es_publico    BOOLEAN NOT NULL DEFAULT false,
  subido_por    UUID REFERENCES auth.users(id),
  activo        BOOLEAN NOT NULL DEFAULT true,   -- soft delete
  tags          TEXT[] NOT NULL DEFAULT '{}',    -- etiquetas libres
  version       INTEGER NOT NULL DEFAULT 1,      -- versionado futuro
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

### Índices clave
- `idx_adjuntos_empresa_entidad` — búsqueda por entidad (RLS + query)
- `idx_adjuntos_tags` — GIN para búsqueda en arrays de tags
- `idx_adjuntos_activo` — filtro soft delete

---

## RPCs

| Función | Descripción |
|---------|-------------|
| `registrar_adjunto(empresa_id, entidad_tipo, entidad_id, nombre, nombre_original, mime_type, tamanio_bytes, storage_path, p_tags)` | Registra un archivo subido. Tags opcionales. |
| `get_adjuntos(entidad_tipo, entidad_id)` | Lista adjuntos activos de una entidad. |
| `get_adjuntos_count(entidad_tipo, entidad_id)` | Conteo rápido para badges. |
| `get_todos_adjuntos(entidad_tipo?, tag?, search?, limit?, offset?)` | Gestor documental: todos los adjuntos de la empresa con filtros. |
| `eliminar_adjunto(adjunto_id)` | Soft delete (`activo = false`). |
| `renombrar_adjunto(adjunto_id, nombre)` | Cambia el nombre visible. |
| `agregar_tag_adjunto(adjunto_id, tag)` | Añade un tag sin duplicar. |
| `quitar_tag_adjunto(adjunto_id, tag)` | Elimina un tag específico. |
| `set_logo_empresa(empresa_id, logo_url)` | Actualiza `empresas.logo_url`. |

---

## Clases Flutter

### `StorageService` (`lib/core/services/storage_service.dart`)

```dart
abstract final class StorageService {
  // Logos — públicos, CDN, image transforms
  static Future<String> uploadLogo({required PlatformFile file, required String empresaId})
  static Future<String?> logoTransformUrl(String? logoUrl, {int width=200, ...})

  // Avatares — privados, signed URL 24 h
  static Future<String> uploadAvatar({required PlatformFile file, required String userId})
  static Future<String?> avatarSignedUrl(String userId, {int expiresInSeconds=3600})

  // Adjuntos — signed URL genérica
  static Future<String?> signedUrl(String storagePath, {String bucket='adjuntos', ...})
}
```

### `AdjuntoModel` (`lib/core/models/adjunto_model.dart`)

Modelo inmutable con helpers visuales: `iconCategory`, `tamanioLabel`, `extension`.
Soporta `tags: List<String>` y `version: int`.

### `AdjuntosPanel` (`lib/core/widgets/adjuntos_panel.dart`)

Widget embebible en cualquier pantalla de detalle:

```dart
AdjuntosPanel(
  empresaId: empresaId,
  entidadTipo: 'factura',
  entidadId: facturaId,
  defaultTags: ['factura', '2026-01'],  // opcionales, pre-etiquetan el archivo
  allowedExtensions: ['pdf', 'xml'],    // null = cualquier tipo
)
```

Funciones: listar, subir (TUS con progreso), eliminar (con confirmación), renombrar.

### `ArchivosScreen` (`lib/features/administracion/screens/archivos_screen.dart`)

Gestor documental en el panel de Administración. Accesible en: **Administración > Archivos**.

Filtros: búsqueda por nombre (debounce 400 ms), tipo de entidad, tag libre.
Vista: `SfDataGrid` (≥600 px) con columnas tipo/nombre/tamaño/tags/fecha/acciones, `ListView` cards (<600 px).
Acciones por fila: Abrir (signed URL → browser), Eliminar (con diálogo de confirmación).

---

## Convenciones

- **Soft delete siempre**: `activo = false`, nunca `DELETE` en adjuntos.
- **Storage path**: `{empresa_id}/{entidad_tipo}/{entidad_id}/{uuid}_{nombre_original}`.
- **Tags**: arrays libres sin vocabulario controlado. Cada módulo puede pre-etiquetar con `defaultTags`.
- **Signed URL**: 1 hora para adjuntos, 24 horas para avatares. Regenerar al expirar.
- **Image transforms**: solo para logos (bucket público). No usar con adjuntos privados.
- **RLS**: toda operación filtrada por `empresa_id` via `private.get_empresa_id()`.

---

## Migración

`foundation/supabase/migrations/20260101000047_gestion_archivos.sql`

Incluye:
- `ALTER TABLE adjuntos ADD COLUMN tags`, `version`
- Índice GIN en `tags`
- Buckets `logos` y `avatares` con Storage policies
- RPCs: `registrar_adjunto` (nuevo con tags), `get_todos_adjuntos`, `agregar_tag_adjunto`, `quitar_tag_adjunto`, `set_logo_empresa`
