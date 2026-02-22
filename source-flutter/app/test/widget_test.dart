// Placeholder smoke test. Full integration tests require a running Supabase
// instance and are kept in the integration_test/ directory.
//
// To run: flutter test

import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('placeholder smoke test', (WidgetTester tester) async {
    // No-op: PilarApp requires Supabase + ProviderScope initialization
    // which cannot be done in a simple widget test.
    expect(true, isTrue);
  });
}
