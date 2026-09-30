// 게임 종료 후 사후 분석 (백테스팅) — POST /game/result/analysis
// API 명세서 v6.1 기준
//
// 7,920개 카드 조합(11장 중 4장 순열)을 이 시나리오에서 실제로 돌려본 결과.
// 최종 자산이 같은 조합은 같은 순위 (1, 1, 1, 4 ...)

// 조합 안의 카드 한 장 (라운드별)
class AnalysisCard {
  final int round;
  final int cardId;
  final String cardName;

  AnalysisCard({
    required this.round,
    required this.cardId,
    required this.cardName,
  });

  factory AnalysisCard.fromJson(Map<String, dynamic> json) {
    return AnalysisCard(
      round:    (json['round'] as num).toInt(),
      cardId:   (json['cardId'] as num).toInt(),
      cardName: (json['cardName'] as String?) ?? '',
    );
  }
}

// 상위 조합 1개
class ComboResult {
  final int rank;
  final List<AnalysisCard> cards; // 라운드 1·25·50·75 순서
  final double finalAsset;
  final double finalReturnRate;

  ComboResult({
    required this.rank,
    required this.cards,
    required this.finalAsset,
    required this.finalReturnRate,
  });

  factory ComboResult.fromJson(Map<String, dynamic> json) {
    final list = (json['cards'] as List<dynamic>?) ?? [];
    return ComboResult(
      rank:            (json['rank'] as num).toInt(),
      cards:           list
          .map((e) => AnalysisCard.fromJson(e as Map<String, dynamic>))
          .toList(),
      finalAsset:      (json['finalAsset'] as num).toDouble(),
      finalReturnRate: (json['finalReturnRate'] as num).toDouble(),
    );
  }

  // 특정 라운드에 고른 카드
  AnalysisCard? cardAt(int round) {
    for (final c in cards) {
      if (c.round == round) return c;
    }
    return null;
  }
}

// 플레이어 조합 결과
class PlayerAnalysisResult extends ComboResult {
  final double topPercent; // 상위 몇 % (rank / total × 100, 작을수록 좋음)

  PlayerAnalysisResult({
    required super.rank,
    required super.cards,
    required super.finalAsset,
    required super.finalReturnRate,
    required this.topPercent,
  });

  factory PlayerAnalysisResult.fromJson(
      Map<String, dynamic> json, int totalCombinations) {
    final base = ComboResult.fromJson(json);
    final raw  = json['topPercent'] as num?;
    return PlayerAnalysisResult(
      rank:            base.rank,
      cards:           base.cards,
      finalAsset:      base.finalAsset,
      finalReturnRate: base.finalReturnRate,
      // 서버 값이 없으면 rank / total로 직접 계산
      topPercent: raw?.toDouble() ??
          (totalCombinations > 0
              ? base.rank / totalCombinations * 100
              : 0),
    );
  }
}

class ResultAnalysis {
  final int totalCombinations;
  final List<ComboResult> topCombos;
  final PlayerAnalysisResult playerResult;

  ResultAnalysis({
    required this.totalCombinations,
    required this.topCombos,
    required this.playerResult,
  });

  factory ResultAnalysis.fromJson(Map<String, dynamic> json) {
    final total = (json['totalCombinations'] as num).toInt();
    final list  = (json['topCombos'] as List<dynamic>?) ?? [];
    return ResultAnalysis(
      totalCombinations: total,
      topCombos: list
          .map((e) => ComboResult.fromJson(e as Map<String, dynamic>))
          .toList(),
      playerResult: PlayerAnalysisResult.fromJson(
          json['playerResult'] as Map<String, dynamic>, total),
    );
  }

  // 1위 조합 (없으면 null)
  ComboResult? get best => topCombos.isNotEmpty ? topCombos.first : null;

  // 같은 순위가 topCombos 안에 여러 개인지 (공동 순위 표시용)
  bool isTied(int rank) =>
      topCombos.where((c) => c.rank == rank).length > 1;
}