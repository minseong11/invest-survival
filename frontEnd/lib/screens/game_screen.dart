import 'dart:async';
import 'package:flutter/material.dart';
import '../models/game_session.dart';
import '../models/round_data.dart';
import '../models/action_result.dart';
import '../models/card_info.dart';
import '../services/game_service.dart';
import '../services/mock_data.dart';
import '../widgets/stock_chart.dart';

class GameScreen extends StatefulWidget {
  final GameSession session;
  const GameScreen({super.key, required this.session});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  final GameService _gameService = GameService();

  late GameSession _session;
  int _currentRoundIndex = 0;

  bool _cardSelected = false;
  bool _isSubmitting = false;
  bool _isAutoPlaying = false;

  // 현재 표시할 카드 선택지
  List<int> _currentCardOptions = [];

  Timer? _autoTimer;

  RoundData get _currentRound {
    final index = _currentRoundIndex.clamp(0, _session.rounds.length - 1);
    return _session.rounds[index];
  }

  List<RoundData> get _chartData => _session.getChartData(
    _currentRoundIndex.clamp(0, _session.rounds.length - 1),
  );

  // 현재 라운드 번호 (1-based)
  int get _currentRound1 => _currentRoundIndex + 1;

  bool get _showCard {
    if (_cardSelected) return false;
    // cardSelectRounds가 있으면 그 기준으로, 없으면 1라운드에 표시
    if (_session.cardSelectRounds.isNotEmpty) {
      return _session.isCardSelectRound(_currentRound1);
    }
    return _currentRound1 == 1;
  }

  // 카드 선택 전엔 종료 버튼 안 보임
  // 다음 라운드가 카드 선택 라운드면 마지막 아님
  bool get _isLastRound {
    if (!_cardSelected) return false;
    final nextRound = _currentRoundIndex + 2;
    if (_session.isCardSelectRound(nextRound)) return false;
    return _currentRoundIndex >= _session.rounds.length - 1;
  }

  @override
  void initState() {
    super.initState();
    _session = widget.session;
    _currentCardOptions = _session.firstCardOptions;
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    super.dispose();
  }

