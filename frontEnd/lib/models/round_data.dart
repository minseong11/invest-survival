import 'price_data.dart';

class RoundData {
  final int round;
  final String date;
  final List<PriceData> priceData;
  final double? roundAsset;       // 카드 선택 전 = null
  final double? returnRate;       // 카드 선택 전 = null
  final List<int> triggeredCards; // 이 라운드에 발동한 카드 ID 목록 (v3 추가)

  RoundData({
    required this.round,
    required this.date,
    required this.priceData,
    this.roundAsset,
    this.returnRate,
    this.triggeredCards = const [],
  });

  factory RoundData.fromJson(Map<String, dynamic> json) {
    final List<dynamic> priceList     = json['priceData']      ?? [];
    final List<dynamic> triggeredList = json['triggeredCards'] ?? [];
    return RoundData(
      round:          json['round']      ?? 0,
      date:           json['date']       ?? '',
      priceData:      priceList.map((e) => PriceData.fromJson(e)).toList(),
      roundAsset:     json['roundAsset'] != null
          ? (json['roundAsset'] as num).toDouble()
          : null,
      returnRate:     json['returnRate'] != null
          ? (json['returnRate'] as num).toDouble()
          : null,
      triggeredCards: triggeredList.map((e) => e as int).toList(),
    );
  }

  PriceData? getPrice(String ticker) {
    try {
      return priceData.firstWhere((p) => p.ticker == ticker);
    } catch (_) {
      return null;
    }
  }
}