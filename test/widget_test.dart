import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pandamj_admin/main.dart';

void main() {
  test('repairs stale saved credentials and selects the new backend', () async {
    SharedPreferences.setMockInitialValues({
      'admin_username': 'stale-user',
      'admin_password': 'stale-password',
      'backend_index': 0,
    });

    final saved = await LoginStore.load();

    expect(saved.backendIndex, 1);
  });

  testWidgets('shows the remembered-login TOTP screen', (tester) async {
    SharedPreferences.setMockInitialValues({
      'admin_username': 'saved-user',
      'admin_password': 'saved-password',
      'backend_index': 0,
      'credential_revision': 1,
    });

    await tester.pumpWidget(const PandaAdminApp(autoLogin: false));
    await tester.pumpAndSettle();

    expect(find.text('熊猫麻将后台'), findsOneWidget);
    expect(find.text('账号和密码已记住，只需输入谷歌验证码'), findsOneWidget);
    expect(find.text('谷歌验证码'), findsOneWidget);
    expect(find.text('老后台'), findsOneWidget);
    expect(find.text('新后台'), findsOneWidget);
  });
}
