import 'package:flutter_application_1/screens/game_result_screen.dart';
import 'package:flutter_test/flutter_test.dart';

// 결과 첫 장의 한 줄 결론: 시장과 비교한 결론과 등급(카드 조합 전체 안의 위치)이 엇갈리면 함께 말한다
void main() {
  group('수익이 났는데 등급이 낮으면 (C·D)', () {
    test('시장은 떨어졌고 나는 수익 → "수익은 냈지만 더 좋은 조합이 많았어요"', () {
      // 실제 플레이 영상: "시장은 떨어졌지만 수익을 냈어요" 바로 아래 "C등급 · 하위 26.6%"
      expect(resultHeadline(4.2, -8.0, grade: 'C'), '수익은 냈지만\n더 좋은 조합이 많았어요');
      expect(resultHeadline(4.2, -8.0, grade: 'D'), '수익은 냈지만\n더 좋은 조합이 많았어요');
    });
    test('둘 다 손실이지만 시장보다 덜 잃음 → "시장보다 덜 잃었지만 …"', () {
      expect(resultHeadline(-5.0, -12.0, grade: 'C'), '시장보다 덜 잃었지만\n더 좋은 조합이 많았어요');
    });
  });

  group('등급이 B 이상이거나 없으면 시장과 비교한 결론 그대로', () {
    test('시장은 떨어졌고 나는 수익', () {
      expect(resultHeadline(4.2, -8.0, grade: 'B'), '시장은 떨어졌지만\n수익을 냈어요');
      expect(resultHeadline(4.2, -8.0), '시장은 떨어졌지만\n수익을 냈어요');   // 분석 응답 없음
    });
    test('시장보다 더 벌었다·덜 잃었다', () {
      expect(resultHeadline(15.0, 10.0, grade: 'A'), '시장보다 5.0%p\n더 벌었어요');
      expect(resultHeadline(-5.0, -12.0, grade: 'B'), '시장보다 7.0%p\n덜 잃었어요');
    });
  });

  group('시장보다 못했는데 등급이 높으면 (S·A)', () {
    test('좋은 카드 조합이었다고 함께 말한다', () {
      expect(resultHeadline(3.0, 10.0, grade: 'A'), '시장보다는 덜 벌었지만\n좋은 카드 조합이었어요');
      expect(resultHeadline(-15.0, -10.0, grade: 'S'), '시장보다는 더 잃었지만\n좋은 카드 조합이었어요');
    });
  });

  test('시장보다 못하고 등급도 낮으면 차이를 그대로', () {
    expect(resultHeadline(-3.0, 10.0, grade: 'C'), '시장은 올랐지만\n손실을 봤어요');
    expect(resultHeadline(3.0, 10.0, grade: 'D'), '시장보다 7.0%p\n덜 벌었어요');
    expect(resultHeadline(-15.0, -10.0, grade: 'C'), '시장보다 5.0%p\n더 잃었어요');
  });

  test('표시하면 0.0%p인 차이와 S&P500 값이 없을 때', () {
    expect(resultHeadline(-10.02, -10.0, grade: 'C'), '시장과 거의\n같은 결과예요');
    expect(resultHeadline(3.0, null, grade: 'C'), '위기에서 살아남았어요');
    expect(resultHeadline(-3.0, null), '이번엔 손실을 봤어요');
  });
}
