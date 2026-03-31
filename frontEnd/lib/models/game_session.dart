import 'round_data.dart';

// POST /game/start 응답 전체
class GameSession {
  final String sessionId;
  final String scenarioTitle;
  final int totalRounds;
  final double initialAsset;
  final List<RoundData> rounds;

  GameSession({
    required this.sessionId,
    required this.scenarioTitle,
    required this.totalRounds,
    required this.initialAsset,
    required this.rounds,
  });

  factory GameSession.fromJson(Map<String, dynamic> json) {
    final List<dynamic> roundList = json['rounds'] ?? [];
    return GameSession(
      sessionId: json['sessionId'] ?? '',
      scenarioTitle: json['scenarioTitle'] ?? '',
      totalRounds: json['totalRounds'] ?? 0,
      initialAsset: (json['initialAsset'] ?? 10000000).toDouble(),
      rounds: roundList.map((e) => RoundData.fromJson(e)).toList(),
    );
  }

  // 특정 라운드 데이터 꺼내기 (0-based index)
  // ex) getRound(0) → 1라운드
  RoundData? getRound(int index) {
    if (index < 0 || index >= rounds.length) return null;
    return rounds[index];
  }

  // 현재 라운드까지 누적 데이터 (차트용)
  // ex) getChartData(2) → 0,1,2라운드 데이터
  List<RoundData> getChartData(int currentIndex) {
    return rounds.sublist(0, currentIndex + 1);
  }
}
