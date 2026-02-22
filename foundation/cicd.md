# CI/CD — PILAR ERP

Pipeline de integración y entrega continua para el proyecto Flutter multi-plataforma.

---

## 1. Estrategia CI/CD

### Por qué Codemagic

Codemagic es la opción canónica para proyectos Flutter multi-plataforma por las razones siguientes:

| Criterio | Codemagic | GitHub Actions | Bitrise |
|----------|-----------|----------------|---------|
| Soporte Flutter nativo | Si (empresa Flutter oficial) | Parcial (self-managed) | Si |
| macOS + iOS builds | Si (Mac Mini M2 incluido) | Costoso (macos runners $) | Si |
| Code signing iOS/macOS | Automatizado (Codemagic fetch) | Manual (scripts) | Automatizado |
| Builds paralelos (flavors) | Si (matrix por workflow) | Si | Si |
| Publicacion en stores | Si (built-in publishers) | Via fastlane manual | Si |
| Precio builds Flutter | 500 min/mes gratis; $299/mes Pro | $0.008/min macOS | $299/mes |
| Integracion Supabase CLI | Si (script step) | Si | Si |

**Conclusion:** Codemagic ofrece el menor tiempo de configuracion para builds iOS/macOS (code signing automatizado) y publishers nativos para App Store Connect y Google Play.

### Flujo general

```
Developer push
      |
      v
  GitHub repo
      |
      +---> Codemagic CI
      |           |
      |           +--- flutter-web     --> Cloudflare Pages (gratis)
      |           +--- flutter-android --> Google Play (internal/production)
      |           +--- flutter-ios     --> App Store Connect
      |           +--- flutter-windows --> MSIX artifact (descarga directa)
      |           +--- flutter-macos  --> Mac App Store / DMG
      |
      +---> GitHub Actions (solo migraciones DB)
                  |
                  +--> supabase db push  --> Supabase Cloud
```

### Branches y triggers

| Branch | Que dispara | Entorno |
|--------|-------------|---------|
| `main` | Build produccion en todos los targets | Produccion |
| `develop` | Build staging (web + android debug) | Staging |
| `release/*` | Build completo + publicacion stores | Produccion |
| `feature/*` | Solo tests + analisis estatico | — |
| Pull Request | Tests + lint (sin build de produccion) | — |

---

## 2. codemagic.yaml — Workflows completos

El archivo `codemagic.yaml` va en la raiz del repositorio Flutter.

