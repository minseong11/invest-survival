import 'package:flutter_application_1/models/market.dart';
import 'package:flutter_application_1/models/round_data.dart';
import 'package:flutter_test/flutter_test.dart';

// (#125) 종목별 흐름 계산 — 차트 아래 종목 칩·카드 선택지에 쓰는 값
RoundData _round(int i, Map<String, double> closes) => RoundData.fromJson({
      'round': i + 1,
      'date': '2008-09-${(i + 1).toString().padLeft(2, '0')}',
      'priceData': [
        for (final e in closes.entries)
          {'ticker': e.key, 'open': e.value, 'close': e.value, 'high': e.value, 'low': e.value, 'changeRate': 0.0}
      ],
    });

void main() {
  test('게임 시작 후 등락 = 첫 가격 대비 마지막 가격', () {
    final rounds = [
      _round(0, {'^SPX': 1000, 'XAUUSD': 800}),
      _round(1, {'^SPX': 950, 'XAUUSD': 820}),
      _round(2, {'^SPX': 900, 'XAUUSD': 840}),
    ];
    expect(changeSinceStart(rounds, '^SPX'), closeTo(-10.0, 1e-9));
    expect(changeSinceStart(rounds, 'XAUUSD'), closeTo(5.0, 1e-9));
  });

  test('금 카드는 GLD로 정의돼 있지만 서버 가격(XAUUSD)으로 찾는다', () {
    final rounds = [
      _round(0, {'XAUUSD': 800}),
      _round(1, {'XAUUSD': 880}),
    ];
    expect(priceTicker('GLD'), 'XAUUSD');
    expect(changeSinceStart(rounds, 'GLD'), closeTo(10.0, 1e-9));
    expect(tickerName('GLD'), '금');
    expect(tickerName('^NDX'), '나스닥100');
  });

  test('가격이 없는 라운드(상장 전)는 건너뛰고, 처음 가격이 있는 라운드가 기준', () {
    final rounds = [
      _round(0, {'^SPX': 1000}),
      _round(1, {'^SPX': 1000, 'USO': 50}),
      _round(2, {'^SPX': 1000, 'USO': 40}),
    ];
    expect(changeSeries(rounds, 'USO'), [(1, 0.0), (2, -20.0)]);
    expect(changeSinceStart(rounds, 'TLT'), isNull);   // 가격이 한 번도 없는 종목
  });
}
