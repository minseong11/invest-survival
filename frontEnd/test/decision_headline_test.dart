import 'package:flutter/material.dart';
import 'package:flutter_application_1/widgets/decision_selector.dart';
import 'package:flutter_test/flutter_test.dart';

// 위기 대응 장면의 속보 제목 — 마지막 글자만 다음 줄로 넘어가지 않게
//  (기존: 21px 고정이라 넓은 화면에서도 "…서킷브레이커 발 / 동"처럼 보였다)
const _headline = '사우디·러시아 유가 전쟁, 미 증시 서킷브레이커 발동';
const _style = TextStyle(fontSize: 21, fontWeight: FontWeight.w800, height: 1.4);

double _fullWidth(double fontSize) {
  final tp = TextPainter(
    text: TextSpan(text: _headline, style: _style.copyWith(fontSize: fontSize)),
    textDirection: TextDirection.ltr,
  )..layout();
  final w = tp.width;
  tp.dispose();
  return w;
}

Future<Text> _pump(WidgetTester tester, double width) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          child: const FitHeadline(text: _headline, style: _style),
        ),
      ),
    ),
  ));
  return tester.widget<Text>(
      find.descendant(of: find.byType(FitHeadline), matching: find.byType(Text)));
}

void main() {
  testWidgets('넉넉하면 원래 크기(21px) 그대로 한 줄', (tester) async {
    final text = await _pump(tester, _fullWidth(21) + 20);
    expect(text.data, _headline);
    expect(text.maxLines, 1);
    expect(text.style!.fontSize, 21);
  });

  testWidgets('조금 모자라면 글자를 살짝 줄여 한 줄로', (tester) async {
    final text = await _pump(tester, _fullWidth(21) * 0.93);
    expect(text.data, _headline);
    expect(text.maxLines, 1);
    expect(text.style!.fontSize, lessThan(21));
    expect(text.style!.fontSize, greaterThanOrEqualTo(17));
  });

  testWidgets('좁은 화면에서는 더 줄이지 않고 쉼표 뒤에서 두 줄로 고르게', (tester) async {
    final text = await _pump(tester, _fullWidth(21) * 0.56);
    expect(text.data, '사우디·러시아 유가 전쟁,\n미 증시 서킷브레이커 발동');
    expect(text.style!.fontSize, 21);
  });
}
