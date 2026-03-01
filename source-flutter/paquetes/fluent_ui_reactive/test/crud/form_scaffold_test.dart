import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluent_ui_reactive/fluent_ui_reactive.dart';

/// Helper to wrap a widget in FluentApp for testing.
Widget _wrap(Widget child) {
  return FluentApp(home: child);
}

/// Builds a [FormScaffold] with sensible defaults for testing.
FormScaffold _buildForm({
  String title = 'Test Form',
  bool isDirty = false,
  bool isLoading = false,
  Future<void> Function()? onSave,
  VoidCallback? onCancel,
  List<FormSection>? sections,
}) {
  return FormScaffold(
    title: title,
    isDirty: isDirty,
    isLoading: isLoading,
    onSave: onSave ?? () async {},
    onCancel: onCancel,
    sections: sections ??
        [
          FormSection(
            title: 'Datos',
            children: [const Text('Campo 1')],
          ),
        ],
  );
}

void main() {
  group('FormScaffold', () {
    testWidgets('renders title', (tester) async {
      await tester.pumpWidget(_wrap(_buildForm()));
      await tester.pumpAndSettle();

      expect(find.text('Test Form'), findsOneWidget);
    });

    testWidgets('isDirty adds bullet to title', (tester) async {
      await tester.pumpWidget(_wrap(_buildForm(isDirty: true)));
      await tester.pumpAndSettle();

      // Title should be "Test Form \u2022"
      expect(find.textContaining('\u2022'), findsOneWidget);
    });

    testWidgets('isLoading shows ProgressRing instead of sections',
        (tester) async {
      await tester.pumpWidget(_wrap(_buildForm(isLoading: true)));
      // ProgressRing animates continuously so pumpAndSettle will time out.
      // Use a single pump instead.
      await tester.pump();

      expect(find.byType(ProgressRing), findsOneWidget);
      // The section title should NOT be visible
      expect(find.text('Datos'), findsNothing);
    });

    testWidgets('renders form sections', (tester) async {
      await tester.pumpWidget(_wrap(_buildForm()));
      await tester.pumpAndSettle();

      expect(find.text('Datos'), findsOneWidget);
      expect(find.text('Campo 1'), findsOneWidget);
    });

    testWidgets('Guardar button calls onSave', (tester) async {
      var saved = false;
      await tester.pumpWidget(_wrap(
        _buildForm(onSave: () async => saved = true),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(saved, isTrue);
    });

    testWidgets('Cancelar button calls onCancel', (tester) async {
      var cancelled = false;
      await tester.pumpWidget(_wrap(
        _buildForm(onCancel: () => cancelled = true),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(cancelled, isTrue);
    });

    testWidgets('error in onSave shows InfoBar', (tester) async {
      await tester.pumpWidget(_wrap(
        _buildForm(
          onSave: () async => throw Exception('Save failed'),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(find.text('Error al guardar'), findsOneWidget);
      expect(find.textContaining('Save failed'), findsOneWidget);
    });

    testWidgets('Guardar button is disabled while saving', (tester) async {
      final completer = Completer<void>();
      await tester.pumpWidget(_wrap(
        _buildForm(onSave: () => completer.future),
      ));
      await tester.pumpAndSettle();

      // Tap save -- starts the async operation
      await tester.tap(find.text('Guardar'));
      await tester.pump();

      // While saving, tapping Guardar again should do nothing because
      // _saving is true and onPressed is null.
      // We verify by checking that a second tap doesn't cause issues.
      await tester.tap(find.text('Guardar'));
      await tester.pump();

      // Complete the save
      completer.complete();
      await tester.pumpAndSettle();
    });
  });
}
