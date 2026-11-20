import 'dart:math';

import 'package:flutter_application_1/widgets/scene/scene_widgets.dart';
import 'package:flutter_test/flutter_test.dart';

// 흰 구름 그림(☁️)이 날씨 배경에 묻히지 않는지 (흰색과의 명암 대비)
//  기존 흐림 배경은 거의 흰 회색이라, 하루 등락이 ±0.5% 미만인 날의 구름이 거의 보이지 않았다
double _contrastWithWhite(MarketMood mood) {
  final darkest = mood.sky.map((c) => c.computeLuminance()).reduce(min);
  return (1.0 + 0.05) / (darkest + 0.05);
}

void main() {
  test('흐린 날 배경은 흰 구름이 보일 만큼 진하다', () {
    for (final change in [0.0, 0.3, -0.4]) {
      final mood = MarketMood.day(change);
      expect(mood.label, '흐림');
      expect(_contrastWithWhite(mood), greaterThanOrEqualTo(2.0), reason: '$change');
    }
    expect(_contrastWithWhite(MarketMood.period(0.5)), greaterThanOrEqualTo(2.0));
  });

  test('비 오는 날 배경도 구름이 묻히지 않는다', () {
    final mood = MarketMood.day(-1.0);
    expect(mood.label, '비');
    expect(_contrastWithWhite(mood), greaterThanOrEqualTo(1.5));
  });
}
