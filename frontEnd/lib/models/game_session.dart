import 'briefing.dart';
import 'round_data.dart';

class GameSession {
  final String sessionId;
  final String scenarioTitle;
  final int totalRounds;
  final double initialAsset;
  final List<int> cardSelectRounds;
  final List<int> firstCardOptions;  // 1라운드 카드 선택지
  final List<RoundData> rounds;

  // (#125) 위기 대응 라운드, '더 산다'에서 사는 지수 이름, 시작 전 브리핑
  //   예전 서버는 보내지 않음 → 빈 목록 / 기본값 / null
  final List<int> decisionRounds;
  final String buyMoreTarget;
  final Briefing? briefing;

  GameSession({
    required this.sessionId,
    required this.scenarioTitle,
    required this.totalRounds,
    required this.initialAsset,
    required this.cardSelectRounds,
    required this.firstCardOptions,
    required this.rounds,
    this.decisionRounds = const [],
    this.buyMoreTarget = 'S&P500',
    this.briefing,
  });

  factory GameSession.fromJson(Map<String, dynamic> json) {
    final List<dynamic> roundList       = json['rounds']           ?? [];
    final List<dynamic> cardSelectList  = json['cardSelectRounds'] ?? [];
    final List<dynamic> firstCardList   = json['firstCardOptions'] ?? [];
    final List<dynamic> decisionList    = json['decisionRounds']   ?? [];
    return GameSession(
      sessionId:        json['sessionId']       ?? '',
      scenarioTitle:    json['scenarioTitle']   ?? '',
      totalRounds:      json['totalRounds']     ?? 0,
      initialAsset:     (json['initialAsset']   ?? 10000000).toDouble(),
      cardSelectRounds: cardSelectList.map((e) => e as int).toList(),
      firstCardOptions: firstCardList.map((e) => e as int).toList(),
      rounds:           roundList.map((e) => RoundData.fromJson(e)).toList(),
      decisionRounds:   decisionList.map((e) => (e as num).toInt()).toList(),
      buyMoreTarget:    (json['buyMoreTarget'] as String?) ?? 'S&P500',
      briefing:         Briefing.fromJson(json['briefing']),
    );
  }

  // 라운드 목록만 바꾼 새 세션 (카드 선택·위기 대응 응답을 합칠 때)
  GameSession copyWithRounds(List<RoundData> rounds) => GameSession(
        sessionId:        sessionId,
        scenarioTitle:    scenarioTitle,
        totalRounds:      totalRounds,
        initialAsset:     initialAsset,
        cardSelectRounds: cardSelectRounds,
        firstCardOptions: firstCardOptions,
        rounds:           rounds,
        decisionRounds:   decisionRounds,
        buyMoreTarget:    buyMoreTarget,
        briefing:         briefing,
      );

  bool isCardSelectRound(int round) => cardSelectRounds.contains(round);

  bool isDecisionRound(int round) => decisionRounds.contains(round);

  // 자동 진행이 멈추고 플레이어의 선택을 기다리는 라운드 (카드 선택 + 위기 대응)
  bool isEventRound(int round) =>
      isCardSelectRound(round) || isDecisionRound(round);

  RoundData? getRound(int index) {
    if (index < 0 || index >= rounds.length) return null;
    return rounds[index];
  }

  List<RoundData> getChartData(int currentIndex) {
    if (currentIndex >= rounds.length) return rounds;
    return rounds.sublist(0, currentIndex + 1);
  }
}
