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
  final double tradeAmount;           // (#125) 위기 대응 응답: 그때 팔거나 산 금액 (원). 버틴다·카드 선택은 0
  // (#125) 다음 이벤트 라운드의 그날 시장 (날짜·종목별 가격·전날 대비 등락·뉴스, 내 자산 없음)
  //        고르기 전에 그날 움직임을 보여 주기 위해. 예전 서버는 보내지 않음 → null
  final RoundData? nextEventMarket;

  ActionResult({
    required this.selectedCard,
    required this.rounds,
    this.nextEventRound,
    this.nextEventType,
    this.nextCardOptions = const [],
    this.nextDecision,
    this.nextRoundNews = const [],
    this.tradeAmount = 0,
    this.nextEventMarket,
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
      tradeAmount:     (json['tradeAmount'] as num?)?.toDouble() ?? 0,
      nextEventMarket: json['nextEventMarket'] is Map<String, dynamic>
          ? RoundData.fromJson(json['nextEventMarket'] as Map<String, dynamic>)
          : null,
    );
  }
}
