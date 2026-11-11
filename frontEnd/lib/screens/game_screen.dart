import 'dart:async';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/game_session.dart';
import '../models/round_data.dart';
import '../models/action_result.dart';
import '../models/card_info.dart';
import '../models/fixed_ranking.dart';
import '../models/v2_recommend_result.dart';
import '../services/game_service.dart';
import '../services/mock_data.dart';
import '../widgets/stock_chart.dart';
import '../widgets/holdings_widget.dart';
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

  // 25·50라운드: V2는 정답 추천이 아니라 참고 예측임을 안내 (중간보고서 4장 평가 결과 반영)
  static const String _v2Notice =
      'AI 예측은 과거 시장으로 학습한 참고용이에요. '
      '처음 보는 시장 테스트에서 평소 순위보다 낫지 않았어요.';

  // 지금 후보 카드들의 평소 순위 (시장을 보지 않는 고정 순위)
  List<int> get _fixedOrder =>
      FixedRanking.order(_currentRound1, _currentCardOptions);

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
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
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
  // AI 피드백 다이얼로그 (메모지처럼 화면 위에 오버레이)
  // =============================================
  void _showFeedbackDialog() {
    if (_aiFeedback.isEmpty) return;
    showTossSheet(
      context,
      title: 'AI가 이렇게 예측했어요',
      body: Text(
        _aiFeedback,
        style: const TextStyle(
            fontSize: 16, height: 1.65, color: TossColors.grey700),
      ),
    );
  }

  // =============================================
  // 자동 진행
  // =============================================
  void _startAutoPlay() {
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
        }
      } else {
        setState(() {
          _currentRoundIndex++;
          _triggeredCardIds =
              _session.rounds[_currentRoundIndex].triggeredCards;
        });
      }
    });
  }

  void _stopAutoPlay() {
    _autoTimer?.cancel();
    _autoTimer = null;
    if (mounted) setState(() => _isAutoPlaying = false);
  }

  void _nextRound() {
    if (_isLastRound) return;
    final next = _currentRoundIndex + 2;
    setState(() {
      _currentRoundIndex++;
      _triggeredCardIds =
          _session.rounds[_currentRoundIndex].triggeredCards;
      if (_session.isCardSelectRound(next)) {
        _cardSelected    = false;
        _triggeredCardIds = [];
        _resetAiState();
      }
    });
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

  void _onMockCardSelected(int cardId) {
    final mockData = MockData.getActionResult(_currentRoundIndex);
    final result   = ActionResult.fromJson(
        mockData['data'] as Map<String, dynamic>);
    _applyActionResult(result, cardId);
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

      // 선택한 카드 누적
      if (!_selectedCardIds.contains(selectedCardId)) {
        _selectedCardIds.add(selectedCardId);
      }
      _lastAddedCardId  = selectedCardId;
      _triggeredCardIds = [];
      _resetAiState();
    });
  }

  void _loadMockSession() {
    _stopAutoPlay();
    final mockSession = GameSession.fromJson(
        MockData.gameSession['data'] as Map<String, dynamic>);
    setState(() {
      _session            = mockSession;
      _currentRoundIndex  = 0;
      _cardSelected       = false;
      _currentCardOptions = mockSession.firstCardOptions;
      _selectedCardIds.clear();
      _lastAddedCardId    = null;
      _triggeredCardIds   = [];
      _resetAiState();
    });
  }

  // =============================================
  // Build (토스 스타일)
  //  회색 배경 위에 흰 섹션: 자산 요약+차트 → 내 포트폴리오 → 전략 선택
  //  하단에는 항상 큰 버튼 하나 (다음 라운드 / 이 전략으로 할게요)
  // =============================================
  double get _displayAsset =>
      _currentRound.roundAsset ?? _session.initialAsset.toDouble();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TossColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(),
            // 개발용 버튼: 디버그 실행에서만 표시 (릴리스·데모 빌드에서는 숨김)
            if (kDebugMode)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: _buildMockButton(),
              ),
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

  // ── 개발용 버튼 ────────────────────────────
  Widget _buildMockButton() {
    return Row(
      children: [
        const TossBadge(
            label: '개발용', bg: TossColors.grey200, fg: TossColors.grey600),
        const SizedBox(width: 8),
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _devBtn('세션 초기화', _loadMockSession),
              _devBtn(
                '임시 카드선택',
                !_cardSelected
                    ? () => _onMockCardSelected(
                        _currentCardOptions.isNotEmpty
                            ? _currentCardOptions[0]
                            : 1)
                    : null,
              ),
              _devBtn('결과 화면', _goToResult),
            ],
          ),
        ),
      ],
    );
  }

  Widget _devBtn(String label, VoidCallback? onTap) {
    return TossChipButton(
      label: label,
      onTap: onTap,
      bg: TossColors.white,
      fg: onTap == null ? TossColors.grey400 : TossColors.grey700,
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

          // 25·50라운드: 평소 순위 + 예측 안내
          if (_canUseV2) ...[
            const SizedBox(height: 12),
            _buildV2Info(_fixedOrder),
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

  // ── 평소 순위 (고정 순위) + AI 예측 안내 ──
  // 평소 순위 = 학습 데이터(2006~2018)에서 이 라운드에 각 카드가 낸 평균 성과 순서.
  // 지금 시장은 보지 않음 → AI 예측과 비교해 보라는 의미로 함께 표시
  Widget _buildV2Info(List<int> order) {
    final names = order
        .map((id) => CardInfo.fromId(id)?.name ?? '카드 $id')
        .join(' › ');
    return InfoBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (order.isNotEmpty) ...[
            Text.rich(
              TextSpan(children: [
                const TextSpan(
                    text: '평소 순위  ',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: TossColors.grey700)),
                TextSpan(
                    text: names,
                    style: const TextStyle(color: TossColors.grey700)),
              ]),
              style: TossText.caption,
            ),
            const SizedBox(height: 4),
          ],
          const Text(_v2Notice, style: TossText.caption),
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
                      '예측 ${contribution >= 0 ? '+' : ''}${contribution.toStringAsFixed(2)}%',
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

  Widget _buildControls() {
    return Row(
      children: [
        Pressable(
          onTap: _isAutoPlaying ? _stopAutoPlay : _startAutoPlay,
          child: AnimatedContainer(
            duration: TossMotion.base,
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: _isAutoPlaying ? TossColors.blue50 : TossColors.white,
              borderRadius: BorderRadius.circular(TossRadius.lg),
            ),
            child: AnimatedSwitcher(
              duration: TossMotion.fast,
              child: Icon(
                _isAutoPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                key: ValueKey(_isAutoPlaying),
                color: _isAutoPlaying
                    ? TossColors.blue500
                    : TossColors.grey700,
                size: 28,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TossButton(
            label: _isAutoPlaying
                ? '자동으로 넘기는 중'
                : _isLastRound
                    ? '결과 보기'
                    : '다음 라운드',
            onTap: _isAutoPlaying
                ? null
                : _isLastRound
                    ? _goToResult
                    : _nextRound,
          ),
        ),
      ],
    );
  }
}
