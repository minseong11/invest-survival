// 하루치 종목 주가 데이터
// priceData 배열 안의 항목 하나
class PriceData {
  final String ticker;
  final double open;
  final double close;
  final double high;
  final double low;
  final double changeRate;

  PriceData({
    required this.ticker,
    required this.open,
    required this.close,
    required this.high,
    required this.low,
    required this.changeRate,
  });

  factory PriceData.fromJson(Map<String, dynamic> json) {
    return PriceData(
      ticker: json['ticker'] ?? '',
      open: (json['open'] ?? 0.0).toDouble(),
      close: (json['close'] ?? 0.0).toDouble(),
      high: (json['high'] ?? 0.0).toDouble(),
      low: (json['low'] ?? 0.0).toDouble(),
      changeRate: (json['changeRate'] ?? 0.0).toDouble(),
    );
  }

  // 양봉(상승)인지 음봉(하락)인지
  bool get isPositive => close >= open;
}