  // ── 자동 진행 ──────────────────────────────
  void _startAutoPlay() {
    setState(() => _isAutoPlaying = true);
    _autoTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      final nextRound = _currentRoundIndex + 2;
      final willHitCard = _session.isCardSelectRound(nextRound);

      if (_isLastRound || willHitCard) {
        _stopAutoPlay();
        if (!_isLastRound) {
          setState(() {
            _currentRoundIndex++;
            _cardSelected = false;
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

  // ── 다음 라운드 (수동) ──────────────────────
  void _nextRound() {
    if (_isLastRound) return;
    final nextRound = _currentRoundIndex + 2;
    setState(() {
      _currentRoundIndex++;
      if (_session.isCardSelectRound(nextRound)) {
        _cardSelected = false;
      }
    });
  }

  // ── 카드 선택 (실제 API) ────────────────────
  Future<void> _onCardSelected(int cardId) async {
    setState(() => _isSubmitting = true);
    try {
      final result = await _gameService.submitAction(
        sessionId: _session.sessionId,
        round: _currentRound1,  // 1-based 라운드 번호
        cardId: cardId,
      );
      _applyActionResult(result);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString()),
        backgroundColor: Colors.red[700],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ── 카드 선택 (Mock) ────────────────────────
  void _onMockCardSelected(int cardId) {
    final mockData = MockData.getActionResult(_currentRoundIndex);
    final result = ActionResult.fromJson(
      mockData['data'] as Map<String, dynamic>,
    );
    _applyActionResult(result);
  }

  // ── ActionResult 반영 ───────────────────────
  void _applyActionResult(ActionResult result) {
    // 디버그 확인용
    print('=== ActionResult ===');
    print('nextEventRound: ${result.nextEventRound}');
    print('nextCardOptions: ${result.nextCardOptions}');
    print('rounds count: ${result.rounds.length}');
    if (result.rounds.isNotEmpty) {
      print('rounds: ${result.rounds.first.round} ~ ${result.rounds.last.round}');
    }
    // 기존 rounds에 새 rounds 덮어쓰기
    // 서버가 준 rounds를 index 기준으로 교체
    // 기존보다 크면 늘려서 추가
    final updatedRounds = List<RoundData>.from(_session.rounds);
    for (final newRound in result.rounds) {
      final index = newRound.round - 1;
      if (index < updatedRounds.length) {
        updatedRounds[index] = newRound;         // 기존 자리 교체
      } else {
        // 기존 리스트보다 크면 빈칸 채우며 추가
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
      _cardSelected = true;
      _currentCardOptions = result.nextCardOptions;
    });
  }

  // ── Mock 세션 초기화 ────────────────────────
  void _loadMockSession() {
    _stopAutoPlay();
    final mockSession = GameSession.fromJson(
      MockData.gameSession['data'] as Map<String, dynamic>,
    );
    setState(() {
      _session = mockSession;
      _currentRoundIndex = 0;
      _cardSelected = false;
      _currentCardOptions = mockSession.firstCardOptions;
    });
  }

  // ── Build ───────────────────────────────────
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
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                child: Column(
                  children: [
                    _buildChartArea(),
                    const SizedBox(height: 10),
                    _buildRoundInfo(),
                    const SizedBox(height: 10),
                    _showCard
                        ? _buildCardSelector()
                        : _buildControls(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 헤더 ────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
      child: Row(
        children: [
          GestureDetector(
            onTap: () { _stopAutoPlay(); Navigator.pop(context); },
            child: const Icon(Icons.arrow_back_ios_rounded, size: 18, color: Color(0xFF111111)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(_session.scenarioTitle,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFF111111))),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFEEEDFE),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$_currentRound1 / ${_session.totalRounds}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF3C3489)),
            ),
          ),
        ],
      ),
    );
  }

  // ── 개발용 버튼 ─────────────────────────────
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
          const Text('개발용', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF856404))),
          const SizedBox(width: 8),
          Expanded(child: _devBtn('세션 초기화', _loadMockSession)),
          const SizedBox(width: 6),
          Expanded(child: _devBtn(
            '임시 카드선택',
            !_cardSelected
                ? () => _onMockCardSelected(_currentCardOptions.isNotEmpty ? _currentCardOptions[0] : 1)
                : null,
          )),
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
          color: onTap == null ? const Color(0xFFEEEEEE) : const Color(0xFF111111),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(label,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
            color: onTap == null ? const Color(0xFFAAAAAA) : Colors.white)),
      ),
    );
  }

  // ── 차트 영역 ───────────────────────────────
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
        child: StockChart(rounds: _chartData),
      ),
    );
  }

  // ── 라운드 정보 ─────────────────────────────
  Widget _buildRoundInfo() {
    final round = _currentRound;
    final asset = round.roundAsset ?? _session.initialAsset;
    final returnRate = round.returnRate;
    final isPos = (returnRate ?? 0) >= 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEEEEEE), width: 1),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(round.date, style: const TextStyle(fontSize: 12, color: Color(0xFF6B7684))),
                const SizedBox(height: 4),
                Row(
                  children: round.priceData.map((price) => Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Row(
                      children: [
                        Container(width: 8, height: 8, decoration: BoxDecoration(
                          color: tickerColor(price.ticker), shape: BoxShape.circle,
                        )),
                        const SizedBox(width: 4),
                        Text(
                          '${price.ticker} ${price.changeRate >= 0 ? '+' : ''}${price.changeRate.toStringAsFixed(2)}%',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                            color: price.isPositive ? const Color(0xFFE03131) : const Color(0xFF1971C2)),
                        ),
                      ],
                    ),
                  )).toList(),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text('총자산', style: TextStyle(fontSize: 11, color: Color(0xFF6B7684))),
              Text('₩${_formatNumber(asset)}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF111111))),
              if (returnRate != null)
                Text(
                  '${isPos ? '+' : ''}${returnRate.toStringAsFixed(2)}%',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                    color: isPos ? const Color(0xFFE03131) : const Color(0xFF1971C2)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ── 카드 선택 UI ────────────────────────────
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
          const Text('전략 카드를 선택하세요',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF6B7684))),
          const SizedBox(height: 10),
          Row(
            children: _currentCardOptions.map((cardId) {
              final card = CardInfo.fromId(cardId);
              if (card == null) return const SizedBox.shrink();
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _buildCardItem(card),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildCardItem(CardInfo card) {
    return GestureDetector(
      onTap: _isSubmitting ? null : () => _onCardSelected(card.id),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFEEEDFE),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF534AB7), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(card.emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(height: 6),
            Text(card.name,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF3C3489))),
            const SizedBox(height: 4),
            Text(card.description,
              style: const TextStyle(fontSize: 10, color: Color(0xFF534AB7), height: 1.4)),
          ],
        ),
      ),
    );
  }

  // ── 수동/자동 컨트롤 ────────────────────────
  Widget _buildControls() {
    return Row(
      children: [
        // 자동 재생 토글
        GestureDetector(
          onTap: _isAutoPlaying ? _stopAutoPlay : _startAutoPlay,
          child: Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              color: _isAutoPlaying ? const Color(0xFF3C3489) : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFEEEEEE), width: 1),
            ),
            child: Icon(
              _isAutoPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: _isAutoPlaying ? Colors.white : const Color(0xFF111111),
              size: 24,
            ),
          ),
        ),
        const SizedBox(width: 10),

        // 다음 라운드 버튼
        Expanded(
          child: SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: (_isLastRound || _isAutoPlaying) ? null : _nextRound,
              style: ElevatedButton.styleFrom(
                backgroundColor: _isLastRound ? const Color(0xFFEEEEEE) : const Color(0xFF111111),
                foregroundColor: _isLastRound ? const Color(0xFFAAAAAA) : Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: Text(
                _isLastRound ? '게임 종료' : '다음 라운드 ($_currentRound1 / ${_session.totalRounds})',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _formatNumber(double value) {
    return value.toStringAsFixed(0).replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    );
  }
}