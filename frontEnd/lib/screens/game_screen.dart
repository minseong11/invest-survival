import 'dart:async';
import 'package:flutter/material.dart';
import '../models/game_session.dart';
import '../models/round_data.dart';
import '../models/action_result.dart';
import '../models/card_info.dart';
import '../models/v1_recommend_result.dart';
import '../models/v2_recommend_result.dart';
import '../services/game_service.dart';
import '../services/mock_data.dart';
import '../widgets/stock_chart.dart';
import '../widgets/holdings_widget.dart';
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

  // V1.5: 백그라운드 로딩
  Map<int, int> _v1RecommendedCards = {};

  // V2: 버튼 눌렀을 때만
  AiState          _aiState             = AiState.idle;
  int?             _v2RecommendedCardId;
  Map<int, double> _contributions       = {};
  String           _aiFeedback          = ''; // LLM 자연어 피드백
  bool             _isFeedbackLoading   = false; // 피드백 버튼 자체 로딩
  List<CardRanking> _lastRankings       = []; // 피드백 요청 시 재사용
  bool             _aiRequested         = false;

  Timer? _autoTimer;

  // 총 자산 카운트업 애니메이션
  late AnimationController _assetAnimController;
  late Animation<double>   _assetAnim;
  double _prevAsset = 0;
  double _targetAsset = 0;

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

  // AI 추천 카드 ID
  int? get _aiRecommendedCardId {
    if (!_aiRequested || _aiState != AiState.done) return null;
    return _v2RecommendedCardId ?? _v1RecommendedCards[_currentRound1];
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

    final initAsset = _session.initialAsset.toDouble();
    _prevAsset   = initAsset;
    _targetAsset = initAsset;

    _assetAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _assetAnim = Tween<double>(begin: initAsset, end: initAsset)
        .animate(CurvedAnimation(
          parent: _assetAnimController,
          curve: Curves.easeOut,
        ));

    _loadV1InBackground();
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _assetAnimController.dispose();
    super.dispose();
  }

  // =============================================
  // V1.5 백그라운드 로딩
  // =============================================
  void _loadV1InBackground() {
    _gameService.getV1Recommendation(
      sessionId: _session.sessionId,
    ).then((result) {
      if (!mounted) return;
      setState(() {
        for (final rec in result.recommendations) {
          _v1RecommendedCards[rec.round] = rec.cardId;
        }
      });
    }).catchError((_) {});
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
  }

  // =============================================
  // AI 피드백 버튼 클릭 → 이미 받아온 feedback을 다이얼로그로 표시
  // (별도 API 호출 없음. getV2Recommendation 응답에 이미 포함돼 있음)
  // =============================================
  void _onFeedbackButtonTap() {
    if (_aiState != AiState.done || _aiFeedback.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('먼저 "AI 추천받기"를 눌러주세요'),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    _showFeedbackDialog();
  }

  // =============================================
  // AI 피드백 다이얼로그 (메모지처럼 화면 위에 오버레이)
  // =============================================
  void _showFeedbackDialog() {
    if (_aiFeedback.isEmpty) return;

    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 32),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 헤더: 아이콘 + 타이틀 + 닫기(X)
                Row(
                  children: [
                    Container(
                      width: 28, height: 28,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEEDFE),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.chat_bubble_outline_rounded,
                          size: 15, color: Color(0xFF3C3489)),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text('AI 투자 코치',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF3C3489))),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.of(dialogContext).pop(),
                      child: Container(
                        width: 26, height: 26,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F3F5),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close_rounded,
                            size: 15, color: Color(0xFF6B7684)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // 피드백 본문
                Text(
                  _aiFeedback,
                  style: const TextStyle(
                      fontSize: 13.5,
                      height: 1.6,
                      color: Color(0xFF111111)),
                ),
              ],
            ),
          ),
        );
      },
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
        _animateAsset();
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
    _animateAsset();
  }

  void _animateAsset() {
    final round      = _currentRound;
    final newAsset   = round.roundAsset ?? _session.initialAsset.toDouble();
    final fromAsset  = _assetAnim.value;

    _assetAnim = Tween<double>(begin: fromAsset, end: newAsset)
        .animate(CurvedAnimation(
          parent: _assetAnimController,
          curve: Curves.easeOut,
        ));
    _assetAnimController.forward(from: 0);
  }

  void _goToResult() {
    _stopAutoPlay();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
          builder: (_) => GameResultScreen(session: _session)),
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
      _applyActionResult(result, cardId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:         Text(e.toString()),
        backgroundColor: Colors.red[700],
        behavior:        SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10)),
      ));
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
  // Build
  // =============================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF9F5),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _buildMockButton(),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 차트 (고정 비율)
                    _buildChartArea(),
                    const SizedBox(height: 8),

                    // 라운드 정보 (내 수익률 | 총 자산 박스)
                    _buildRoundInfo(),
                    const SizedBox(height: 8),

                    // 보유카드 (항상 동일한 위젯)
                    if (_selectedCardIds.isNotEmpty) ...[
                      HoldingCardsWidget(
                        cards:           _holdingCards,
                        triggeredCardIds: _triggeredCardIds,
                      ),
                      const SizedBox(height: 8),
                    ],

                    // 카드 선택 or 컨트롤
                    if (_showCard)
                      _buildCardSelector()
                    else
                      _buildControls(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 헤더 ──────────────────────────────────
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
      child: Row(
        children: [
          GestureDetector(
            onTap: () { _stopAutoPlay(); Navigator.pop(context); },
            child: const Icon(Icons.arrow_back_ios_rounded,
                size: 18, color: Color(0xFF111111)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(_session.scenarioTitle,
                style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111111))),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFEEEDFE),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('$_currentRound1 / ${_session.totalRounds}',
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF3C3489))),
          ),
        ],
      ),
    );
  }

  // ── 개발용 버튼 ────────────────────────────
  Widget _buildMockButton() {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3CD),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFFD700), width: 1),
      ),
      child: Row(
        children: [
          const Text('개발용',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF856404))),
          const SizedBox(width: 8),
          Expanded(child: _devBtn('세션 초기화', _loadMockSession)),
          const SizedBox(width: 6),
          Expanded(child: _devBtn(
            '임시 카드선택',
            !_cardSelected
                ? () => _onMockCardSelected(
                    _currentCardOptions.isNotEmpty
                        ? _currentCardOptions[0]
                        : 1)
                : null,
          )),
          const SizedBox(width: 6),
          Expanded(child: _devBtn('결과 화면', _goToResult)),
        ],
      ),
    );
  }

  Widget _devBtn(String label, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: onTap == null
              ? const Color(0xFFEEEEEE)
              : const Color(0xFF111111),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: onTap == null
                    ? const Color(0xFFAAAAAA)
                    : Colors.white)),
      ),
    );
  }

  // ── 차트 ──────────────────────────────────
  Widget _buildChartArea() {
    return Expanded(
      flex: 4,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(8, 8, 12, 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: const Color(0xFFEEEEEE), width: 1),
        ),
        child: StockChart(
          rounds:       _chartData,
          initialAsset: _session.initialAsset.toDouble(),
        ),
      ),
    );
  }

  // ── 라운드 정보 (개선안 B - 박스 분리) ────────
  Widget _buildRoundInfo() {
    final round      = _currentRound;
    final returnRate = round.returnRate;
    final isPos      = (returnRate ?? 0) >= 0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 내 수익률 박스
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
              horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: const Color(0xFFEEEEEE), width: 1),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '내 수익률',
                style: TextStyle(
                    fontSize: 10, color: Color(0xFF6B7684)),
              ),
              Text(
                returnRate != null
                    ? '${isPos ? '+' : ''}${returnRate.toStringAsFixed(2)}%'
                    : '0.00%',
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: isPos
                        ? const Color(0xFFE03131)
                        : const Color(0xFF1971C2)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // 총 자산 박스
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
              horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: const Color(0xFFEEEEEE), width: 1),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '총 자산',
                style: TextStyle(
                    fontSize: 10, color: Color(0xFF6B7684)),
              ),
              Row(
                children: [
                  AnimatedBuilder(
                    animation: _assetAnim,
                    builder: (_, __) => Text(
                      '${_formatNumber(_assetAnim.value)}원',
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF111111)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(round.date,
                      style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFF6B7684))),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── 카드 선택 UI ───────────────────────────
  Widget _buildCardSelector() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEEEEEE), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('전략 카드를 선택하세요',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF6B7684))),
              const Spacer(),
              // AI 피드백 버튼: 항상 표시 (누르면 그때 요청)
              _buildFeedbackButton(),
              const SizedBox(width: 6),
              // AI 버튼: 25·50라운드만 표시
              if (_canUseV2) _buildAiButton(),
            ],
          ),

          // 로딩 바
          if (_aiState == AiState.loading) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: const LinearProgressIndicator(
                backgroundColor: Color(0xFFEEEDFE),
                valueColor:
                    AlwaysStoppedAnimation(Color(0xFF534AB7)),
                minHeight: 3,
              ),
            ),
            const SizedBox(height: 3),
            const Text('AI가 최적 카드를 분석 중입니다...',
                style: TextStyle(
                    fontSize: 9, color: Color(0xFF534AB7)),
                textAlign: TextAlign.center),
          ],

          const SizedBox(height: 10),

          // 카드 3개: 균등 패딩
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: List.generate(_currentCardOptions.length, (i) {
                final cardId = _currentCardOptions[i];
                final card   = CardInfo.fromId(cardId);
                if (card == null) return const SizedBox.shrink();
                final isLast = i == _currentCardOptions.length - 1;
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: isLast ? 0 : 8),
                    child: _buildCardItem(card),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  // ── AI 버튼 ────────────────────────────────
  // ── AI 피드백 버튼 (메모지 다이얼로그 열기) ──
  Widget _buildFeedbackButton() {
    return GestureDetector(
      onTap: _onFeedbackButtonTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFFEEEDFE),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF3C3489), width: 1),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline_rounded,
                size: 12, color: Color(0xFF3C3489)),
            SizedBox(width: 4),
            Text('AI 피드백',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF3C3489))),
          ],
        ),
      ),
    );
  }

  Widget _buildAiButton() {
    switch (_aiState) {
      case AiState.idle:
        return GestureDetector(
          onTap: _requestAiRecommendation,
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFF3C3489),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('✨', style: TextStyle(fontSize: 12)),
                SizedBox(width: 4),
                Text('AI 추천받기',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white)),
              ],
            ),
          ),
        );
      case AiState.loading:
        return Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFF534AB7).withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 10, height: 10,
                child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    valueColor:
                        AlwaysStoppedAnimation(Colors.white)),
              ),
              SizedBox(width: 6),
              Text('분석 중...',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.white)),
            ],
          ),
        );
      case AiState.done:
        return Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFF0F6E56),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('✅', style: TextStyle(fontSize: 12)),
              SizedBox(width: 4),
              Text('추천 완료',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.white)),
            ],
          ),
        );
      case AiState.error:
        return GestureDetector(
          onTap: _requestAiRecommendation,
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFE03131),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('⚠️', style: TextStyle(fontSize: 12)),
                SizedBox(width: 4),
                Text('다시 시도',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white)),
              ],
            ),
          ),
        );
    }
  }

  // ── 카드 아이템 ────────────────────────────
  Widget _buildCardItem(CardInfo card) {
    final aiPick      = _aiRecommendedCardId == card.id;
    final contribution = _contributions[card.id];
    final showContrib  =
        _aiRequested && _aiState == AiState.done && contribution != null;

    return GestureDetector(
      onTap: _isSubmitting ? null : () => _onCardSelected(card.id),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFEEEDFE),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFF534AB7),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 상단 영역: 뱃지 있든 없든 동일 높이 확보
            SizedBox(
              height: 20,
              child: aiPick
                  ? Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE03131),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('AI 추천',
                            style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: Colors.white)),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            const SizedBox(height: 2),

            Text(card.emoji,
                style: const TextStyle(fontSize: 22)),
            const SizedBox(height: 6),
            Text(card.name,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF3C3489))),
            const SizedBox(height: 4),
            Text(card.description,
                style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF534AB7),
                    height: 1.4)),

            // 기여도: 추천 완료 후에만
            if (showContrib) ...[
              const SizedBox(height: 6),
              Text(
                '${contribution >= 0 ? '+' : ''}${contribution.toStringAsFixed(2)}%',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: contribution >= 0
                        ? const Color(0xFF0F6E56)
                        : const Color(0xFF993C1D)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── 컨트롤 ────────────────────────────────
  Widget _buildControls() {
    return Row(
      children: [
        GestureDetector(
          onTap: _isAutoPlaying ? _stopAutoPlay : _startAutoPlay,
          child: Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              color: _isAutoPlaying
                  ? const Color(0xFF3C3489)
                  : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: const Color(0xFFEEEEEE), width: 1),
            ),
            child: Icon(
              _isAutoPlaying
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
              color: _isAutoPlaying
                  ? Colors.white
                  : const Color(0xFF111111),
              size: 24,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _isAutoPlaying
                  ? null
                  : _isLastRound
                      ? _goToResult
                      : _nextRound,
              style: ElevatedButton.styleFrom(
                backgroundColor: _isLastRound
                    ? const Color(0xFF3C3489)
                    : const Color(0xFF111111),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: Text(
                _isLastRound
                    ? '결과 보기'
                    : '다음 라운드 ($_currentRound1 / ${_session.totalRounds})',
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── 유틸 ──────────────────────────────────
  String _formatNumber(double value) {
    return value
        .toStringAsFixed(0)
        .replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]},',
        );
  }
}