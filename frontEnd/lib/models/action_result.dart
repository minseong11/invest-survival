import 'decision.dart';
import 'news_item.dart';
import 'round_data.dart';

// 카드 선택(/game/round/action)·위기 대응(/game/round/decision) 응답
class ActionResult {
  final String selectedCard;          // 카드 선택 응답일 때 카드 이름
  final List<RoundData> rounds;       // 이번 이벤트 라운드부터 다음 이벤트 라운드 직전까지
  final int? nextEventRound;          // 없으면 100라운드까지 끝난 것
  final String? nextEventType;        // (#125) 'CARD' / 'DECISION' (예전 서버는 null → 카드 선택으로 취급)
  final List<int> nextCardOptions;    // 다음 카드 선택지
  final DecisionPrompt? nextDecision; // (#125) 다음이 위기 대응이면 그 속보
  final List<NewsItem> nextRoundNews; // (11주차) 다음 이벤트 라운드의 뉴스

  ActionResult({
    required this.selectedCard,
    required this.rounds,
    this.nextEventRound,
    this.nextEventType,
    this.nextCardOptions = const [],
    this.nextDecision,
    this.nextRoundNews = const [],
  });

  factory ActionResult.fromJson(Map<String, dynamic> json) {
    final List<dynamic> roundList    = json['rounds']          ?? [];
    final List<dynamic> nextCardList = json['nextCardOptions'] ?? [];
    return ActionResult(
      selectedCard:    json['selectedCard']  ?? '',
      nextEventRound:  json['nextEventRound'],
      nextEventType:   json['nextEventType'] as String?,
      nextCardOptions: nextCardList.map((e) => e as int).toList(),
      nextDecision:    DecisionPrompt.fromJson(json['nextDecision']),
      rounds:          roundList.map((e) => RoundData.fromJson(e)).toList(),
      nextRoundNews:   NewsItem.listFromJson(json['nextRoundNews']),
    );
  }
}
