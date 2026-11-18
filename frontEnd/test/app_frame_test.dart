import 'package:flutter/material.dart';
import 'package:flutter_application_1/widgets/app_frame.dart';
import 'package:flutter_test/flutter_test.dart';

// (#125) 넓은 화면(노트북 브라우저)에서는 휴대폰 폭으로 가운데에 보여준다
Future<void> _pump(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    builder: (context, child) => AppFrame(child: child!),
    home: Scaffold(
      body: Builder(builder: (context) => Text('폭 ${MediaQuery.of(context).size.width.toInt()}')),
    ),
  ));
}

void main() {
  testWidgets('넓은 화면에서는 가운데에 휴대폰 폭으로', (tester) async {
    await _pump(tester, 1280);
    expect(tester.getSize(find.byType(Scaffold)).width, kMaxAppWidth);
    expect(tester.getCenter(find.byType(Scaffold)).dx, 640);
    expect(find.text('폭 ${kMaxAppWidth.toInt()}'), findsOneWidget);   // 안쪽 화면도 줄어든 폭을 안다
  });

  testWidgets('휴대폰 폭에서는 그대로', (tester) async {
    await _pump(tester, 412);
    expect(tester.getSize(find.byType(Scaffold)).width, 412);
    expect(find.text('폭 412'), findsOneWidget);
  });
}
