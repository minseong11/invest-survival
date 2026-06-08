class RoundRecommendation {
  final int round;
  final int cardId;
  final String cardName;
  final double predictedReturn;

  RoundRecommendation({
    required this.round,
    required this.cardId,
    required this.cardName,
    required this.predictedReturn,
  });

  factory RoundRecommendation.fromJson(Map<String, dynamic> json) {
    return RoundRecommendation(
      round:           json['round'] as int,
      cardId:          json['cardId'] as int,
      cardName:        json['cardName'] as String,
      predictedReturn: (json['predictedReturn'] as num).toDouble(),
    );
  }
}

class V1RecommendResult {
  final List<RoundRecommendation> recommendations;

  V1RecommendResult({required this.recommendations});

  factory V1RecommendResult.fromJson(Map<String, dynamic> json) {
    final list = json['recommendations'] as List<dynamic>;
    return V1RecommendResult(
      recommendations: list
          .map((e) => RoundRecommendation.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  // 특정 라운드의 추천 카드 ID 반환
  int? cardIdForRound(int round) {
    try {
      return recommendations.firstWhere((r) => r.round == round).cardId;
    } catch (_) {
      return null;
    }
  }
}