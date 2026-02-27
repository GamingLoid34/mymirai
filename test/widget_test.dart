import 'package:flutter_test/flutter_test.dart';
import 'package:my_mirai/main.dart';

void main() {
  testWidgets('login page renders app title', (WidgetTester tester) async {
    await tester.pumpWidget(const MyMiraiApp());

    expect(find.text('My Mirai'), findsOneWidget);
    expect(find.text('Logga in'), findsOneWidget);
  });
}
