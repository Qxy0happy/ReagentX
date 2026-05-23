import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:reagent_x/app.dart';

void main() {
  testWidgets('App renders without error', (WidgetTester tester) async {
    await tester.pumpWidget(const ReagentXApp());
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