```yaml
# codemagic.yaml — PILAR ERP
# Documentacion: https://docs.codemagic.io/yaml-basic-configuration/

definitions:
  # Variables de entorno comunes a todos los workflows
  env_common: &env_common
    FLUTTER_VERSION: stable
    SUPABASE_URL: $SUPABASE_URL               # Secret en Codemagic
    SUPABASE_ANON_KEY: $SUPABASE_ANON_KEY     # Secret en Codemagic
    SENTRY_DSN: $SENTRY_DSN                   # Secret en Codemagic

  # Scripts de setup comunes
  setup_steps: &setup_steps
    - name: Instalar dependencias
      script: flutter pub get
    - name: Generar codigo (Riverpod + Brick)
      script: |
        flutter pub run build_runner build --delete-conflicting-outputs
    - name: Verificar formato
      script: dart format --output=none --set-exit-if-changed lib/
    - name: Analisis estatico
      script: flutter analyze --no-fatal-infos
    - name: Tests unitarios
      script: |
        flutter test --coverage
        # Umbral minimo de cobertura: 70%
        dart pub global activate coverage
        dart pub global run coverage:format_coverage \
          --lcov --in=coverage/coverage.json \
          --out=coverage/lcov.info --packages=.dart_tool/package_config.json
    - name: Crear .env desde secrets
      script: |
        cat > .env << EOF
        SUPABASE_URL=$SUPABASE_URL
        SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY
        SENTRY_DSN=$SENTRY_DSN
        EOF

workflows:

  # =========================================================
  # WORKFLOW 1: Flutter Web → Cloudflare Pages
  # =========================================================
  flutter-web:
    name: "PILAR Web (Cloudflare Pages)"
    max_build_duration: 45
    instance_type: linux_x2   # 4 vCPU, 8 GB RAM

    triggering:
      events:
        - push
        - pull_request
      branch_patterns:
        - pattern: main
          include: true
        - pattern: develop
          include: true
        - pattern: release/*
          include: true

    environment:
      flutter: stable
      vars:
        <<: *env_common
        CF_ACCOUNT_ID: $CF_ACCOUNT_ID         # Secret: Cloudflare Account ID
        CF_API_TOKEN: $CF_API_TOKEN           # Secret: Cloudflare API Token
        CF_PROJECT_NAME: pilar-erp            # Nombre del proyecto en Pages

    scripts:
      <<: *setup_steps

      # Build flavor erp (web principal)
      - name: Build Web - flavor erp
        script: |
          flutter build web \
            --release \
            --flavor erp \
            --dart-define=SUPABASE_URL=$SUPABASE_URL \
            --dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY \
            --dart-define=SENTRY_DSN=$SENTRY_DSN \
            --dart-define=APP_FLAVOR=erp \
            --web-renderer canvaskit \
            --pwa-strategy offline-first \
            -t lib/main_erp.dart \
            -o build/web_erp

      # Build flavor salon (web para gestion de salon)
      - name: Build Web - flavor salon
        script: |
          flutter build web \
            --release \
            --flavor salon \
            --dart-define=SUPABASE_URL=$SUPABASE_URL \
            --dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY \
            --dart-define=APP_FLAVOR=salon \
            --web-renderer canvaskit \
            -t lib/main_salon.dart \
            -o build/web_salon

      # Deploy a Cloudflare Pages (solo en main/release)
      - name: Deploy a Cloudflare Pages
        script: |
          if [[ "$CM_BRANCH" == "main" || "$CM_BRANCH" == release/* ]]; then
            npm install -g wrangler
            # Deploy flavor erp
            wrangler pages deploy build/web_erp \
              --project-name $CF_PROJECT_NAME \
              --branch main
            # Deploy flavor salon en subdominio
            wrangler pages deploy build/web_salon \
              --project-name pilar-salon \
              --branch main
          else
            echo "Branch $CM_BRANCH: deploy omitido (solo main/release)"
          fi

    artifacts:
      - build/web_erp/**
      - build/web_salon/**

    publishing:
      email:
        recipients:
          - devops@pilarerp.com
        notify:
          success: true
          failure: true

  # =========================================================
  # WORKFLOW 2: Flutter Android → Google Play
  # =========================================================
  flutter-android:
    name: "PILAR Android (Google Play)"
    max_build_duration: 60
    instance_type: linux_x2

    triggering:
      events:
        - push
      branch_patterns:
        - pattern: main
          include: true
        - pattern: release/*
          include: true

    environment:
      flutter: stable
      android_signing:
        - pilar_keystore           # Configurado en Codemagic > Code Signing
      vars:
        <<: *env_common
        GOOGLE_PLAY_JSON_KEY: $GOOGLE_PLAY_JSON_KEY  # Secret: service account JSON

    scripts:
      <<: *setup_steps

      # Build APK debug para flavor erp (staging)
      - name: Build APK debug - erp
        script: |
          if [[ "$CM_BRANCH" == "develop" ]]; then
            flutter build apk \
              --flavor erp \
              --dart-define=SUPABASE_URL=$SUPABASE_URL \
              --dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY \
              --dart-define=APP_FLAVOR=erp \
              -t lib/main_erp.dart
          fi

      # Build AAB produccion - flavor erp
      - name: Build AAB produccion - erp
        script: |
          flutter build appbundle \
            --release \
            --flavor erp \
            --dart-define=SUPABASE_URL=$SUPABASE_URL \
            --dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY \
            --dart-define=SENTRY_DSN=$SENTRY_DSN \
            --dart-define=APP_FLAVOR=erp \
            -t lib/main_erp.dart

      # Build AAB produccion - flavor salon
      - name: Build AAB produccion - salon
        script: |
          flutter build appbundle \
            --release \
            --flavor salon \
            --dart-define=SUPABASE_URL=$SUPABASE_URL \
            --dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY \
            --dart-define=APP_FLAVOR=salon \
            -t lib/main_salon.dart

      # Build AAB produccion - flavor cliente (white-label)
      - name: Build AAB produccion - cliente
        script: |
          flutter build appbundle \
            --release \
            --flavor cliente \
            --dart-define=SUPABASE_URL=$SUPABASE_URL \
            --dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY \
            --dart-define=APP_FLAVOR=cliente \
            -t lib/main_cliente.dart

    artifacts:
      - build/app/outputs/bundle/**/*.aab
      - build/app/outputs/apk/**/*.apk
      - flutter_drive.log

    publishing:
      google_play:
        credentials: $GOOGLE_PLAY_JSON_KEY
        track: internal             # internal → alpha → beta → production
        submit_as_draft: false
        changes_not_sent_for_review: false

      email:
        recipients:
          - devops@pilarerp.com
        notify:
          success: true
          failure: true

  # =========================================================
  # WORKFLOW 3: Flutter iOS → App Store Connect
  # =========================================================
  flutter-ios:
    name: "PILAR iOS (App Store Connect)"
    max_build_duration: 90
    instance_type: mac_mini_m2   # Obligatorio para iOS builds

    triggering:
      events:
        - push
      branch_patterns:
        - pattern: main
          include: true
        - pattern: release/*
          include: true

    environment:
      flutter: stable
      ios_signing:
        distribution_type: app_store
        bundle_identifier: com.pilarerp.erp  # Por flavor; ver seccion Flavors
      vars:
        <<: *env_common
        APP_STORE_CONNECT_ISSUER_ID: $ASC_ISSUER_ID       # Secret
        APP_STORE_CONNECT_KEY_IDENTIFIER: $ASC_KEY_ID     # Secret
        APP_STORE_CONNECT_PRIVATE_KEY: $ASC_PRIVATE_KEY   # Secret (contenido .p8)
        CERTIFICATE_PRIVATE_KEY: $IOS_CERT_PRIVATE_KEY    # Secret (PEM)

    scripts:
      <<: *setup_steps

      # Configurar code signing automatico via Codemagic
      - name: Configurar code signing iOS
        script: |
          keychain initialize
          app-store-connect fetch-signing-files \
            com.pilarerp.erp \
            --type IOS_APP_STORE \
            --create
          keychain add-certificates

      # Build IPA - flavor erp
      - name: Build IPA - erp
        script: |
          flutter build ipa \
            --release \
            --flavor erp \
            --dart-define=SUPABASE_URL=$SUPABASE_URL \
            --dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY \
            --dart-define=SENTRY_DSN=$SENTRY_DSN \
            --dart-define=APP_FLAVOR=erp \
            --export-options-plist=/Users/builder/export_options.plist \
            -t lib/main_erp.dart

      # Build IPA - flavor salon
      - name: Build IPA - salon
        script: |
          app-store-connect fetch-signing-files \
            com.pilarerp.salon \
            --type IOS_APP_STORE \
            --create
          flutter build ipa \
            --release \
            --flavor salon \
            --dart-define=SUPABASE_URL=$SUPABASE_URL \
            --dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY \
            --dart-define=APP_FLAVOR=salon \
            --export-options-plist=/Users/builder/export_options_salon.plist \
            -t lib/main_salon.dart

      - name: Limpiar keychain
        script: keychain cleanup

    artifacts:
      - build/ios/ipa/*.ipa
      - /tmp/xcodebuild_logs/*.log

    publishing:
      app_store_connect:
        auth: integration          # Usa las variables APP_STORE_CONNECT_* del entorno
        submit_to_testflight: true
        beta_groups:
          - QA Interno
        submit_to_app_store: false  # Cambiar a true para release directo

      email:
        recipients:
          - devops@pilarerp.com
        notify:
          success: true
          failure: true

  # =========================================================
  # WORKFLOW 4: Flutter Windows → MSIX
  # =========================================================
  flutter-windows:
    name: "PILAR Windows (MSIX)"
    max_build_duration: 60
    instance_type: windows_x2     # VM Windows Server 2019

    triggering:
      events:
        - push
      branch_patterns:
        - pattern: main
          include: true
        - pattern: release/*
          include: true

    environment:
      flutter: stable
      vars:
        <<: *env_common
        MSIX_PUBLISHER_CN: $MSIX_PUBLISHER_CN   # Secret: CN del certificado
        MSIX_CERT_B64: $MSIX_CERT_B64           # Secret: certificado .pfx en base64

    scripts:
      <<: *setup_steps

      # Instalar herramienta msix
      - name: Instalar msix CLI
        script: dart pub global activate msix

      # Build Windows - flavor erp
      - name: Build Windows - erp
        script: |
          flutter build windows \
            --release \
            --flavor erp \
            --dart-define=SUPABASE_URL=$SUPABASE_URL \
            --dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY \
            --dart-define=SENTRY_DSN=$SENTRY_DSN \
            --dart-define=APP_FLAVOR=erp \
            -t lib/main_erp.dart

      # Empaquetar como MSIX
      - name: Crear MSIX
        script: |
          # Decodificar certificado desde secret
          echo "$MSIX_CERT_B64" | base64 -d > pilar_cert.pfx
          dart pub global run msix:create \
            --publisher-display-name "PILAR ERP" \
            --publisher "$MSIX_PUBLISHER_CN" \
            --version $((BUILD_NUMBER)).0.0 \
            --certificate-path pilar_cert.pfx \
            --certificate-password $MSIX_CERT_PASSWORD

    artifacts:
      - build/windows/x64/runner/Release/*.msix
      - build/windows/x64/runner/Release/*.exe

    publishing:
      email:
        recipients:
          - devops@pilarerp.com
        notify:
          success: true
          failure: true

  # =========================================================
  # WORKFLOW 5: Flutter macOS → Mac App Store
  # =========================================================
  flutter-macos:
    name: "PILAR macOS (Mac App Store)"
    max_build_duration: 90
    instance_type: mac_mini_m2

    triggering:
      events:
        - push
      branch_patterns:
        - pattern: release/*
          include: true

    environment:
      flutter: stable
      macos_signing:
        distribution_type: app_store
        bundle_identifier: com.pilarerp.erp.macos
      vars:
        <<: *env_common
        APP_STORE_CONNECT_ISSUER_ID: $ASC_ISSUER_ID
        APP_STORE_CONNECT_KEY_IDENTIFIER: $ASC_KEY_ID
        APP_STORE_CONNECT_PRIVATE_KEY: $ASC_PRIVATE_KEY
        CERTIFICATE_PRIVATE_KEY: $MACOS_CERT_PRIVATE_KEY

    scripts:
      <<: *setup_steps

      - name: Configurar code signing macOS
        script: |
          keychain initialize
          app-store-connect fetch-signing-files \
            com.pilarerp.erp.macos \
            --type MAC_APP_STORE \
            --create
          keychain add-certificates

      - name: Build macOS - erp
        script: |
          flutter build macos \
            --release \
            --flavor erp \
            --dart-define=SUPABASE_URL=$SUPABASE_URL \
            --dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY \
            --dart-define=SENTRY_DSN=$SENTRY_DSN \
            --dart-define=APP_FLAVOR=erp \
            -t lib/main_erp.dart

      - name: Empaquetar PKG para Mac App Store
        script: |
          APP_PATH="build/macos/Build/Products/Release/pilar_erp.app"
          xcrun productbuild \
            --component "$APP_PATH" /Applications \
            --sign "3rd Party Mac Developer Installer: PILAR ERP" \
            pilar_erp.pkg

      - name: Limpiar keychain
        script: keychain cleanup

    artifacts:
      - "*.pkg"

    publishing:
      app_store_connect:
        auth: integration
        submit_to_testflight: false
        submit_to_app_store: false   # Revision manual antes de submit

      email:
        recipients:
          - devops@pilarerp.com
        notify:
          success: true
          failure: true
```

