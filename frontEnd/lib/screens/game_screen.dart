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

// AI 추천 버튼 상태
enum AiState { idle, loading, done, error }

class GameScreen extends StatefulWidget {
  final GameSession session;
  const GameScreen({super.key, required this.session});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  final GameService _gameService = GameService();

  late GameSession _session;
  int  _currentRoundIndex = 0;
  bool _cardSelected      = false;
  bool _isSubmitting      = false;
  bool _isAutoPlaying     = false;

  List<int> _currentCardOptions = [];

  // 이미 선택한 카드 누적 (V2 alreadyCards 파라미터용)
  final List<int> _selectedCardIds = [];
  int? _lastAddedCardId;

  // V1.5: 게임 시작 후 백그라운드 로딩
  Map<int, int> _v1RecommendedCards = {}; // {라운드: cardId}

  // V2: AI 추천받기 버튼 눌렀을 때만 동작
  AiState          _aiState             = AiState.idle;
  int?             _v2RecommendedCardId;
  Map<int, double> _contributions       = {}; // {cardId: contribution}
  bool             _aiRequested         = false;

  Timer? _autoTimer;

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

  // V2 사용 가능한 라운드: 25·50만 (75 역상관 제외)
  bool get _canUseV2 => [25, 50].contains(_currentRound1);

  // AI 추천 카드 ID (V2 우선, 없으면 V1.5)
  int? get _aiRecommendedCardId {
    if (!_aiRequested || _aiState != AiState.done) return null;
    return _v2RecommendedCardId ?? _v1RecommendedCards[_currentRound1];
  }

