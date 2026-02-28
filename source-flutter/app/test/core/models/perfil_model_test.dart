import 'package:flutter_test/flutter_test.dart';
import 'package:pilar_erp/core/providers/perfil_provider.dart';

void main() {
  // ---------------------------------------------------------------------------
  // PerfilUsuario.fromJson
  // ---------------------------------------------------------------------------

  group('PerfilUsuario.fromJson', () {
    test('parsea todos los campos correctamente', () {
      final json = {
        'usuario_id': 'u-001',
        'empresa_id': 'e-001',
        'nombre_display': 'Juan Pérez',
        'avatar_url': 'https://cdn.example.com/avatar.jpg',
        'telefono': '0999000111',
        'email_contacto': 'juan@empresa.com',
        'email_login': 'juan.perez@gmail.com',
        'nombre_global': 'Juan Carlos Pérez',
        'zona_horaria': 'America/Guayaquil',
      };

      final p = PerfilUsuario.fromJson(json);

      expect(p.usuarioId, 'u-001');
      expect(p.empresaId, 'e-001');
      expect(p.nombreDisplay, 'Juan Pérez');
      expect(p.avatarUrl, 'https://cdn.example.com/avatar.jpg');
      expect(p.telefono, '0999000111');
      expect(p.emailContacto, 'juan@empresa.com');
      expect(p.emailLogin, 'juan.perez@gmail.com');
      expect(p.nombreGlobal, 'Juan Carlos Pérez');
      expect(p.zonaHoraria, 'America/Guayaquil');
    });

    test('usa zona_horaria Guayaquil por defecto', () {
      final json = {
        'usuario_id': 'u-001',
        'empresa_id': 'e-001',
        'email_login': 'test@test.com',
      };

      final p = PerfilUsuario.fromJson(json);
      expect(p.zonaHoraria, 'America/Guayaquil');
    });

    test('campos opcionales son null cuando no están en JSON', () {
      final json = {
        'usuario_id': 'u-001',
        'empresa_id': 'e-001',
        'email_login': 'test@test.com',
      };

      final p = PerfilUsuario.fromJson(json);

      expect(p.nombreDisplay, isNull);
      expect(p.avatarUrl, isNull);
      expect(p.telefono, isNull);
      expect(p.emailContacto, isNull);
      expect(p.nombreGlobal, isNull);
    });

    test('usa string vacío cuando usuario_id o empresa_id son null', () {
      final json = <String, dynamic>{};

      final p = PerfilUsuario.fromJson(json);

      expect(p.usuarioId, '');
      expect(p.empresaId, '');
      expect(p.emailLogin, '');
    });
  });

  // ---------------------------------------------------------------------------
  // PerfilUsuario.displayName (propiedad computada)
  // ---------------------------------------------------------------------------

  group('PerfilUsuario.displayName', () {
    test('retorna nombreDisplay cuando está definido (máxima prioridad)', () {
      const p = PerfilUsuario(
        usuarioId: 'u-001',
        empresaId: 'e-001',
        emailLogin: 'login@test.com',
        nombreDisplay: 'Nombre Empresa',
        nombreGlobal: 'Nombre Global',
      );

      expect(p.displayName, 'Nombre Empresa');
    });

    test('retorna nombreGlobal cuando no hay nombreDisplay', () {
      const p = PerfilUsuario(
        usuarioId: 'u-001',
        empresaId: 'e-001',
        emailLogin: 'login@test.com',
        nombreGlobal: 'Nombre Global',
      );

      expect(p.displayName, 'Nombre Global');
    });

    test('retorna emailLogin como fallback final', () {
      const p = PerfilUsuario(
        usuarioId: 'u-001',
        empresaId: 'e-001',
        emailLogin: 'login@test.com',
      );

      expect(p.displayName, 'login@test.com');
    });
  });

  // ---------------------------------------------------------------------------
  // PerfilUsuario.initial (propiedad computada)
  // ---------------------------------------------------------------------------

  group('PerfilUsuario.initial', () {
    test('retorna la inicial en mayúscula del displayName', () {
      const p = PerfilUsuario(
        usuarioId: 'u-001',
        empresaId: 'e-001',
        emailLogin: 'j@test.com',
        nombreDisplay: 'juan',
      );

      expect(p.initial, 'J');
    });

    test('retorna ? cuando displayName está vacío', () {
      const p = PerfilUsuario(
        usuarioId: 'u-001',
        empresaId: 'e-001',
        emailLogin: '',
      );

      expect(p.initial, '?');
    });
  });

  // ---------------------------------------------------------------------------
  // PerfilUsuario.copyWith
  // ---------------------------------------------------------------------------

  group('PerfilUsuario.copyWith', () {
    const base = PerfilUsuario(
      usuarioId: 'u-001',
      empresaId: 'e-001',
      emailLogin: 'base@test.com',
      nombreDisplay: 'Base',
      avatarUrl: 'https://old.jpg',
      telefono: '0900000000',
      emailContacto: 'base@empresa.com',
      zonaHoraria: 'America/Guayaquil',
    );

    test('actualiza solo los campos especificados', () {
      final updated = base.copyWith(nombreDisplay: 'Nuevo Nombre');

      expect(updated.nombreDisplay, 'Nuevo Nombre');
      expect(updated.avatarUrl, 'https://old.jpg');       // sin cambio
      expect(updated.telefono, '0900000000');             // sin cambio
      expect(updated.emailContacto, 'base@empresa.com'); // sin cambio
      expect(updated.zonaHoraria, 'America/Guayaquil');  // sin cambio
    });

    test('preserva usuarioId, empresaId y emailLogin', () {
      final updated = base.copyWith(telefono: '0999111222');

      expect(updated.usuarioId, 'u-001');
      expect(updated.empresaId, 'e-001');
      expect(updated.emailLogin, 'base@test.com');
    });

    test('actualiza múltiples campos a la vez', () {
      final updated = base.copyWith(
        nombreDisplay: 'Nuevo',
        avatarUrl: 'https://new.jpg',
        zonaHoraria: 'America/New_York',
      );

      expect(updated.nombreDisplay, 'Nuevo');
      expect(updated.avatarUrl, 'https://new.jpg');
      expect(updated.zonaHoraria, 'America/New_York');
      expect(updated.telefono, '0900000000'); // sin cambio
    });
  });
}
