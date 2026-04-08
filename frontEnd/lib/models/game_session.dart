import 'round_data.dart';

class GameSession {
  final String sessionId;
  final String scenarioTitle;
  final int totalRounds;
  final double initialAsset;
  final List<int> cardSelectRounds;
  final List<int> firstCardOptions;  // 1라운드 카드 선택지
  final List<RoundData> rounds;

  GameSession({
    required this.sessionId,
    required this.scenarioTitle,
    required this.totalRounds,
    required this.initialAsset,
    required this.cardSelectRounds,
    required this.firstCardOptions,
    required this.rounds,
  });

  factory GameSession.fromJson(Map<String, dynamic> json) {
    final List<dynamic> roundList       = json['rounds']           ?? [];
    final List<dynamic> cardSelectList  = json['cardSelectRounds'] ?? [];
    final List<dynamic> firstCardList   = json['firstCardOptions'] ?? [];
    return GameSession(
      sessionId:        json['sessionId']       ?? '',
      scenarioTitle:    json['scenarioTitle']   ?? '',
      totalRounds:      json['totalRounds']     ?? 0,
      initialAsset:     (json['initialAsset']   ?? 10000000).toDouble(),
      cardSelectRounds: cardSelectList.map((e) => e as int).toList(),
      firstCardOptions: firstCardList.map((e) => e as int).toList(),
      rounds:           roundList.map((e) => RoundData.fromJson(e)).toList(),
    );
  }

  bool isCardSelectRound(int round) => cardSelectRounds.contains(round);

  RoundData? getRound(int index) {
    if (index < 0 || index >= rounds.length) return null;
    return rounds[index];
  }

  List<RoundData> getChartData(int currentIndex) {
    if (currentIndex >= rounds.length) return rounds;
    return rounds.sublist(0, currentIndex + 1);
  }
}