import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foxlingo/main.dart';
import 'package:foxlingo/pages/home_page.dart';
import 'package:foxlingo/utils/app_settings.dart';
import 'package:foxlingo/utils/translation_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('loads the home page', (tester) async {
    final settings = AppSettings();
    final translationSettings = TranslationSettings();
    await tester.pumpWidget(
      FoxLingoApp(settings: settings, translationSettings: translationSettings),
    );
    await tester.pump();

    expect(find.byType(HomePage), findsOneWidget);
  });
}
