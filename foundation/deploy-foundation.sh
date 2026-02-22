#!/usr/bin/env bash
# =============================================================================
# PILAR ERP — foundation/deploy-foundation.sh
#
# Despliega Foundation completo en un proyecto Supabase cloud.
# Con SUPABASE_ACCESS_TOKEN automatiza los 4 pasos:
#   1. Borra el proyecto actual (DELETE /v1/projects/{ref})
#   2. Crea proyecto nuevo       (POST   /v1/projects)
#   3. Espera ACTIVE_HEALTHY     (GET    /v1/projects/{ref})
#   4. Actualiza keys en .env    (GET    /v1/projects/{ref}/api-keys)
# Luego aplica las 19 migraciones y despliega las 3 Edge Functions.
#
# NO requiere psql, SUPABASE_DB_PASSWORD ni SUPABASE_ORG_ID.
# Todo se hace vía Supabase Management API + CLI.
#
# PRERREQUISITOS:
#   supabase   → brew install supabase/tap/supabase
#   curl       → incluido en macOS
#   python3    → incluido en macOS
#
# USO:
#   cp .env.example .env   # completar SUPABASE_ACCESS_TOKEN
#   ./foundation/deploy-foundation.sh
# =============================================================================

set -euo pipefail

# ─── Colores ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

ok()      { echo -e "  ${GREEN}✓${NC} $*"; }
info()    { echo -e "  ${CYAN}→${NC} $*"; }
warn()    { echo -e "  ${YELLOW}⚠${NC} $*"; }
err()     { echo -e "  ${RED}✗ ERROR:${NC} $*"; }
section() { echo -e "\n${YELLOW}▶ $*${NC}"; }
die()     { err "$*"; exit 1; }

# ─── Rutas ────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MIGRATIONS_DIR="$SCRIPT_DIR/supabase/migrations"
ENV_FILE="$ROOT/.env"
SUPABASE_API="https://api.supabase.com/v1"

# ─── Cargar .env ──────────────────────────────────────────────────────────────
if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
else
  die "No se encontró $ENV_FILE\n       Crear desde: cp .env.example .env"
fi

# ─── Validar token ────────────────────────────────────────────────────────────
if [[ -z "${SUPABASE_ACCESS_TOKEN:-}" || "${SUPABASE_ACCESS_TOKEN}" == sbp_xxx* ]]; then
  die "SUPABASE_ACCESS_TOKEN requerido en .env\n       Obtener en: Supabase Dashboard → Account → Access Tokens"
fi

SUPABASE_REGION="${SUPABASE_REGION:-us-east-1}"
SUPABASE_PROJECT_NAME="${SUPABASE_PROJECT_NAME:-pilar}"

# ─── Helpers ──────────────────────────────────────────────────────────────────

# Parsear campo de objeto JSON
json_get() {
  local json="$1" key="$2"
  echo "$json" | python3 -c \
    "import json,sys; d=json.load(sys.stdin); print(d.get('$key',''))" 2>/dev/null
}

# Actualizar o añadir clave en .env
update_env() {
  local KEY="$1" VALUE="$2"
  if grep -q "^${KEY}=" "$ENV_FILE" 2>/dev/null; then
    sed -i '' "s|^${KEY}=.*|${KEY}=${VALUE}|" "$ENV_FILE"
  else
    echo "${KEY}=${VALUE}" >> "$ENV_FILE"
  fi
}

# Ejecutar SQL en el proyecto via Management API
db_query() {
  local SQL="$1"
  local BODY
  BODY=$(python3 -c "import json,sys; print(json.dumps({'query': sys.stdin.read()}))" \
    <<< "$SQL")
  curl -s -X POST \
    "${SUPABASE_API}/projects/${SUPABASE_PROJECT_REF}/database/query" \
    -H "Authorization: Bearer ${SUPABASE_ACCESS_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$BODY"
}

