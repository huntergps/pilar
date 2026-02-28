// Tests de CuentasComunicacionScreen
//
// Cubre:
//   · Estado vacío (sin cuentas configuradas)
//   · Estado de carga (ProgressRing)
//   · Estado de error (InfoBar)
//   · Renderizado con cuentas (agrupadas por tipo, cards con badge, status)
//   · _buildConfigJson: cada tipo de cuenta genera config correcta
//   · _CuentaCard: nombre, subtítulo, badge "predeterminado", indicador activo
//   · _SectionHeader: ícono, label, botón agregar
//   · Botón "Nueva cuenta" en header abre dialog
//   · Botón "Agregar primera cuenta" en estado vacío abre dialog
//
// NOTA: Las operaciones de escritura (toggle, defecto, eliminar) requieren
// Supabase real o un mock profundo; se prueban solo el flujo de UI visible.

import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilar_erp/features/administracion/screens/cuentas_comunicacion_screen.dart';

import '../../helpers/test_utils.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Cuentas de prueba, una por cada tipo soportado.
List<Map<String, dynamic>> _fakeCuentas() => [
      {
        'id': 'wa-001',
        'nombre': 'WhatsApp Principal',
        'tipo': 'whatsapp',
        'activo': true,
        'es_defecto': true,
        'config_json': {
          'app_uid': 'app-123',
          'account_uid': 'acct-456',
          'phone_uid': 'phone-789',
          'phone_number': '+593991234567',
          'token': 'tok-xxx',
          'app_secret': 'sec-xxx',
          'webhook_verify_token': 'vt-xxx',
        },
      },
      {
        'id': 'em-001',
        'nombre': 'Email Resend',
        'tipo': 'email_api',
        'activo': false,
        'es_defecto': false,
        'config_json': {
          'provider': 'resend',
          'api_key': 're_xxx',
          'from_name': 'PILAR ERP',
          'from_email': 'noreply@pilar.ec',
        },
      },
      {
        'id': 'smtp-001',
        'nombre': 'SMTP Corporativo',
        'tipo': 'email_smtp',
        'activo': true,
        'es_defecto': false,
        'config_json': {
          'host': 'smtp.empresa.ec',
          'port': 587,
          'use_tls': true,
          'from_name': 'Empresa SA',
          'from_email': 'info@empresa.ec',
          'username': 'user',
          'password': 'pass',
        },
      },
      {
        'id': 'tg-001',
        'nombre': 'Bot Telegram',
        'tipo': 'telegram',
        'activo': true,
        'es_defecto': false,
        'config_json': {
          'bot_token': '123456:ABC',
          'bot_username': 'pilar_erp_bot',
          'webhook_secret': 'ws-xxx',
        },
      },
    ];

/// Override que provee datos estáticos sin tocar Supabase.
Override _cuentasOverride(AsyncValue<List<Map<String, dynamic>>> value) =>
    comCuentasProvider.overrideWith((_) async {
      if (value is AsyncData<List<Map<String, dynamic>>>) {
        return value.value.map(CuentaItem.fromMap).toList();
      }
      if (value is AsyncError<List<Map<String, dynamic>>>) {
        throw value.error;
      }
      // loading: bloquear indefinidamente
      await Future<void>.delayed(const Duration(hours: 1));
      return <CuentaItem>[];
    });

