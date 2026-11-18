import 'round_data.dart';

// =============================================
// (#125) 게임에 나오는 종목 — 서버 GameService의 TICKERS·TICKER_NAMES와 같은 순서·이름
// 서버는 라운드마다 그날 가격이 있는 모든 종목을 보낸다 (상장 전 종목은 빠진다).
// 기존에는 S&P500과 보유 중인 종목만 보내서, 갖고 있지 않은 종목은 흐름을 보고 고를 수 없었다.
// =============================================
const List<String> kMarketTickers = ['^SPX', '^NDX', 'XAUUSD', 'USO', 'AAPL', 'TLT'];

const Map<String, String> kTickerNames = {
  '^SPX': 'S&P500',
  '^NDX': '나스닥100',
  'XAUUSD': '금',
  'USO': '원유',
  'AAPL': '애플',
  'TLT': '미국 장기채',
};

/// 카드 정의(card_info.dart)는 금을 'GLD'로 부르고, 서버 가격은 'XAUUSD'로 온다
String priceTicker(String ticker) => ticker == 'GLD' ? 'XAUUSD' : ticker;

String tickerName(String ticker) =>
    kTickerNames[priceTicker(ticker)] ?? ticker.replaceAll('^', '');

/// rounds에서 그 종목의 (라운드 위치, 첫 가격 대비 등락률 %) 목록. 가격이 없는 라운드는 건너뛴다
List<(int, double)> changeSeries(List<RoundData> rounds, String ticker) {
  final t = priceTicker(ticker);
  double? base;
  final out = <(int, double)>[];
  for (int i = 0; i < rounds.length; i++) {
    final p = rounds[i].getPrice(t);
    if (p == null || p.close <= 0) continue;
    base ??= p.close;
    out.add((i, (p.close - base) / base * 100));
  }
  return out;
}

/// rounds의 첫 가격 대비 마지막 가격의 등락률(%) — 게임 시작 후 얼마나 움직였는지. 가격이 없으면 null
double? changeSinceStart(List<RoundData> rounds, String ticker) {
  final series = changeSeries(rounds, ticker);
  return series.isEmpty ? null : series.last.$2;
}
