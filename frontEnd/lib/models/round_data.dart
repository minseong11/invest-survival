import 'holding.dart';
import 'news_item.dart';
import 'price_data.dart';

// (#125) 발동 조건은 맞았지만 실행되지 못한 카드 (서버 rounds[].skippedCards)
//   reason: CASH_LOW(현금 부족) / MAX_REACHED(최대 횟수 소진) / NO_HOLDINGS(팔 주식 없음) / NO_PRICE(가격 없음)
class SkippedCard {
  final int cardId;
  final String reason;

  const SkippedCard({required this.cardId, required this.reason});

  static const cashLow    = 'CASH_LOW';
  static const maxReached = 'MAX_REACHED';
  static const noHoldings = 'NO_HOLDINGS';
  static const noPrice    = 'NO_PRICE';

  // 화면에 보여줄 짧은 이유
  static String label(String reason) => switch (reason) {
        cashLow    => '현금 부족',
        maxReached => '횟수 소진',
        noHoldings => '팔 주식 없음',
        noPrice    => '가격 없음',
        _          => '건너뜀',
      };

  static List<SkippedCard> listFromJson(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => SkippedCard(
              cardId: (e['cardId'] as num?)?.toInt() ?? 0,
              reason: (e['reason'] as String?) ?? '',
            ))
        .toList();
  }
}

class RoundData {
  final int round;
  final String date;
  final List<PriceData> priceData;
  final double? roundAsset;       // 카드 선택 전 = null
  final double? returnRate;       // 카드 선택 전 = null
  final List<int> triggeredCards; // 이 라운드에 발동한 카드 ID 목록 (v3 추가)
  final List<SkippedCard> skippedCards; // (#125) 조건은 맞았지만 실행되지 못한 카드

  // (11주차) 보유 자산 — 서버가 아직 안 보내면 빈 목록 / null (화면에서 해당 칸 생략)
  final List<Holding> holdings;   // 종목별 수익률·비중
  final double? cash;             // 현금(원)
  final double? cashWeight;       // 총자산 중 현금 비중(%)
  final List<NewsItem> news;      // (11주차) 이 라운드 날짜의 뉴스

  RoundData({
    required this.round,
    required this.date,
    required this.priceData,
    this.roundAsset,
    this.returnRate,
    this.triggeredCards = const [],
    this.skippedCards = const [],
    this.holdings = const [],
    this.cash,
    this.cashWeight,
    this.news = const [],
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
      skippedCards:   SkippedCard.listFromJson(json['skippedCards']),
      holdings:       holdingList
          .map((e) => Holding.fromJson(e as Map<String, dynamic>))
          .toList(),
      cash:           json['cash'] != null
          ? (json['cash'] as num).toDouble()
          : null,
      cashWeight:     json['cashWeight'] != null
          ? (json['cashWeight'] as num).toDouble()
          : null,
      news:           NewsItem.listFromJson(json['news']),
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