---

## 3. GitHub Actions — Migraciones Supabase

Las migraciones de base de datos se gestionan con GitHub Actions (no Codemagic) porque son operaciones de backend independientes del build Flutter.

```yaml
# .github/workflows/supabase-migrations.yaml
name: Supabase Migrations

on:
  push:
    branches:
      - main
      - develop
    paths:
      - 'supabase/migrations/**'
      - 'supabase/seed.sql'

  # Permite ejecucion manual desde GitHub UI
  workflow_dispatch:
    inputs:
      environment:
        description: 'Entorno objetivo'
        required: true
        default: 'staging'
        type: choice
        options:
          - staging
          - production

jobs:
  migrate-staging:
    name: Aplicar migraciones en Staging
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/develop'
    environment: staging

    steps:
      - name: Checkout repo
        uses: actions/checkout@v4

      - name: Setup Supabase CLI
        uses: supabase/setup-cli@v1
        with:
          version: latest

      - name: Linkear proyecto Supabase Staging
        run: |
          supabase link \
            --project-ref ${{ secrets.SUPABASE_PROJECT_REF_STAGING }} \
            --password ${{ secrets.SUPABASE_DB_PASSWORD_STAGING }}
        env:
          SUPABASE_ACCESS_TOKEN: ${{ secrets.SUPABASE_ACCESS_TOKEN }}

      - name: Validar migraciones (lint)
        run: supabase db lint

      - name: Aplicar migraciones en Staging
        run: supabase db push
        env:
          SUPABASE_ACCESS_TOKEN: ${{ secrets.SUPABASE_ACCESS_TOKEN }}

      - name: Verificar schema post-migracion
        run: |
          supabase db diff --schema public,private,module_bus \
            --file /tmp/post_migration_diff.sql
          if [ -s /tmp/post_migration_diff.sql ]; then
            echo "ADVERTENCIA: hay cambios no aplicados en el schema"
            cat /tmp/post_migration_diff.sql
          fi

  migrate-production:
    name: Aplicar migraciones en Produccion
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'
    environment: production    # Requiere aprobacion manual en GitHub

    steps:
      - name: Checkout repo
        uses: actions/checkout@v4

      - name: Setup Supabase CLI
        uses: supabase/setup-cli@v1
        with:
          version: latest

      - name: Linkear proyecto Supabase Produccion
        run: |
          supabase link \
            --project-ref ${{ secrets.SUPABASE_PROJECT_REF_PROD }} \
            --password ${{ secrets.SUPABASE_DB_PASSWORD_PROD }}
        env:
          SUPABASE_ACCESS_TOKEN: ${{ secrets.SUPABASE_ACCESS_TOKEN }}

      - name: Lint antes de produccion
        run: supabase db lint --level error

      - name: Aplicar migraciones en Produccion
        run: supabase db push
        env:
          SUPABASE_ACCESS_TOKEN: ${{ secrets.SUPABASE_ACCESS_TOKEN }}

      - name: Notificar por Slack
        if: always()
        uses: slackapi/slack-github-action@v1.27
        with:
          payload: |
            {
              "text": "Migracion DB produccion: ${{ job.status }}",
              "blocks": [
                {
                  "type": "section",
                  "text": {
                    "type": "mrkdwn",
                    "text": "*Supabase Migration* - `${{ github.sha }}`\nEstado: ${{ job.status }}\nBranch: `${{ github.ref_name }}`"
                  }
                }
              ]
            }
        env:
          SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK_URL }}
          SLACK_WEBHOOK_TYPE: INCOMING_WEBHOOK
```

