import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/game_session.dart';
import '../models/round_data.dart';
import '../models/action_result.dart';
import '../models/card_info.dart';
import '../models/decision.dart';
import '../models/news_item.dart';
import '../models/v2_recommend_result.dart';
import '../services/game_service.dart';
import '../widgets/briefing_card.dart';
import '../widgets/decision_selector.dart';
import '../widgets/stock_chart.dart';
import '../widgets/holdings_widget.dart';
import '../widgets/news_banner.dart';
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

  // (11주차) 뉴스 배너 — 화면 위에 겹쳐 띄워 기존 배치를 건드리지 않음
  List<NewsItem> _pendingSelectNews = [];   // 다음 카드 선택 라운드 뉴스 (nextRoundNews)
  final Set<String> _shownNewsKeys = {};    // 이미 띄운 뉴스 (날짜+헤드라인)
  final List<NewsItem> _newsLog = [];       // 지금까지 나온 뉴스 (목록)
  NewsItem? _bannerNews;
  bool _bannerSticky = false;               // (토스 개편 후 미사용: 선택 라운드 뉴스는 카드 선택 섹션 안에 표시)
  List<NewsItem> _selectNews = [];          // 카드 선택 섹션의 '오늘 나온 뉴스'
  Timer? _bannerTimer;

  Timer? _autoTimer;

  // 카드 선택 화면에서 고른 카드 (확정 버튼을 눌러야 제출)
  int? _pendingCardId;

  // (#125) 위기 대응
  DecisionPrompt? _decisionPrompt;          // 다음 위기 대응 라운드의 속보 (서버 nextDecision)
  String? _pendingChoice;                   // 고른 대응 (확정 버튼을 눌러야 제출)
  final Map<int, String> _decisions = {};   // 라운드 → 내가 한 대응 (차트 표시용)

  // (#125) 카드가 건너뛴 이유는 같은 이유로 처음 건너뛸 때만 알린다 (매 라운드 알리면 계속 떠 있음)
  final Set<String> _announcedSkips = {};
  String _skipNotice = '';

  // ── Getters ────────────────────────────────
  RoundData get _currentRound {
    final idx = _currentRoundIndex.clamp(0, _session.rounds.length - 1);
    return _session.rounds[idx];
  }

  List<RoundData> get _chartData => _session.getChartData(
      _currentRoundIndex.clamp(0, _session.rounds.length - 1));

  int get _currentRound1 => _currentRoundIndex + 1;

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
          '지금은 위의 시작 전 브리핑을 참고하세요';
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
    _bannerTimer?.cancel();
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
          // (#125) 이 숫자는 최종 수익률 예측이 아니라 후보 평균과의 차이
          const Text(
            '숫자는 후보 3장의 평균과 비교한 예상 차이(%p)예요. 최종 수익률을 예측한 값이 아니에요.',
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

          // ④ 참고용 안내 (평가 결과 반영)
          const SizedBox(height: 12),
          const Text(
            'AI 예측은 과거 시장으로 학습한 참고용이에요. S&P500의 흐름과 고른 카드만 보고 판단하고, '
            '처음 보는 시장에서는 틀릴 수 있어요.',
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
          // (#125) 가운데 기준선(후보 평균)에서 +는 오른쪽, -는 왼쪽으로 뻗는다
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
      setState(() => _selectNews = items
          .where((n) => n.key != promptKey && seen.add(n.key))
          .toList());
    }
    _showNews(items, sticky: sticky);
    _updateSkipNotice();
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

  void _showNews(List<NewsItem> items, {required bool sticky}) {
    final fresh = <NewsItem>[];
    for (final n in items) {
      if (_shownNewsKeys.add(n.key)) fresh.add(n); // 이미 띄운 뉴스는 건너뜀
    }
    if (fresh.isEmpty) return;
    _bannerTimer?.cancel();
    // 위험 뉴스는 진동으로 한 번 더 알림
    if (fresh.any((n) => n.level == 'danger')) HapticFeedback.mediumImpact();
    if (sticky) {
      setState(() => _newsLog.addAll(fresh));
      return;
    }
    setState(() {
      _newsLog.addAll(fresh);
      _bannerNews   = fresh.first; // 같은 날 뉴스가 여러 개면 첫 번째만 배너, 나머지는 목록
      _bannerSticky = false;
    });
    _bannerTimer = Timer(const Duration(seconds: 5), _hideBanner);
  }

  void _hideBanner() {
    _bannerTimer?.cancel();
    if (!mounted || _bannerNews == null) return;
    setState(() {
      _bannerNews   = null;
      _bannerSticky = false;
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
      showTossToast(context, DecisionChoice.done(choice));
    } catch (e) {
      if (!mounted) return;
      showTossToast(context, e.toString());
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
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
      _selectNews         = [];
      // 골랐으니 선택용 배너는 닫음
      if (_bannerSticky) {
        _bannerNews   = null;
        _bannerSticky = false;
      }

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
    // (12주차) 고르면 재생 버튼을 누르지 않아도 바로 다음 라운드로 진행
    _startAutoPlay();
  }

  // =============================================
  // Build (토스 스타일)
  //  회색 배경 위에 흰 섹션: 자산 요약+차트 → 내 포트폴리오 → 전략 선택
  //  하단에는 항상 큰 버튼 하나 (멈추기·이어서 / 이 전략으로 할게요 / 결과 보기)
  // =============================================
  double get _displayAsset =>
      _currentRound.roundAsset ?? _session.initialAsset.toDouble();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildSummary(),
                    // (#125) 첫 카드를 고르기 전: 시작 전 시장 브리핑
                    if (_notStarted &&
                        _session.briefing != null &&
                        !_session.briefing!.isEmpty) ...[
                      const SizedBox(height: 8),
                      FadeInUp(
                          child: BriefingCard(briefing: _session.briefing!)),
                    ],
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
                    AnimatedSize(
                      duration: TossMotion.base,
                      curve: TossMotion.enter,
                      alignment: Alignment.topCenter,
                      child: _waiting
                          ? Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: FadeInUp(
                                key: ValueKey('selector-$_currentRound1'),
                                child: _showCard
                                    ? _buildCardSelector()
                                    : DecisionSelector(
                                        prompt: _decisionPrompt?.round ==
                                                _currentRound1
                                            ? _decisionPrompt
                                            : null,
                                        otherNews:     _selectNews,
                                        selected:      _pendingChoice,
                                        hasHoldings:   _hasHoldings,
                                        hasCash:       _hasCash,
                                        buyMoreTarget: _session.buyMoreTarget,
                                        enabled:       !_isSubmitting,
                                        onSelect: (c) =>
                                            setState(() => _pendingChoice = c),
                                      ),
                              ),
                            )
                          : const SizedBox(width: double.infinity),
                    ),
                  ],
                ),
              ),
            ),
            _buildBottomBar(),
          ],
        ),
            // (11주차) 뉴스 배너 — 화면 위에서 내려오는 알림, 아래 배치는 움직이지 않음
            Positioned(
              left: 12,
              right: 12,
              top: 8,
              child: AnimatedSwitcher(
                duration: TossMotion.slow,
                switchInCurve: TossMotion.spring,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, anim) => SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, -0.6),
                    end: Offset.zero,
                  ).animate(anim),
                  child: FadeTransition(opacity: anim, child: child),
                ),
                child: _bannerNews == null
                    ? const SizedBox.shrink()
                    : NewsBanner(
                        key:     ValueKey(_bannerNews!.key),
                        news:    _bannerNews!,
                        sticky:  _bannerSticky,
                        onClose: _hideBanner,
                      ),
              ),
            ),
          ],
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
              Pressable(
                onTap: () { _stopAutoPlay(); Navigator.pop(context); },
                haptic: false,
                child: const Padding(
                  padding: EdgeInsets.all(10),
                  child: Icon(Icons.arrow_back_ios_new_rounded,
                      size: 20, color: TossColors.grey900),
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
              // (11주차) 지금까지 나온 뉴스 목록
              if (_newsLog.isNotEmpty) ...[
                Pressable(
                  onTap: () => showNewsLogSheet(context, _newsLog),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: TossColors.grey200,
                      borderRadius: BorderRadius.circular(TossRadius.sm),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.newspaper_rounded,
                            size: 14, color: TossColors.grey700),
                        const SizedBox(width: 4),
                        Text('${_newsLog.length}',
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: TossColors.grey700)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
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
              value: asset, style: TossText.display),
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
                      AnimatedContainer(
                        duration: TossMotion.base,
                        curve: TossMotion.enter,
                        height: _waiting ? 130 : 190,
                        child: StockChart(
                          rounds:          _chartData,
                          initialAsset:    initial,
                          cardIndexes:     _cardIndexes,
                          decisionIndexes: _decisionIndexes,
                        ),
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
    // (#125) 발동한 카드가 없고 처음 건너뛴 카드가 있으면 그 이유를 회색으로 알림
    final text  = names.isNotEmpty ? '$names 발동' : _skipNotice;
    final fired = names.isNotEmpty;
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
                    color: fired ? const Color(0xFFFFF3E0) : TossColors.grey100,
                    borderRadius: BorderRadius.circular(TossRadius.sm),
                  ),
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: fired
                            ? const Color(0xFFC25E00)
                            : TossColors.grey600),
                  ),
                ),
        ),
      ),
    );
  }

  // ── 전략 카드 선택 ─────────────────────────
  Widget _buildCardSelector() {
    return TossSection(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                    _notStarted
                        ? '첫 전략을\n골라주세요'
                        : '이번 라운드 전략을\n골라주세요',
                    style: TossText.title3),
              ),
              // AI 설명·AI 예측 버튼: 25·50라운드만 표시
              if (_canUseV2) ...[
                _buildFeedbackButton(),
                const SizedBox(width: 6),
                _buildAiButton(),
              ],
            ],
          ),

          // 1·75라운드: 추천을 제공하지 않는 이유 안내
          if (_noAiReason != null) ...[
            const SizedBox(height: 12),
            InfoBox(child: Text(_noAiReason!, style: TossText.caption)),
          ],

          // (11주차) 오늘 나온 뉴스 — 카드와 연결하지 않고 참고용으로만
          if (_selectNews.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildSelectNews(),
          ],

          // 로딩 바
          if (_aiState == AiState.loading) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: const LinearProgressIndicator(minHeight: 3),
            ),
            const SizedBox(height: 6),
            const Text('과거 시장으로 예측하고 있어요', style: TossText.small),
          ],

          const SizedBox(height: 8),
          ...List.generate(_currentCardOptions.length, (i) {
            final card = CardInfo.fromId(_currentCardOptions[i]);
            if (card == null) return const SizedBox.shrink();
            return FadeInUp(
              delay: Duration(milliseconds: 60 * i),
              child: _buildCardItem(card),
            );
          }),
        ],
      ),
    );
  }

  // ── 카드 선택 라운드의 뉴스 ─────────────────
  Widget _buildSelectNews() {
    return InfoBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('오늘 나온 뉴스', style: TossText.small),
          for (final n in _selectNews)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Builder(builder: (_) {
                    final st = NewsStyle.of(n.level);
                    return Container(
                      margin: const EdgeInsets.only(top: 1),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: st.softBg,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(st.label,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: st.softFg)),
                    );
                  }),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(n.headline,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            height: 1.4,
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
  Widget _buildCardItem(CardInfo card) {
    final aiPick       = _aiRecommendedCardId == card.id;
    final contribRaw   = _contributions[card.id];
    final showContrib  =
        _aiRequested && _aiState == AiState.done && contribRaw != null;
    final contribution = contribRaw ?? 0.0;
    final selected     = _pendingCardId == card.id;

    return Pressable(
      onTap: _isSubmitting
          ? null
          : () => setState(() => _pendingCardId = card.id),
      scale: 0.98,
      child: AnimatedContainer(
        duration: TossMotion.base,
        curve: TossMotion.enter,
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        width: double.infinity,
        decoration: BoxDecoration(
          color: selected ? TossColors.blue50 : Colors.transparent,
          borderRadius: BorderRadius.circular(TossRadius.lg),
        ),
        child: Row(
          children: [
            EmojiTile(
              emoji: card.emoji,
              bg: selected ? TossColors.white : TossColors.grey100,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(card.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TossText.body2),
                      ),
                      if (aiPick) ...[
                        const SizedBox(width: 6),
                        const TossBadge(
                            label: 'AI 1위',
                            bg: TossColors.red50,
                            fg: TossColors.red500),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(card.description.replaceAll('\n', ' '),
                      style: TossText.caption),
                  // (#125) 팔 S&P500이 없으면 이 카드는 발동해도 아무 일도 일어나지 않는다
                  if (card.id == 8 && !_holdsSpx) ...[
                    const SizedBox(height: 3),
                    const Text('지금은 가진 S&P500이 없어요. S&P500을 사는 카드와 함께 쓸 때 효과가 있어요',
                        style: TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            color: Color(0xFFC25E00))),
                  ],
                  if (showContrib) ...[
                    const SizedBox(height: 4),
                    // (#125) 이 값은 기대수익률이 아니라 후보 3장 평균과의 예상 차이(%p)
                    Text(
                      'AI 예측: 후보 평균보다 ${formatSigned(contribution, unit: '%p')}',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: TossColors.rate(contribution)),
                    ),
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
      child: _showCard
          ? _buildConfirmButton()
          : _showDecision
              ? _buildDecisionButton()
              : _buildControls(),
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
