import 'news_item.dart';

// =============================================
// (#125) 위기 대응 선택
// 뉴스 속보가 나온 라운드에서 게임이 멈추고 셋 중 하나를 고른다. 서버 값은 HOLD / SELL_HALF / BUY_MORE
//   HOLD      버틴다     — 아무것도 하지 않고 전략 카드에 맡김
//   SELL_HALF 절반 판다  — 보유 자산을 종목마다 절반씩 그날 종가에 매도
//   BUY_MORE  더 산다    — 현금의 30%로 시나리오 기준 지수(S&P500 또는 나스닥100)를 그날 종가에 매수
// 비율(절반·30%)은 서버 GameService·game_logic.py와 같은 값이다.
// =============================================
class DecisionChoice {
  DecisionChoice._();

  static const hold     = 'HOLD';
  static const sellHalf = 'SELL_HALF';
  static const buyMore  = 'BUY_MORE';
  static const all      = [hold, sellHalf, buyMore];

  static String label(String choice) => switch (choice) {
        sellHalf => '절반 판다',
        buyMore  => '더 산다',
        _        => '버틴다',
      };

  static String emoji(String choice) => switch (choice) {
        sellHalf => '🏃',
        buyMore  => '🛒',
        _        => '🧘',
      };

  // 선택 화면의 설명. target: '더 산다'에서 사는 지수 이름
  static String description(String choice, {String target = 'S&P500'}) =>
      switch (choice) {
        sellHalf => '가진 자산을 종목마다 절반씩 팔아 현금으로 바꿔요',
        buyMore  => '현금의 30%로 $target을 더 사요',
        _        => '아무것도 하지 않고 전략 카드에 맡겨요',
      };

  // 고른 뒤 알림: "버티기로 했어요"
  static String done(String choice) => switch (choice) {
        sellHalf => '절반을 팔았어요',
        buyMore  => '더 샀어요',
        _        => '버티기로 했어요',
      };

  // 결과 화면의 가정: "버텼다면"
  static String ifDone(String choice) => switch (choice) {
        sellHalf => '절반 팔았다면',
        buyMore  => '더 샀다면',
        _        => '버텼다면',
      };
}

// 다음 위기 대응 라운드의 속보 (서버 nextDecision)
// { "round": 10, "news": {date, headline, level, source, sourceUrl}, "buyMoreTarget": "S&P500" }
class DecisionPrompt {
  final int round;
  final NewsItem news;
  final String buyMoreTarget;

  const DecisionPrompt({
    required this.round,
    required this.news,
    this.buyMoreTarget = 'S&P500',
  });

  static DecisionPrompt? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final news = raw['news'];
    if (news is! Map) return null;
    return DecisionPrompt(
      round: (raw['round'] as num?)?.toInt() ?? 0,
      news: NewsItem.fromJson(Map<String, dynamic>.from(news)),
      buyMoreTarget: (raw['buyMoreTarget'] as String?) ?? 'S&P500',
    );
  }
}