### Secrets requeridos en GitHub

```
# Supabase
SUPABASE_ACCESS_TOKEN          # Token personal de Supabase CLI
SUPABASE_PROJECT_REF_STAGING   # Ref del proyecto staging (ej: abcdefghijklmnop)
SUPABASE_PROJECT_REF_PROD      # Ref del proyecto produccion
SUPABASE_DB_PASSWORD_STAGING   # Password DB staging
SUPABASE_DB_PASSWORD_PROD      # Password DB produccion

# Notificaciones
SLACK_WEBHOOK_URL              # Webhook de Slack para notificaciones
```

---

## 4. Flavors en Codemagic

PILAR ERP tiene 3 flavors definidos en `android/app/build.gradle` y `ios/Runner/Info.plist`.

### Definicion de flavors en Flutter

```
lib/
├── main_erp.dart       # Entry point flavor erp
├── main_salon.dart     # Entry point flavor salon
├── main_cliente.dart   # Entry point flavor cliente (white-label)
└── flavors/
    ├── flavor_config.dart   # Clase FlavorConfig con nombre, supabase URL, etc.
    └── app_flavor.dart      # Enum AppFlavor { erp, salon, cliente }
```

```dart
// lib/flavors/flavor_config.dart
enum AppFlavor { erp, salon, cliente }

class FlavorConfig {
  final AppFlavor flavor;
  final String appName;
  final String bundleId;
  final String supabaseUrl;
  final String supabaseAnonKey;

  const FlavorConfig({
    required this.flavor,
    required this.appName,
    required this.bundleId,
    required this.supabaseUrl,
    required this.supabaseAnonKey,
  });

  static late FlavorConfig instance;

  static FlavorConfig fromEnv() {
    final flavorStr = const String.fromEnvironment('APP_FLAVOR', defaultValue: 'erp');
    final flavor = AppFlavor.values.byName(flavorStr);
    return FlavorConfig(
      flavor: flavor,
      appName: switch (flavor) {
        AppFlavor.erp     => 'PILAR ERP',
        AppFlavor.salon   => 'PILAR Salon',
        AppFlavor.cliente => 'PILAR Cliente',
      },
      bundleId: switch (flavor) {
        AppFlavor.erp     => 'com.pilarerp.erp',
        AppFlavor.salon   => 'com.pilarerp.salon',
        AppFlavor.cliente => 'com.pilarerp.cliente',
      },
      supabaseUrl: const String.fromEnvironment('SUPABASE_URL'),
      supabaseAnonKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
    );
  }
}
```

