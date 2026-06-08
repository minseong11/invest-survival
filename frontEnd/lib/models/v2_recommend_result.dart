class CardRanking {
  final int rank;
  final int cardId;
  final String cardName;
  final double contribution;

  CardRanking({
    required this.rank,
    required this.cardId,
    required this.cardName,
    required this.contribution,
  });

  factory CardRanking.fromJson(Map<String, dynamic> json) {
    return CardRanking(
      rank:         json['rank'] as int,
      cardId:       json['cardId'] as int,
      cardName:     json['cardName'] as String,
      contribution: (json['contribution'] as num).toDouble(),
    );
  }
}

class V2RecommendResult {
  final int recommendedCardId;
  final String recommendedCardName;
  final List<CardRanking> rankings;

  V2RecommendResult({
    required this.recommendedCardId,
    required this.recommendedCardName,
    required this.rankings,
  });

  factory V2RecommendResult.fromJson(Map<String, dynamic> json) {
    final list = json['rankings'] as List<dynamic>;
    return V2RecommendResult(
      recommendedCardId:   json['recommendedCardId'] as int,
      recommendedCardName: json['recommendedCardName'] as String,
      rankings: list
          .map((e) => CardRanking.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  // 특정 카드의 기여도 반환
  double? contributionFor(int cardId) {
    try {
      return rankings.firstWhere((r) => r.cardId == cardId).contribution;
    } catch (_) {
      return null;
    }
  }
}