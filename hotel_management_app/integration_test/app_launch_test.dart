import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../lib/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Miftah launches on Android', (tester) async {
    await app.main();
    await tester.pumpAndSettle(const Duration(seconds: 10));
    expect(find.text('اسم المستخدم'), findsOneWidget);
    expect(find.text('تسجيل الدخول'), findsOneWidget);
  });
}

