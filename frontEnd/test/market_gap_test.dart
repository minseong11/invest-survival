import 'package:flutter_application_1/screens/game_screen.dart';
import 'package:flutter_test/flutter_test.dart';

// 진행 화면 점수판 문구: 내 수익률 − 같은 기간 S&P500
void main() {
  test('표시하면 0.0%p인 차이는 "시장과 같아요"', () {
    expect(marketGapText(0), '시장과 같아요');          // 1라운드
    expect(marketGapText(0.04), '시장과 같아요');
    expect(marketGapText(-0.04), '시장과 같아요');       // 기존: "시장보다 0.0%p 뒤처져요"
  });

  test('앞서면 앞서요, 뒤지면 뒤처져요 (소수 첫째 자리)', () {
    expect(marketGapText(22.84), '시장보다 22.8%p 앞서요');
    expect(marketGapText(0.06), '시장보다 0.1%p 앞서요');
    expect(marketGapText(-3.1), '시장보다 3.1%p 뒤처져요');
  });
}
