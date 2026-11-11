import 'news_item.dart';
import 'round_data.dart';

class ActionResult {
  final String selectedCard;
  final List<RoundData> rounds;
  final int? nextEventRound;
  final List<int> nextCardOptions;  // 다음 증강 카드 선택지
  final List<NewsItem> nextRoundNews; // (11주차) 다음 카드 선택 라운드의 뉴스

  ActionResult({
    required this.selectedCard,
    required this.rounds,
    this.nextEventRound,
    this.nextCardOptions = const [],
    this.nextRoundNews = const [],
  });

  factory ActionResult.fromJson(Map<String, dynamic> json) {
    final List<dynamic> roundList    = json['rounds']          ?? [];
    final List<dynamic> nextCardList = json['nextCardOptions'] ?? [];
    return ActionResult(
      selectedCard:    json['selectedCard']  ?? '',
      nextEventRound:  json['nextEventRound'],
      nextCardOptions: nextCardList.map((e) => e as int).toList(),
      rounds:          roundList.map((e) => RoundData.fromJson(e)).toList(),
      nextRoundNews:   NewsItem.listFromJson(json['nextRoundNews']),
    );
  }
}