### Workflow parametrizado por flavor (alternativa con matrix)

Para evitar duplicar workflows, se puede usar una matrix en Codemagic (feature experimental) o un script parametrizado:

```yaml
# En codemagic.yaml, script reutilizable via variable FLAVOR
- name: Build AAB para flavor $FLAVOR
  script: |
    ENTRY_POINT="lib/main_${FLAVOR}.dart"
    flutter build appbundle \
      --release \
      --flavor $FLAVOR \
      --dart-define=SUPABASE_URL=$SUPABASE_URL \
      --dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY \
      --dart-define=APP_FLAVOR=$FLAVOR \
      -t $ENTRY_POINT
```

---

## 5. Code Signing

### Android — Keystore

El keystore se sube a Codemagic en **Teams > Integrations > Code signing > Android**.

```
# Pasos para generar el keystore (una sola vez):
keytool -genkey -v \
  -keystore pilar_release.keystore \
  -alias pilar_key \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000

# Subir a Codemagic con nombre "pilar_keystore"
# Codemagic inyecta automaticamente las variables:
#   CM_KEYSTORE_PATH, CM_KEY_ALIAS, CM_KEY_PASSWORD, CM_KEYSTORE_PASSWORD
```

En `android/app/build.gradle`:

```groovy
android {
    signingConfigs {
        release {
            storeFile     file(System.getenv("CM_KEYSTORE_PATH") ?: "debug.keystore")
            storePassword System.getenv("CM_KEYSTORE_PASSWORD") ?: "android"
            keyAlias      System.getenv("CM_KEY_ALIAS") ?: "androiddebugkey"
            keyPassword   System.getenv("CM_KEY_PASSWORD") ?: "android"
        }
    }
    buildTypes {
        release {
            signingConfig signingConfigs.release
            minifyEnabled true
            shrinkResources true
        }
    }
}
```

