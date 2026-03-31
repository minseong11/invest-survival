import 'package:flutter/material.dart';
import '../models/game_session.dart';
import '../models/round_data.dart';
import '../models/action_result.dart';
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

  // 카드 선택 완료 여부
  bool _cardSelected = false;

  // 카드 선택 로딩
  bool _isSubmitting = false;

  RoundData get _currentRound => _session.rounds[_currentRoundIndex];
  List<RoundData> get _chartData => _session.getChartData(_currentRoundIndex);
  String get _ticker => _currentRound.priceData.isNotEmpty
      ? _currentRound.priceData[0].ticker
      : '';

  // 1라운드에 카드가 나와야 하는지
  bool get _showCard => _currentRoundIndex == 0 && !_cardSelected;

  @override
  void initState() {
    super.initState();
    _session = widget.session;
  }

  void _loadMockSession() {
    final mockSession = GameSession.fromJson(
      MockData.gameSession['data'] as Map<String, dynamic>,
    );
    setState(() {
      _session = mockSession;
      _currentRoundIndex = 0;
      _cardSelected = false;
    });
  }

  // 카드 선택 → POST /game/round/action
  Future<void> _onCardSelected(int cardId) async {
    setState(() => _isSubmitting = true);

    try {
      final result = await _gameService.submitAction(
        sessionId: _session.sessionId,
        round: _currentRound.round,
        cardId: cardId,
      );
      _applyActionResult(result);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          backgroundColor: Colors.red[700],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // 임시 데이터로 카드 선택 테스트
  void _onMockCardSelected() {
    final result = ActionResult.fromJson(
      MockData.actionResult['data'] as Map<String, dynamic>,
    );
    _applyActionResult(result);
  }

  // 카드 선택 결과를 세션 rounds에 반영
  void _applyActionResult(ActionResult result) {
    // 기존 rounds에서 actionResult의 rounds로 교체
    final updatedRounds = List<RoundData>.from(_session.rounds);
    for (final newRound in result.rounds) {
      final index = newRound.round - 1; // round는 1-based
      if (index >= 0 && index < updatedRounds.length) {
        updatedRounds[index] = newRound;
      }
    }

    setState(() {
      _session = GameSession(
        sessionId: _session.sessionId,
        scenarioTitle: _session.scenarioTitle,
        totalRounds: _session.totalRounds,
        initialAsset: _session.initialAsset,
        rounds: updatedRounds,
      );
      _cardSelected = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF9F5),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _buildMockButton(),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Column(
                  children: [
                    _buildChartArea(),
                    const SizedBox(height: 12),
                    _buildRoundInfo(),
                    const SizedBox(height: 12),

                    // 1라운드 + 카드 미선택 → 카드 UI
                    // 그 외 → 다음 라운드 버튼
                    _showCard
                        ? _buildCardSelector()
                        : _buildNextRoundButton(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

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
          const Text(
            '개발용',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF856404),
            ),
          ),
          const SizedBox(width: 8),
          _devButton('세션 초기화', _loadMockSession),
          const SizedBox(width: 6),
          _devButton('임시 카드선택', _onMockCardSelected),
        ],
      ),
    );
  }

  Widget _devButton(String label, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF111111),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: const Icon(
              Icons.arrow_back_ios_rounded,
              size: 18,
              color: Color(0xFF111111),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _session.scenarioTitle,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Color(0xFF111111),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFEEEDFE),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${_currentRoundIndex + 1} / ${_session.totalRounds}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF3C3489),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartArea() {
    return Expanded(
      flex: 7,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFEEEEEE), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 12),
              child: Row(
                children: [
                  Text(
                    _ticker,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF6B7684),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _currentRound.priceData.isNotEmpty
                        ? _currentRound.priceData[0].close.toStringAsFixed(2)
                        : '-',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF111111),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: StockChart(
                rounds: _chartData,
                ticker: _ticker,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoundInfo() {
    final round = _currentRound;
    final asset = round.roundAsset ?? _session.initialAsset;
    final returnRate = round.returnRate;
    final isPositiveReturn = (returnRate ?? 0) >= 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEEEEEE), width: 1),
      ),
      child: Row(
        children: [
          // 날짜 + 종목 등락률
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  round.date,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6B7684),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: round.priceData.map((price) {
                    final isPositive = price.isPositive;
                    return Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            price.ticker,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF6B7684),
                            ),
                          ),
                          Text(
                            '${isPositive ? '+' : ''}${price.changeRate.toStringAsFixed(2)}%',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isPositive
                                  ? const Color(0xFFE03131)
                                  : const Color(0xFF1971C2),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),

          // 총자산 + 수익률
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                '총자산',
                style: TextStyle(
                  fontSize: 11,
                  color: Color(0xFF6B7684),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '₩${_formatNumber(asset)}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111111),
                ),
              ),
              if (returnRate != null) ...[
                const SizedBox(height: 2),
                Text(
                  '${isPositiveReturn ? '+' : ''}${returnRate.toStringAsFixed(2)}%',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isPositiveReturn
                        ? const Color(0xFFE03131)
                        : const Color(0xFF1971C2),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // 1라운드 카드 선택 UI
  Widget _buildCardSelector() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEEEEEE), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '전략 카드를 선택하세요',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF6B7684),
            ),
          ),
          const SizedBox(height: 10),

          // 거인의 어깨 카드
          GestureDetector(
            onTap: _isSubmitting ? null : () => _onCardSelected(1),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFEEEDFE),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF534AB7),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '거인의 어깨',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF3C3489),
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          '현재 자산의 30%로 S&P500 즉시 매수',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF534AB7),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_isSubmitting)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF534AB7),
                      ),
                    )
                  else
                    const Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 16,
                      color: Color(0xFF534AB7),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNextRoundButton() {
    final isLastRound = _currentRoundIndex >= _session.totalRounds - 1;

    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: isLastRound
            ? null
            : () => setState(() => _currentRoundIndex++),
        style: ElevatedButton.styleFrom(
          backgroundColor: isLastRound
              ? const Color(0xFFEEEEEE)
              : const Color(0xFF111111),
          foregroundColor: isLastRound
              ? const Color(0xFFAAAAAA)
              : Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Text(
          isLastRound
              ? '게임 종료'
              : '다음 라운드 (${_currentRoundIndex + 2}/${_session.totalRounds})',
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  String _formatNumber(double value) {
    return value.toStringAsFixed(0).replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    );
  }
}