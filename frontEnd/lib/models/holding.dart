// =============================================
// 보유 자산 (11주차, 서버 rounds[].holdings)
// 서버가 라운드마다 종목별로 보내는 값. 수량이 0인 종목은 오지 않는다.
// 같은 종목을 사는 카드가 여러 장이어도(예: 황금 적립·금 피난처 → 금) 종목 하나로 합쳐진다.
//
// {
//   "ticker": "^SPX", "name": "S&P500", "shares": 1.23, "avgPrice": 1250.3,
//   "currentPrice": 1180.2, "costAmount": 1540000, "value": 1453000,
//   "returnRate": -5.65,   // 평균 매수가 대비 누적 수익률(%)
//   "weight": 14.5         // 총자산 중 비중(%)
// }
// =============================================
class Holding {
  final String ticker;
  final String name;
  final double shares;
  final double avgPrice;
  final double currentPrice;
  final double costAmount;
  final double value;
  final double returnRate;
  final double weight;

  const Holding({
    required this.ticker,
    required this.name,
    this.shares = 0,
    this.avgPrice = 0,
    this.currentPrice = 0,
    this.costAmount = 0,
    this.value = 0,
    this.returnRate = 0,
    this.weight = 0,
  });

  static double _d(dynamic v) => v == null ? 0 : (v as num).toDouble();

  factory Holding.fromJson(Map<String, dynamic> json) {
    final ticker = (json['ticker'] ?? '') as String;
    return Holding(
      ticker:       ticker,
      name:         (json['name'] as String?) ?? ticker.replaceAll('^', ''),
      shares:       _d(json['shares']),
      avgPrice:     _d(json['avgPrice']),
      currentPrice: _d(json['currentPrice']),
      costAmount:   _d(json['costAmount']),
      value:        _d(json['value']),
      returnRate:   _d(json['returnRate']),
      weight:       _d(json['weight']),
    );
  }
}