  // 보유 종목 데이터
  List<HoldingInfo> get _holdings => extractHoldings(
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
    _loadV1InBackground();
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
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
    }).catchError((_) {
      // V1.5 실패해도 게임 진행 가능
    });
  }

  // =============================================
  // V2 AI 추천 (버튼 클릭 시)
  // =============================================
  Future<void> _requestAiRecommendation() async {
    if (_aiState == AiState.loading) return;
    setState(() {
      _aiRequested         = true;
      _aiState             = AiState.loading;
      _v2RecommendedCardId = null;
      _contributions       = {};
    });

    try {
      if (_canUseV2) {
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
          _aiState             = AiState.done;
        });
      } else {
        // 1·75라운드: V1.5 사전 추천 사용
        await Future.delayed(const Duration(milliseconds: 300));
        if (!mounted) return;
        setState(() => _aiState = AiState.done);
      }
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
            _cardSelected = false;
            _resetAiState();
          });
        }
      } else {
        setState(() => _currentRoundIndex++);
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
      if (_session.isCardSelectRound(next)) {
        _cardSelected = false;
        _resetAiState();
      }
    });
  }

  void _goToResult() {
    _stopAutoPlay();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => GameResultScreen(session: _session)),
    );
  }

  // =============================================
  // 카드 선택 API
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
      _lastAddedCardId = selectedCardId;
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
                  children: [
                    _buildChartArea(),
                    const SizedBox(height: 8),
                    _buildRoundInfo(),
                    const SizedBox(height: 8),
                    if (_showCard) ...[
                      if (_selectedCardIds.isNotEmpty) ...[
                        HoldingsMiniGrid(holdings: _holdings),
                        const SizedBox(height: 8),
                      ],
                      _buildCardSelector(),
                    ] else ...[
                      if (_selectedCardIds.isNotEmpty) ...[
                        HoldingsGameWidget(holdings: _holdings),
                        const SizedBox(height: 8),
                      ],
                      _buildControls(),
                    ],
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
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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

  // ── 차트 (수익률%) ─────────────────────────
  Widget _buildChartArea() {
    return Expanded(
      flex: 7,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(8, 12, 12, 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFEEEEEE), width: 1),
        ),
        child: StockChart(
          rounds:       _chartData,
          initialAsset: _session.initialAsset.toDouble(),
        ),
      ),
    );
  }

  // ── 라운드 정보 ────────────────────────────
  Widget _buildRoundInfo() {
    final round      = _currentRound;
    final asset      = round.roundAsset ?? _session.initialAsset.toDouble();
    final returnRate = round.returnRate;
    final isPos      = (returnRate ?? 0) >= 0;

    // 시장 대비 우위 계산
    double? spxReturnRate;
    final spxBase = _session.rounds.isNotEmpty
        ? _session.rounds.first.getPrice('^SPX')?.close
        : null;
    final spxNow = round.getPrice('^SPX')?.close;
    if (spxBase != null && spxNow != null && spxBase > 0) {
      spxReturnRate = (spxNow - spxBase) / spxBase * 100;
    }
    final beatMarket = returnRate != null &&
        spxReturnRate != null &&
        returnRate > spxReturnRate;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEEEEEE), width: 1),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(round.date,
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF6B7684))),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: round.priceData.map((price) {
                        final pos = price.changeRate >= 0;
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8, height: 8,
                              decoration: BoxDecoration(
                                color: _tickerColor(price.ticker),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${price.ticker} ${pos ? '+' : ''}${price.changeRate.toStringAsFixed(2)}%',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: pos
                                      ? const Color(0xFFE03131)
                                      : const Color(0xFF1971C2)),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${_formatNumber(asset)}원',
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF111111))),
                  if (returnRate != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      '${isPos ? '+' : ''}${returnRate.toStringAsFixed(2)}%',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isPos
                              ? const Color(0xFFE03131)
                              : const Color(0xFF1971C2)),
                    ),
                  ],
                ],
              ),
            ],
          ),

          // 시장 대비 배너
          if (returnRate != null && spxReturnRate != null) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: beatMarket
                    ? const Color(0xFFE6F9F0)
                    : const Color(0xFFFFF0F0),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                beatMarket
                    ? '▲ 시장 대비 +${(returnRate - spxReturnRate).toStringAsFixed(1)}%p 우위'
                    : '▼ 시장 대비 ${(returnRate - spxReturnRate).toStringAsFixed(1)}%p 뒤처짐',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: beatMarket
                        ? const Color(0xFF0F6E56)
                        : const Color(0xFFE03131)),
                textAlign: TextAlign.center,
              ),
            ),
          ],

          // 발동 카드
          if (round.triggeredCards.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFEEEDFE),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Wrap(
                spacing: 6,
                children: round.triggeredCards.map((id) {
                  final card = CardInfo.fromId(id);
                  if (card == null) return const SizedBox.shrink();
                  return Text('${card.emoji} ${card.name} 발동',
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF3C3489)));
                }).toList(),
              ),
            ),
          ],
        ],
      ),
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
              _buildAiButton(),
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

          Row(
            children: _currentCardOptions.asMap().entries.map((e) {
              final cardId = e.value;
              final last   = e.key == _currentCardOptions.length - 1;
              final card   = CardInfo.fromId(cardId);
              if (card == null) return const SizedBox.shrink();
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: last ? 0 : 8),
                  child: _buildCardItem(card),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ── AI 버튼 ────────────────────────────────
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
    final aiPick       = _aiRecommendedCardId == card.id;
    final contribution = _contributions[card.id];
    final showContrib  =
        _aiRequested && _aiState == AiState.done && contribution != null;

    return GestureDetector(
      onTap: _isSubmitting ? null : () => _onCardSelected(card.id),
      child: Stack(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: aiPick
                  ? const Color(0xFFDEDCFD)
                  : const Color(0xFFEEEDFE),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: aiPick
                    ? const Color(0xFF3C3489)
                    : const Color(0xFF534AB7),
                width: aiPick ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                // 기여도: 버튼 눌러서 완료됐을 때만
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
          // AI 추천 뱃지
          if (aiPick)
            Positioned(
              top: 4, right: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF3C3489),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('AI 추천',
                    style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
              ),
            ),
        ],
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
  Color _tickerColor(String ticker) {
    const colors = {
      '^SPX': Color(0xFF1971C2),
      '^NDX': Color(0xFF7048E8),
      'GLD':  Color(0xFFE67700),
      'USO':  Color(0xFF2F9E44),
      'AAPL': Color(0xFF868E96),
      'TLT':  Color(0xFFE64980),
    };
    return colors[ticker] ?? const Color(0xFF6B7684);
  }

  String _formatNumber(double value) {
    return value
        .toStringAsFixed(0)
        .replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]},',
        );
  }
}