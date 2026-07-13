// Widget tests for BizaroHQ Stereo.
import 'package:flutter_test/flutter_test.dart';

import 'package:car_stereo_launcher/main.dart';

void main() {
  testWidgets('Car Launcher loads correctly', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    expect(find.text('SPEED'), findsOneWidget);
    expect(find.text('MEDIA'), findsOneWidget);
  });
}