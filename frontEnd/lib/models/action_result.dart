import 'round_data.dart';

// POST /game/round/action 응답
class ActionResult {
  final String selectedCard;
  final List<RoundData> rounds;   // 카드 선택 시점 ~ 다음 증강 직전까지
  final int? nextEventRound;      // 다음 증강 라운드 (없으면 null = 게임 끝까지)

  ActionResult({
    required this.selectedCard,
    required this.rounds,
    this.nextEventRound,
  });

  factory ActionResult.fromJson(Map<String, dynamic> json) {
    final List<dynamic> roundList = json['rounds'] ?? [];
    return ActionResult(
      selectedCard: json['selectedCard'] ?? '',
      rounds: roundList.map((e) => RoundData.fromJson(e)).toList(),
      nextEventRound: json['nextEventRound'],
    );
  }
}