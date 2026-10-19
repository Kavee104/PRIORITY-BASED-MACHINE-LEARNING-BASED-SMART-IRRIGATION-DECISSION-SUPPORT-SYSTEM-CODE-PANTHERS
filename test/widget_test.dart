// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:smart_irrigation/app_localization.dart';
import 'package:smart_irrigation/main.dart';
import 'package:smart_irrigation/priority_schedule_screen.dart';

void main() {
  testWidgets('App launch smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const SmartIrrigationApp());

    // Verify that login title is rendered
    expect(find.text('Smart Irrigation'), findsWidgets);
  });

  testWidgets('User can switch the login screen to Sinhala', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    AppLocaleController.instance.locale.value = const Locale('en');
    addTearDown(() {
      AppLocaleController.instance.locale.value = const Locale('en');
    });

    await tester.pumpWidget(const SmartIrrigationApp());
    await tester.tap(find.byIcon(Icons.language_rounded).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('සිංහල'));
    await tester.pumpAndSettle();

    expect(find.text('සාදරයෙන් පිළිගනිමු'), findsOneWidget);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('app_language'), 'si');
  });

  testWidgets('Priority schedule fits a 400px mobile viewport', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(400, 642);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: PriorityScheduleScreen()));
    await tester.pump(const Duration(seconds: 4));

    expect(find.text('Priority Schedule'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
