import 'package:flutter_application_1/widgets/stock_chart.dart';
import 'package:flutter_application_1/widgets/toss/toss_widgets.dart';
import 'package:flutter_test/flutter_test.dart';

// 숫자 표기·차트 축 계산 (#125에서 고친 화면 버그가 다시 생기지 않게)
void main() {
  group('formatSigned', () {
    test('손실에도 부호가 붙는다 (기존: "(20.95%)"로 표시되던 문제)', () {
      expect(formatSigned(-20.95, digits: 2), '-20.95%');
      expect(formatSigned(20.95, digits: 2), '+20.95%');
    });

    test('0으로 반올림되는 값에는 부호를 붙이지 않는다', () {
      expect(formatSigned(0), '0.0%');
      expect(formatSigned(-0.04), '0.0%');
      expect(formatSigned(0.04), '0.0%');
    });

    test('단위를 바꿀 수 있다', () {
      expect(formatSigned(1.44, unit: '%p'), '+1.4%p');
      expect(formatSigned(-0.25, unit: '%p'), '-0.3%p');
    });
  });

  group('formatShortWon', () {
    test('만원 단위로 줄인다', () {
      expect(formatShortWon(3000000), '300만원');
      expect(formatShortWon(12345678), '1,234만원');
      expect(formatShortWon(83332), '8만원');
    });

    test('만원 미만은 원 단위 그대로', () {
      expect(formatShortWon(8332), '8,332원');
    });
  });

  group('formatRankPosition', () {
    test('절반보다 위는 상위, 아래는 하위 (기존: 하위권도 "상위 87.9%")', () {
      expect(formatRankPosition(17.7), '상위 17.7%');
      expect(formatRankPosition(50.0), '상위 50.0%');
      expect(formatRankPosition(87.9), '하위 12.1%');
    });

    test('양 끝은 "0.1% 이내"', () {
      expect(formatRankPosition(0.05), '상위 0.1% 이내');
      expect(formatRankPosition(99.96), '하위 0.1% 이내');
    });
  });

  // 같은 값이 앱의 숫자(수익률 막대 "-13.3%")와 AI 서버가 쓴 글(AI 코치 "13.3% 줄었어요")에 함께 나온다.
  // AI 서버(Python)는 display_format.fixed()로 아래와 같은 글자를 만든다
  //   — 같은 표: backend/python_simulation/tests/test_display_format.py (한쪽을 바꾸면 다른 쪽도 같이)
  test('소수 자리 반올림 — AI 서버 글과 같은 반올림', () {
    const cases = <(double, int, String)>[
      (13.25, 1, '13.3'),    // 정확히 절반 → 0에서 먼 쪽
      (-13.25, 1, '-13.3'),
      (0.25, 1, '0.3'),
      (13.75, 1, '13.8'),
      (2.5, 0, '3'),
      (0.125, 2, '0.13'),
      (13.35, 1, '13.3'),    // 실제 값이 13.3499… → 내림
      (21.65, 1, '21.6'),
      (0.05, 1, '0.1'),      // 실제 값이 0.05000…0277 → 올림
      (99.95, 1, '100.0'),
      (-34.9, 1, '-34.9'),
      (10.0, 1, '10.0'),
      (0.0, 1, '0.0'),
      (1.005, 2, '1.00'),
      (8.345, 2, '8.35'),
    ];
    for (final (value, digits, expected) in cases) {
      expect(value.toStringAsFixed(digits), expected, reason: '$value');
    }
  });

  test('formatWon: 천 단위 쉼표', () {
    expect(formatWon(10000000), '10,000,000');
    expect(formatWon(-2616153), '-2,616,153');
  });

  group('computeChartAxis', () {
    // 눈금이 일정한 간격으로 놓이려면 위아래 끝이 간격의 배수여야 한다
    void expectAligned(double min, double max) {
      final axis = computeChartAxis(min, max);
      expect(axis.min % axis.interval, 0, reason: '아래 끝 ${axis.min}, 간격 ${axis.interval}');
      expect(axis.max % axis.interval, 0, reason: '위 끝 ${axis.max}, 간격 ${axis.interval}');
      expect(axis.min, lessThanOrEqualTo(min));
      expect(axis.max, greaterThanOrEqualTo(max));
      expect(axis.min, lessThanOrEqualTo(0));
      expect(axis.max, greaterThanOrEqualTo(0));
      final ticks = (axis.max - axis.min) / axis.interval;
      expect(ticks, lessThanOrEqualTo(6), reason: '눈금 $ticks칸');
      expect(ticks, greaterThanOrEqualTo(2), reason: '눈금 $ticks칸');
    }

    test('여러 범위에서 끝이 간격의 배수', () {
      expectAligned(-12.9, 0.4);     // 기존에 -18%·-15% 라벨이 겹치던 범위
      expectAligned(-41.1, 2.0);
      expectAligned(-0.3, 0.2);
      expectAligned(-6.8, 35.0);
      expectAligned(0, 0);
      expectAligned(-95, 180);
    });

    test('손실만 있어도 0%가 축에 들어간다', () {
      final axis = computeChartAxis(-30, -5);
      expect(axis.max, greaterThanOrEqualTo(0));
    });
  });
}
