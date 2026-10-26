import 'package:finals_notes/ui/settings_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('шторка настроек собирается и показывает выбор движка', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: SettingsSheet(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Настройки'), findsOneWidget);
    expect(find.text('Движок перевода'), findsOneWidget);
    expect(find.text('DeepL'), findsOneWidget);
    expect(find.text('Google'), findsOneWidget);
    // Ключ вшит в сборку, поэтому по умолчанию выбран DeepL и поле ключа видно.
    expect(find.text('Ключ DeepL API'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('переключение на Google прячет поле ключа', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: SettingsSheet(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Google'));
    await tester.pumpAndSettle();

    expect(find.text('Ключ DeepL API'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