# Ejecutar un archivo SQL via Management API; salir si hay error
db_exec_file() {
  local FILE="$1"
  local RESP
  RESP=$(db_query "$(cat "$FILE")")

  # Detectar error en la respuesta JSON
  local ERR
  ERR=$(echo "$RESP" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    if isinstance(d, dict):
        msg = d.get('error') or d.get('message') or d.get('hint') or ''
        if msg:
            print(msg)
except Exception:
    pass
" 2>/dev/null)

  if [[ -n "$ERR" ]]; then
    echo ""
    err "Error en $(basename "$FILE"):"
    echo "    $ERR"
    exit 1
  fi
}

# ─── Verificar herramientas ───────────────────────────────────────────────────
section "Verificando herramientas..."
check_cmd() {
  if ! command -v "$1" &>/dev/null; then
    die "'$1' no encontrado.\n       Instalar: $2"
  fi
  ok "$1"
}
check_cmd supabase "brew install supabase/tap/supabase"
check_cmd curl     "incluido en macOS"
check_cmd python3  "incluido en macOS"

# ─── Auto-detectar organización ───────────────────────────────────────────────
section "Detectando organización..."
ORGS_RESP=$(curl -s "${SUPABASE_API}/organizations" \
  -H "Authorization: Bearer ${SUPABASE_ACCESS_TOKEN}")

SUPABASE_ORG_ID=$(echo "$ORGS_RESP" | python3 -c \
  "import json,sys; orgs=json.load(sys.stdin); print(orgs[0]['id'])" 2>/dev/null)
ORG_NAME=$(echo "$ORGS_RESP" | python3 -c \
  "import json,sys; orgs=json.load(sys.stdin); print(orgs[0].get('name',''))" 2>/dev/null)

[[ -z "$SUPABASE_ORG_ID" ]] && die "No se pudo detectar la organización.\n       Verificar SUPABASE_ACCESS_TOKEN."
ok "${ORG_NAME} (${SUPABASE_ORG_ID})"

# ─── Banner ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${BLUE}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${BLUE}║  PILAR ERP — Foundation Deploy                   ║${NC}"
echo -e "${BOLD}${BLUE}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Org       : ${CYAN}${ORG_NAME}${NC}"
echo -e "  Región    : ${CYAN}${SUPABASE_REGION}${NC}"
echo ""

# ─── Menú: modo de operación ──────────────────────────────────────────────────

# Listar todos los proyectos de la organización
ALL_PROJECTS_RESP=$(curl -s "${SUPABASE_API}/projects" \
  -H "Authorization: Bearer ${SUPABASE_ACCESS_TOKEN}")

# Parsear lista de proyectos a arrays paralelos (compatible bash 3.2 macOS)
PROJ_IDS=()
while IFS= read -r line; do PROJ_IDS+=("$line"); done < <(echo "$ALL_PROJECTS_RESP" | python3 -c "
import json,sys
projs = json.load(sys.stdin)
for p in projs: print(p.get('id',''))
" 2>/dev/null)

PROJ_NAMES=()
while IFS= read -r line; do PROJ_NAMES+=("$line"); done < <(echo "$ALL_PROJECTS_RESP" | python3 -c "
import json,sys
projs = json.load(sys.stdin)
for p in projs: print(p.get('name',''))
" 2>/dev/null)

PROJ_STATS=()
while IFS= read -r line; do PROJ_STATS+=("$line"); done < <(echo "$ALL_PROJECTS_RESP" | python3 -c "
import json,sys
projs = json.load(sys.stdin)
for p in projs: print(p.get('status',''))
" 2>/dev/null)

echo -e "  ${BOLD}¿Qué deseas hacer?${NC}"
echo ""
echo -e "  ${CYAN}[1]${NC} Crear proyecto NUEVO"
echo -e "  ${CYAN}[2]${NC} Reemplazar un proyecto existente"
echo ""
echo -ne "  Opción [1/2]: "
read -r MODO

# Variables a definir en cada rama
MODE_DELETE=false
DELETE_REF=""
DELETE_NAME=""

case "$MODO" in
  1)
    # ── Modo NUEVO: pedir nombre, no borrar nada ─────────────────────────────
    echo ""
    echo -ne "  Nombre del nuevo proyecto [${SUPABASE_PROJECT_NAME}]: "
    read -r INPUT_NAME
    [[ -n "$INPUT_NAME" ]] && SUPABASE_PROJECT_NAME="$INPUT_NAME"
    MODE_DELETE=false
    ok "Modo: NUEVO proyecto '${SUPABASE_PROJECT_NAME}'"
    ;;
  2)
    # ── Modo REEMPLAZAR: listar proyectos y elegir ───────────────────────────
    if [[ ${#PROJ_IDS[@]} -eq 0 ]]; then
      die "No se encontraron proyectos en la organización. Usa la opción 1."
    fi
    echo ""
    echo -e "  ${BOLD}Proyectos disponibles:${NC}"
    echo ""
    for i in "${!PROJ_IDS[@]}"; do
      NUM=$((i + 1))
      # Marcar el proyecto activo en .env con (*)
      MARKER="  "
      [[ "${PROJ_IDS[$i]}" == "${SUPABASE_PROJECT_REF:-}" ]] && MARKER="${GREEN}*${NC} "
      printf "  ${CYAN}[%d]${NC} ${MARKER}%-25s %-26s %s\n" \
        "$NUM" "${PROJ_NAMES[$i]}" "${PROJ_IDS[$i]}" "${PROJ_STATS[$i]}"
    done
    echo ""
    echo -ne "  Selecciona el proyecto a reemplazar [1-${#PROJ_IDS[@]}]: "
    read -r SEL

    if ! [[ "$SEL" =~ ^[0-9]+$ ]] || \
       [[ "$SEL" -lt 1 ]] || \
       [[ "$SEL" -gt "${#PROJ_IDS[@]}" ]]; then
      die "Selección inválida."
    fi

    IDX=$((SEL - 1))
    DELETE_REF="${PROJ_IDS[$IDX]}"
    DELETE_NAME="${PROJ_NAMES[$IDX]}"

    echo ""
    echo -e "  ${RED}${BOLD}⚠  Esto borrará permanentemente '${DELETE_NAME}'${NC}"
    echo -ne "  Escribe el nombre del proyecto para confirmar: "
    read -r CONFIRM_NAME
    if [[ "$CONFIRM_NAME" != "$DELETE_NAME" ]]; then
      die "Nombre incorrecto ('${CONFIRM_NAME}' ≠ '${DELETE_NAME}'). Cancelado."
    fi

    # Usar el mismo nombre para el proyecto de reemplazo (o pedir uno nuevo)
    echo -ne "  Nombre del nuevo proyecto [${DELETE_NAME}]: "
    read -r INPUT_NAME
    SUPABASE_PROJECT_NAME="${INPUT_NAME:-$DELETE_NAME}"

    MODE_DELETE=true
    ok "Modo: REEMPLAZAR '${DELETE_NAME}' → nuevo '${SUPABASE_PROJECT_NAME}'"
    ;;
  *)
    die "Opción inválida. Ejecuta el script de nuevo y elige 1 o 2."
    ;;
esac

# ─── Paso 1: Borrar proyecto seleccionado (solo modo REEMPLAZAR) ──────────────
if $MODE_DELETE; then
  section "Paso 1 — Borrando proyecto '${DELETE_NAME}' (${DELETE_REF})..."
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE \
    "${SUPABASE_API}/projects/${DELETE_REF}" \
    -H "Authorization: Bearer ${SUPABASE_ACCESS_TOKEN}")

  if [[ "$HTTP_CODE" == "2"* ]]; then
    ok "Proyecto eliminado (HTTP ${HTTP_CODE})"
  elif [[ "$HTTP_CODE" == "404" ]]; then
    warn "Proyecto no encontrado (ya fue borrado, continuando)"
  else
    warn "Respuesta inesperada: HTTP ${HTTP_CODE} (continuando)"
  fi
  sleep 3
else
  section "Paso 1 — Saltando delete (modo NUEVO proyecto)"
fi

# ─── Paso 2: Crear proyecto nuevo ─────────────────────────────────────────────
section "Paso 2 — Creando proyecto '${SUPABASE_PROJECT_NAME}'..."

# Generar contraseña aleatoria (solo se usa internamente al crear el proyecto)
DB_PASS=$(python3 -c "import secrets; print(secrets.token_urlsafe(24))")

CREATE_BODY=$(python3 -c "
import json
print(json.dumps({
  'name':            '${SUPABASE_PROJECT_NAME}',
  'organization_id': '${SUPABASE_ORG_ID}',
  'db_pass':         '${DB_PASS}',
  'region':          '${SUPABASE_REGION}',
}))
")

CREATE_RESP=$(curl -s -X POST \
  "${SUPABASE_API}/projects" \
  -H "Authorization: Bearer ${SUPABASE_ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$CREATE_BODY")

NEW_REF=$(json_get "$CREATE_RESP" "id")

if [[ -z "$NEW_REF" ]]; then
  err "No se pudo crear el proyecto. Respuesta de la API:"
  echo "  $CREATE_RESP"
  exit 1
fi

ok "Proyecto creado: ${NEW_REF}"
SUPABASE_PROJECT_REF="$NEW_REF"

# Actualizar PROJECT_REF y URL en .env
update_env "SUPABASE_PROJECT_REF" "$NEW_REF"
update_env "SUPABASE_URL"         "https://${NEW_REF}.supabase.co"
ok ".env → SUPABASE_PROJECT_REF y SUPABASE_URL actualizados"

# ─── Paso 3: Esperar ACTIVE_HEALTHY ───────────────────────────────────────────
section "Paso 3 — Esperando ACTIVE_HEALTHY..."

WAIT_SECS=0
MAX_WAIT=300
SPINNER=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
SP_IDX=0

while true; do
  STATUS_RESP=$(curl -s \
    "${SUPABASE_API}/projects/${SUPABASE_PROJECT_REF}" \
    -H "Authorization: Bearer ${SUPABASE_ACCESS_TOKEN}")
  STATUS=$(json_get "$STATUS_RESP" "status")

  echo -ne "  ${SPINNER[$SP_IDX]} Estado: ${CYAN}${STATUS:-desconocido}${NC} (${WAIT_SECS}s)    \r"
  SP_IDX=$(( (SP_IDX + 1) % ${#SPINNER[@]} ))

  if [[ "$STATUS" == "ACTIVE_HEALTHY" ]]; then
    echo -e "  ${GREEN}✓${NC} ACTIVE_HEALTHY alcanzado en ${WAIT_SECS}s              "
    break
  fi

  if [[ $WAIT_SECS -ge $MAX_WAIT ]]; then
    echo ""
    die "Timeout: el proyecto no alcanzó ACTIVE_HEALTHY en ${MAX_WAIT}s."
  fi

  sleep 5
  WAIT_SECS=$((WAIT_SECS + 5))
done

# ─── Paso 4: Actualizar API keys en .env ──────────────────────────────────────
section "Paso 4 — Actualizando API keys en .env..."

KEYS_RESP=$(curl -s \
  "${SUPABASE_API}/projects/${SUPABASE_PROJECT_REF}/api-keys" \
  -H "Authorization: Bearer ${SUPABASE_ACCESS_TOKEN}")

NEW_ANON=$(echo "$KEYS_RESP" | python3 -c "
import json,sys
keys = json.load(sys.stdin)
for k in keys:
    if k.get('name') == 'anon':
        print(k.get('api_key',''))
        break
" 2>/dev/null)

NEW_SERVICE=$(echo "$KEYS_RESP" | python3 -c "
import json,sys
keys = json.load(sys.stdin)
for k in keys:
    if k.get('name') == 'service_role':
        print(k.get('api_key',''))
        break
" 2>/dev/null)

if [[ -n "$NEW_ANON" ]]; then
  update_env "SUPABASE_ANON_KEY"        "$NEW_ANON"
  update_env "SUPABASE_SERVICE_ROLE_KEY" "$NEW_SERVICE"
  ok ".env → SUPABASE_ANON_KEY y SUPABASE_SERVICE_ROLE_KEY actualizados"
else
  warn "No se pudieron obtener las API keys — actualizar manualmente en .env"
fi

info "Esperando 10s para que el DB esté listo..."
sleep 10

# ─── Aplicar migraciones Foundation ──────────────────────────────────────────
MIGRATIONS=(
  "001_core.sql"
  "002_functions.sql"
  "003_seed_roles.sql"
  "004_seed_modules.sql"
  "005_helpers.sql"
  "006_field_extensions.sql"
  "007_shared_tables.sql"
  "008_catalogo_geografico.sql"
  "009_catalogo_monedas.sql"
  "010_secuencias.sql"
  "011_feature_flags.sql"
  "012_invitaciones_pendientes.sql"
  "013_plan_modulos.sql"
  "014_auto_permisos.sql"
  "015_mfa_config.sql"
  "016_saml_sso.sql"
  "017_financial_functions.sql"
  "018_background_jobs.sql"
  "019_auth_hook.sql"
)

section "Aplicando ${#MIGRATIONS[@]} migraciones Foundation..."
echo ""

# Verificar que todos los archivos existen
for FILE in "${MIGRATIONS[@]}"; do
  [[ -f "$MIGRATIONS_DIR/$FILE" ]] || die "No encontrado: $MIGRATIONS_DIR/$FILE"
done

TOTAL=${#MIGRATIONS[@]}
for i in "${!MIGRATIONS[@]}"; do
  FILE="${MIGRATIONS[$i]}"
  NUM=$(printf "%02d" $((i + 1)))

  echo -ne "  ${CYAN}${NUM}/${TOTAL}${NC} ${FILE}... "
  db_exec_file "$MIGRATIONS_DIR/$FILE"
  echo -e "${GREEN}✓${NC}"
done

echo ""
ok "${TOTAL}/${TOTAL} migraciones aplicadas"

# ─── Deploy Edge Functions ────────────────────────────────────────────────────
section "Desplegando Edge Functions..."
echo ""

deploy_fn() {
  local NAME="$1"; shift
  local EXTRA_FLAGS=("$@")
  echo -ne "  ${CYAN}→${NC} ${NAME}... "
  # supabase CLI detecta funciones desde SCRIPT_DIR/supabase/functions/ (donde está config.toml)
  if SUPABASE_ACCESS_TOKEN="$SUPABASE_ACCESS_TOKEN" \
     supabase functions deploy "$NAME" \
       --project-ref "$SUPABASE_PROJECT_REF" \
       --workdir "$SCRIPT_DIR" \
       "${EXTRA_FLAGS[@]+"${EXTRA_FLAGS[@]}"}" \
       2>/tmp/pilar_fn_err; then
    echo -e "${GREEN}✓${NC}"
  else
    echo -e "${YELLOW}⚠ falló${NC}"
    warn "$(head -3 /tmp/pilar_fn_err 2>/dev/null || echo 'ver /tmp/pilar_fn_err')"
  fi
}

# verify_jwt: false → auth-setup-handler valida el token internamente (servicio → webhook)
deploy_fn "auth-setup-handler" "--no-verify-jwt"
deploy_fn "invite-user"
deploy_fn "upload-logo"

# ─── Verificación final ───────────────────────────────────────────────────────
section "Verificación final..."
echo ""

VERIFY_SQL="SELECT
  (SELECT count(*)::text FROM roles)                                  ||'|'||
  (SELECT count(*)::text FROM permisos)                               ||'|'||
  (SELECT count(*)::text FROM modulos)                                ||'|'||
  (SELECT count(*)::text FROM planes_suscripcion)                     ||'|'||
  (SELECT count(*)::text FROM paises)                                 ||'|'||
  (SELECT count(*)::text FROM provincias)                             ||'|'||
  (SELECT count(*)::text FROM monedas)                                ||'|'||
  (SELECT count(*)::text FROM feature_flags WHERE empresa_id IS NULL) ||'|'||
  (SELECT financial_round(10.565, 2)::text);"

VERIFY_RESP=$(db_query "$VERIFY_SQL")
VERIFY=$(echo "$VERIFY_RESP" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    if isinstance(data, list) and len(data) > 0:
        print(list(data[0].values())[0])
except Exception:
    pass
" 2>/dev/null)

IFS='|' read -r ROLES PERMISOS MODULOS PLANES PAISES PROV MONEDAS FLAGS FR <<< "$VERIFY"

PASS=true
check_val() {
  local LABEL="$1" VAL="$2" EXPECTED="$3"
  VAL="${VAL// /}"
  if [[ "$VAL" == "$EXPECTED" ]]; then
    printf "  ${GREEN}✓${NC} %-30s %s\n" "$LABEL:" "$VAL"
  else
    printf "  ${RED}✗${NC} %-30s %s ${RED}(esperado: %s)${NC}\n" "$LABEL:" "$VAL" "$EXPECTED"
    PASS=false
  fi
}

check_val "Roles"                    "$ROLES"    "11"
check_val "Permisos"                 "$PERMISOS" "22"
check_val "Módulos infra"            "$MODULOS"  "3"
check_val "Planes SaaS"              "$PLANES"   "4"
check_val "Países"                   "$PAISES"   "239"
check_val "Provincias Ecuador"       "$PROV"     "24"
check_val "Monedas (semilla USD)"     "$MONEDAS"  "1"
check_val "Feature flags globales"   "$FLAGS"    "6"
check_val "financial_round(10.565,2)" "$FR"      "10.57"

# ─── Resumen ──────────────────────────────────────────────────────────────────
echo ""
if $PASS; then
  echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════╗${NC}"
  echo -e "${GREEN}${BOLD}║  ✅ Foundation deployed y verificado             ║${NC}"
  echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════╝${NC}"
else
  echo -e "${YELLOW}${BOLD}╔══════════════════════════════════════════════════╗${NC}"
  echo -e "${YELLOW}${BOLD}║  ⚠  Foundation deployed con advertencias         ║${NC}"
  echo -e "${YELLOW}${BOLD}╚══════════════════════════════════════════════════╝${NC}"
fi
echo ""
echo -e "  Proyecto  : ${CYAN}https://supabase.com/dashboard/project/${SUPABASE_PROJECT_REF}${NC}"
echo ""
echo -e "  ${BOLD}Próximos pasos:${NC}"
echo "  · Módulos core/extensiones: ./scripts/build-supabase.sh && cd foundation && supabase db push --project-ref ${SUPABASE_PROJECT_REF}"
echo "  · Dashboard → Auth → Hooks → Custom Access Token → public.custom_access_token_hook"
echo "  · Dashboard → Database → Webhooks → empresas INSERT → auth-setup-handler"
echo ""
