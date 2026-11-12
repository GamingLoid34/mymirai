import 'package:flutter_test/flutter_test.dart';

import 'package:my_mirai/app.dart';
import 'package:my_mirai/config.dart';
import 'package:my_mirai/data/dev_homework_repository.dart';
import 'package:my_mirai/services/auth_service.dart';

void main() {
  testWidgets('App starts on Hem tab', (WidgetTester tester) async {
    await tester.pumpWidget(
      MyMiraiApp(
        homeworkRepository: DevHomeworkRepository(),
        authService: AuthService.testSignedIn(
          uid: kDevAssignedToUserId,
          familyId: kDevFamilyId,
        ),
      ),
    );

    expect(find.text('My Mirai'), findsOneWidget);
    expect(find.text('Hem'), findsOneWidget);
  });
}
