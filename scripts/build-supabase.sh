#!/usr/bin/env bash
# =============================================================================
# PILAR ERP — build-supabase.sh
#
# Ensambla las migraciones SQL y Edge Functions de los módulos dentro del
# CLI project root de Supabase: foundation/supabase/
#
# Estructura fuente (fuentes editables):
#   foundation/supabase/migrations/   → Foundation: 0NN_*.sql (NO se tocan)
#   foundation/supabase/functions/    → Foundation functions (NO se tocan)
#   modules/<tipo>/<mod>/supabase/migrations/
#   modules/<tipo>/<mod>/supabase/functions/
#
# Artefactos de salida (generados, no editar directamente):
#   foundation/supabase/migrations/mod_NNN_<modulo>_<file>.sql
#   foundation/supabase/functions/<nombre>/
#
# Uso:
#   ./scripts/build-supabase.sh                    # Todos los módulos
#   ./scripts/build-supabase.sh --only facturacion # Solo ese módulo
#   ./scripts/build-supabase.sh --skip ia rrhh     # Excluir módulos
# =============================================================================

set -euo pipefail

BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_DIR="$BASE/foundation/supabase"
MIGRATIONS_DIR="$TARGET_DIR/migrations"
FUNCTIONS_DIR="$TARGET_DIR/functions"

# Foundation functions que nunca se eliminan ni sobreescriben
FOUNDATION_FUNCTIONS=("_shared" "auth-setup-handler" "invite-user" "upload-logo")

# ─── Colores ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC} $*"; }
warning() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
section() { echo -e "${CYAN}$*${NC}"; }