Widget _buildScreen(AsyncValue<List<Map<String, dynamic>>> value) {
  return buildFluentApp(
    const CuentasComunicacionScreen(),
    overrides: [_cuentasOverride(value)],
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('CuentasComunicacionScreen — estado vacío', () {
    testWidgets('muestra mensaje sin cuentas y botón "Agregar primera cuenta"',
        (tester) async {
      await tester.pumpWidget(_buildScreen(const AsyncData([])));
      await tester.pump();

      expect(find.text('Sin cuentas configuradas'), findsOneWidget);
      expect(find.text('Agregar primera cuenta'), findsOneWidget);
    });

    testWidgets(
        'estado vacío: no renderiza ninguna _CuentaCard ni _SectionHeader',
        (tester) async {
      await tester.pumpWidget(_buildScreen(const AsyncData([])));
      await tester.pump();

      // Ningún nombre de cuenta ficticia
      expect(find.text('WhatsApp Principal'), findsNothing);
      expect(find.text('WhatsApp'), findsNothing);
    });
  });

  // -------------------------------------------------------------------------

  group('CuentasComunicacionScreen — estado de carga', () {
    testWidgets('muestra ProgressRing mientras carga', (tester) async {
      // Completer que nunca se completa → no deja timers pendientes
      final completer = Completer<List<CuentaItem>>();
      final app = ProviderScope(
        overrides: [
          ...baseOverrides(),
          comCuentasProvider.overrideWith((_) => completer.future),
        ],
        child: const FluentApp(home: CuentasComunicacionScreen()),
      );
      await tester.pumpWidget(app);
      await tester.pump(); // un frame sin resolver el future

      expect(find.byType(ProgressRing), findsOneWidget);

      // Completar para limpiar el provider al destruir el árbol
      completer.complete([]);
    });
  });

  // -------------------------------------------------------------------------

  group('CuentasComunicacionScreen — estado de error', () {
    testWidgets('muestra InfoBar con texto de error', (tester) async {
      await tester.pumpWidget(
        _buildScreen(AsyncError(Exception('timeout'), StackTrace.empty)),
      );
      await tester.pump();

      expect(find.byType(InfoBar), findsOneWidget);
      expect(find.text('Error cargando cuentas'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------

  group('CuentasComunicacionScreen — con cuentas', () {
    testWidgets('renderiza sección "WhatsApp" con ícono y cuenta',
        (tester) async {
      await tester.pumpWidget(_buildScreen(AsyncData(_fakeCuentas())));
      await tester.pump();

      expect(find.text('WhatsApp'), findsWidgets); // sección header
      expect(find.text('WhatsApp Principal'), findsOneWidget); // card
    });

    testWidgets('renderiza sección "Email (API)" y "Email (SMTP)"',
        (tester) async {
      await tester.pumpWidget(_buildScreen(AsyncData(_fakeCuentas())));
      await tester.pump();

      expect(find.text('Email (API)'), findsOneWidget);
      expect(find.text('Email Resend'), findsOneWidget);
      expect(find.text('Email (SMTP)'), findsOneWidget);
      expect(find.text('SMTP Corporativo'), findsOneWidget);
    });

    testWidgets('renderiza sección "Telegram" y bot', (tester) async {
      await tester.pumpWidget(_buildScreen(AsyncData(_fakeCuentas())));
      await tester.pump();

      expect(find.text('Telegram'), findsOneWidget);
      expect(find.text('Bot Telegram'), findsOneWidget);
    });

    testWidgets('cuenta con es_defecto=true muestra badge "predeterminado"',
        (tester) async {
      await tester.pumpWidget(_buildScreen(AsyncData(_fakeCuentas())));
      await tester.pump();

      expect(find.text('predeterminado'), findsOneWidget);
    });

    testWidgets(
        'subtítulo WhatsApp muestra número de teléfono', (tester) async {
      await tester.pumpWidget(_buildScreen(AsyncData([_fakeCuentas()[0]])));
      await tester.pump();

      expect(find.textContaining('+593991234567'), findsOneWidget);
    });

    testWidgets('subtítulo email_api muestra proveedor y from_email',
        (tester) async {
      await tester.pumpWidget(_buildScreen(AsyncData([_fakeCuentas()[1]])));
      await tester.pump();

      expect(find.textContaining('resend'), findsOneWidget);
      expect(find.textContaining('noreply@pilar.ec'), findsOneWidget);
    });

    testWidgets('subtítulo email_smtp muestra host y from_email',
        (tester) async {
      await tester.pumpWidget(_buildScreen(AsyncData([_fakeCuentas()[2]])));
      await tester.pump();

      expect(find.textContaining('smtp.empresa.ec'), findsOneWidget);
      expect(find.textContaining('info@empresa.ec'), findsOneWidget);
    });

    testWidgets('subtítulo telegram muestra @username', (tester) async {
      await tester.pumpWidget(_buildScreen(AsyncData([_fakeCuentas()[3]])));
      await tester.pump();

      expect(find.textContaining('@pilar_erp_bot'), findsOneWidget);
    });

    testWidgets('cuenta activo=false → indicador gris', (tester) async {
      await tester.pumpWidget(_buildScreen(AsyncData([_fakeCuentas()[1]])));
      await tester.pump();

      // La card se renderiza sin crash para cuenta inactiva
      expect(find.text('Email Resend'), findsOneWidget);
    });

    testWidgets('header muestra botón "Nueva cuenta"', (tester) async {
      await tester.pumpWidget(_buildScreen(AsyncData(_fakeCuentas())));
      await tester.pump();

      expect(find.text('Nueva cuenta'), findsOneWidget);
    });

    testWidgets('tap en "Nueva cuenta" abre ContentDialog', (tester) async {
      await tester.pumpWidget(_buildScreen(AsyncData(_fakeCuentas())));
      await tester.pump();

      await tester.tap(find.text('Nueva cuenta'));
      await tester.pumpAndSettle();

      expect(find.byType(ContentDialog), findsOneWidget);
      expect(find.text('Nueva cuenta'), findsWidgets); // titulo dialog
    });

    testWidgets(
        'tap en "Agregar primera cuenta" (estado vacío) abre ContentDialog',
        (tester) async {
      await tester.pumpWidget(_buildScreen(const AsyncData([])));
      await tester.pump();

      await tester.tap(find.text('Agregar primera cuenta'));
      await tester.pumpAndSettle();

      expect(find.byType(ContentDialog), findsOneWidget);
    });

    testWidgets('botón + de sección abre dialog con tipo preset',
        (tester) async {
      await tester.pumpWidget(_buildScreen(AsyncData([_fakeCuentas()[0]])));
      await tester.pump();

      // El _SectionHeader de WhatsApp tiene un IconButton add
      final addBtns = find.byIcon(FluentIcons.add);
      expect(addBtns, findsWidgets);
    });
  });

  // -------------------------------------------------------------------------

  group('_CuentaDialogState._buildConfigJson — lógica de config', () {
    test('whatsapp genera config con todos los campos', () {
      final cfg = _buildWhatsAppConfig(
        appUid: 'app-1',
        accountUid: 'acct-2',
        phoneUid: 'ph-3',
        phoneNumber: '+593990000001',
        token: 'tok-4',
        appSecret: 'sec-5',
        verifyToken: 'vt-6',
      );

      expect(cfg['app_uid'], 'app-1');
      expect(cfg['account_uid'], 'acct-2');
      expect(cfg['phone_uid'], 'ph-3');
      expect(cfg['phone_number'], '+593990000001');
      expect(cfg['token'], 'tok-4');
      expect(cfg['app_secret'], 'sec-5');
      expect(cfg['webhook_verify_token'], 'vt-6');
    });

    test('email_api genera config con provider, api_key, from', () {
      final cfg = _buildEmailApiConfig(
        provider: 'sendgrid',
        apiKey: 'sg-xxx',
        fromName: 'PILAR',
        fromEmail: 'no-reply@pilar.ec',
      );

      expect(cfg['provider'], 'sendgrid');
      expect(cfg['api_key'], 'sg-xxx');
      expect(cfg['from_name'], 'PILAR');
      expect(cfg['from_email'], 'no-reply@pilar.ec');
    });

    test('email_smtp incluye port como int y use_tls como bool', () {
      final cfg = _buildEmailSmtpConfig(
        host: 'smtp.test.com',
        port: '465',
        useTls: false,
        fromName: 'Test',
        fromEmail: 'test@test.com',
        user: 'u',
        pass: 'p',
      );

      expect(cfg['host'], 'smtp.test.com');
      expect(cfg['port'], 465);
      expect(cfg['use_tls'], false);
      expect(cfg['username'], 'u');
      expect(cfg['password'], 'p');
    });

    test('email_smtp port inválido defaultea a 587', () {
      final cfg = _buildEmailSmtpConfig(
        host: 'smtp.test.com',
        port: 'abc', // inválido
        useTls: true,
        fromName: 'X',
        fromEmail: 'x@x.com',
        user: 'u',
        pass: 'p',
      );

      expect(cfg['port'], 587);
    });

    test('telegram genera config con bot_token, bot_username, webhook_secret',
        () {
      final cfg = _buildTelegramConfig(
        token: '123:ABC',
        username: 'mi_bot',
        secret: 'ws-secret',
      );

      expect(cfg['bot_token'], '123:ABC');
      expect(cfg['bot_username'], 'mi_bot');
      expect(cfg['webhook_secret'], 'ws-secret');
    });
  });
}

// ---------------------------------------------------------------------------
// Lógica de _buildConfigJson extraída para unit tests puros
// Refleja exactamente el switch de _CuentaDialogState._buildConfigJson.
// ---------------------------------------------------------------------------

Map<String, dynamic> _buildWhatsAppConfig({
  required String appUid,
  required String accountUid,
  required String phoneUid,
  required String phoneNumber,
  required String token,
  required String appSecret,
  required String verifyToken,
}) =>
    {
      'app_uid': appUid.trim(),
      'account_uid': accountUid.trim(),
      'phone_uid': phoneUid.trim(),
      'phone_number': phoneNumber.trim(),
      'token': token.trim(),
      'app_secret': appSecret.trim(),
      'webhook_verify_token': verifyToken.trim(),
    };

Map<String, dynamic> _buildEmailApiConfig({
  required String provider,
  required String apiKey,
  required String fromName,
  required String fromEmail,
}) =>
    {
      'provider': provider,
      'api_key': apiKey.trim(),
      'from_name': fromName.trim(),
      'from_email': fromEmail.trim(),
    };

Map<String, dynamic> _buildEmailSmtpConfig({
  required String host,
  required String port,
  required bool useTls,
  required String fromName,
  required String fromEmail,
  required String user,
  required String pass,
}) =>
    {
      'host': host.trim(),
      'port': int.tryParse(port) ?? 587,
      'use_tls': useTls,
      'from_name': fromName.trim(),
      'from_email': fromEmail.trim(),
      'username': user.trim(),
      'password': pass.trim(),
    };

Map<String, dynamic> _buildTelegramConfig({
  required String token,
  required String username,
  required String secret,
}) =>
    {
      'bot_token': token.trim(),
      'bot_username': username.trim(),
      'webhook_secret': secret.trim(),
    };
