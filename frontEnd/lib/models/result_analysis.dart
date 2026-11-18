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

// (#125) 화면에는 차이를 소수 1자리(%p)로 표시한다. 0.05%p 미만은 "+0.0%p 놓침"으로 보이므로
//        더 좋았던 선택으로 치지 않는다 (사실상 같은 결과 → 내 선택이 최선)
const double kMinVisibleGap = 0.05;

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

  // (#125) 어떤 카드를 골라도 결과가 (화면에 보이는 자리까지) 같았던 라운드 — "최선"이 아니라 "차이 없음"
  //        (예: 현금이 부족해 어떤 카드를 골라도 아무 일도 일어나지 않은 75라운드)
  bool get noDifference =>
      alternatives.isNotEmpty &&
      alternatives.every((a) => a.diffReturnRate.abs() < kMinVisibleGap);

  // 내 선택보다 더 좋았던 대안 중 최고 (없으면 null → 내 선택이 이 라운드 최선)
  RoundAlternative? get better {
    if (alternatives.isEmpty) return null;
    final top = alternatives.reduce(
        (a, b) => a.diffReturnRate >= b.diffReturnRate ? a : b);
    return top.diffReturnRate >= kMinVisibleGap ? top : null;
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

// =============================================
// (#125) 최대 낙폭 · 카드별 성적표 · 위기 대응 돌아보기 · 그 후 이야기
// 서버가 보내지 않거나 형식이 다르면 null / 빈 목록 → 화면에서 해당 칸 생략 (예전 서버와도 호환)
// =============================================

double _d(dynamic v) => v == null ? 0 : (v as num).toDouble();

// 최대 낙폭: 고점 대비 가장 크게 떨어진 비율 (%, 0 이하)
class RiskInfo {
  final double playerMdd;        // 내 자산
  final String? playerMddDate;
  final double marketMdd;        // 같은 기간 S&P500
  final String? marketMddDate;
  final double marketReturnRate; // 같은 기간 S&P500 수익률

  RiskInfo({
    required this.playerMdd,
    this.playerMddDate,
    required this.marketMdd,
    this.marketMddDate,
    this.marketReturnRate = 0,
  });

  factory RiskInfo.fromJson(Map<String, dynamic> json) => RiskInfo(
        playerMdd:        _d(json['playerMdd']),
        playerMddDate:    json['playerMddDate'] as String?,
        marketMdd:        _d(json['marketMdd']),
        marketMddDate:    json['marketMddDate'] as String?,
        marketReturnRate: _d(json['marketReturnRate']),
      );
}

// 카드별 성적표 한 줄: "이 카드를 고르지 않았다면"과 비교한 효과
class CardReportItem {
  final int round;
  final int cardId;
  final String cardName;
  final String cardType;          // BUY_ONCE / BUY_SPLIT / BUY_ON_CONDITION / SELL_ON_CONDITION / BUY_EVERY_N
  final int triggerCount;         // 실제로 매매가 일어난 횟수
  final double tradeAmount;       // 매매 금액 합계 (원)
  final Map<String, int> skips;   // 조건은 맞았지만 실행되지 못한 횟수 {사유: 횟수}
  final double effectReturnRate;  // 내 결과 − 이 카드를 뺀 결과 (%p). +면 이 카드가 결과를 끌어올림

  CardReportItem({
    required this.round,
    required this.cardId,
    required this.cardName,
    required this.cardType,
    required this.triggerCount,
    required this.tradeAmount,
    required this.skips,
    required this.effectReturnRate,
  });

  bool get isSell => cardType == 'SELL_ON_CONDITION';
  int get skipTotal => skips.values.fold(0, (a, b) => a + b);

  // 가장 많이 건너뛴 이유 (없으면 null)
  String? get mainSkipReason {
    if (skips.isEmpty) return null;
    return skips.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  factory CardReportItem.fromJson(Map<String, dynamic> json) {
    final rawSkips = json['skips'];
    return CardReportItem(
      round:            (json['round'] as num).toInt(),
      cardId:           (json['cardId'] as num).toInt(),
      cardName:         (json['cardName'] as String?) ?? '',
      cardType:         (json['cardType'] as String?) ?? '',
      triggerCount:     (json['triggerCount'] as num?)?.toInt() ?? 0,
      tradeAmount:      _d(json['tradeAmount']),
      skips: rawSkips is Map
          ? rawSkips.map((k, v) => MapEntry('$k', (v as num).toInt()))
          : const {},
      effectReturnRate: _d(json['effectReturnRate']),
    );
  }
}

// 위기 대응에서 다른 선택을 했다면
class DecisionAlternative {
  final String choice;
  final double finalReturnRate;
  final double diffReturnRate; // 다른 선택 − 내 결과 (%p, +면 다른 선택이 더 좋았음)

  DecisionAlternative({
    required this.choice,
    required this.finalReturnRate,
    required this.diffReturnRate,
  });

  factory DecisionAlternative.fromJson(Map<String, dynamic> json) =>
      DecisionAlternative(
        choice:          (json['choice'] as String?) ?? '',
        finalReturnRate: _d(json['finalReturnRate']),
        diffReturnRate:  _d(json['diffReturnRate']),
      );
}

class DecisionRoundReview {
  final int round;
  final String date;
  final String headline;    // 그때의 속보
  final String level;
  final String choice;      // 내 선택 (HOLD / SELL_HALF / BUY_MORE)
  final double tradeAmount; // 그때 팔거나 산 금액 (원)
  final List<DecisionAlternative> alternatives; // 결과가 좋은 순

  DecisionRoundReview({
    required this.round,
    required this.date,
    required this.headline,
    required this.level,
    required this.choice,
    required this.tradeAmount,
    required this.alternatives,
  });

  // (#125) 어떤 대응을 했어도 결과가 같았던 속보 — "가장 좋은 대응"이 아니라 "차이 없음"
  bool get noDifference =>
      alternatives.isNotEmpty &&
      alternatives.every((a) => a.diffReturnRate.abs() < kMinVisibleGap);

  // 내 선택보다 좋았던 다른 선택 중 최고 (없으면 null → 내 선택이 가장 좋았음)
  DecisionAlternative? get better {
    if (alternatives.isEmpty) return null;
    final top = alternatives
        .reduce((a, b) => a.diffReturnRate >= b.diffReturnRate ? a : b);
    return top.diffReturnRate >= kMinVisibleGap ? top : null;
  }

  factory DecisionRoundReview.fromJson(Map<String, dynamic> json) =>
      DecisionRoundReview(
        round:       (json['round'] as num).toInt(),
        date:        (json['date'] as String?) ?? '',
        headline:    (json['headline'] as String?) ?? '',
        level:       (json['level'] as String?) ?? 'caution',
        choice:      (json['choice'] as String?) ?? '',
        tradeAmount: _d(json['tradeAmount']),
        alternatives: ((json['alternatives'] as List<dynamic>?) ?? [])
            .map((e) => DecisionAlternative.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class DecisionReview {
  final List<DecisionRoundReview> rounds;
  final double allHoldFinalReturnRate; // 전부 버텼을 때의 수익률
  final double effectReturnRate;       // 내 결과 − 전부 버텼을 때 (%p)

  DecisionReview({
    required this.rounds,
    required this.allHoldFinalReturnRate,
    required this.effectReturnRate,
  });

  bool get allHold => rounds.every((r) => r.choice == 'HOLD');

  factory DecisionReview.fromJson(Map<String, dynamic> json) => DecisionReview(
        rounds: ((json['rounds'] as List<dynamic>?) ?? [])
            .map((e) => DecisionRoundReview.fromJson(e as Map<String, dynamic>))
            .toList(),
        allHoldFinalReturnRate: _d(json['allHoldFinalReturnRate']),
        effectReturnRate:       _d(json['effectReturnRate']),
      );
}

// 그 후 이야기: 게임이 끝난 뒤 실제 시장
class EpiloguePoint {
  final String label;             // "6개월 뒤" / "1년 뒤"
  final String date;
  final double spxChangeRate;     // 게임 종료일 대비 S&P500 (%)
  final double playerReturnRate;  // 내 최종 보유 자산을 그대로 뒀을 때, 원금 대비 (%)
  final double? bestReturnRate;   // 게임 1위 조합을 그대로 뒀을 때, 원금 대비 (%)

  EpiloguePoint({
    required this.label,
    required this.date,
    required this.spxChangeRate,
    required this.playerReturnRate,
    this.bestReturnRate,
  });

  factory EpiloguePoint.fromJson(Map<String, dynamic> json) => EpiloguePoint(
        label:            (json['label'] as String?) ?? '',
        date:             (json['date'] as String?) ?? '',
        spxChangeRate:    _d(json['spxChangeRate']),
        playerReturnRate: _d(json['playerReturnRate']),
        bestReturnRate:   (json['bestReturnRate'] as num?)?.toDouble(),
      );
}

class Epilogue {
  final String endDate; // 게임 마지막 라운드 날짜
  final List<EpiloguePoint> points;

  Epilogue({required this.endDate, required this.points});

  factory Epilogue.fromJson(Map<String, dynamic> json) => Epilogue(
        endDate: (json['endDate'] as String?) ?? '',
        points: ((json['points'] as List<dynamic>?) ?? [])
            .map((e) => EpiloguePoint.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class ResultAnalysis {
  final int totalCombinations;
  final List<ComboResult> topCombos;
  final PlayerAnalysisResult playerResult;
  final int cardPoolSize; // 이 시나리오에서 사용 가능한 카드 수 (#87: 닷컴은 상장 전 종목 제외로 9장)
  final OfferedAnalysis? offered; // 받은 후보 안 분석 (없거나 형식이 다르면 null)

  // (#125)
  final String grade;                    // S / A / B / C / D (전체 조합 순위 기준). 없으면 ''
  final RiskInfo? risk;
  final List<CardReportItem> cardReport;
  final DecisionReview? decisionReview;  // 위기 대응이 없는 게임이면 null
  final Epilogue? epilogue;

  ResultAnalysis({
    required this.totalCombinations,
    required this.topCombos,
    required this.playerResult,
    this.cardPoolSize = 11,
    this.offered,
    this.grade = '',
    this.risk,
    this.cardReport = const [],
    this.decisionReview,
    this.epilogue,
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

    // (#125) 추가 분석도 하나가 실패해도 나머지는 그대로 보여준다
    T? tryParse<T>(String key, T Function(Map<String, dynamic>) parse) {
      try {
        final raw = json[key];
        return raw is Map<String, dynamic> ? parse(raw) : null;
      } catch (_) {
        return null;
      }
    }

    List<CardReportItem> cardReport = const [];
    try {
      final raw = json['cardReport'];
      if (raw is List) {
        cardReport = raw
            .map((e) => CardReportItem.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {
      cardReport = const [];
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
      grade: (json['grade'] as String?) ?? '',
      risk: tryParse('risk', RiskInfo.fromJson),
      cardReport: cardReport,
      decisionReview: tryParse('decisionReview', DecisionReview.fromJson),
      epilogue: tryParse('epilogue', Epilogue.fromJson),
    );
  }

  // 1위 조합 (없으면 null)
  ComboResult? get best => topCombos.isNotEmpty ? topCombos.first : null;
}