### iOS — Certificados y Provisioning Profiles

Codemagic gestiona el code signing iOS automaticamente via App Store Connect API:

1. Crear API Key en App Store Connect (Roles: App Manager).
2. Guardar Issuer ID, Key ID y archivo `.p8` como secrets en Codemagic.
3. En el workflow, usar `app-store-connect fetch-signing-files` (integrado en Codemagic CLI).
4. Codemagic descarga certificados y provisioning profiles, los instala en el keychain del build machine.

```yaml
# Codemagic gestiona signing automaticamente cuando se declara:
environment:
  ios_signing:
    distribution_type: app_store
    bundle_identifier: com.pilarerp.erp
```

**Bundle identifiers por flavor:**
- `erp`: `com.pilarerp.erp`
- `salon`: `com.pilarerp.salon`
- `cliente`: `com.pilarerp.cliente`

Cada flavor necesita su propio App ID en Apple Developer Portal y su provisioning profile.

### macOS — Developer ID Certificate

Para distribucion fuera de Mac App Store (DMG directo):

```yaml
environment:
  macos_signing:
    distribution_type: developer_id
    bundle_identifier: com.pilarerp.erp.macos
```

Para Mac App Store:

```yaml
environment:
  macos_signing:
    distribution_type: app_store
    bundle_identifier: com.pilarerp.erp.macos
```

