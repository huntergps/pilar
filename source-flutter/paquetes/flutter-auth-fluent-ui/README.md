# supabase_auth_ui_fluent

Widgets de autenticación para Flutter usando **Fluent UI** (Windows 11 design system) y **Supabase**. Es un port de [`supabase_auth_ui`](https://github.com/supabase-community/flutter-auth-ui) que reemplaza todos los widgets de Material Design por sus equivalentes en `fluent_ui`.

## Diferencias con supabase_auth_ui (Material)

| Material | Fluent UI |
|----------|-----------|
| `TextFormField` | `TextFormBox` |
| `TextFormField(obscureText: true)` | `PasswordFormBox` (con botón revelar) |
| `ElevatedButton` | `FilledButton` |
| `TextButton` | `HyperlinkButton` |
| `CircularProgressIndicator` | `ProgressRing` |
| `CheckboxListTile` | `Checkbox` (con parámetro `content:`) |
| `ScaffoldMessenger.showSnackBar` | `displayInfoBar` con `InfoBar` |
| `Theme.of(context)` | `FluentTheme.of(context)` |
| `Icons.*` | `FluentIcons.*` |
| `ListTileControlAffinity` | `CheckboxAffinity` |

## Instalación

En `pubspec.yaml`:

```yaml
dependencies:
  supabase_auth_ui_fluent:
    path: ../flutter-auth-fluent-ui  # o la ruta/versión correspondiente
  fluent_ui: ^4.14.0
  supabase_flutter: ^2.5.6
```

## Configuración inicial

Inicializa Supabase antes de usar cualquier widget (normalmente en `main.dart`):

```dart
import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://TU_PROYECTO.supabase.co',
    anonKey: 'TU_ANON_KEY',
  );

  runApp(const MyApp());
}
```

La app debe usar `FluentApp` (no `MaterialApp`) para que los widgets funcionen correctamente:

```dart
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return FluentApp(
      title: 'Mi App',
      theme: FluentThemeData.light(),
      darkTheme: FluentThemeData.dark(),
      themeMode: ThemeMode.system,
      home: const LoginPage(),
    );
  }
}
```

---

## Email Auth

`SupaEmailAuth` crea un formulario completo de login / registro con email y contraseña. Incluye botón para recuperar contraseña.

```dart
import 'package:fluent_ui/fluent_ui.dart';
import 'package:supabase_auth_ui_fluent/supabase_auth_ui_fluent.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ScaffoldPage(
      header: const PageHeader(title: Text('Iniciar sesión')),
      content: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: SupaEmailAuth(
              redirectTo: kIsWeb ? null : 'io.miapp.example://callback',
              onSignInComplete: (AuthResponse response) {
                // Navegar a la pantalla principal
                Navigator.of(context).pushReplacementNamed('/home');
              },
              onSignUpComplete: (AuthResponse response) {
                // Informar al usuario que revise su correo
                Navigator.of(context).pushReplacementNamed('/verify-email');
              },
              onError: (Object error) {
                // Manejo de error personalizado (opcional)
                // Si no se define, se muestra un InfoBar de error automáticamente
                debugPrint('Error de auth: $error');
              },
            ),
          ),
        ),
      ),
    );
  }
}
```

### Con campos de metadata adicionales

Agrega campos extra al formulario de registro que se guardan en `user_metadata`:

```dart
SupaEmailAuth(
  redirectTo: kIsWeb ? null : 'io.miapp.example://callback',
  onSignInComplete: (response) => Navigator.pushReplacementNamed(context, '/home'),
  onSignUpComplete: (response) => Navigator.pushReplacementNamed(context, '/home'),

  // Campo de texto adicional: { 'nombre_completo': 'Juan Pérez' }
  metadataFields: [
    MetaDataField(
      label: 'Nombre completo',
      key: 'nombre_completo',
      prefixIcon: const Icon(FluentIcons.contact),
      validator: (val) {
        if (val == null || val.isEmpty) return 'Ingresa tu nombre';
        return null;
      },
    ),

    // Campo booleano: { 'acepta_marketing': true }
    BooleanMetaDataField(
      label: 'Quiero recibir novedades por email',
      key: 'acepta_marketing',
    ),

    // Campo booleano requerido con texto enriquecido
    BooleanMetaDataField(
      key: 'acepta_terminos',
      isRequired: true,
      richLabelSpans: [
        const TextSpan(text: 'He leído y acepto los '),
        TextSpan(
          text: 'Términos y Condiciones',
          style: TextStyle(
            color: FluentTheme.of(context).accentColor,
            decoration: TextDecoration.underline,
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () {
              // Navegar a los términos
              Navigator.pushNamed(context, '/terminos');
            },
        ),
      ],
    ),
  ],

  // Metadata extra que siempre se incluye en el registro
  extraMetadata: {
    'origen': 'app_movil',
    'version': '1.0.0',
  },
),
```

### Con confirmPassword y localización en español

```dart
SupaEmailAuth(
  showConfirmPasswordField: true,
  isInitiallySigningIn: false, // abre en modo registro
  onSignInComplete: (response) {},
  onSignUpComplete: (response) {},
  localization: const SupaEmailAuthLocalization(
    enterEmail: 'Ingresa tu email',
    validEmailError: 'Email no válido',
    enterPassword: 'Contraseña',
    passwordLengthError: 'Mínimo 6 caracteres',
    confirmPassword: 'Confirmar contraseña',
    confirmPasswordError: 'Las contraseñas no coinciden',
    signIn: 'Entrar',
    signUp: 'Registrarse',
    forgotPassword: '¿Olvidaste tu contraseña?',
    dontHaveAccount: '¿No tienes cuenta? Regístrate',
    haveAccount: '¿Ya tienes cuenta? Entra',
    sendPasswordReset: 'Enviar email de recuperación',
    passwordResetSent: 'Email enviado, revisa tu bandeja',
    backToSignIn: 'Volver al inicio de sesión',
    unexpectedError: 'Error inesperado',
    requiredFieldError: 'Este campo es obligatorio',
  ),
),
```

---

## Magic Link Auth

`SupaMagicAuth` crea un formulario de inicio de sesión sin contraseña mediante enlace mágico por email. Requiere configurar deep links en tu app.

```dart
SupaMagicAuth(
  redirectUrl: kIsWeb ? null : 'io.miapp.example://magic-link',
  onSuccess: (Session session) {
    Navigator.of(context).pushReplacementNamed('/home');
  },
  onError: (Object error) {
    debugPrint('Error: $error');
  },
  localization: const SupaMagicAuthLocalization(
    enterEmail: 'Ingresa tu email',
    validEmailError: 'Email no válido',
    continueWithMagicLink: 'Continuar con enlace mágico',
    checkYourEmail: '¡Revisa tu email!',
    unexpectedError: 'Error inesperado',
  ),
),
```

---

## Reset Password

`SupaResetPassword` crea el formulario para establecer una nueva contraseña. Úsalo en la pantalla a la que redirige el enlace de recuperación de contraseña.

```dart
SupaResetPassword(
  accessToken: Supabase.instance.client.auth.currentSession?.accessToken,
  onSuccess: (UserResponse response) {
    // Contraseña actualizada correctamente
    Navigator.of(context).pushReplacementNamed('/home');
  },
  onError: (Object error) {
    debugPrint('Error: $error');
  },
  localization: const SupaResetPasswordLocalization(
    enterPassword: 'Nueva contraseña',
    passwordLengthError: 'Mínimo 6 caracteres',
    updatePassword: 'Actualizar contraseña',
    passwordResetSent: '¡Contraseña actualizada correctamente!',
    unexpectedError: 'Error inesperado',
  ),
),
```

---

## Phone Auth

`SupaPhoneAuth` crea un formulario de login / registro con número de teléfono y contraseña.

```dart
// Inicio de sesión con teléfono
SupaPhoneAuth(
  authAction: SupaAuthAction.signIn,
  onSuccess: (AuthResponse response) {
    Navigator.of(context).pushReplacementNamed('/home');
  },
  onError: (Object error) {
    debugPrint('Error: $error');
  },
),

// Registro con teléfono (seguido de SupaVerifyPhone para verificar OTP)
SupaPhoneAuth(
  authAction: SupaAuthAction.signUp,
  onSuccess: (AuthResponse response) {
    Navigator.of(context).pushNamed(
      '/verify-phone',
      arguments: {'phone': response.user?.phone},
    );
  },
),
```

---

## Verify Phone

`SupaVerifyPhone` verifica el código OTP enviado al teléfono tras el registro con `SupaPhoneAuth`.

```dart
// En la ruta '/verify-phone'
// Los argumentos de navegación deben incluir {'phone': '+593...'}
SupaVerifyPhone(
  onSuccess: (AuthResponse response) {
    Navigator.of(context).pushReplacementNamed('/home');
  },
  onError: (Object error) {
    debugPrint('Error: $error');
  },
  localization: const SupaVerifyPhoneLocalization(
    enterCodeSent: 'Código enviado a tu teléfono',
    enterOneTimeCode: 'Ingresa el código de verificación',
    verifyPhone: 'Verificar',
    unexpectedErrorOccurred: 'Error inesperado',
  ),
),
```

---

## Social Auth

`SupaSocialsAuth` muestra botones para autenticación con proveedores OAuth (Google, Apple, GitHub, etc.). Requiere configurar deep links.

### Variante con icono y texto (por defecto)

```dart
SupaSocialsAuth(
  socialProviders: const [
    OAuthProvider.google,
    OAuthProvider.apple,
    OAuthProvider.github,
    OAuthProvider.discord,
  ],
  colored: true, // botones con colores de marca
  redirectUrl: kIsWeb ? null : 'io.miapp.example://callback',
  onSuccess: (Session session) {
    Navigator.of(context).pushReplacementNamed('/home');
  },
  onError: (Object error) {
    debugPrint('Error OAuth: $error');
  },
  localization: const SupaSocialsAuthLocalization(
    successSignInMessage: '¡Sesión iniciada correctamente!',
    unexpectedError: 'Error inesperado',
    oAuthButtonLabels: {
      OAuthProvider.google: 'Continuar con Google',
      OAuthProvider.apple: 'Continuar con Apple',
      OAuthProvider.github: 'Continuar con GitHub',
      OAuthProvider.discord: 'Continuar con Discord',
    },
  ),
),
```

### Variante solo iconos circulares

```dart
SupaSocialsAuth(
  socialProviders: const [
    OAuthProvider.google,
    OAuthProvider.apple,
    OAuthProvider.github,
    OAuthProvider.twitter,
    OAuthProvider.facebook,
  ],
  socialButtonVariant: SocialButtonVariant.icon,
  colored: true,
  redirectUrl: kIsWeb ? null : 'io.miapp.example://callback',
  onSuccess: (Session session) {},
),
```

### Con Google nativo (Android / iOS)

```dart
SupaSocialsAuth(
  socialProviders: const [OAuthProvider.google],
  nativeGoogleAuthConfig: const NativeGoogleAuthConfig(
    webClientId: '123456789-abc.apps.googleusercontent.com',   // Android
    iosClientId: '123456789-xyz.apps.googleusercontent.com',  // iOS
  ),
  redirectUrl: kIsWeb ? null : 'io.miapp.example://callback',
  onSuccess: (Session session) {},
),
```

### Sin colores de marca (adaptado al tema de la app)

```dart
SupaSocialsAuth(
  socialProviders: const [
    OAuthProvider.google,
    OAuthProvider.github,
  ],
  colored: false,  // usa el estilo del tema fluent_ui
  redirectUrl: kIsWeb ? null : 'io.miapp.example://callback',
  onSuccess: (Session session) {},
),
```

---

## Pantalla de login completa (Email + Redes sociales)

Ejemplo de una pantalla de login real combinando varios componentes:

```dart
class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ScaffoldPage.scrollable(
      children: [
        const SizedBox(height: 48),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Logo / título
                  Text(
                    'Bienvenido',
                    style: FluentTheme.of(context).typography.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Inicia sesión para continuar',
                    style: FluentTheme.of(context).typography.body,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),

                  // Redes sociales
                  SupaSocialsAuth(
                    socialProviders: const [
                      OAuthProvider.google,
                      OAuthProvider.apple,
                    ],
                    colored: true,
                    redirectUrl: kIsWeb ? null : 'io.miapp://callback',
                    onSuccess: (session) =>
                        Navigator.pushReplacementNamed(context, '/home'),
                    showSuccessSnackBar: false,
                  ),

                  const SizedBox(height: 24),

                  // Divisor
                  Row(
                    children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'o continúa con email',
                          style: FluentTheme.of(context).typography.caption,
                        ),
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Email + contraseña
                  SupaEmailAuth(
                    redirectTo: kIsWeb ? null : 'io.miapp://callback',
                    onSignInComplete: (response) =>
                        Navigator.pushReplacementNamed(context, '/home'),
                    onSignUpComplete: (response) =>
                        Navigator.pushReplacementNamed(context, '/home'),
                    localization: const SupaEmailAuthLocalization(
                      enterEmail: 'Email',
                      enterPassword: 'Contraseña',
                      signIn: 'Iniciar sesión',
                      signUp: 'Crear cuenta',
                      forgotPassword: '¿Olvidaste tu contraseña?',
                      dontHaveAccount: '¿No tienes cuenta? Regístrate',
                      haveAccount: '¿Ya tienes cuenta? Entra',
                      sendPasswordReset: 'Enviar enlace de recuperación',
                      passwordResetSent: 'Revisa tu email',
                      backToSignIn: 'Volver',
                      validEmailError: 'Email no válido',
                      passwordLengthError: 'Mínimo 6 caracteres',
                      unexpectedError: 'Error inesperado',
                      requiredFieldError: 'Campo obligatorio',
                      confirmPassword: 'Confirmar contraseña',
                      confirmPasswordError: 'Las contraseñas no coinciden',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
```

---

## Theming

Los widgets usan `FluentTheme.of(context)` para adaptarse automáticamente al tema de tu app. Puedes personalizar colores, tipografía y estilos desde `FluentThemeData`:

```dart
FluentApp(
  theme: FluentThemeData(
    accentColor: Colors.blue,
    brightness: Brightness.light,
    // Los FilledButton usarán accentColor automáticamente
    // Los HyperlinkButton usarán accentColor para el texto
  ),
  darkTheme: FluentThemeData(
    accentColor: Colors.blue,
    brightness: Brightness.dark,
  ),
  themeMode: ThemeMode.system,
  home: const LoginPage(),
),
```

### Personalizar iconos de los campos

```dart
SupaEmailAuth(
  prefixIconEmail: const Icon(FluentIcons.globe),       // icono email
  prefixIconPassword: const Icon(FluentIcons.lock),     // icono contraseña
  onSignInComplete: (response) {},
  onSignUpComplete: (response) {},
),
```

---

## Mapeo completo de componentes

| Componente | Descripción |
|-----------|-------------|
| `SupaEmailAuth` | Formulario email + contraseña (login, registro, recuperación) |
| `SupaMagicAuth` | Formulario de enlace mágico sin contraseña |
| `SupaPhoneAuth` | Formulario teléfono + contraseña |
| `SupaVerifyPhone` | Verificación de código OTP por SMS |
| `SupaResetPassword` | Formulario para establecer nueva contraseña |
| `SupaSocialsAuth` | Botones OAuth (Google, Apple, GitHub, Discord, etc.) |

## Clases de soporte

| Clase | Descripción |
|-------|-------------|
| `MetaDataField` | Campo de texto adicional en el formulario de registro |
| `BooleanMetaDataField` | Checkbox adicional en el formulario de registro |
| `CheckboxAffinity` | Posición del checkbox: `leading` o `trailing` |
| `NativeGoogleAuthConfig` | Configuración de Google Sign In nativo |
| `SocialButtonVariant` | Estilo de botones: `icon` o `iconAndText` |
| `SupaAuthAction` | Acción en `SupaPhoneAuth`: `signIn` o `signUp` |

## Localización

Todos los widgets aceptan un parámetro `localization` para personalizar los textos:

```dart
SupaEmailAuthLocalization(enterEmail: 'Email', signIn: 'Entrar', ...)
SupaMagicAuthLocalization(continueWithMagicLink: 'Enlace mágico', ...)
SupaPhoneAuthLocalization(enterPhoneNumber: 'Teléfono', ...)
SupaResetPasswordLocalization(updatePassword: 'Guardar contraseña', ...)
SupaSocialsAuthLocalization(oAuthButtonLabels: {OAuthProvider.google: 'Google'}, ...)
SupaVerifyPhoneLocalization(verifyPhone: 'Verificar', ...)
```
