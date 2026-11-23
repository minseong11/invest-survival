import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/game_session.dart';
import '../models/round_data.dart';
import '../models/action_result.dart';
import '../models/card_info.dart';
import '../models/fixed_ranking.dart';
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
  Map<int, double> _contributions       = {};
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

  // (#125) 카드 장면의 오늘 시장 안내. 위기 대응은 선택지 아래에 이미 '오늘 종가로 바로 매매' 안내가 있고,
  //        AI 예측도 오늘 종가까지 본다는 말은 25·50라운드의 AI 참고용 안내에 있다
  String? get _todayCaption => _showCard ? '고른 카드는 오늘 종가부터 작동해요' : null;

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
      _contributions       = {};
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
      final contribs = <int, double>{};
      for (final r in result.rankings) {
        contribs[r.cardId] = r.contribution;
      }
      setState(() {
        _v2RecommendedCardId = result.recommendedCardId;
        _aiPicks[_currentRound1] = result.recommendedCardId;
        _contributions       = contribs;
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
    _contributions       = {};
    _aiFeedback          = '';
    _lastRankings        = [];
    _pendingCardId       = null;
    _pendingChoice       = null;
  }

  // =============================================
  // AI 피드백 버튼 클릭 → 이미 받아온 feedback을 다이얼로그로 표시
  // (별도 API 호출 없음. getV2Recommendation 응답에 이미 포함돼 있음)
  // =============================================
  void _onFeedbackButtonTap() {
    if (_aiState != AiState.done || _aiFeedback.isEmpty) {
      showTossToast(context, '먼저 AI 예측을 받아주세요');
      return;
    }
    _showFeedbackDialog();
  }

  // =============================================
  // AI 설명 시트 (12주차: 한눈에 보이게)
  //  ① 후보 3장 예측 순위 (막대)  ② 왜 그런지 짧은 설명  ③ 카드 규칙  ④ 참고용 안내
  //  서버 feedback 중 "카드 규칙 · " 줄은 따로 떼어 회색 상자에 넣는다
  // =============================================
  void _showFeedbackDialog() {
    if (_aiFeedback.isEmpty) return;

    final lines = _aiFeedback
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    // 서버가 보내는 3줄 구조: "지금 시장: …" / "이 카드는: …" / "그래서: …"
    String? pick(String head) {
      for (final l in lines) {
        if (l.startsWith('$head: ')) return l.substring(head.length + 2);
      }
      return null;
    }

    final market = pick('지금 시장');
    final cardIs = pick('이 카드는');
    final so     = pick('그래서');
    final ruleLines =
        lines.where((l) => l.startsWith('카드 규칙 · ')).toList();
    final structured = market != null || cardIs != null || so != null;
    // 예전 서버(긴 글 한 덩어리)와도 호환
    final legacy = structured
        ? ''
        : lines.where((l) => !l.startsWith('카드 규칙 · ')).join('\n');

    final ranked = [..._lastRankings]..sort((a, b) => a.rank.compareTo(b.rank));
    final double maxAbs = ranked.isEmpty
        ? 1.0
        : ranked
            .map((r) => r.contribution.abs())
            .reduce((a, b) => a > b ? a : b)
            .clamp(0.1, double.infinity)
            .toDouble();
    final topCard =
        ranked.isEmpty ? null : CardInfo.fromId(ranked.first.cardId);

    showTossSheet(
      context,
      title: topCard == null
          ? 'AI는 이 카드를 골랐어요'
          : 'AI의 선택은\n${topCard.emoji} ${topCard.name}',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ① 왜? — 근거 3줄 (시장·카드는 프로그램이, '그래서'만 AI가 씀)
          if (market != null) _buildReasonRow('📉', '지금 시장', market),
          if (cardIs != null)
            _buildReasonRow(topCard?.emoji ?? '🃏', '이 카드는', cardIs),
          if (so != null) _buildReasonRow('💡', '그래서', so, highlight: true),
          if (legacy.isNotEmpty)
            Text(legacy,
                style: const TextStyle(
                    fontSize: 16, height: 1.6, color: TossColors.grey800)),

          // ② 후보 3장 예측 비교
          const SizedBox(height: 16),
          const Text('후보 카드 예측 비교', style: TossText.small),
          const SizedBox(height: 4),
          for (final r in ranked) _buildRankBar(r, maxAbs),
          const SizedBox(height: 4),
          // (#125) 이 숫자는 최종 수익률 예측이 아니라 "아직 고르지 않은 카드 전체"의 평균과의 차이
          //        (학습 라벨 Card_Contribution = 이 카드를 골랐을 때 최종 수익률 − 고를 수 있는 카드 전체의 평균,
          //         monte_carlo_v2.py). 지금 나온 후보 3장의 평균이 아니므로 세 값을 더해도 0이 아니다
          const Text(
            '숫자는 아직 고르지 않은 카드 전체의 평균과 비교한 예상 차이(%p)예요. 최종 수익률을 예측한 값이 아니에요.',
            style: TossText.small,
          ),

          // ③ 정확한 카드 규칙
          if (ruleLines.isNotEmpty) ...[
            const SizedBox(height: 12),
            InfoBox(
              child: Text(
                ruleLines.map((l) => l.replaceFirst('카드 규칙 · ', '')).join('\n'),
                style: TossText.caption.copyWith(color: TossColors.grey700),
              ),
            ),
          ],

          // ④ 평소 순위와 나란히 (12주차 피드백 2번)
          if (_fixedOrder.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text.rich(
              TextSpan(children: [
                const TextSpan(
                    text: '평소 순위  ',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(
                    text: _fixedOrder
                        .map((id) => CardInfo.fromId(id)?.name ?? '카드 $id')
                        .join(' › ')),
              ]),
              style: TossText.caption.copyWith(color: TossColors.grey700),
            ),
          ],

          // ⑤ 참고용 안내 (평가 결과 반영)
          const SizedBox(height: 8),
          const Text(
            'AI 예측은 과거 시장으로 학습한 참고용이에요. S&P500의 흐름과 고른 카드만 보고 판단하고, '
            '처음 보는 시장 테스트에서는 평소 순위보다 낫지 않았어요.',
            style: TossText.small,
          ),
        ],
      ),
    );
  }

  // 근거 한 줄: 아이콘 칸 + 작은 머리말 + 본문
  Widget _buildReasonRow(String emoji, String head, String body,
      {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EmojiTile(
            emoji: emoji,
            size: 40,
            bg: highlight ? TossColors.blue50 : TossColors.grey100,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(head,
                    style: TossText.small.copyWith(
                        color: highlight
                            ? TossColors.blue600
                            : TossColors.grey500)),
                const SizedBox(height: 1),
                Text(body,
                    style: TextStyle(
                        fontSize: 16,
                        height: 1.4,
                        fontWeight:
                            highlight ? FontWeight.w700 : FontWeight.w500,
                        color: TossColors.grey900)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRankBar(CardRanking r, double maxAbs) {
    final card  = CardInfo.fromId(r.cardId);
    final first = r.rank == 1;
    final ratio = (r.contribution.abs() / maxAbs).clamp(0.0, 1.0);
    final color = first ? TossColors.blue500 : TossColors.grey300;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 116,
            child: Row(
              children: [
                Text(card?.emoji ?? '🃏', style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    card?.name ?? r.cardName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: first ? FontWeight.w700 : FontWeight.w500,
                        color: first ? TossColors.grey900 : TossColors.grey600),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // (#125) 가운데 기준선(카드 전체 평균)에서 +는 오른쪽, -는 왼쪽으로 뻗는다
          //        (기존에는 절댓값 길이라 -0.4%가 +0.3%보다 길게 보였다)
          Expanded(
            child: LayoutBuilder(
              builder: (_, c) {
                final half = c.maxWidth / 2;
                final len  = (half * ratio).clamp(2.0, half).toDouble();
                final up   = r.contribution >= 0;
                return SizedBox(
                  height: 14,
                  child: Stack(
                    children: [
                      Positioned(
                        left: half - 0.5,
                        top: 0,
                        bottom: 0,
                        child: Container(width: 1, color: TossColors.grey300),
                      ),
                      Positioned(
                        left: up ? half : half - len,
                        top: 2,
                        child: Container(
                          height: 10,
                          width: len,
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.horizontal(
                              left: Radius.circular(up ? 0 : 5),
                              right: Radius.circular(up ? 5 : 0),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 58,
            child: Text(
              formatSigned(r.contribution, unit: '%p'),
              textAlign: TextAlign.right,
              style: TossText.number.copyWith(
                  fontSize: 14, color: TossColors.rate(r.contribution)),
            ),
          ),
        ],
      ),
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

  // 진행 화면 그래프 높이: 화면 높이의 약 4분의 1 (작은 화면 190px ~ 큰 화면 280px)
  //  기존 190px 고정 — 종목 선을 여러 개 겹쳐 보면 빡빡했고, 키 큰 화면에서는 아래가 비었다.
  //  화면 크기로만 정하므로 게임 중에 보유 자산·카드가 늘어도 그래프 크기는 바뀌지 않는다
  double get _chartHeight =>
      (MediaQuery.sizeOf(context).height * 0.26).clamp(190.0, 280.0);

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
            // 최근 뉴스 칸 — 라운드 표시 바로 아래에 늘 자리를 차지한다 (아무것도 가리지 않음)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              child: NewsStrip(
                news:  _stripNews,
                count: _newsLog.length,
                fresh: _newsFresh,
                onTap: () => showNewsLogSheet(context, _newsLog),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildSummary(),
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

  // ── 자산 요약 + 차트 ───────────────────────
  Widget _buildSummary() {
    final asset   = _displayAsset;
    final initial = _session.initialAsset.toDouble();
    final rate    = _currentRound.returnRate;
    final diff    = asset - initial;

    return TossSection(
      padding: const EdgeInsets.fromLTRB(20, 20, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('총 자산', style: TossText.sub),
              const Spacer(),
              Text(_currentRound.date, style: TossText.small),
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
            // (#125) 퍼센트에도 부호를 붙인다 (기존: 손실일 때 "(20.95%)"로 표시)
            RollingText(
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
          // (12주차) 첫 카드를 고르기 전에는 차트 없이 심플하게. 고르면 차트가 펼쳐짐
          AnimatedSize(
            duration: TossMotion.slow,
            curve: TossMotion.enter,
            alignment: Alignment.topCenter,
            child: _notStarted
                ? const SizedBox(width: double.infinity)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
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
                        ),
                      ),
                      // (#125) 종목별 흐름 — 갖고 있지 않은 종목도 게임 시작 후 등락을 보고, 눌러서 차트에 겹쳐 본다
                      MarketChips(
                        rounds:   _displayRounds,
                        selected: _overlayTickers,
                        onToggle: _toggleOverlay,
                      ),
                    ],
                  ),
          ),
        ],
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
  Widget _sceneClose() {
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
            child: Icon(Icons.close_rounded, size: 24, color: TossColors.grey500),
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

  // 장면 안의 그래프: 진행 화면과 같은 그래프 + 종목 칩 (누르면 그 종목 선이 겹쳐짐)
  //  기존: 내 자산 숫자와 S&P500 작은 흐름선만 있어서, 카드·위기 대응을 고르는 순간에
  //        다른 종목의 흐름을 볼 수 없었다.
  //  내 자산은 고른 뒤에 계산되므로 어제 종가까지, S&P500·종목은 오늘 종가까지라 날짜를 함께 적는다
  //  (기존: "내 자산 +0.1%"와 "S&P500 -17.4%"가 기준 날짜 없이 나란히 있어 헷갈렸다)
  Widget _buildSceneChart({String? todayNote}) {
    final asset    = _displayAsset;
    final initial  = _session.initialAsset.toDouble();
    final rate     = _currentRound.returnRate ?? 0;
    final cash     = _currentRound.cashWeight;
    final rounds   = _displayRounds;
    final spxMove  = changeSinceStart(rounds, '^SPX');
    final today    = _todayMarket;
    final assetDay = TodayMarketCard.koreanDate(_currentRound.date);
    // 종목별 오늘 등락 — 종목 타일 안에 함께 보여 준다 ('오늘 시장' 칸을 한 줄로 줄이면서 옮김)
    final todayChanges = <String, double>{
      if (today != null)
        for (final t in kMarketTickers)
          if (today.getPrice(t) case final p?) t: p.changeRate,
    };

    Widget dayTag(String text) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: TossColors.white,
            borderRadius: BorderRadius.circular(TossRadius.sm),
          ),
          child: Text(text,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: TossColors.grey600)),
        );

    // (한 화면에) 내 자산·S&P500 두 줄 → 오늘 시장 한 줄 → 그래프 100px(범례 없이) → 종목 타일 3칸 × 2줄
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 10, 7),
      decoration: BoxDecoration(
        color: TossColors.grey50,
        borderRadius: BorderRadius.circular(TossRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 내 자산 쪽을 넓게 (반반이면 휴대폰 폭에서 "현금 / 52%"처럼 끊겼다)
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 좁은 화면에서는 날짜 표시가 다음 줄로 내려간다
                    Wrap(
                      spacing: 6,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text('내 자산', style: TossText.small),
                        dayTag('$assetDay 종가'),
                      ],
                    ),
                    const SizedBox(height: 2),
                    // 금액 옆에 수익률·현금 비중. 자리가 모자라면 수익률·현금이 통째로 다음 줄로
                    Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.end,
                      children: [
                        Text(formatShortWon(asset),
                            style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: TossColors.grey900,
                                fontFeatures: [FontFeature.tabularFigures()])),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 1),
                          child: Text(
                              cash == null
                                  ? formatSigned(rate)
                                  : '${formatSigned(rate)} · 현금 ${cash.toStringAsFixed(0)}%',
                              style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: TossColors.rate(rate),
                                  fontFeatures: const [FontFeature.tabularFigures()])),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (spxMove != null) ...[
                const SizedBox(width: 10),
                Flexible(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 6,
                        runSpacing: 2,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          const Text('S&P500', style: TossText.small),
                          if (today != null)
                            dayTag('${TodayMarketCard.koreanDate(today.date)}까지'),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text.rich(
                        TextSpan(children: [
                          TextSpan(
                              text: formatSigned(spxMove),
                              style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: TossColors.rate(spxMove))),
                          const TextSpan(
                              text: ' 시작 후',
                              style: TextStyle(
                                  fontSize: 11, color: TossColors.grey500)),
                        ]),
                        style: const TextStyle(
                            fontFeatures: [FontFeature.tabularFigures()]),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          if (today != null) ...[
            const SizedBox(height: 6),
            TodayMarketLine(today: today, note: todayNote),
          ],
          const SizedBox(height: 8),
          SizedBox(
            height: 100,
            child: StockChart(
              rounds:          rounds,
              initialAsset:    initial,
              cardIndexes:     _cardIndexes,
              decisionIndexes: _decisionIndexes,
              extraTickers:    _overlayTickers,
              showLegend:      false,
            ),
          ),
          MarketChips(
            rounds:       rounds,
            selected:     _overlayTickers,
            onToggle:     _toggleOverlay,
            compact:      true,
            todayChanges: todayChanges,
          ),
        ],
      ),
    );
  }

  // ── 카드 선택 장면 ─────────────────────────
  Widget _buildCardScene() {
    final n     = _selectedCardIds.length;
    final ord   = n < _ordinals.length ? _ordinals[n] : '다음';
    final today = _todayMarket;

    // (한 화면에) 제목은 위쪽 태그 줄에, 오늘 시장·종목별 오늘 등락은 그래프 칸 안에,
    //  평소 순위는 카드 옆 배지로 — 스크롤 없이 그래프를 보면서 카드를 고를 수 있게
    //  (기존: 25라운드는 첫 화면에 후보 카드가 하나도 보이지 않아 위아래로 오가며 골랐다 — 실제 플레이 영상)
    // 순서대로 착착: 제목 → 그래프 → 안내·AI → 후보 카드 → 확정 버튼 (화면을 누르면 바로 전부)
    return RevealScope(
      child: SceneSheet(
      fullScreen: true,
      tag: Reveal(
        order: 0,
        child: Wrap(
          spacing: 10,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SceneTag('🃏 $_sceneWhen',
                bg: TossColors.blue50, fg: TossColors.blue600),
            Text('$ord 전략을 골라주세요',
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: TossColors.grey900)),
          ],
        ),
      ),
      trailing: _sceneClose(),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!_notStarted) ...[
            Reveal(order: 1, child: _buildSceneChart(todayNote: _todayCaption)),
            const SizedBox(height: 8),
          ] else if (today != null) ...[
            // 1라운드: 그래프에 그릴 날이 없어 오늘 시장 칸을 그대로 (종목별 오늘 등락 포함)
            Reveal(
              order: 1,
              child: TodayMarketCard(today: today, caption: _todayCaption),
            ),
            const SizedBox(height: 8),
          ],

          // (#125) 현금이 총자산의 5%보다 적으면 사는 카드는 발동하지 않는다 — 고르기 전에 알려 준다
          //        (기존: 75라운드에 현금이 5%뿐인데 사는 카드를 골라도 미리 알 수 없었고,
          //         결과는 "발동 0회 · 현금 부족" — 실제 플레이 영상에서 확인)
          if (_cashLow) ...[
            InfoBox(
              child: Text(
                '현금이 총자산의 5%보다 적어요 (지금 ${(_currentRound.cashWeight ?? 0).toStringAsFixed(1)}%). '
                '사는 카드 중 지금 발동하는 건 고르는 즉시 사는 카드뿐이에요.',
                style: TossText.caption.copyWith(
                    fontSize: 12, color: const Color(0xFFC25E00)),
              ),
            ),
            const SizedBox(height: 8),
          ],

          // (11주차) 오늘 나온 뉴스 — 카드와 연결하지 않고 참고용으로만
          if (_selectNews.isNotEmpty) ...[
            _buildSelectNews(),
            const SizedBox(height: 8),
          ],

          // AI 도우미: 25·50라운드만. 1·75라운드는 제공하지 않는 이유를 한 줄로
          if (_canUseV2) ...[
            Reveal(order: 3, child: _buildAiHelper()),
            const SizedBox(height: 4),
            Reveal(
              order: 3,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                    _fixedOrder.isEmpty ? _v2Notice : _v2NoticeWithMedals,
                    style: TossText.small.copyWith(fontSize: 11)),
              ),
            ),
            const SizedBox(height: 6),
          ] else if (_noAiReason != null) ...[
            Reveal(
              order: 3,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(_noAiReason!, style: TossText.small),
              ),
            ),
            const SizedBox(height: 6),
          ],

          ...List.generate(_currentCardOptions.length, (i) {
            final card = CardInfo.fromId(_currentCardOptions[i]);
            if (card == null) return const SizedBox.shrink();
            return Reveal(order: 4 + i, child: _buildCardItem(card));
          }),
        ],
      ),
      bottom: Reveal(order: 6, child: _buildConfirmButton()),
    ),
    );
  }

  // =============================================
  // (12주차 피드백 2번) 평소 순위(고정 순위) 복원
  //  평소 순위 = 학습 기간(2006~2018) 이 라운드에서 각 카드가 낸 평균 기여도 순서. 지금 시장은 보지 않는다.
  //  7주차 평가에서 V2가 처음 보는 시장에서 이 기준보다 낫다는 근거를 찾지 못했으므로,
  //  AI 예측과 나란히 보여 주고 비교하게 한다 (#121에서 빠졌던 것을 다시 넣음)
  // =============================================
  List<int> get _fixedOrder =>
      FixedRanking.order(_currentRound1, _currentCardOptions);

  static const String _v2Notice =
      'AI 예측은 과거 시장으로 학습한 참고용이에요. '
      '처음 보는 시장 테스트에서 평소 순위보다 낫지 않았어요.';

  // (한 화면에) 평소 순위 칸(약 150px)을 없애고 카드 옆 🥇🥈🥉 배지로 — 그 뜻과 평가 결과를 짧게
  static const String _v2NoticeWithMedals =
      '🥇🥈🥉 평소 순위: 지금 시장은 보지 않는 과거 평균 순서\n'
      'AI 예측은 오늘 종가까지 본 참고용 · 처음 보는 시장 테스트에서 평소 순위보다 낫지 않았어요';

  // AI 도우미 줄 (25·50라운드) — 한 줄: 🤖 상태 글 + [AI 설명] [AI 예측]
  //  글은 짧게 한 줄로: 휴대폰 폭에서 "카드마다 AI 예측을 표시했어 / 요"처럼 끊겼다. 더 좁으면 글자를 살짝 줄인다
  Widget _buildAiHelper() {
    final text = switch (_aiState) {
      AiState.idle    => 'AI 예측을 볼까요?',
      AiState.loading => 'AI가 예측하고 있어요',
      AiState.done    => 'AI 예측을 표시했어요',
      AiState.error   => '예측을 받지 못했어요',
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
      decoration: BoxDecoration(
        color: TossColors.blue50,
        borderRadius: BorderRadius.circular(TossRadius.lg),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Text('🤖', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(text,
                      maxLines: 1,
                      style: const TextStyle(
                          fontSize: 13.5,
                          height: 1.3,
                          fontWeight: FontWeight.w600,
                          color: TossColors.grey800)),
                ),
              ),
              _buildFeedbackButton(),
              const SizedBox(width: 6),
              _buildAiButton(),
            ],
          ),
          if (_aiState == AiState.loading) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: const LinearProgressIndicator(minHeight: 3),
            ),
          ],
        ],
      ),
    );
  }

  // ── 위기 대응 장면 ─────────────────────────
  Widget _buildDecisionScene() {
    final prompt = _decisionPrompt?.round == _currentRound1 ? _decisionPrompt : null;
    final good   = prompt?.news.level == 'positive';

    final flash = switch (prompt?.news.level) {
      'danger'   => TossColors.orange500,
      'positive' => TossColors.green500,
      _          => TossColors.grey500,
    };

    final sheet = SceneSheet(
      fullScreen: true,
      tag: good
          ? SceneTag('📣 $_sceneWhen · 기회',
              bg: TossColors.green50, fg: const Color(0xFF02874F))
          : SceneTag('🚨 $_sceneWhen · 위기 대응',
              bg: const Color(0xFFFFF3E0), fg: const Color(0xFFC25E00)),
      trailing: _sceneClose(),
      body: DecisionSelector(
        prompt:        prompt,
        otherNews:     _selectNews,
        selected:      _pendingChoice,
        hasHoldings:   _hasHoldings,
        hasCash:       _hasCash,
        buyMoreTarget: _session.buyMoreTarget,
        enabled:       !_isSubmitting,
        onSelect: (c) => setState(() => _pendingChoice = c),
        // 속보와 질문 사이: 지금 내 상황 + 오늘 시장 (AI와 같은 정보로 고르게)
        // 오늘 시장·종목별 오늘 등락은 그래프 칸 안에 (한 화면에 들어가도록)
        info: _buildSceneChart(),
      ),
      bottom: Reveal(order: 6, child: _buildDecisionButton()),
    );

    // 속보가 뜰 때 화면 전체가 한 번 번쩍 (위험 주황 / 긍정 초록) → 0.6초 동안 사라짐
    return RevealScope(
      child: Stack(
        fit: StackFit.expand,
        children: [
          sheet,
          IgnorePointer(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 1, end: 0),
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutCubic,
              builder: (_, v, __) =>
                  Container(color: flash.withValues(alpha: 0.5 * v)),
            ),
          ),
        ],
      ),
    );
  }

  // ── 카드 선택 라운드의 뉴스 ─────────────────
  //  (한 화면에) 머리말·여백을 줄인 작은 칸
  Widget _buildSelectNews() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 9),
      decoration: BoxDecoration(
        color: TossColors.grey50,
        borderRadius: BorderRadius.circular(TossRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('오늘 나온 뉴스', style: TossText.small.copyWith(fontSize: 11)),
          for (final n in _selectNews)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Builder(builder: (_) {
                    final st = NewsStyle.of(n.level);
                    return Container(
                      margin: const EdgeInsets.only(top: 1),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: st.softBg,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(st.label,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: st.softFg)),
                    );
                  }),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(n.headline,
                        style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                            color: TossColors.grey900)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── AI 설명 버튼 (바텀시트 열기) ───────────
  Widget _buildFeedbackButton() {
    final ready = _aiState == AiState.done && _aiFeedback.isNotEmpty;
    return TossChipButton(
      label: 'AI 설명',
      onTap: _onFeedbackButtonTap,
      bg: TossColors.grey100,
      fg: ready ? TossColors.grey800 : TossColors.grey500,
    );
  }

  // ── AI 예측 버튼 (상태 4개) ────────────────
  Widget _buildAiButton() {
    switch (_aiState) {
      case AiState.idle:
        return TossChipButton(
          label: 'AI 예측',
          onTap: _requestAiRecommendation,
          leading: const Text('✨', style: TextStyle(fontSize: 12)),
        );
      case AiState.loading:
        return const TossChipButton(
          label: '예측 중',
          leading: SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
                strokeWidth: 1.8,
                valueColor: AlwaysStoppedAnimation(TossColors.blue600)),
          ),
        );
      case AiState.done:
        return const TossChipButton(
          label: '예측 완료',
          bg: TossColors.green50,
          fg: TossColors.green500,
          leading: Icon(Icons.check_rounded,
              size: 14, color: TossColors.green500),
        );
      case AiState.error:
        return TossChipButton(
          label: '다시 시도',
          onTap: _requestAiRecommendation,
          bg: TossColors.red50,
          fg: TossColors.red500,
          leading: const Icon(Icons.refresh_rounded,
              size: 14, color: TossColors.red500),
        );
    }
  }

  // ── 카드 한 줄 (ListRow) ───────────────────
  //  (한 화면에) ① 이름 + 평소 순위·AI 1위 배지  ② 설명  ③ 그 종목의 게임 시작 후 등락 · AI 예측
  //  (기존: 평소 순위가 카드 위 별도 칸(약 150px)이고, 종목 등락·AI 예측이 한 줄씩 따로였다)
  static const _medals = ['🥇', '🥈', '🥉'];

  // 카드 이름 옆 작은 배지 (TossBadge보다 위아래 여백이 작아 이름 줄이 높아지지 않는다)
  Widget _miniBadge(String label, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 11.5,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: fg)),
      );

  Widget _buildCardItem(CardInfo card) {
    final aiPick       = _aiRecommendedCardId == card.id;
    final contribRaw   = _contributions[card.id];
    final showContrib  =
        _aiRequested && _aiState == AiState.done && contribRaw != null;
    final contribution = contribRaw ?? 0.0;
    final selected     = _pendingCardId == card.id;
    // (#125) 이 카드가 사고파는 종목이 게임 시작 후 얼마나 움직였는지 (갖고 있지 않아도 보고 고를 수 있게)
    //        1라운드는 위의 시작 전 브리핑에 직전 20거래일 등락이 있다
    final moved = _notStarted ? null : changeSinceStart(_displayRounds, card.ticker);
    // (12주차 피드백 2번) 평소 순위 — 학습 기간 이 라운드에서의 평균 기여도 순서 (25·50라운드만 값이 있다)
    final rank  = _fixedOrder.indexOf(card.id);

    return Pressable(
      onTap: _isSubmitting
          ? null
          : () => setState(() => _pendingCardId = card.id),
      scale: 0.98,
      child: AnimatedContainer(
        duration: TossMotion.base,
        curve: TossMotion.enter,
        margin: const EdgeInsets.symmetric(vertical: 1),
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
        width: double.infinity,
        decoration: BoxDecoration(
          color: selected ? TossColors.blue50 : Colors.transparent,
          borderRadius: BorderRadius.circular(TossRadius.lg),
        ),
        child: Row(
          children: [
            EmojiTile(
              emoji: card.emoji,
              size: 40,
              bg: selected ? TossColors.white : TossColors.grey100,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 3,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(card.name,
                          style: TossText.body2.copyWith(height: 1.3)),
                      if (rank >= 0 && rank < _medals.length)
                        _miniBadge('${_medals[rank]} 평소 ${rank + 1}위',
                            TossColors.grey100, TossColors.grey700),
                      if (aiPick)
                        _miniBadge(
                            'AI 1위', TossColors.red50, TossColors.red500),
                    ],
                  ),
                  const SizedBox(height: 1),
                  Text(card.description.replaceAll('\n', ' '),
                      style: TossText.caption
                          .copyWith(fontSize: 12.5, height: 1.35)),
                  if (moved != null || showContrib) ...[
                    const SizedBox(height: 2),
                    Wrap(
                      spacing: 10,
                      runSpacing: 1,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (moved != null)
                          Text.rich(
                            TextSpan(children: [
                              TextSpan(
                                  text: '${tickerName(card.ticker)} · 게임 시작 후 '),
                              TextSpan(
                                  text: formatSigned(moved),
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: TossColors.rate(moved),
                                      fontFeatures: const [
                                        FontFeature.tabularFigures()
                                      ])),
                            ]),
                            style: TossText.small,
                          ),
                        // (#125) 이 값은 기대수익률이 아니라 아직 고르지 않은 카드 전체 평균과의 예상 차이(%p)
                        if (showContrib)
                          Text(
                            'AI 예측: 카드 평균보다 ${formatSigned(contribution, unit: '%p')}',
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: TossColors.rate(contribution)),
                          ),
                      ],
                    ),
                  ],
                  // (#125) 팔 S&P500이 없으면 이 카드는 발동해도 아무 일도 일어나지 않는다
                  if (card.id == 8 && !_holdsSpx) ...[
                    const SizedBox(height: 2),
                    const Text('지금은 가진 S&P500이 없어요 · S&P500을 사는 카드와 함께 쓰면 효과',
                        style: TextStyle(
                            fontSize: 11.5,
                            height: 1.35,
                            color: Color(0xFFC25E00))),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            AnimatedSwitcher(
              duration: TossMotion.base,
              transitionBuilder: (c, a) =>
                  ScaleTransition(scale: a, child: c),
              child: Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                key: ValueKey(selected),
                size: 24,
                color: selected ? TossColors.blue500 : TossColors.grey300,
              ),
            ),
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