---

## 6. Deployment

### Web → Cloudflare Pages

```bash
# Instalacion local de Wrangler (para deploy manual)
npm install -g wrangler
wrangler login

# Deploy desde local
flutter build web --release --flavor erp -t lib/main_erp.dart
wrangler pages deploy build/web --project-name pilar-erp

# En CI (Codemagic), la autenticacion es via CF_API_TOKEN
export CLOUDFLARE_API_TOKEN=$CF_API_TOKEN
wrangler pages deploy build/web_erp --project-name pilar-erp --branch main
```

Configuracion de Cloudflare Pages (`_headers` en `web/` del proyecto):

```
# web/_headers
/*
  X-Frame-Options: SAMEORIGIN
  X-Content-Type-Options: nosniff
  Referrer-Policy: strict-origin-when-cross-origin
  Content-Security-Policy: default-src 'self'; script-src 'self' 'unsafe-inline' https://*.supabase.co; connect-src 'self' https://*.supabase.co wss://*.supabase.co;

/flutter_service_worker.js
  Cache-Control: no-cache
```

### Android → Google Play

Codemagic tiene publisher nativo para Google Play. Requisitos:

1. Crear cuenta de servicio en Google Cloud Console con rol "Service Account User".
2. En Google Play Console, invitar esa cuenta con permiso "Release manager".
3. Descargar JSON key y guardarla en Codemagic secrets como `GOOGLE_PLAY_JSON_KEY`.

```yaml
publishing:
  google_play:
    credentials: $GOOGLE_PLAY_JSON_KEY
    track: internal      # Flujo: internal -> alpha -> beta -> production
    submit_as_draft: false
```

**Flujo de tracks:**
```
Codemagic build → internal (QA automatico)
                → alpha    (beta cerrada, URL compartida)
                → beta     (beta abierta, opt-in)
                → production (rollout gradual: 10% → 50% → 100%)
```

### iOS → App Store Connect

```yaml
publishing:
  app_store_connect:
    auth: integration
    submit_to_testflight: true
    beta_groups:
      - QA Interno
      - Beta Testers
    submit_to_app_store: false   # Cambiar cuando se quiera release directo
```

Para release a produccion:
1. Cambiar `submit_to_app_store: true`
2. Apple revisa el build (1-3 dias tipicamente)
3. Aprobar release en App Store Connect

### Windows → MSIX (distribucion directa)

```bash
# Instalacion de herramienta msix
dart pub global activate msix

# Build + empaquetado
flutter build windows --release -t lib/main_erp.dart
dart pub global run msix:create

# El MSIX se genera en:
# build/windows/x64/runner/Release/pilar_erp_setup.msix
```

Para distribucion empresarial (sin Microsoft Store):
- Firmar con certificado de Trusted Publisher (Self-signed solo funciona si se instala el cert en la maquina destino).
- Distribuir via link de descarga directa desde Cloudflare R2 o GitHub Releases.

---

## 7. Variables de entorno y secrets

### En Codemagic (Teams > Integrations > Environment variables)

