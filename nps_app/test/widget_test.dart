import 'package:flutter_test/flutter_test.dart';
import 'package:nps_app/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const NpsApp());
    expect(find.text('NPS File Processor'), findsOneWidget);
  });
}
