// 게임 종료 후 사후 분석 (백테스팅) — POST /game/result/analysis
// API 명세서 v6.1 기준
//
// 사용 가능한 카드 중 4장 순열(11장이면 7,920개, 닷컴 9장이면 3,024개)을 이 시나리오에서 실제로 돌려본 결과.
// 최종 자산이 같은 조합은 서버가 하나로 묶어 보냄 (tiedCount) → 순위가 1, 7, 8처럼 건너뛸 수 있음

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

// =============================================
// (11주차) 받은 후보 안 분석 — offeredAnalysis
// 라운드마다 실제로 제시된 3장만으로 만들 수 있는 조합(최대 81개) 기준
// =============================================

// 이 라운드만 다른 후보로 바꿨을 때 (나머지 라운드 선택은 그대로)
class RoundAlternative {
  final int cardId;
  final String cardName;
  final double finalReturnRate;
  final double diffReturnRate; // 대안 - 내 결과 (%p, +면 대안이 더 좋았음)

  RoundAlternative({
    required this.cardId,
    required this.cardName,
    required this.finalReturnRate,
    required this.diffReturnRate,
  });

  factory RoundAlternative.fromJson(Map<String, dynamic> json) {
    return RoundAlternative(
      cardId:          (json['cardId'] as num).toInt(),
      cardName:        (json['cardName'] as String?) ?? '',
      finalReturnRate: (json['finalReturnRate'] as num).toDouble(),
      diffReturnRate:  (json['diffReturnRate'] as num).toDouble(),
    );
  }
}

class RoundAlternatives {
  final int round;
  final List<int> offeredCards;
  final int playerCardId;
  final List<RoundAlternative> alternatives; // 최종 자산 높은 순

  RoundAlternatives({
    required this.round,
    required this.offeredCards,
    required this.playerCardId,
    required this.alternatives,
  });

  factory RoundAlternatives.fromJson(Map<String, dynamic> json) {
    return RoundAlternatives(
      round:        (json['round'] as num).toInt(),
      offeredCards: ((json['offeredCards'] as List<dynamic>?) ?? [])
          .map((e) => (e as num).toInt())
          .toList(),
      playerCardId: (json['playerCardId'] as num).toInt(),
      alternatives: ((json['alternatives'] as List<dynamic>?) ?? [])
          .map((e) => RoundAlternative.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  // 내 선택보다 더 좋았던 대안 중 최고 (없으면 null → 내 선택이 이 라운드 최선)
  RoundAlternative? get better {
    if (alternatives.isEmpty) return null;
    final top = alternatives.reduce(
        (a, b) => a.diffReturnRate >= b.diffReturnRate ? a : b);
    return top.diffReturnRate > 0 ? top : null;
  }
}

class OfferedAnalysis {
  final int totalCombinations;
  final ComboResult bestCombo;
  final PlayerAnalysisResult playerResult;
  final List<RoundAlternatives> roundAlternatives;

  OfferedAnalysis({
    required this.totalCombinations,
    required this.bestCombo,
    required this.playerResult,
    required this.roundAlternatives,
  });

  factory OfferedAnalysis.fromJson(Map<String, dynamic> json) {
    final total = (json['totalCombinations'] as num).toInt();
    return OfferedAnalysis(
      totalCombinations: total,
      bestCombo: ComboResult.fromJson(json['bestCombo'] as Map<String, dynamic>),
      playerResult: PlayerAnalysisResult.fromJson(
          json['playerResult'] as Map<String, dynamic>, total),
      roundAlternatives: ((json['roundAlternatives'] as List<dynamic>?) ?? [])
          .map((e) => RoundAlternatives.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  RoundAlternatives? roundAt(int round) {
    for (final r in roundAlternatives) {
      if (r.round == round) return r;
    }
    return null;
  }
}

class ResultAnalysis {
  final int totalCombinations;
  final List<ComboResult> topCombos;
  final PlayerAnalysisResult playerResult;
  final int cardPoolSize; // 이 시나리오에서 사용 가능한 카드 수 (#87: 닷컴은 상장 전 종목 제외로 9장)
  final OfferedAnalysis? offered; // 받은 후보 안 분석 (없거나 형식이 다르면 null)

  ResultAnalysis({
    required this.totalCombinations,
    required this.topCombos,
    required this.playerResult,
    this.cardPoolSize = 11,
    this.offered,
  });

  factory ResultAnalysis.fromJson(Map<String, dynamic> json) {
    final total = (json['totalCombinations'] as num).toInt();
    final list  = (json['topCombos'] as List<dynamic>?) ?? [];

    // 후보 안 분석은 실패해도 나머지 결과는 그대로 보여준다
    OfferedAnalysis? offered;
    try {
      final raw = json['offeredAnalysis'];
      if (raw is Map<String, dynamic>) offered = OfferedAnalysis.fromJson(raw);
    } catch (_) {
      offered = null;
    }

    return ResultAnalysis(
      totalCombinations: total,
      topCombos: list
          .map((e) => ComboResult.fromJson(e as Map<String, dynamic>))
          .toList(),
      playerResult: PlayerAnalysisResult.fromJson(
          json['playerResult'] as Map<String, dynamic>, total),
      cardPoolSize: (json['cardPoolSize'] as num?)?.toInt() ?? 11,
      offered: offered,
    );
  }

  // 1위 조합 (없으면 null)
  ComboResult? get best => topCombos.isNotEmpty ? topCombos.first : null;

  // 상위 목록에서 순위가 건너뛰는지 (예: 1위 → 7위)
  // 서버가 최종 자산이 같은 조합을 하나로 묶어 보내므로(tiedCount) 발생
  bool get hasSkippedRank {
    for (var i = 1; i < topCombos.length; i++) {
      if (topCombos[i].rank != topCombos[i - 1].rank + 1) return true;
    }
    return false;
  }
}