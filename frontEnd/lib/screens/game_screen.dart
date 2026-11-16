import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/game_session.dart';
import '../models/round_data.dart';
import '../models/action_result.dart';
import '../models/card_info.dart';
import '../models/news_item.dart';
import '../models/v2_recommend_result.dart';
import '../services/game_service.dart';
import '../widgets/stock_chart.dart';
import '../widgets/holdings_widget.dart';
import '../widgets/news_banner.dart';
import '../widgets/toss/toss_widgets.dart';
import '../theme/toss_theme.dart';
import 'game_result_screen.dart';

enum AiState { idle, loading, done, error }

class GameScreen extends StatefulWidget {
  final GameSession session;
  const GameScreen({super.key, required this.session});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with TickerProviderStateMixin {
  final GameService _gameService = GameService();

  late GameSession _session;
  int  _currentRoundIndex = 0;
  bool _cardSelected      = false;
  bool _isSubmitting      = false;
  bool _isAutoPlaying     = false;

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
  bool             _isFeedbackLoading   = false; // 피드백 버튼 자체 로딩
  List<CardRanking> _lastRankings       = []; // 피드백 요청 시 재사용
  bool             _aiRequested         = false;

  // 라운드별 AI 예측 1순위 (결과 화면에서 '내 선택'과 비교)
  final Map<int, int> _aiPicks = {};
  final Map<int, List<int>> _aiCandidates = {}; // 그때 받은 후보 카드 3장

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

  // ── Getters ────────────────────────────────
  RoundData get _currentRound {
    final idx = _currentRoundIndex.clamp(0, _session.rounds.length - 1);
    return _session.rounds[idx];
  }

  List<RoundData> get _chartData => _session.getChartData(
      _currentRoundIndex.clamp(0, _session.rounds.length - 1));

  int get _currentRound1 => _currentRoundIndex + 1;

  bool get _showCard {
    if (_cardSelected) return false;
    if (_session.cardSelectRounds.isNotEmpty) {
      return _session.isCardSelectRound(_currentRound1);
    }
    return _currentRound1 == 1;
  }

  bool get _isLastRound {
    if (!_cardSelected) return false;
    final next = _currentRoundIndex + 2;
    if (_session.isCardSelectRound(next)) return false;
    return _currentRoundIndex >= _session.rounds.length - 1;
  }

  // V2: 25·50라운드만 (1·75 제외)
  bool get _canUseV2 => [25, 50].contains(_currentRound1);

  // 1·75라운드: AI 예측을 제공하지 않는 이유 (v6.1 합의 1번)
  //  - 1라운드: so_far 시장 데이터가 없어 V2가 판단할 근거가 없음
  //  - 75라운드: 남은 라운드가 적어 카드 간 결과 차이가 작음
  String? get _noAiReason {
    if (_currentRound1 == 1) {
      return '아직 시장 데이터가 없어 이 라운드는 AI 예측을 제공하지 않아요';
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

  // 지금 보고 있는 라운드 데이터 (보유 자산 표시용)
  RoundData? get _currentRoundData =>
      _currentRoundIndex < _session.rounds.length
          ? _session.rounds[_currentRoundIndex]
          : null;

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
      _aiFeedback           = '';
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
        _aiCandidates[_currentRound1] = List.from(_currentCardOptions);
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
    _isFeedbackLoading   = false;
    _lastRankings        = [];
    _pendingCardId       = null;
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
    final ruleLines =
        lines.where((l) => l.startsWith('카드 규칙 · ')).toList();
    final reason = lines
        .where((l) =>
            !l.startsWith('카드 규칙 · ') && !l.startsWith('예측 기여도(실측 아님)'))
        .join('\n');

    final ranked = [..._lastRankings]..sort((a, b) => a.rank.compareTo(b.rank));
    final maxAbs = ranked.isEmpty
        ? 1.0
        : ranked
            .map((r) => r.contribution.abs())
            .reduce((a, b) => a > b ? a : b)
            .clamp(0.1, double.infinity);

    showTossSheet(
      context,
      title: 'AI는 이 카드를 골랐어요',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ① 예측 순위
          for (final r in ranked) _buildRankBar(r, maxAbs.toDouble()),
          const SizedBox(height: 4),
          const Text('막대는 이 카드가 최종 수익률에 더할 것으로 예측한 값이에요',
              style: TossText.small),

          // ② 이유
          if (reason.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text('왜 이렇게 예측했나요?', style: TossText.body2),
            const SizedBox(height: 6),
            Text(reason,
                style: const TextStyle(
                    fontSize: 16, height: 1.6, color: TossColors.grey800)),
          ],

          // ③ 카드 규칙 (서버가 CARD_FACTS로 붙인 정확한 문장)
          if (ruleLines.isNotEmpty) ...[
            const SizedBox(height: 16),
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
            'AI 예측은 과거 시장으로 학습한 참고용이에요. 처음 보는 시장에서는 틀릴 수 있어요.',
            style: TossText.small,
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
            width: 128,
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
          Expanded(
            child: LayoutBuilder(
              builder: (_, c) => Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  height: 10,
                  width: (c.maxWidth * ratio).clamp(4.0, c.maxWidth).toDouble(),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 52,
            child: Text(
              '${r.contribution >= 0 ? '+' : ''}${r.contribution.toStringAsFixed(1)}%',
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
    final sticky = _showCard;
    final items  = [...roundNews, if (sticky) ..._pendingSelectNews];
    if (sticky) {
      // 카드 선택 라운드: 뉴스는 위에서 띄우지 않고 카드 선택 섹션 안에 고정
      final seen = <String>{};
      setState(() =>
          _selectNews = items.where((n) => seen.add(n.key)).toList());
    }
    _showNews(items, sticky: sticky);
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
    _autoTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      final next        = _currentRoundIndex + 2;
      final willHitCard = _session.isCardSelectRound(next);
      if (_isLastRound || willHitCard) {
        _stopAutoPlay();
        if (!_isLastRound) {
          setState(() {
            _currentRoundIndex++;
            _cardSelected    = false;
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

  void _goToResult() {
    _stopAutoPlay();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
          builder: (_) => GameResultScreen(
                session: _session,
                aiPicks: Map<int, int>.from(_aiPicks),
                aiCandidates: Map<int, List<int>>.from(_aiCandidates),
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
      _applyActionResult(result, cardId);
    } catch (e) {
      if (!mounted) return;
      showTossToast(context, e.toString());
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _applyActionResult(ActionResult result, int selectedCardId) {
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
      _session = GameSession(
        sessionId:        _session.sessionId,
        scenarioTitle:    _session.scenarioTitle,
        totalRounds:      _session.totalRounds,
        initialAsset:     _session.initialAsset,
        cardSelectRounds: _session.cardSelectRounds,
        firstCardOptions: _session.firstCardOptions,
        rounds:           updatedRounds,
      );
      _cardSelected       = true;
      _currentCardOptions = result.nextCardOptions;
      _pendingSelectNews  = result.nextRoundNews;
      _selectNews         = [];
      // 카드를 골랐으니 선택용 배너는 닫음
      if (_bannerSticky) {
        _bannerNews   = null;
        _bannerSticky = false;
      }

      // 선택한 카드 누적
      if (!_selectedCardIds.contains(selectedCardId)) {
        _selectedCardIds.add(selectedCardId);
      }
      _lastAddedCardId  = selectedCardId;
      _triggeredCardIds = [];
      _resetAiState();
    });
    // (12주차) 카드를 고르면 재생 버튼을 누르지 않아도 바로 다음 라운드로 진행
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
                    if (_selectedCardIds.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      HoldingCardsWidget(
                        cards:            _holdingCards,
                        triggeredCardIds: _triggeredCardIds,
                        holdings:         _currentRoundData?.holdings ?? const [],
                        cashWeight:       _currentRoundData?.cashWeight,
                      ),
                    ],
                    AnimatedSize(
                      duration: TossMotion.base,
                      curve: TossMotion.enter,
                      alignment: Alignment.topCenter,
                      child: _showCard
                          ? Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: FadeInUp(
                                key: ValueKey('selector-$_currentRound1'),
                                child: _buildCardSelector(),
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
            RollingText(
              '${diff >= 0 ? '+' : '-'}${formatWon(diff.abs())}원 '
              '(${rate.abs().toStringAsFixed(2)}%)',
              value: asset,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: TossColors.rate(rate),
                  fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          const SizedBox(height: 12),
          AnimatedContainer(
            duration: TossMotion.base,
            curve: TossMotion.enter,
            height: _showCard ? 130 : 190,
            child: StockChart(
              rounds:       _chartData,
              initialAsset: initial,
            ),
          ),
        ],
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
              const Expanded(
                child: Text('이번 라운드 전략을\n골라주세요',
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
                  if (showContrib) ...[
                    const SizedBox(height: 4),
                    Text(
                      '예측 ${contribution >= 0 ? '+' : ''}${contribution.toStringAsFixed(1)}%',
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
      child: _showCard ? _buildConfirmButton() : _buildControls(),
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
