import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/game_session.dart';
import '../models/round_data.dart';
import '../models/action_result.dart';
import '../models/card_info.dart';
import '../models/decision.dart';
import '../models/market.dart';
import '../models/news_item.dart';
import '../models/v2_recommend_result.dart';
import '../services/game_service.dart';
import '../widgets/decision_selector.dart';
import '../widgets/stock_chart.dart';
import '../widgets/today_market.dart';
import '../widgets/holdings_widget.dart';
import '../widgets/market_chips.dart';
import '../widgets/news_banner.dart';
import '../widgets/scene/briefing_scene.dart';
import '../widgets/scene/scene_widgets.dart';
import '../widgets/toss/toss_widgets.dart';
import '../theme/toss_theme.dart';
import 'game_result_screen.dart';

enum AiState { idle, loading, done, error }

class GameScreen extends StatefulWidget {
  final GameSession session;
  // 테스트에서 가짜 서버를 넣을 수 있게 (없으면 실제 서버)
  final GameService? service;
  const GameScreen({super.key, required this.session, this.service});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with TickerProviderStateMixin {
  late final GameService _gameService = widget.service ?? GameService();

  late GameSession _session;
  int  _currentRoundIndex = 0;
  // 지금 라운드가 이벤트 라운드(카드 선택·위기 대응)일 때, 그 선택을 마쳤는지
  bool _eventDone         = false;
  bool _isSubmitting      = false;
  bool _isAutoPlaying     = false;
  int  _speed             = 1;     // (#125) 자동 진행 배속 (1·2·4)

  List<int> _currentCardOptions = [];

  // 선택한 카드 누적 (보유카드 + V2 alreadyCards용)
  final List<int> _selectedCardIds = [];
  int? _lastAddedCardId;

  // 이번 라운드 발동 카드 (애니메이션용)
  List<int> _triggeredCardIds = [];

  // V2: 버튼 눌렀을 때만
  AiState          _aiState             = AiState.idle;
  int?             _v2RecommendedCardId;
  String           _aiFeedback          = ''; // LLM 자연어 피드백
  List<CardRanking> _lastRankings       = []; // 피드백 요청 시 재사용
  bool             _aiRequested         = false;

  // 라운드별 AI 예측 1순위 (결과 화면에서 '내 선택'과 비교)
  final Map<int, int> _aiPicks = {};

  // (11주차) 뉴스 — 위쪽 '최근 뉴스' 칸 (기존: 화면 맨 위를 5초 동안 덮는 배너)
  List<NewsItem> _pendingSelectNews = [];   // 다음 카드 선택 라운드 뉴스 (nextRoundNews)
  final Set<String> _shownNewsKeys = {};    // 이미 나온 뉴스 (날짜+헤드라인)
  final List<NewsItem> _newsLog = [];       // 지금까지 나온 뉴스 (목록)
  NewsItem? _stripNews;                     // 최근 뉴스 칸에 보이는 뉴스
  bool _newsFresh = false;                  // 방금 나온 뉴스 → 칸이 잠깐 물들고 '새 소식'
  Timer? _newsFreshTimer;
  List<NewsItem> _selectNews = [];          // 카드 선택 섹션의 '오늘 나온 뉴스'

  Timer? _autoTimer;

  // 카드 선택 화면에서 고른 카드 (확정 버튼을 눌러야 제출)
  int? _pendingCardId;
  // (#125) 차트에 겹쳐 보는 종목 (차트 아래 종목 칩에서 켜고 끔)
  Set<String> _overlayTickers = {};

  // (#125) 위기 대응
  DecisionPrompt? _decisionPrompt;          // 다음 위기 대응 라운드의 속보 (서버 nextDecision)
  RoundData? _eventMarket;                  // (#125) 다음 이벤트 라운드의 그날 시장 (서버 nextEventMarket)
  String? _pendingChoice;                   // 고른 대응 (확정 버튼을 눌러야 제출)
  final Map<int, String> _decisions = {};   // 라운드 → 내가 한 대응 (차트 표시용)

  // (#125) 카드가 건너뛴 이유는 같은 이유로 처음 건너뛸 때만 알린다 (매 라운드 알리면 계속 떠 있음)
  final Set<String> _announcedSkips = {};
  String _skipNotice = '';

  // (#125) 위기 대응을 확정한 직후 차트 위 알림 칸에 잠깐 보여주는 문구 ("절반을 팔았어요 · 140만원")
  //   화면 아래 토스트로 띄우면 다음 선택의 확정 버튼을 가리므로 알림 칸을 쓴다
  String _decisionNotice = '';
  Timer? _decisionNoticeTimer;

  // (게임 장면 개편) 고른 직후 가운데에 잠깐 뜨는 확인 카드 ("🏃 절반을 팔았어요 · 135만원")
  //  고른 것이 무슨 일을 했는지 보여 주고 1.4초 뒤 사라진다 (누르는 것을 막지 않는다)
  ({String emoji, String title, String sub})? _flash;
  Timer? _flashTimer;

  // 고른 뒤에는 차트가 보이도록 게임 화면을 맨 위로
  final ScrollController _scrollController = ScrollController();

  // (장면 개편) 선택은 게임 화면 아래가 아니라, 위로 올라오는 장면 시트에서 한다
  //   기존: 선택지가 게임 화면 맨 아래에 붙어 고를 때마다 스크롤해서 내려가야 했다
  bool _briefingDone = false;   // 시작 브리핑(넘겨 보는 3장면)을 다 봤는지
  static const _ordinals = ['첫 번째', '두 번째', '세 번째', '마지막'];

  // ── Getters ────────────────────────────────
  RoundData get _currentRound {
    final idx = _currentRoundIndex.clamp(0, _session.rounds.length - 1);
    return _session.rounds[idx];
  }

  List<RoundData> get _chartData => _session.getChartData(
      _currentRoundIndex.clamp(0, _session.rounds.length - 1));

  int get _currentRound1 => _currentRoundIndex + 1;

  // (#125) 지금 고르는 라운드의 그날 시장 — 카드·위기 대응은 그날 종가로 매매하고, AI 예측도 그날 종가까지 본다
  //        1라운드는 시작 응답의 1라운드, 그 뒤는 서버가 미리 보낸 이벤트 라운드 가격(nextEventMarket)
  RoundData? get _todayMarket {
    if (!_waiting) return null;
    if (_currentRound1 == 1) {
      return _session.rounds.isEmpty ? null : _session.rounds.first;
    }
    final m = _eventMarket;
    return (m != null && m.round == _currentRound1) ? m : null;
  }

  // (#125) 차트·종목 칩·카드별 등락에 쓰는 라운드 — 고르는 중이면 그날 시장까지 (AI와 같은 기준).
  //        내 자산은 고른 뒤에 계산되므로 전날까지만 있다
  List<RoundData> get _displayRounds {
    final base = _chartData;
    final today = _todayMarket;
    if (today == null || base.isEmpty || today.round != base.last.round + 1) return base;
    return [...base, today];
  }

  // (#125) 사는 카드가 발동하지 않는 상태 — 현금이 총자산의 5% 미만 (게임 계산과 같은 기준)
  bool get _cashLow => !_notStarted && (_currentRound.cashWeight ?? 100) < 5;

  // (#125) 자동 진행 중에는 다음 라운드 전에 숫자가 멈추도록 굴리는 시간을 줄인다
  //        (기존 0.42초 — ×1의 라운드 간격이 0.5초라 숫자가 거의 항상 굴러가는 중이어서 읽기 어려웠다)
  Duration get _rollDuration => _isAutoPlaying
      ? Duration(milliseconds: 250 ~/ _speed)
      : const Duration(milliseconds: 420);

  // 첫 카드를 고르기 전 (차트를 숨기고 카드 선택만 보여줌)
  bool get _notStarted => _selectedCardIds.isEmpty;

  // 지금까지 카드를 고른 라운드의 차트 위치 (0부터)
  Set<int> get _cardIndexes {
    final rounds = [..._session.cardSelectRounds]..sort();
    return rounds.take(_selectedCardIds.length).map((r) => r - 1).toSet();
  }

  bool get _atCardRound => _session.cardSelectRounds.isNotEmpty
      ? _session.isCardSelectRound(_currentRound1)
      : _currentRound1 == 1;

  // 카드를 골라야 하는 상태
  bool get _showCard => !_eventDone && _atCardRound;

  // (#125) 위기 대응을 골라야 하는 상태
  bool get _showDecision =>
      !_eventDone && !_atCardRound && _session.isDecisionRound(_currentRound1);

  // 플레이어의 선택을 기다리는 중 (자동 진행이 멈춰 있음)
  bool get _waiting => _showCard || _showDecision;

  bool get _isLastRound {
    if (_waiting) return false;
    final next = _currentRoundIndex + 2;
    if (_session.isEventRound(next)) return false;
    return _currentRoundIndex >= _session.rounds.length - 1;
  }

  // 지금 화면에 보이는 라운드에서 가진 자산이 있는지 / 현금이 남았는지 (위기 대응 선택지를 막을 때 사용)
  bool get _hasHoldings => _currentRound.holdings.isNotEmpty;
  bool get _hasCash => (_currentRound.cash ?? _session.initialAsset) > 0;
  bool get _holdsSpx => _currentRound.holdings.any((h) => h.ticker == '^SPX');

  // 위기 대응을 한 라운드의 차트 위치 (0부터)
  Set<int> get _decisionIndexes => _decisions.keys.map((r) => r - 1).toSet();

  // V2: 25·50라운드만 (1·75 제외)
  bool get _canUseV2 => [25, 50].contains(_currentRound1);

  // 1·75라운드: AI 예측을 제공하지 않는 이유 (v6.1 합의 1번)
  //  - 1라운드: so_far 시장 데이터가 없어 V2가 판단할 근거가 없음
  //  - 75라운드: 남은 라운드가 적어 카드 간 결과 차이가 작음
  String? get _noAiReason {
    if (_currentRound1 == 1) {
      return 'AI 예측은 게임 중 시장 흐름이 쌓이는 25·50라운드에 나와요. '
          '지금은 방금 본 시작 전 브리핑과 오늘 시장을 참고하세요';
    }
    if (_currentRound1 == 75) {
      return '남은 라운드가 적어 카드 간 결과 차이가 작기 때문에 AI 예측을 제공하지 않아요';
    }
    return null;
  }

  // AI 예측 1순위 카드 ID (V2 결과만 사용. V1.5 사전 추천은 v6.0에서 제거)
  int? get _aiRecommendedCardId {
    if (!_aiRequested || _aiState != AiState.done) return null;
    return _v2RecommendedCardId;
  }

  // 보유카드 데이터
  List<HoldingCardInfo> get _holdingCards => extractHoldingCards(
        selectedCardIds:   _selectedCardIds,
        rounds:            _session.rounds,
        currentRoundIndex: _currentRoundIndex,
        newCardId:         _lastAddedCardId,
      );

  // =============================================
  // 생명주기
  // =============================================
  @override
  void initState() {
    super.initState();
    _session            = widget.session;
    _currentCardOptions = _session.firstCardOptions;

    // 1라운드 뉴스 (게임 시작 응답 rounds[0].news)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onRoundEntered();
    });
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _newsFreshTimer?.cancel();
    _decisionNoticeTimer?.cancel();
    _flashTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  // =============================================
  // V2 AI 추천 (버튼 클릭 시, 25·50라운드만)
  // =============================================
  Future<void> _requestAiRecommendation() async {
    if (_aiState == AiState.loading) return;
    // 1·75라운드에서는 버튼 자체가 없음 → 호출 안 됨

    setState(() {
      _aiRequested         = true;
      _aiState             = AiState.loading;
      _v2RecommendedCardId = null;
      _aiFeedback          = '';
    });

    try {
      final result = await _gameService.getV2Recommendation(
        sessionId:      _session.sessionId,
        currentRound:   _currentRound1,
        alreadyCards:   List.from(_selectedCardIds),
        candidateCards: List.from(_currentCardOptions),
      );
      if (!mounted) return;
      setState(() {
        _v2RecommendedCardId = result.recommendedCardId;
        _aiPicks[_currentRound1] = result.recommendedCardId;
        _lastRankings        = result.rankings;
        _aiFeedback          = result.feedback; // v5.0: recommend 응답에 함께 포함
        _aiState             = AiState.done;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _aiState = AiState.error);
    }
  }

  void _resetAiState() {
    _aiState             = AiState.idle;
    _aiRequested         = false;
    _v2RecommendedCardId = null;
    _aiFeedback          = '';
    _lastRankings        = [];
    _pendingCardId       = null;
    _pendingChoice       = null;
  }

  // =============================================
  // AI 비교 시트 (게임 장면 개편)
  //  결론부터: "AI라면 ○○를 골라요" → 후보 카드 3장이 한 장씩 뒤집혀 나오고 1위에 'AI 추천'
  //  → 순위 막대(숫자 없음) → 이유 두 줄(지금 / 그래서) → 닫기 · ○○로 할게요.
  //  다른 카드를 누르면 "○○는 2위예요"와 그 카드의 규칙으로 바뀐다.
  //  (기존: -1.6%p 같은 숫자가 1위도 마이너스라 "추천인데 손해?"처럼 헷갈렸고, 안내문이 길었다)
  //  서버 feedback 3줄 "지금 시장: …" / "이 카드는: …" / "그래서: …" 중 지금 시장·그래서를 쓴다
  // =============================================
  Future<void> _showAiSheet() async {
    final ranked = [..._lastRankings]..sort((a, b) => a.rank.compareTo(b.rank));
    if (ranked.isEmpty) return;

    final lines = _aiFeedback
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    String? pick(String head) {
      for (final l in lines) {
        if (l.startsWith('$head: ')) return l.substring(head.length + 2);
      }
      return null;
    }

    final market = pick('지금 시장');
    final so     = pick('그래서') ?? pick('이 카드는');
    // 막대 길이: 1위 = 가득, 꼴찌 = 30% (값의 크기가 아니라 순서를 보여 준다)
    final values = ranked.map((r) => r.contribution).toList();
    final hi = values.reduce(math.max), lo = values.reduce(math.min);
    double bar(double v) => hi - lo < 1e-9 ? 1 : 0.3 + 0.7 * (v - lo) / (hi - lo);
    final topId = ranked.first.cardId;
    var sel = topId;

    final chosen = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: TossColors.white,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(TossRadius.sheet)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.9),
          child: StatefulBuilder(builder: (ctx, setSheet) {
            final card = CardInfo.fromId(sel);
            final name = card?.name ?? '';
            final rank = ranked.firstWhere((r) => r.cardId == sel).rank;
            final isTop = sel == topId;
            final title = isTop
                ? 'AI라면 $name${_josa(name, '을', '를')} 골라요'
                : '$name${_josa(name, '은', '는')} $rank위예요';

            return RevealScope(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('✨ AI가 ${ranked.length}장을 비교했어요',
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: TossColors.blue600)),
                    const SizedBox(height: 6),
                    AnimatedSwitcher(
                      duration: TossMotion.base,
                      layoutBuilder: (current, previous) => Stack(
                        alignment: Alignment.topLeft,
                        children: [...previous, if (current != null) current],
                      ),
                      child: Text(title,
                          key: ValueKey(title), style: TossText.title2),
                    ),
                    const SizedBox(height: 22),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (int i = 0; i < ranked.length; i++) ...[
                          if (i > 0) const SizedBox(width: 8),
                          Expanded(
                            child: Reveal(
                              order: 2 + i * 2,
                              rise: 30,
                              child: _aiMiniCard(
                                ranked[i],
                                bar(ranked[i].contribution),
                                top: i == 0,
                                selected: ranked[i].cardId == sel,
                                onTap: () => setSheet(() => sel = ranked[i].cardId),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 18),
                    Reveal(
                      order: 2 + ranked.length * 2,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                        decoration: BoxDecoration(
                          color: TossColors.grey100,
                          borderRadius: BorderRadius.circular(TossRadius.lg),
                        ),
                        child: Column(
                          children: [
                            if (market != null) _aiReasonLine('지금', market, false),
                            if (market != null) const SizedBox(height: 8),
                            isTop
                                ? _aiReasonLine('그래서', so ?? card?.description ?? '', true)
                                : _aiReasonLine('이 카드는',
                                    card?.description.replaceAll('\n', ' ') ?? '', true),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'AI는 오늘 종가까지의 S&P500 흐름과 고른 카드만 보고 예측해요. '
                      '과거 시장으로 배운 참고용이라 틀릴 수 있어요.',
                      style: TossText.small,
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: TossButton(
                            label: '닫기',
                            type: TossButtonType.secondary,
                            onTap: () => Navigator.of(ctx).pop(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: TossButton(
                            label: '$name${_josa(name, '으로', '로')} 할게요',
                            onTap: () => Navigator.of(ctx).pop(sel),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
    if (chosen == null || !mounted || !_showCard || _isSubmitting) return;
    setState(() => _pendingCardId = chosen);
    _onCardSelected(chosen);
  }

  Widget _aiMiniCard(CardRanking r, double barRatio,
      {required bool top, required bool selected, required VoidCallback onTap}) {
    final card = CardInfo.fromId(r.cardId);
    final tint = card == null
        ? TossColors.grey500
        : (kTickerColors[priceTicker(card.ticker)] ?? TossColors.blue500);
    return Pressable(
      onTap: onTap,
      scale: 0.97,
      child: AnimatedContainer(
        duration: TossMotion.base,
        curve: TossMotion.enter,
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
        transform: Matrix4.translationValues(0, selected ? -4 : 0, 0),
        decoration: BoxDecoration(
          color: TossColors.white,
          borderRadius: BorderRadius.circular(TossRadius.lg),
          border: Border.all(
            color: selected ? TossColors.blue500 : TossColors.grey200,
            width: selected ? 2 : 1.5,
          ),
          boxShadow: selected && top
              ? [
                  BoxShadow(
                    color: TossColors.blue500.withValues(alpha: 0.25),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Column(
          children: [
            SizedBox(
              height: 20,
              child: top
                  ? const TossBadge(
                      label: 'AI 추천',
                      bg: TossColors.blue500,
                      fg: TossColors.white)
                  : null,
            ),
            const SizedBox(height: 6),
            EmojiTile(
              emoji: card?.emoji ?? '🃏',
              size: 48,
              bg: tint.withValues(alpha: 0.12),
            ),
            const SizedBox(height: 8),
            Text(card?.name ?? r.cardName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: TossColors.grey900)),
            const SizedBox(height: 2),
            Text('${r.rank}위',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: top ? TossColors.blue600 : TossColors.grey500)),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: Container(
                height: 6,
                color: TossColors.grey100,
                alignment: Alignment.centerLeft,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: barRatio),
                  duration: const Duration(milliseconds: 700),
                  curve: TossMotion.enter,
                  builder: (_, v, __) => FractionallySizedBox(
                    widthFactor: v.clamp(0.0, 1.0),
                    heightFactor: 1,
                    child: Container(
                        color: top ? TossColors.blue500 : TossColors.grey400),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _aiReasonLine(String head, String body, bool strong) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 52,
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(head,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: strong ? TossColors.blue600 : TossColors.grey500)),
          ),
        ),
        Expanded(
          child: Text(body,
              style: TextStyle(
                  fontSize: strong ? 15 : 14,
                  height: 1.5,
                  fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
                  color: strong ? TossColors.grey900 : TossColors.grey700)),
        ),
      ],
    );
  }

  // =============================================
  // 뉴스 배너 (11주차)
  // =============================================
  // 라운드에 들어올 때마다 호출. 그 라운드 뉴스 + (카드 선택 라운드면) nextRoundNews
  void _onRoundEntered() {
    final roundNews =
        _session.getRound(_currentRoundIndex)?.news ?? const <NewsItem>[];
    final sticky = _waiting;
    final items  = [...roundNews, if (sticky) ..._pendingSelectNews];
    if (sticky) {
      // 선택 라운드: 뉴스는 위에서 띄우지 않고 선택 섹션 안에 고정
      // (위기 대응 라운드의 속보는 제목 아래에 크게 따로 보여주므로 목록에서는 뺀다)
      final seen = <String>{};
      final promptKey = _showDecision ? _decisionPrompt?.news.key : null;
      setState(() {
        _selectNews = items
            .where((n) => n.key != promptKey && seen.add(n.key))
            .toList();
      });
    }
    _showNews(items);
    _updateSkipNotice();
  }

  void _scrollToTop() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(0,
        duration: TossMotion.slow, curve: TossMotion.enter);
  }

  // (#125) 이번 라운드에 조건은 맞았지만 실행되지 못한 카드 → 같은 이유로는 처음 한 번만 알림
  void _updateSkipNotice() {
    final round = _session.getRound(_currentRoundIndex);
    final fresh = <String>[];
    for (final s in round?.skippedCards ?? const <SkippedCard>[]) {
      if (!_announcedSkips.add('${s.cardId}|${s.reason}')) continue;
      final card = CardInfo.fromId(s.cardId);
      if (card == null) continue;
      fresh.add('${card.emoji} ${card.name} 쉼 · ${SkippedCard.label(s.reason)}');
    }
    final notice = fresh.join('  ');
    if (notice != _skipNotice) setState(() => _skipNotice = notice);
  }

  // 새 뉴스는 위쪽 '최근 뉴스' 칸에 — 아무것도 가리지 않고 다음 뉴스가 올 때까지 남는다.
  //  선택 라운드의 뉴스는 장면 안 '오늘 나온 뉴스'에도 함께 보인다
  void _showNews(List<NewsItem> items) {
    final fresh = <NewsItem>[];
    for (final n in items) {
      if (_shownNewsKeys.add(n.key)) fresh.add(n); // 이미 나온 뉴스는 건너뜀
    }
    if (fresh.isEmpty) return;
    // 위험 뉴스는 진동으로 한 번 더 알림
    if (fresh.any((n) => n.level == 'danger')) HapticFeedback.mediumImpact();
    setState(() {
      _newsLog.addAll(fresh);
      _stripNews = fresh.first;   // 같은 날 뉴스가 여러 개면 첫 번째, 나머지는 목록에서
      _newsFresh = true;
    });
    _newsFreshTimer?.cancel();
    _newsFreshTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) setState(() => _newsFresh = false);
    });
  }

  // =============================================
  // 자동 진행
  // =============================================
  void _startAutoPlay() {
    _autoTimer?.cancel();
    if (_isLastRound) return;
    setState(() => _isAutoPlaying = true);
    _autoTimer = Timer.periodic(Duration(milliseconds: 500 ~/ _speed), (_) {
      if (!mounted) return;
      final next         = _currentRoundIndex + 2;
      // 다음 라운드가 카드 선택·위기 대응 라운드면 멈추고 선택을 기다린다
      final willHitEvent = _session.isEventRound(next);
      if (_isLastRound || willHitEvent) {
        _stopAutoPlay();
        if (!_isLastRound) {
          setState(() {
            _currentRoundIndex++;
            _eventDone        = false;
            _triggeredCardIds = [];
            _resetAiState();
          });
          _onRoundEntered();
        }
      } else {
        setState(() {
          _currentRoundIndex++;
          _triggeredCardIds =
              _session.rounds[_currentRoundIndex].triggeredCards;
        });
        _onRoundEntered();
      }
    });
  }

  void _stopAutoPlay() {
    _autoTimer?.cancel();
    _autoTimer = null;
    if (mounted) setState(() => _isAutoPlaying = false);
  }

  // (#125) 배속 바꾸기: 1 → 2 → 4 → 1. 진행 중이면 새 속도로 이어서 진행
  void _cycleSpeed() {
    setState(() => _speed = _speed >= 4 ? 1 : _speed * 2);
    if (_isAutoPlaying) _startAutoPlay();
  }

  void _goToResult() {
    _stopAutoPlay();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
          builder: (_) => GameResultScreen(
                session: _session,
                aiPicks: Map<int, int>.from(_aiPicks),
                service: widget.service,
              )),
    );
  }

  // =============================================
  // 카드 선택
  // =============================================
  Future<void> _onCardSelected(int cardId) async {
    setState(() => _isSubmitting = true);
    try {
      final result = await _gameService.submitAction(
        sessionId: _session.sessionId,
        round:     _currentRound1,
        cardId:    cardId,
      );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      final card = CardInfo.fromId(cardId);
      if (card != null) {
        _showFlash(card.emoji, '${card.name} 장착!', '오늘 종가부터 작동해요');
      }
      _applyActionResult(result, selectedCardId: cardId);
    } catch (e) {
      if (!mounted) return;
      showTossToast(context, e.toString());
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // (#125) 위기 대응 확정
  Future<void> _onDecisionSelected(String choice) async {
    final round = _currentRound1;
    setState(() => _isSubmitting = true);
    try {
      final result = await _gameService.submitDecision(
        sessionId: _session.sessionId,
        round:     round,
        choice:    choice,
      );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      _decisions[round] = choice;
      _applyActionResult(result);
      _showDecisionNotice(choice, result.tradeAmount);
      _showFlash(
        DecisionChoice.emoji(choice),
        DecisionChoice.done(choice),
        result.tradeAmount > 0
            ? '${formatShortWon(result.tradeAmount)} · 오늘 종가로'
            : '전략 카드에 맡겨요',
      );
    } catch (e) {
      if (!mounted) return;
      showTossToast(context, e.toString());
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showDecisionNotice(String choice, double tradeAmount) {
    final amount = tradeAmount > 0 ? ' · ${formatShortWon(tradeAmount)}' : '';
    _decisionNoticeTimer?.cancel();
    setState(() => _decisionNotice =
        '${DecisionChoice.emoji(choice)} ${DecisionChoice.done(choice)}$amount');
    _decisionNoticeTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _decisionNotice = '');
    });
  }

  void _showFlash(String emoji, String title, String sub) {
    _flashTimer?.cancel();
    setState(() => _flash = (emoji: emoji, title: title, sub: sub));
    _flashTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _flash = null);
    });
  }

  Widget _buildFlash() {
    final f = _flash;
    return IgnorePointer(
      child: AnimatedSwitcher(
        duration: TossMotion.base,
        switchInCurve: TossMotion.spring,
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.85, end: 1).animate(anim),
            child: child,
          ),
        ),
        child: f == null
            ? const SizedBox.shrink(key: ValueKey('flash-none'))
            : Center(
                key: ValueKey('flash-${f.title}'),
                child: Container(
                  width: 260,
                  padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
                  decoration: BoxDecoration(
                    color: TossColors.white,
                    borderRadius: BorderRadius.circular(TossRadius.sheet),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 30,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      EmojiTile(emoji: f.emoji, size: 72, bg: TossColors.blue50),
                      const SizedBox(height: 14),
                      Text(f.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: TossColors.grey900)),
                      const SizedBox(height: 4),
                      Text(f.sub,
                          textAlign: TextAlign.center,
                          style: TossText.caption),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  // 카드 선택·위기 대응 응답을 화면 상태에 합친다 (selectedCardId: 카드 선택일 때만)
  void _applyActionResult(ActionResult result, {int? selectedCardId}) {
    final updatedRounds = List<RoundData>.from(_session.rounds);
    for (final newRound in result.rounds) {
      final index = newRound.round - 1;
      if (index < updatedRounds.length) {
        updatedRounds[index] = newRound;
      } else {
        while (updatedRounds.length < index) {
          updatedRounds.add(updatedRounds.last);
        }
        updatedRounds.add(newRound);
      }
    }
    setState(() {
      _session            = _session.copyWithRounds(updatedRounds);
      _eventDone          = true;
      _currentCardOptions = result.nextCardOptions;
      _pendingSelectNews  = result.nextRoundNews;
      _decisionPrompt     = result.nextDecision;
      _eventMarket        = result.nextEventMarket;
      _selectNews         = [];

      // 선택한 카드 누적
      if (selectedCardId != null) {
        if (!_selectedCardIds.contains(selectedCardId)) {
          _selectedCardIds.add(selectedCardId);
        }
        _lastAddedCardId = selectedCardId;
      }
      _triggeredCardIds = [];
      _resetAiState();
    });
    _updateSkipNotice();
    _scrollToTop();
    // (12주차) 고르면 재생 버튼을 누르지 않아도 바로 다음 라운드로 진행
    _startAutoPlay();
  }

  // =============================================
  // Build (토스 스타일)
  //  게임 화면: 자산 요약+차트 → 내 포트폴리오, 하단 버튼 하나 (멈추기·이어서 / 결과 보기)
  //  선택하는 순간은 위로 올라오는 장면 시트에서 (_buildSceneLayer)
  // =============================================
  double get _displayAsset =>
      _currentRound.roundAsset ?? _session.initialAsset.toDouble();

  // 진행 화면 그래프 높이: 화면 높이의 약 5분의 1 (150px ~ 210px)
  //  (장면 단순화 2) 26%(190~280px)에서 줄임 — 아래 '내 포트폴리오'가 스크롤 없이 보이게.
  //  화면 크기로만 정하므로 게임 중에 보유 자산·카드가 늘어도 그래프 크기는 바뀌지 않는다
  double get _chartHeight =>
      (MediaQuery.sizeOf(context).height * 0.2).clamp(150.0, 210.0);

  // (#125) 게임 중에 나가려 하면 한 번 묻는다
  //   헤더의 뒤로 버튼, 브라우저·트랙패드의 뒤로 가기, 안드로이드 뒤로 버튼 모두 여기로 온다.
  //   기존에는 바로 처음 화면으로 나가서 진행 중인 게임이 사라졌다 (맥 트랙패드로 옆으로 밀다가 나가기도 함)
  Future<void> _confirmLeave() async {
    final wasPlaying = _isAutoPlaying;
    _stopAutoPlay();
    final leave = await showTossConfirm(
      context,
      title: '게임을 그만둘까요?',
      message: '처음 화면으로 나가면 지금 하던 게임은 이어서 할 수 없어요.',
      confirmLabel: '그만두기',
      cancelLabel: '계속하기',
    );
    if (!mounted) return;
    if (leave) {
      Navigator.of(context).pop();
    } else if (wasPlaying) {
      _startAutoPlay();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // 첫 카드를 고르기 전에는 잃을 것이 없으니 묻지 않는다
      canPop: _notStarted,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
      backgroundColor: TossColors.background,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
        Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildSummary(),
                    // (게임 장면 개편) 오늘 있었던 일 한 줄 — 점수판 바로 아래 (기존: 라운드 표시 아래 맨 위)
                    //  늘 자리를 차지해 아무것도 가리지 않고, 다음 뉴스가 올 때까지 남는다
                    const SizedBox(height: 8),
                    NewsStrip(
                      news:  _stripNews,
                      count: _newsLog.length,
                      fresh: _newsFresh,
                      onTap: () => showNewsLogSheet(context, _newsLog),
                    ),
                    if (_selectedCardIds.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      // (#125) 선택 라운드에서는 아직 그 라운드 데이터가 없어 직전 라운드의 보유 자산을 보여준다
                      //        (기존에는 선택 라운드마다 보유 자산 칸이 사라졌다)
                      HoldingCardsWidget(
                        cards:            _holdingCards,
                        triggeredCardIds: _triggeredCardIds,
                        holdings:         _currentRound.holdings,
                        cashWeight:       _currentRound.cashWeight,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            _buildBottomBar(),
          ],
        ),
            // (장면 개편) 선택해야 하는 순간: 시작 브리핑 / 카드 선택 / 위기 대응
            _buildSceneLayer(),
            // 고른 직후 확인 카드
            Positioned.fill(child: _buildFlash()),
          ],
        ),
      ),
    ),
    );
  }

  // ── 헤더 + 라운드 진행 바 ──────────────────
  Widget _buildHeader() {
    final total = _session.totalRounds <= 0 ? 1 : _session.totalRounds;
    final progress = (_currentRound1 / total).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 20, 10),
      child: Column(
        children: [
          Row(
            children: [
              Semantics(
                button: true,
                label: '뒤로 가기',
                excludeSemantics: true,
                onTap: () => Navigator.maybePop(context),
                child: Pressable(
                  onTap: () => Navigator.maybePop(context),   // 게임 중이면 PopScope가 한 번 묻는다
                  haptic: false,
                  child: const Padding(
                    padding: EdgeInsets.all(10),
                    child: Icon(Icons.arrow_back_ios_new_rounded,
                        size: 20, color: TossColors.grey900),
                  ),
                ),
              ),
              Expanded(
                child: Text(_session.scenarioTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: TossColors.grey900)),
              ),
              // (#125) 자동 진행 배속
              if (!_notStarted) ...[
                Pressable(
                  onTap: _cycleSpeed,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: _speed > 1 ? TossColors.blue50 : TossColors.grey200,
                      borderRadius: BorderRadius.circular(TossRadius.sm),
                    ),
                    child: Text('×$_speed',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _speed > 1
                                ? TossColors.blue600
                                : TossColors.grey700)),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Text('$_currentRound1',
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: TossColors.blue500,
                      fontFeatures: [FontFeature.tabularFigures()])),
              Text(' / ${_session.totalRounds} 라운드',
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: TossColors.grey500)),
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: progress),
                duration: TossMotion.base,
                curve: TossMotion.enter,
                builder: (_, v, __) => LinearProgressIndicator(
                  value: v,
                  minHeight: 3,
                  backgroundColor: TossColors.grey200,
                  valueColor:
                      const AlwaysStoppedAnimation(TossColors.blue500),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 점수판: 내 자산 vs 시장 + 두 선 차트 ─────────
  //  (게임 장면 개편) 내 자산 옆에 S&P500과 "시장보다 x%p 앞서요"를 붙여 게임 점수처럼 읽히게.
  //  차트는 내 자산·S&P500 두 선만 (범례·뉴스 점 없음). 종목별 흐름은 아래 링크로 시트에서 본다
  //  (기존: 범례 5개 + 종목 칩 6개가 차트 아래에 붙어 진행 화면을 스크롤해야 했다)
  Widget _buildSummary() {
    final asset   = _displayAsset;
    final initial = _session.initialAsset.toDouble();
    final rate    = _currentRound.returnRate;
    final diff    = asset - initial;
    final spx     = _notStarted ? null : changeSinceStart(_displayRounds, '^SPX');
    final gap     = (rate == null || spx == null) ? null : rate - spx;

    return TossSection(
      padding: const EdgeInsets.fromLTRB(20, 18, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  '내 자산 · ${TodayMarketCard.koreanDate(_currentRound.date)} 종가',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TossText.sub,
                ),
              ),
              const SizedBox(width: 8),
              if (gap != null) _buildGapBadge(gap),
            ],
          ),
          const SizedBox(height: 2),
          RollingText('${formatWon(asset)}원',
              value: asset, style: TossText.display, duration: _rollDuration),
          const SizedBox(height: 2),
          if (rate == null)
            const Text('전략 카드를 고르면 투자가 시작돼요',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: TossColors.grey500))
          else
            Row(
              children: [
                // (#125) 퍼센트에도 부호를 붙인다 (기존: 손실일 때 "(20.95%)"로 표시)
                Flexible(
                  child: RollingText(
                    '${diff >= 0 ? '+' : '-'}${formatWon(diff.abs())}원 '
                    '(${formatSigned(rate, digits: 2)})',
                    value: asset,
                    duration: _rollDuration,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: TossColors.rate(rate),
                        fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                ),
                if (spx != null) ...[
                  const SizedBox(width: 10),
                  // 차트의 회색 점선이 S&P500 (범례 대신 숫자 옆에 같은 모양)
                  Container(width: 12, height: 2, color: TossColors.grey300),
                  const SizedBox(width: 4),
                  Text.rich(
                    TextSpan(children: [
                      const TextSpan(text: 'S&P500 '),
                      TextSpan(
                          text: formatSigned(spx),
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: TossColors.rate(spx))),
                    ]),
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: TossColors.grey600,
                        fontFeatures: [FontFeature.tabularFigures()]),
                  ),
                ],
              ],
            ),
          // (12주차) 첫 카드를 고르기 전에는 차트 없이 심플하게. 고르면 차트가 펼쳐짐
          AnimatedSize(
            duration: TossMotion.slow,
            curve: TossMotion.enter,
            alignment: Alignment.topCenter,
            child: _notStarted
                ? const SizedBox(width: double.infinity)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildTriggerNotice(),
                      SizedBox(
                        height: _chartHeight,
                        child: StockChart(
                          rounds:          _displayRounds,
                          initialAsset:    initial,
                          cardIndexes:     _cardIndexes,
                          decisionIndexes: _decisionIndexes,
                          extraTickers:    _overlayTickers,
                          compact:         true,
                        ),
                      ),
                      // 종목별 흐름 (갖고 있지 않은 종목도) — 시트에서 보고, 눌러서 차트에 겹쳐 본다
                      Align(
                        alignment: Alignment.centerRight,
                        child: Pressable(
                          onTap: _showSceneChartSheet,
                          haptic: false,
                          child: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                            child: Text('종목별 흐름 보기 ›',
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: TossColors.blue600)),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // "시장보다 22.8%p 앞서요" / "시장보다 3.1%p 뒤처져요"
  Widget _buildGapBadge(double gap) {
    final ahead = gap >= 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: ahead ? TossColors.blue50 : TossColors.grey100,
        borderRadius: BorderRadius.circular(TossRadius.sm),
      ),
      child: Text(
        ahead
            ? '시장보다 ${gap.toStringAsFixed(1)}%p 앞서요'
            : '시장보다 ${(-gap).toStringAsFixed(1)}%p 뒤처져요',
        style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: ahead ? TossColors.blue600 : TossColors.grey600),
      ),
    );
  }

  // ── 카드 발동 알림 (자동 매매가 일어난 라운드에 잠깐 표시) ──
  // 높이를 고정해 알림이 뜨고 사라져도 차트가 흔들리지 않게 함
  Widget _buildTriggerNotice() {
    final names = _triggeredCardIds
        .map((id) => CardInfo.fromId(id))
        .whereType<CardInfo>()
        .map((c) => '${c.emoji} ${c.name}')
        .join(' · ');
    // (#125) 우선순위: 방금 한 위기 대응(파랑) > 발동한 카드(주황) > 처음 건너뛴 카드의 이유(회색)
    final decided = _decisionNotice.isNotEmpty;
    final fired   = !decided && names.isNotEmpty;
    final text    = decided
        ? _decisionNotice
        : (names.isNotEmpty ? '$names 발동' : _skipNotice);
    return SizedBox(
      height: 34,
      child: Align(
        alignment: Alignment.centerLeft,
        child: AnimatedSwitcher(
          duration: TossMotion.fast,
          child: text.isEmpty
              ? const SizedBox.shrink()
              : Container(
                  key: ValueKey(text),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: decided
                        ? TossColors.blue50
                        : (fired ? const Color(0xFFFFF3E0) : TossColors.grey100),
                    borderRadius: BorderRadius.circular(TossRadius.sm),
                  ),
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: decided
                            ? TossColors.blue600
                            : (fired
                                ? const Color(0xFFC25E00)
                                : TossColors.grey600)),
                  ),
                ),
        ),
      ),
    );
  }

  // =============================================
  // (장면 개편) 장면 레이어
  //  선택해야 하는 순간에 게임 화면 전체를 덮는 장면이 뜬다 (같은 화면 안이라 뒤로 가기·상태 전달이 단순).
  //  ① 시작 브리핑(넘겨 보는 3장면) → ② 카드 선택(아래에서 올라옴) → 고르면 장면이 내려가고 게임이 이어진다.
  //  ③ 위기 대응은 '속보' 장면: 짧은 플래시와 함께 툭 내려앉는다.
  //  장면 위쪽에 라운드·날짜, 본문 첫머리에 내 자산·S&P500 흐름을 둬서 게임 맥락을 잃지 않게 한다.
  // =============================================
  bool get _showBriefing =>
      _notStarted && !_briefingDone && _session.briefing?.isEmpty == false;

  String get _sceneKey => _showBriefing
      ? 'brief'
      : _showCard
          ? 'card-$_currentRound1'
          : 'decision-$_currentRound1';

  Widget _buildSceneLayer() {
    final show = _showBriefing || _waiting;
    return Positioned.fill(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 뒤 배경 (게임 화면을 어둡게)
          IgnorePointer(
            ignoring: !show,
            child: AnimatedOpacity(
              opacity: show ? 1 : 0,
              duration: TossMotion.base,
              child: Container(color: Colors.black.withValues(alpha: 0.45)),
            ),
          ),
          AnimatedSwitcher(
            duration: TossMotion.slow,
            switchInCurve: TossMotion.enter,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, anim) {
              final k = child.key;
              // 속보: 살짝 크게 시작해 제자리로 '툭' + 페이드
              if (k is ValueKey<String> && k.value.startsWith('decision')) {
                return FadeTransition(
                  opacity: anim,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 1.06, end: 1).animate(anim),
                    child: child,
                  ),
                );
              }
              // 브리핑·카드 선택: 아래에서 올라옴
              return SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 1),
                  end: Offset.zero,
                ).animate(anim),
                child: child,
              );
            },
            layoutBuilder: (current, previous) => Stack(
              fit: StackFit.expand,
              children: [...previous, if (current != null) current],
            ),
            child: !show
                ? const SizedBox.shrink(key: ValueKey('scene-none'))
                : KeyedSubtree(
                    key: ValueKey(_sceneKey),
                    child: _showBriefing
                        ? BriefingScene(
                            briefing: _session.briefing!,
                            scenarioTitle: _session.scenarioTitle,
                            startDate: _session.rounds.isEmpty
                                ? ''
                                : _session.rounds.first.date,
                            onDone: () => setState(() => _briefingDone = true),
                          )
                        : _showCard
                            ? _buildCardScene()
                            : _buildDecisionScene(),
                  ),
          ),
        ],
      ),
    );
  }

  // 장면 오른쪽 위 닫기: 게임 나가기 (게임 중이면 PopScope가 한 번 묻는다)
  //  그림만 있는 버튼이라 화면 읽기 기능이 '게임 나가기'라고 읽도록 이름을 붙이고, 마우스를 올리면 알려 준다
  Widget _sceneClose({Color color = TossColors.grey500}) {
    return Tooltip(
      message: '게임 나가기',
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        label: '게임 나가기',
        excludeSemantics: true,
        onTap: () => Navigator.maybePop(context),
        child: Pressable(
          onTap: () => Navigator.maybePop(context),
          haptic: false,
          child: const Padding(
            padding: EdgeInsets.all(8),
            child: Icon(Icons.close_rounded, size: 24, color: color),
          ),
        ),
      ),
    );
  }

  // "25라운드 · 3월 24일"
  String get _sceneWhen {
    final today = _todayMarket;
    return today == null
        ? '$_currentRound1라운드'
        : '$_currentRound1라운드 · ${TodayMarketCard.koreanDate(today.date)}';
  }

  // 차트에 겹쳐 볼 종목 켜고 끄기 (게임 화면·장면이 같은 선택을 쓴다)
  void _toggleOverlay(String ticker) {
    setState(() {
      final next = {..._overlayTickers};
      if (!next.remove(ticker)) next.add(ticker);
      _overlayTickers = next;
    });
  }

  // =============================================
  // (장면 단순화) 선택 장면의 '지금 상황' 칸 — 숫자 두 개 + 그래프 보기 버튼
  //  기존(#128): 진행 화면과 같은 그래프·종목 칩·내 자산 구성이 장면에 그대로 있어
  //   진행 화면과 헷갈리고, 한 장면을 보려면 스크롤해야 했다.
  //  선택 장면은 '고르는 곳'이라 그래프는 버튼으로 띄워 본다 (진행 화면은 '흐름을 보는 곳').
  //  종목 흐름은 카드마다 붙은 "애플 · 게임 시작 후 -23.7%"와 오늘 시장 칸에서 계속 보인다.
  //  내 자산은 고른 뒤에 계산되므로 어제 종가까지, S&P500은 오늘 종가까지라 날짜를 함께 적는다.
  // =============================================
  Widget _buildSceneStatus({bool dark = false}) {
    final asset    = _displayAsset;
    final rate     = _currentRound.returnRate ?? 0;
    final cash     = _currentRound.cashWeight;
    final spxMove  = changeSinceStart(_displayRounds, '^SPX');
    final today    = _todayMarket;
    final assetDay = TodayMarketCard.koreanDate(_currentRound.date);

    final ink  = dark ? TossColors.white : TossColors.grey900;
    final soft = dark ? TossColors.grey400 : TossColors.grey500;
    Color rateColor(double v) =>
        dark ? DecisionSelector.darkRate(v) : TossColors.rate(v);

    Widget label(String text, String day) => Wrap(
          spacing: 4,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(text, style: TossText.small.copyWith(color: soft)),
            Text(day,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: soft)),
          ],
        );

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        color: dark ? TossColors.white.withValues(alpha: 0.07) : TossColors.grey50,
        borderRadius: BorderRadius.circular(TossRadius.lg),
        border: dark
            ? Border.all(color: TossColors.white.withValues(alpha: 0.12))
            : null,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                label('내 자산', '$assetDay 종가'),
                const SizedBox(height: 2),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(
                        text: formatShortWon(asset),
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: ink)),
                    TextSpan(
                        text: '  ${formatSigned(rate)}',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: rateColor(rate))),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (cash != null)
                  Text('현금 ${cash.toStringAsFixed(0)}%',
                      style: TossText.small.copyWith(color: soft)),
              ],
            ),
          ),
          if (spxMove != null)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  label('S&P500 시작 후',
                      today == null ? '' : '${TodayMarketCard.koreanDate(today.date)}까지'),
                  const SizedBox(height: 2),
                  Text(formatSigned(spxMove),
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: rateColor(spxMove),
                          fontFeatures: const [FontFeature.tabularFigures()])),
                ],
              ),
            ),
          // 그래프 보기 — 누르면 아래에서 그래프·종목 칩·내 자산 구성이 올라온다
          Tooltip(
            message: '그래프 보기',
            child: Pressable(
              onTap: _showSceneChartSheet,
              child: Container(
                width: 52,
                height: 48,
                decoration: BoxDecoration(
                  color: dark
                      ? TossColors.white.withValues(alpha: 0.1)
                      : TossColors.white,
                  borderRadius: BorderRadius.circular(TossRadius.md),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.show_chart_rounded,
                        size: 20,
                        color: dark ? const Color(0xFF6EA8FF) : TossColors.blue500),
                    Text('그래프',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: dark ? const Color(0xFF6EA8FF) : TossColors.blue600)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 오늘 시장 한 줄: 날씨 그림 + 그날 S&P500 등락 (다른 종목의 오늘 등락은 카드마다 붙는다)
  Widget _buildTodayLine(RoundData today) {
    final spx  = today.getPrice('^SPX');
    final mood = spx == null ? null : MarketMood.day(spx.changeRate);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
      decoration: BoxDecoration(
        color: TossColors.grey50,
        borderRadius: BorderRadius.circular(TossRadius.lg),
      ),
      child: Row(
        children: [
          if (mood != null) ...[
            MoodHero(mood: mood, size: 40),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('오늘 ${TodayMarketCard.koreanDate(today.date)} 시장',
                    style: TossText.small),
                if (spx != null)
                  Text.rich(
                    TextSpan(children: [
                      const TextSpan(text: 'S&P500 '),
                      TextSpan(
                          text: formatSigned(spx.changeRate),
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: TossColors.rate(spx.changeRate))),
                      if (mood != null)
                        TextSpan(
                            text: ' · ${mood.line}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w500,
                                color: TossColors.grey600)),
                    ]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: TossColors.grey900),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 그래프 시트: 진행 화면과 같은 그래프 + 종목 칩(누르면 겹쳐 보기, 게임 화면과 같이 씀) + 내 자산 구성
  void _showSceneChartSheet() {
    showTossSheet(
      context,
      title: '지금까지 흐름',
      confirmLabel: '닫기',
      body: StatefulBuilder(
        builder: (context, setSheet) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 200,
              child: StockChart(
                rounds:          _displayRounds,
                initialAsset:    _session.initialAsset.toDouble(),
                cardIndexes:     _cardIndexes,
                decisionIndexes: _decisionIndexes,
                extraTickers:    _overlayTickers,
              ),
            ),
            MarketChips(
              rounds:   _displayRounds,
              selected: _overlayTickers,
              onToggle: (t) {
                _toggleOverlay(t);
                setSheet(() {});
              },
            ),
            const SizedBox(height: 14),
            _buildSceneHoldings(_displayAsset),
          ],
        ),
      ),
    );
  }

  // 장면 그래프 칸 안 '내 자산 구성': 종목마다 금액·비중, 마지막에 현금
  //  금액은 서버가 보낸 평가금액(value)과 현금(cash). 그래프 위 '내 자산'과 같은 날(전날 종가) 기준
  Widget _buildSceneHoldings(double asset) {
    final holdings = [..._currentRound.holdings]
      ..sort((a, b) => b.value.compareTo(a.value));
    final cashWeight = _currentRound.cashWeight;
    final cash = _currentRound.cash ??
        (cashWeight == null ? null : asset * cashWeight / 100);
    if (holdings.isEmpty && cash == null) return const SizedBox.shrink();

    Widget dot(Color color) => Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        );

    Widget pill(Color color, String name, double value, double? weight) =>
        Container(
          padding: const EdgeInsets.fromLTRB(8, 5, 10, 5),
          decoration: BoxDecoration(
            color: TossColors.white,
            borderRadius: BorderRadius.circular(TossRadius.sm + 2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              dot(color),
              const SizedBox(width: 6),
              Text(name,
                  style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: TossColors.grey700)),
              const SizedBox(width: 6),
              Text(formatShortWon(value),
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: TossColors.grey900,
                      fontFeatures: [FontFeature.tabularFigures()])),
              if (weight != null) ...[
                const SizedBox(width: 4),
                Text('${weight.toStringAsFixed(0)}%',
                    style: const TextStyle(
                        fontSize: 11.5, color: TossColors.grey500)),
              ],
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('내 자산 구성', style: TossText.small),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final h in holdings)
              pill(kTickerColors[h.ticker] ?? TossColors.grey500,
                  tickerName(h.ticker), h.value, h.weight),
            if (cash != null)
              pill(TossColors.grey300, '현금', cash, cashWeight),
            if (holdings.isEmpty)
              const Text('아직 산 종목은 없어요', style: TossText.small),
          ],
        ),
      ],
    );
  }

  // ── 카드 선택 장면 ─────────────────────────
  //  (게임 장면 개편) 후보 카드 3장이 한 장씩 날아와 부채꼴로 펼쳐진다. 누른 카드가 떠오르고
  //  아래 칸이 그 카드의 설명·종목 흐름으로 바뀐다. 그 아래 AI 비교 한 줄, 맨 아래 확정 버튼.
  //  카드 칸이 남은 높이를 채우고 카드 크기를 거기에 맞추므로 어떤 화면에서도 스크롤이 없다
  //  (기존: 카드 3장이 목록 한 줄씩이라 게임 같지 않았다)
  Widget _buildCardScene() {
    final n     = _selectedCardIds.length;
    final ord   = n < _ordinals.length ? _ordinals[n] : '다음';
    final today = _todayMarket;
    final count = _currentCardOptions.length;

    return RevealScope(
      child: SceneSheet(
      fullScreen: true,
      scrollBody: false,
      tag: SceneTag('🃏 $_sceneWhen',
          bg: TossColors.blue50, fg: TossColors.blue600),
      trailing: _sceneClose(),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Reveal(
              order: 0,
              child: Text('$ord 전략을 골라주세요', style: TossText.title2),
            ),
            const SizedBox(height: 12),
            if (!_notStarted) ...[
              Reveal(order: 1, child: _buildSceneStatus()),
              const SizedBox(height: 8),
            ],
            // (#125) 오늘 시장 — 그날 종가로 매매하므로 그날 움직임을 보고 고른다
            if (today != null) ...[
              Reveal(order: 2, child: _buildTodayLine(today)),
              const SizedBox(height: 8),
            ],
            // (#125) 현금이 총자산의 5%보다 적으면 사는 카드는 발동하지 않는다 — 고르기 전에 알려 준다
            if (_cashLow) ...[
              Text(
                '현금이 총자산의 5%보다 적어요 (지금 ${(_currentRound.cashWeight ?? 0).toStringAsFixed(1)}%). '
                '사는 카드는 지금 발동하지 않아요.',
                style: const TextStyle(
                    fontSize: 13, height: 1.4, color: Color(0xFFC25E00)),
              ),
              const SizedBox(height: 8),
            ],
            // (11주차) 오늘 나온 뉴스 — 한 줄로 (누르면 전부)
            if (_selectNews.isNotEmpty) ...[
              _buildSelectNews(),
              const SizedBox(height: 8),
            ],
            Expanded(child: _buildCardFan()),
            const SizedBox(height: 10),
            Reveal(order: 3 + count * 2, child: _buildCardDetail()),
            const SizedBox(height: 8),
            // AI 비교 한 줄: 25·50라운드만. 1·75라운드는 제공하지 않는 이유를 한 줄로
            if (_canUseV2)
              Reveal(order: 4 + count * 2, child: _buildAiHelper())
            else if (_noAiReason != null)
              Reveal(
                order: 4 + count * 2,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(_noAiReason!, style: TossText.small),
                ),
              ),
          ],
        ),
      ),
      bottom: Reveal(order: 5 + count * 2, child: _buildConfirmButton()),
    ),
    );
  }

  // 후보 카드 부채꼴: 가운데 카드가 위, 고른 카드는 맨 위로 떠오른다
  Widget _buildCardFan() {
    final cards = [
      for (final id in _currentCardOptions)
        if (CardInfo.fromId(id) case final c?) c,
    ];
    if (cards.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(builder: (context, box) {
      final n   = cards.length;
      final w   = box.maxWidth;
      final h   = box.maxHeight;
      final mid = (n - 1) / 2;
      // 카드 크기: 폭으로 3장이 조금 겹치게, 높이로는 칸 안에 들어가게
      final byWidth  = w / (n * 0.82 + 0.18);
      final byHeight = (h - 28) / 1.42;
      final cardW = math.min(math.min(byWidth, byHeight), 150.0).clamp(72.0, 150.0);
      final cardH = cardW * 1.42;
      final step  = n == 1 ? 0.0 : math.min(cardW * 0.9, (w - cardW) / (n - 1));
      final left0 = (w - (cardW + step * (n - 1))) / 2;
      final top0  = math.max(0.0, (h - cardH - cardW * 0.1) / 2 + 6);

      final picked = cards.indexWhere((c) => c.id == _pendingCardId);
      int depth(int i) => i == picked ? 2 : (i == mid.round() ? 1 : 0);
      final order = List.generate(n, (i) => i)
        ..sort((a, b) => depth(a).compareTo(depth(b)));

      return Stack(
        clipBehavior: Clip.none,
        children: [
          for (final i in order)
            Positioned(
              key: ValueKey('fan-${cards[i].id}'),
              left: left0 + step * i,
              top: top0 + (i - mid).abs() * cardW * 0.1,
              width: cardW,
              height: cardH,
              // 한 장씩 아래에서 날아온다
              child: Reveal(
                order: 3 + i * 2,
                rise: 120,
                child: Transform.rotate(
                  angle: (i - mid) * 0.12,
                  child: _buildFanCard(cards[i], cardW, picked >= 0 && picked != i),
                ),
              ),
            ),
        ],
      );
    });
  }

  Widget _buildFanCard(CardInfo card, double w, bool dimmed) {
    final selected = _pendingCardId == card.id;
    final aiPick   = _aiRecommendedCardId == card.id;
    final tint     = kTickerColors[priceTicker(card.ticker)] ?? TossColors.blue500;

    return Pressable(
      onTap: _isSubmitting
          ? null
          : () => setState(() => _pendingCardId = card.id),
      scale: 0.97,
      child: AnimatedSlide(
        offset: Offset(0, selected ? -0.07 : 0),
        duration: TossMotion.base,
        curve: TossMotion.spring,
        child: AnimatedScale(
          scale: selected ? 1.06 : 1,
          duration: TossMotion.base,
          curve: TossMotion.spring,
          child: AnimatedOpacity(
            opacity: dimmed ? 0.8 : 1,
            duration: TossMotion.base,
            child: AnimatedContainer(
              duration: TossMotion.base,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: TossColors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: selected ? TossColors.blue500 : TossColors.grey200,
                  width: selected ? 2 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: selected
                        ? TossColors.blue500.withValues(alpha: 0.25)
                        : Colors.black.withValues(alpha: 0.07),
                    blurRadius: selected ? 22 : 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        height: w * 0.66,
                        alignment: Alignment.center,
                        color: tint.withValues(alpha: 0.12),
                        child: Text(card.emoji,
                            style: TextStyle(fontSize: w * 0.3)),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                          // 작은 화면에서는 글자를 줄여 카드 안에 넣는다 (넘치지 않게)
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.topLeft,
                            child: SizedBox(
                              width: w - 20,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(card.name,
                                      maxLines: 2,
                                      style: const TextStyle(
                                          fontSize: 15,
                                          height: 1.3,
                                          fontWeight: FontWeight.w800,
                                          color: TossColors.grey900)),
                                  const SizedBox(height: 2),
                                  Text(tickerName(card.ticker),
                                      maxLines: 1,
                                      style: TossText.small),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (aiPick)
                    const Positioned(
                      top: 8,
                      left: 8,
                      child: TossBadge(
                          label: 'AI 1위',
                          bg: TossColors.blue500,
                          fg: TossColors.white),
                    ),
                  if (selected)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: const BoxDecoration(
                            color: TossColors.blue500, shape: BoxShape.circle),
                        child: const Icon(Icons.check_rounded,
                            size: 15, color: TossColors.white),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 고른 카드의 설명 + 이 카드 종목의 오늘·게임 시작 후 등락 (고르기 전에는 안내 한 줄)
  //  높이를 넉넉히 잡아 두어 카드를 바꿔 눌러도 위의 카드 크기가 흔들리지 않게 한다
  Widget _buildCardDetail() {
    final card = _pendingCardId == null ? null : CardInfo.fromId(_pendingCardId!);
    // (#125) 이 카드가 사고파는 종목이 게임 시작 후 얼마나 움직였는지 (갖고 있지 않아도 보고 고를 수 있게)
    //        1라운드는 시작 전 브리핑에 직전 20거래일 등락이 있다
    final moved = (card == null || _notStarted)
        ? null
        : changeSinceStart(_displayRounds, card.ticker);
    final todayMove = card == null
        ? null
        : _todayMarket?.getPrice(priceTicker(card.ticker))?.changeRate;

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 92),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: TossColors.grey50,
          borderRadius: BorderRadius.circular(TossRadius.lg),
        ),
        child: AnimatedSwitcher(
          duration: TossMotion.base,
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.topLeft,
            children: [...previous, if (current != null) current],
          ),
          child: card == null
              ? const SizedBox(
                  key: ValueKey('detail-none'),
                  width: double.infinity,
                  child: Text('카드를 눌러 어떤 전략인지 살펴보세요',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: TossColors.grey500)),
                )
              : SizedBox(
                  key: ValueKey('detail-${card.id}'),
                  width: double.infinity,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(card.description.replaceAll('\n', ' '),
                          style: const TextStyle(
                              fontSize: 16,
                              height: 1.45,
                              fontWeight: FontWeight.w700,
                              color: TossColors.grey900)),
                      if (todayMove != null || moved != null) ...[
                        const SizedBox(height: 6),
                        Text.rich(
                          TextSpan(children: [
                            TextSpan(text: todayMove != null
                                ? '${tickerName(card.ticker)} 오늘 '
                                : '${tickerName(card.ticker)} · '),
                            if (todayMove != null)
                              TextSpan(
                                  text: formatSigned(todayMove),
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: TossColors.rate(todayMove))),
                            if (moved != null) ...[
                              TextSpan(text: todayMove != null ? ' · 시작 후 ' : '시작 후 '),
                              TextSpan(
                                  text: formatSigned(moved),
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: TossColors.rate(moved))),
                            ],
                          ]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13, color: TossColors.grey700),
                        ),
                      ],
                      // (#125) 팔 S&P500이 없으면 이 카드는 발동해도 아무 일도 일어나지 않는다
                      if (card.id == 8 && !_holdsSpx) ...[
                        const SizedBox(height: 4),
                        const Text('지금은 가진 S&P500이 없어요 · S&P500을 사는 카드와 함께 쓰세요',
                            style: TextStyle(
                                fontSize: 12.5,
                                height: 1.4,
                                color: Color(0xFFC25E00))),
                      ],
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  // AI 비교 한 줄 (25·50라운드): 물어보기 → 비교 중 → "AI는 ○○를 골랐어요" + 이유 보기
  Widget _buildAiHelper() {
    final pickId = _aiRecommendedCardId;
    final pick   = pickId == null ? null : CardInfo.fromId(pickId);
    final text = switch (_aiState) {
      AiState.idle    => 'AI에게 ${_currentCardOptions.length}장을 비교해 달라고 할까요?',
      AiState.loading => '과거 시장으로 비교하고 있어요',
      AiState.done    => pick == null
          ? 'AI가 비교를 마쳤어요'
          : 'AI는 ${pick.name}${_josa(pick.name, '을', '를')} 골랐어요',
      AiState.error   => '예측을 받지 못했어요',
    };
    final Widget button = switch (_aiState) {
      AiState.idle => TossChipButton(
          label: '물어보기', onTap: _requestAiRecommendation),
      AiState.loading => const TossChipButton(
          label: '비교 중',
          leading: SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
                strokeWidth: 1.8,
                valueColor: AlwaysStoppedAnimation(TossColors.blue600)),
          ),
        ),
      AiState.done => TossChipButton(label: '이유 보기', onTap: _showAiSheet),
      AiState.error => TossChipButton(
          label: '다시 시도',
          onTap: _requestAiRecommendation,
          bg: TossColors.red50,
          fg: TossColors.red500,
          leading: const Icon(Icons.refresh_rounded,
              size: 14, color: TossColors.red500),
        ),
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: TossColors.grey50,
        borderRadius: BorderRadius.circular(TossRadius.lg),
      ),
      child: Row(
        children: [
          const EmojiTile(emoji: '✨', size: 30, bg: TossColors.blue50),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: TossColors.grey800)),
          ),
          const SizedBox(width: 6),
          button,
        ],
      ),
    );
  }

  // 받침 따라 조사 고르기: 원유 베팅'을' / 금 피난처'를'
  static String _josa(String word, String withBatchim, String without) {
    if (word.isEmpty) return without;
    final c = word.codeUnitAt(word.length - 1);
    if (c < 0xAC00 || c > 0xD7A3) return without;
    final jong = (c - 0xAC00) % 28;
    if (withBatchim == '으로') return (jong == 0 || jong == 8) ? '로' : '으로';
    return jong == 0 ? without : withBatchim;
  }

  // ── 위기 대응 장면 ─────────────────────────
  //  (게임 장면 개편) 어두운 화면이 빨갛게 번쩍이며 시작하고, 맨 위에 속보 띠가 흐른다.
  //  헤드라인 → 그날 S&P500 하루 등락을 크게 → 내 상황 → 선택지가 한 장씩 올라온다
  //  (기존: 흰 시트 안의 속보 카드라 다른 선택 화면과 느낌이 같았다)
  Widget _buildDecisionScene() {
    final prompt = _decisionPrompt?.round == _currentRound1 ? _decisionPrompt : null;
    final level  = prompt?.news.level;
    final good   = level == 'positive';
    final today  = _todayMarket;
    final spxDay = today?.getPrice('^SPX')?.changeRate;

    final flash = switch (level) {
      'danger'   => const Color(0xFFE5333F),
      'positive' => TossColors.green500,
      _          => TossColors.grey500,
    };
    // 속보 띠: 이 속보 + 같은 날 다른 뉴스
    final band = [
      if (prompt != null) prompt.news.headline,
      for (final n in _selectNews) n.headline,
    ].join('   ·   ');

    final sheet = SceneSheet(
      fullScreen: true,
      color: _darkScene,
      header: band.isEmpty
          ? null
          : Container(
              height: 34,
              color: flash,
              padding: const EdgeInsets.only(left: 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: TossColors.white,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(good ? '희소식' : '속보',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: flash)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Marquee(
                      text: band,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: TossColors.white),
                    ),
                  ),
                ],
              ),
            ),
      tag: good
          ? SceneTag('📣 $_sceneWhen · 기회',
              bg: TossColors.green500.withValues(alpha: 0.18),
              fg: const Color(0xFF5BE0A6))
          : SceneTag('🚨 $_sceneWhen · 위기 대응',
              bg: TossColors.white.withValues(alpha: 0.1),
              fg: TossColors.white),
      trailing: _sceneClose(color: TossColors.grey400),
      body: DecisionSelector(
        prompt:        prompt,
        otherNews:     _selectNews,
        selected:      _pendingChoice,
        hasHoldings:   _hasHoldings,
        hasCash:       _hasCash,
        buyMoreTarget: _session.buyMoreTarget,
        enabled:       !_isSubmitting,
        dayMove:       spxDay,
        onSelect: (c) => setState(() => _pendingChoice = c),
        info: _buildSceneStatus(dark: true),
      ),
      bottom: Reveal(order: 10, child: _buildDecisionButton()),
    );

    // 속보가 뜰 때 화면 전체가 한 번 번쩍 (위험 빨강 / 긍정 초록) → 0.7초 동안 사라짐
    return RevealScope(
      child: Stack(
        fit: StackFit.expand,
        children: [
          sheet,
          IgnorePointer(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 1, end: 0),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (_, v, __) =>
                  Container(color: flash.withValues(alpha: 0.6 * v)),
            ),
          ),
        ],
      ),
    );
  }

  static const _darkScene = Color(0xFF17171C);

  // ── 카드 선택 라운드의 뉴스: 한 줄 (같은 날 뉴스가 더 있으면 "외 n개", 누르면 전부) ──
  Widget _buildSelectNews() {
    final n  = _selectNews.first;
    final st = NewsStyle.of(n.level);
    final more = _selectNews.length - 1;
    return Pressable(
      onTap: () => showNewsLogSheet(context, _selectNews),
      haptic: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 9, 12, 9),
        decoration: BoxDecoration(
          color: TossColors.grey50,
          borderRadius: BorderRadius.circular(TossRadius.lg),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: st.softBg,
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(st.label,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: st.softFg)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(n.headline,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: TossColors.grey900)),
            ),
            if (more > 0) ...[
              const SizedBox(width: 6),
              Text('외 $more개', style: TossText.small),
            ],
          ],
        ),
      ),
    );
  }

  // ── 하단 고정 버튼 ─────────────────────────
  Widget _buildBottomBar() {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Container(
      color: TossColors.background,
      padding: EdgeInsets.fromLTRB(16, 8, 16, 12 + bottomInset),
      // 카드·위기 대응의 확정 버튼은 장면 시트 아래에 있다
      child: _buildControls(),
    );
  }

  // (#125) 위기 대응 확정
  Widget _buildDecisionButton() {
    final picked = _pendingChoice;
    return TossButton(
      label: picked == null ? '대응을 골라주세요' : '이렇게 할게요',
      loading: _isSubmitting,
      onTap: picked == null ? null : () => _onDecisionSelected(picked),
    );
  }

  Widget _buildConfirmButton() {
    final picked = _pendingCardId;
    return TossButton(
      label: picked == null ? '전략을 골라주세요' : '이 전략으로 할게요',
      loading: _isSubmitting,
      onTap: picked == null ? null : () => _onCardSelected(picked),
    );
  }

  // 진행 중: 일시정지/이어서 버튼 하나. 마지막 라운드: 결과 보기
  // (12주차) 다음 라운드 버튼 제거 — 카드를 고르면 자동으로 넘어감
  Widget _buildControls() {
    if (_isLastRound) {
      return TossButton(label: '결과 보기', onTap: _goToResult);
    }
    return TossButton(
      label: _isAutoPlaying ? '잠시 멈추기' : '이어서 진행하기',
      type: _isAutoPlaying ? TossButtonType.secondary : TossButtonType.primary,
      icon: Icon(
        _isAutoPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
        size: 22,
        color: _isAutoPlaying ? TossColors.grey700 : TossColors.white,
      ),
      onTap: _isAutoPlaying ? _stopAutoPlay : _startAutoPlay,
    );
  }
}
