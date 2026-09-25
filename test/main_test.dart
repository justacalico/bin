import 'package:bin/main.dart' as app;
import 'package:bin/ui/home_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('app boots to home page', (tester) async {
    app.main();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(HomePage), findsOneWidget);
  });
}
