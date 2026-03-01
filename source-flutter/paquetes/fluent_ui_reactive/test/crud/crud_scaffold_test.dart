import 'dart:async';
import 'dart:ui';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluent_ui_reactive/fluent_ui_reactive.dart';

/// Helper to wrap a widget in FluentApp for testing.
Widget _wrap(Widget child) {
  return ProviderScope(
    child: FluentApp(home: child),
  );
}

/// Sample items used across tests.
final _items = [
  {'id': '1', 'name': 'Alice'},
  {'id': '2', 'name': 'Bob'},
  {'id': '3', 'name': 'Charlie'},
];

/// Builds a [CrudScaffold] with sensible defaults for testing.
CrudScaffold<Map<String, dynamic>> _buildScaffold({
  AsyncValue<List<Map<String, dynamic>>>? value,
  VoidCallback? onNew,
  void Function(Map<String, dynamic>)? onRowTap,
  Future<void> Function(Map<String, dynamic>)? onDelete,
  bool showSearch = false,
  Widget? emptyWidget,
}) {
  return CrudScaffold<Map<String, dynamic>>(
    title: 'Test Title',
    value: value ?? const AsyncData([]),
    columns: [
      PilarColumn(field: 'name', label: 'Nombre'),
    ],
    rowToMap: (item) => {'name': item['name']},
    onNew: onNew,
    onRowTap: onRowTap,
    onDelete: onDelete,
    showSearch: showSearch,
    searchFields: showSearch ? (item) => [item['name'] as String] : null,
    emptyWidget: emptyWidget,
  );
}

void main() {
  group('CrudScaffold', () {
    testWidgets('renders title', (tester) async {
      await tester.pumpWidget(_wrap(_buildScaffold()));
      await tester.pumpAndSettle();

      expect(find.text('Test Title'), findsOneWidget);
    });

    testWidgets('shows items', (tester) async {
      await tester.pumpWidget(_wrap(
        _buildScaffold(value: AsyncData(List.of(_items))),
      ));
      await tester.pumpAndSettle();

      // Items show somewhere in the widget tree (grid or list)
      expect(find.text('Alice'), findsWidgets);
      expect(find.text('Bob'), findsWidgets);
    });

    testWidgets('shows ProgressRing when loading', (tester) async {
      await tester.pumpWidget(_wrap(
        _buildScaffold(value: const AsyncLoading()),
      ));
      // ProgressRing animates, so just pump once
      await tester.pump();

      expect(find.byType(ProgressRing), findsOneWidget);
    });

    testWidgets('shows error text when AsyncError', (tester) async {
      await tester.pumpWidget(_wrap(
        _buildScaffold(
          value: AsyncError('Something went wrong', StackTrace.empty),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('Something went wrong'), findsOneWidget);
    });

    testWidgets('shows empty state when list is empty', (tester) async {
      await tester.pumpWidget(_wrap(
        _buildScaffold(value: const AsyncData([])),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Sin registros'), findsOneWidget);
    });

    testWidgets('shows custom empty widget', (tester) async {
      await tester.pumpWidget(_wrap(
        _buildScaffold(
          value: const AsyncData([]),
          emptyWidget: const Text('Custom empty'),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Custom empty'), findsOneWidget);
    });

    testWidgets('Nuevo button calls onNew', (tester) async {
      var called = false;
      await tester.pumpWidget(_wrap(
        _buildScaffold(onNew: () => called = true),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Nuevo'));
      await tester.pumpAndSettle();

      expect(called, isTrue);
    });

    testWidgets('search filters items', (tester) async {
      await tester.pumpWidget(_wrap(
        _buildScaffold(
          value: AsyncData(List.of(_items)),
          showSearch: true,
        ),
      ));
      await tester.pumpAndSettle();

      // All three items visible
      expect(find.text('Alice'), findsWidgets);
      expect(find.text('Charlie'), findsWidgets);

      // Type in search box
      final searchBox = find.byType(TextBox);
      expect(searchBox, findsOneWidget);
      await tester.enterText(searchBox, 'ali');
      await tester.pumpAndSettle();

      // Only Alice matches
      expect(find.text('Alice'), findsWidgets);
      expect(find.text('Bob'), findsNothing);
      expect(find.text('Charlie'), findsNothing);
    });

    testWidgets('delete confirmation dialog calls onDelete when confirmed',
        (tester) async {
      // Use a wider surface so CommandBar items fit on screen
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final deleted = <String>[];
      await tester.pumpWidget(_wrap(
        _buildScaffold(
          value: AsyncData(List.of(_items)),
          onRowTap: (_) {},
          onDelete: (item) async => deleted.add(item['name'] as String),
        ),
      ));
      await tester.pumpAndSettle();

      // Tap on first item to select it
      await tester.tap(find.text('Alice').first);
      await tester.pumpAndSettle();

      // Tap Eliminar in the CommandBar
      await tester.tap(find.text('Eliminar').first);
      await tester.pumpAndSettle();

      // ContentDialog should be visible
      expect(find.byType(ContentDialog), findsOneWidget);

      // Find the "Eliminar" button inside the ContentDialog
      final dialogEliminar = find.descendant(
        of: find.byType(ContentDialog),
        matching: find.text('Eliminar'),
      );
      expect(dialogEliminar, findsOneWidget);
      await tester.tap(dialogEliminar);
      await tester.pumpAndSettle();

      expect(deleted, ['Alice']);
    });

    testWidgets('cancel delete does NOT call onDelete', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      var deleteCalled = false;
      await tester.pumpWidget(_wrap(
        _buildScaffold(
          value: AsyncData(List.of(_items)),
          onRowTap: (_) {},
          onDelete: (item) async => deleteCalled = true,
        ),
      ));
      await tester.pumpAndSettle();

      // Select item
      await tester.tap(find.text('Alice').first);
      await tester.pumpAndSettle();

      // Tap Eliminar in the CommandBar
      await tester.tap(find.text('Eliminar').first);
      await tester.pumpAndSettle();

      // Cancel via the dialog button
      final dialogCancelar = find.descendant(
        of: find.byType(ContentDialog),
        matching: find.text('Cancelar'),
      );
      expect(dialogCancelar, findsOneWidget);
      await tester.tap(dialogCancelar);
      await tester.pumpAndSettle();

      expect(deleteCalled, isFalse);
    });
  });
}
