import 'round_data.dart';

class ActionResult {
  final String selectedCard;
  final List<RoundData> rounds;
  final int? nextEventRound;
  final List<int> nextCardOptions;  // 다음 증강 카드 선택지

  ActionResult({
    required this.selectedCard,
    required this.rounds,
    this.nextEventRound,
    this.nextCardOptions = const [],
  });

  factory ActionResult.fromJson(Map<String, dynamic> json) {
    final List<dynamic> roundList    = json['rounds']          ?? [];
    final List<dynamic> nextCardList = json['nextCardOptions'] ?? [];
    return ActionResult(
      selectedCard:    json['selectedCard']  ?? '',
      nextEventRound:  json['nextEventRound'],
      nextCardOptions: nextCardList.map((e) => e as int).toList(),
      rounds:          roundList.map((e) => RoundData.fromJson(e)).toList(),
    );
  }
}