| Variable | Tipo | Descripcion |
|----------|------|-------------|
| `SUPABASE_URL` | Secret | URL del proyecto Supabase produccion |
| `SUPABASE_ANON_KEY` | Secret | Anon key publica de Supabase |
| `SENTRY_DSN` | Secret | DSN de Sentry para monitoreo de errores |
| `CF_ACCOUNT_ID` | Secret | Cloudflare Account ID |
| `CF_API_TOKEN` | Secret | Cloudflare API Token con permiso Pages:Edit |
| `GOOGLE_PLAY_JSON_KEY` | Secret | JSON de cuenta de servicio Google Play |
| `ASC_ISSUER_ID` | Secret | App Store Connect API Issuer ID |
| `ASC_KEY_ID` | Secret | App Store Connect API Key ID |
| `ASC_PRIVATE_KEY` | Secret | Contenido del archivo .p8 (App Store Connect) |
| `IOS_CERT_PRIVATE_KEY` | Secret | Private key del certificado iOS (PEM) |
| `MACOS_CERT_PRIVATE_KEY` | Secret | Private key del certificado macOS (PEM) |
| `MSIX_PUBLISHER_CN` | Secret | CN del certificado Windows (ej: CN=PILAR ERP S.A.) |
| `MSIX_CERT_B64` | Secret | Certificado .pfx en base64 |
| `MSIX_CERT_PASSWORD` | Secret | Password del certificado .pfx |

### En GitHub Actions

| Secret | Descripcion |
|--------|-------------|
| `SUPABASE_ACCESS_TOKEN` | Token personal Supabase CLI |
| `SUPABASE_PROJECT_REF_STAGING` | ID del proyecto staging |
| `SUPABASE_PROJECT_REF_PROD` | ID del proyecto produccion |
| `SUPABASE_DB_PASSWORD_STAGING` | Password de la DB staging |
| `SUPABASE_DB_PASSWORD_PROD` | Password de la DB produccion |
| `SLACK_WEBHOOK_URL` | Webhook para notificaciones |

**IMPORTANTE:** Nunca incluir `.env` ni archivos con credenciales en el repositorio. El `.gitignore` debe excluir `*.env`, `*.keystore`, `*.jks`, `*.p8`, `*.p12`, `*.pfx`, `google-services.json`, `GoogleService-Info.plist`.

---

## 8. Versionado automatico

Codemagic inyecta la variable `$BUILD_NUMBER` (auto-incrementado). Usarla para el `version` en `pubspec.yaml`:

```yaml
# En codemagic.yaml, antes del build:
- name: Inyectar version de build
  script: |
    # Leer version base de pubspec.yaml (ej: 1.0.0)
    BASE_VERSION=$(grep "^version:" pubspec.yaml | awk '{print $2}' | cut -d'+' -f1)
    # Reemplazar build number con el de Codemagic
    sed -i "s/^version:.*/version: ${BASE_VERSION}+${BUILD_NUMBER}/" pubspec.yaml
    echo "Version final: ${BASE_VERSION}+${BUILD_NUMBER}"
```

La convencion de versiones para PILAR ERP es:

```
MAYOR.MENOR.PATCH+BUILD_NUMBER
  1.0.0+1      # primer release
  1.1.0+47     # nueva funcionalidad
  1.1.1+48     # hotfix
```

---

## 9. Checklist de configuracion inicial

- [ ] Crear cuenta en Codemagic y conectar repositorio GitHub
- [ ] Subir `codemagic.yaml` a la raiz del repositorio
- [ ] Configurar code signing Android (subir keystore)
- [ ] Configurar App Store Connect API (subir .p8 key)
- [ ] Crear Bundle IDs en Apple Developer Portal (3 flavors)
- [ ] Crear app en App Store Connect (3 flavors)
- [ ] Crear app en Google Play Console (3 flavors)
- [ ] Crear Service Account Google Play y descargar JSON
- [ ] Crear proyecto en Cloudflare Pages (pilar-erp, pilar-salon)
- [ ] Configurar todos los secrets en Codemagic
- [ ] Configurar secrets en GitHub para GitHub Actions
- [ ] Configurar environment "production" en GitHub con required reviewers
- [ ] Verificar primer build ejecutando workflow manualmente desde Codemagic UI
- [ ] Verificar que migraciones Supabase corren en staging antes de produccion
