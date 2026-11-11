import 'holding.dart';
import 'price_data.dart';

class RoundData {
  final int round;
  final String date;
  final List<PriceData> priceData;
  final double? roundAsset;       // 카드 선택 전 = null
  final double? returnRate;       // 카드 선택 전 = null
  final List<int> triggeredCards; // 이 라운드에 발동한 카드 ID 목록 (v3 추가)

  // (11주차) 보유 자산 — 서버가 아직 안 보내면 빈 목록 / null (화면에서 해당 칸 생략)
  final List<Holding> holdings;   // 종목별 수익률·비중
  final double? cash;             // 현금(원)
  final double? cashWeight;       // 총자산 중 현금 비중(%)

  RoundData({
    required this.round,
    required this.date,
    required this.priceData,
    this.roundAsset,
    this.returnRate,
    this.triggeredCards = const [],
    this.holdings = const [],
    this.cash,
    this.cashWeight,
  });

  factory RoundData.fromJson(Map<String, dynamic> json) {
    final List<dynamic> priceList     = json['priceData']      ?? [];
    final List<dynamic> triggeredList = json['triggeredCards'] ?? [];
    final List<dynamic> holdingList   = json['holdings']       ?? [];
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
      holdings:       holdingList
          .map((e) => Holding.fromJson(e as Map<String, dynamic>))
          .toList(),
      cash:           json['cash'] != null
          ? (json['cash'] as num).toDouble()
          : null,
      cashWeight:     json['cashWeight'] != null
          ? (json['cashWeight'] as num).toDouble()
          : null,
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