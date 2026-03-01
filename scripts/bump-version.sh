#!/usr/bin/env bash
# =============================================================================
# bump-version.sh — Sube la versión de PILAR ERP
#
# Uso:
#   ./scripts/bump-version.sh patch    # 0.1.0+1 → 0.1.1+2
#   ./scripts/bump-version.sh minor    # 0.1.1+2 → 0.2.0+3
#   ./scripts/bump-version.sh major    # 0.2.0+3 → 1.0.0+4
#   ./scripts/bump-version.sh build    # solo incrementa build: 0.2.0+3 → 0.2.0+4
#
# El número de versión actualizado se escribe en pubspec.yaml y se imprime
# en consola para confirmar el cambio.
# =============================================================================
set -euo pipefail

PUBSPEC="source-flutter/app/pubspec.yaml"

# ── Leer versión actual ───────────────────────────────────────────────────────
current=$(grep -m1 '^version:' "$PUBSPEC" | awk '{print $2}')
semver="${current%+*}"   # parte antes de +
build="${current#*+}"    # build number (parte después de +)

IFS='.' read -r major minor patch <<< "$semver"

# ── Calcular nueva versión ────────────────────────────────────────────────────
bump="${1:-patch}"
new_build=$(( build + 1 ))

case "$bump" in
  major)
    new_semver="$(( major + 1 )).0.0"
    ;;
  minor)
    new_semver="${major}.$(( minor + 1 )).0"
    ;;
  patch)
    new_semver="${major}.${minor}.$(( patch + 1 ))"
    ;;
  build)
    new_semver="${semver}"
    ;;
  *)
    echo "❌ Uso: $0 [major|minor|patch|build]"
    exit 1
    ;;
esac

new_version="${new_semver}+${new_build}"

# ── Actualizar pubspec.yaml ───────────────────────────────────────────────────
sed -i '' "s/^version: .*/version: ${new_version}/" "$PUBSPEC"

echo "✅ Versión actualizada: ${current} → ${new_version}"
echo ""
echo "Próximos pasos:"
echo "  1. Revisar CHANGELOG.md y añadir notas de esta versión"
echo "  2. git add source-flutter/app/pubspec.yaml pubspec.lock CHANGELOG.md"
echo "  3. git commit -m \"chore: bump version to ${new_version}\""
echo "  4. git tag v${new_semver}"