# ─── Argumentos ───────────────────────────────────────────────────────────────
SKIP_MODULES=()
ONLY_MODULE=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --skip)
      shift
      while [[ $# -gt 0 && ! "$1" =~ ^-- ]]; do
        SKIP_MODULES+=("$1")
        shift
      done
      ;;
    --only)
      shift
      [[ $# -gt 0 ]] || error "--only requiere un argumento"
      ONLY_MODULE="$1"
      shift
      ;;
    *)
      error "Argumento desconocido: $1. Uso: --skip <mod>... | --only <mod>"
      ;;
  esac
done

is_foundation_function() {
  local name="$1"
  for fn in "${FOUNDATION_FUNCTIONS[@]}"; do
    [[ "$fn" == "$name" ]] && return 0
  done
  return 1
}

should_skip() {
  local mod="$1"
  if [[ -n "$ONLY_MODULE" && "$ONLY_MODULE" != "$mod" ]]; then
    return 0
  fi
  for s in "${SKIP_MODULES[@]:-}"; do
    [[ "$s" == "$mod" ]] && return 0
  done
  return 1
}

# ─── Validar que el target existe ─────────────────────────────────────────────
[[ -d "$MIGRATIONS_DIR" ]] || error "No existe el directorio: $MIGRATIONS_DIR"
[[ -d "$FUNCTIONS_DIR"  ]] || error "No existe el directorio: $FUNCTIONS_DIR"

# ─── Cleanup: eliminar solo artefactos generados previamente ─────────────────
section "── Limpiando artefactos anteriores ────────────────────────────────"

# Solo eliminar mod_*.sql (nunca tocar 0NN_*.sql de foundation)
MOD_FILES=("$MIGRATIONS_DIR"/mod_*.sql)
if [[ -e "${MOD_FILES[0]}" ]]; then
  for f in "${MOD_FILES[@]}"; do
    rm -f "$f"
    info "  Eliminado: $(basename "$f")"
  done
else
  info "  Sin archivos mod_*.sql anteriores"
fi

# Eliminar subdirectorios de functions que NO sean de foundation
for fn_dir in "$FUNCTIONS_DIR"/*/; do
  [[ -d "$fn_dir" ]] || continue
  fn_name="$(basename "$fn_dir")"
  if ! is_foundation_function "$fn_name"; then
    rm -rf "$fn_dir"
    info "  Eliminado functions/$fn_name"
  fi
done

# ─── Calcular NNN inicial: después del último foundation migration ────────────
FOUNDATION_COUNT=$(ls "$MIGRATIONS_DIR"/[0-9]*.sql 2>/dev/null | wc -l | tr -d ' ')
N=$((FOUNDATION_COUNT + 1))

info "  Foundation: $FOUNDATION_COUNT migraciones encontradas (001 … $(printf '%03d' "$FOUNDATION_COUNT"))"
info "  Módulos empezarán en: $(printf '%03d' "$N")"

# ─── Contadores para el resumen ───────────────────────────────────────────────
MOD_MIGRATIONS=0
FUNC_COUNT=0

# ─── Funciones de copia ───────────────────────────────────────────────────────

copy_migrations() {
  local module_name="$1"
  local src_dir="$2/supabase/migrations"

  if [[ ! -d "$src_dir" ]]; then
    return
  fi

  local found=0
  for f in $(ls "$src_dir"/*.sql 2>/dev/null | sort); do
    local basename dest
    basename="$(basename "$f")"
    dest="$MIGRATIONS_DIR/mod_$(printf '%03d' $N)_${module_name}_${basename}"
    cp "$f" "$dest"
    info "  + mod_$(printf '%03d' $N)_${module_name}_${basename}"
    N=$((N + 1))
    MOD_MIGRATIONS=$((MOD_MIGRATIONS + 1))
    found=1
  done

  if [[ $found -eq 0 ]]; then
    info "  (sin archivos .sql en $src_dir)"
  fi
}

copy_functions() {
  local module_name="$1"
  local src_dir="$2/supabase/functions"

  if [[ ! -d "$src_dir" ]]; then
    return
  fi

  # Merge _shared/: copiar solo archivos que NO existan ya en foundation _shared
  if [[ -d "$src_dir/_shared" ]]; then
    mkdir -p "$FUNCTIONS_DIR/_shared"
    for src_file in "$src_dir/_shared/"*; do
      [[ -f "$src_file" ]] || continue
      local fname
      fname="$(basename "$src_file")"
      if [[ -f "$FUNCTIONS_DIR/_shared/$fname" ]]; then
        info "  ~ _shared/$fname ya existe en foundation (preservado, no sobreescrito)"
      else
        cp "$src_file" "$FUNCTIONS_DIR/_shared/$fname"
        info "  + _shared/$fname (de $module_name)"
      fi
    done
  fi

  # Copiar cada función (subdirectorios que no son _shared)
  for fn_dir in "$src_dir"/*/; do
    [[ -d "$fn_dir" ]] || continue
    local fn_name
    fn_name="$(basename "$fn_dir")"
    [[ "$fn_name" == "_shared" ]] && continue

    if is_foundation_function "$fn_name"; then
      warning "  functions/$fn_name colisiona con función de foundation (saltando)"
      continue
    fi

    cp -r "$fn_dir" "$FUNCTIONS_DIR/${fn_name}"
    info "  + functions/$fn_name"
    FUNC_COUNT=$((FUNC_COUNT + 1))
  done
}

# =============================================================================
# MÓDULOS DE INFRAESTRUCTURA
# =============================================================================
section "── Infraestructura ─────────────────────────────────────────────────"

for mod in administracion comunicacion; do
  if ! should_skip "$mod"; then
    info "  [${mod}]"
    copy_migrations "$mod" "$BASE/modules/infraestructura/$mod"
    copy_functions  "$mod" "$BASE/modules/infraestructura/$mod"
  fi
done

# =============================================================================
# MÓDULOS CORE
# =============================================================================
section "── Core ────────────────────────────────────────────────────────────"

for mod in entidades facturacion ventas compras inventario tesoreria contabilidad; do
  if ! should_skip "$mod"; then
    info "  [${mod}]"
    copy_migrations "$mod" "$BASE/modules/core/$mod"
    copy_functions  "$mod" "$BASE/modules/core/$mod"
  fi
done

# =============================================================================
# EXTENSIONES
# =============================================================================
section "── Extensiones ─────────────────────────────────────────────────────"

for mod in facturacion_ec tributacion_ec ia pagos-online citas-belleza \
           pos ecommerce rrhh crm proyectos \
           activos-fijos consumibles taller garantias-rma \
           suscripciones servicio-de-campo intercompany; do
  if ! should_skip "$mod"; then
    info "  [${mod}]"
    copy_migrations "$mod" "$BASE/modules/extensiones/$mod"
    copy_functions  "$mod" "$BASE/modules/extensiones/$mod"
  fi
done

# =============================================================================
# RESUMEN
# =============================================================================
TOTAL_MIGRATIONS=$(ls "$MIGRATIONS_DIR"/*.sql 2>/dev/null | wc -l | tr -d ' ')
TOTAL_FUNCTIONS=$(ls -d "$FUNCTIONS_DIR"/*/ 2>/dev/null | wc -l | tr -d ' ')

echo ""
section "════════════════════════════════════════════════════════════════"
info "Build completado:"
info "  Foundation:  $FOUNDATION_COUNT migraciones (fuente, sin modificar)"
info "  Módulos:     $MOD_MIGRATIONS migraciones (mod_*.sql ensambladas)"
info "  Total:       $TOTAL_MIGRATIONS migraciones en foundation/supabase/migrations/"
info "  Edge Funcs:  $TOTAL_FUNCTIONS funciones en foundation/supabase/functions/"
info ""
info "Próximos pasos (ejecutar desde foundation/):"
info "  cd foundation"
info "  supabase start          # Levantar entorno local"
info "  supabase db push        # Aplicar migraciones"
info "  supabase db lint        # Validar schema"
section "════════════════════════════════════════════════════════════════"
