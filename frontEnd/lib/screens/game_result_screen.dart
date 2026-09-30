import 'package:flutter/material.dart';
import '../models/game_session.dart';
import '../models/card_info.dart';
import '../models/result_analysis.dart';
import '../services/game_service.dart';

class GameResultScreen extends StatefulWidget {
  final GameSession session;

  const GameResultScreen({super.key, required this.session});

  @override
  State<GameResultScreen> createState() => _GameResultScreenState();
}

class _GameResultScreenState extends State<GameResultScreen>
    with SingleTickerProviderStateMixin {
  final GameService _gameService = GameService();

  late AnimationController _controller;
  late Animation<double> _assetAnim;
  late Animation<double> _returnAnim;

  // 사후 분석 (백테스팅, API v6.1)
  ResultAnalysis? _analysis;
  bool _analysisLoading = true;

  static const List<int> _selectRounds = [1, 25, 50, 75];

  static const Color _purple     = Color(0xFF3C3489);
  static const Color _purpleSoft = Color(0xFFEEEDFE);
  static const Color _gray       = Color(0xFF6B7684);
  static const Color _border     = Color(0xFFEEEEEE);
  static const Color _profitRed  = Color(0xFFE03131);
  static const Color _lossBlue   = Color(0xFF1971C2);

  double get _finalAsset {
    for (int i = widget.session.rounds.length - 1; i >= 0; i--) {
      if (widget.session.rounds[i].roundAsset != null) {
        return widget.session.rounds[i].roundAsset!;
      }
    }
    return widget.session.initialAsset.toDouble();
  }

  double get _finalReturnRate {
    for (int i = widget.session.rounds.length - 1; i >= 0; i--) {
      if (widget.session.rounds[i].returnRate != null) {
        return widget.session.rounds[i].returnRate!;
      }
    }
    return 0.0;
  }

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    // 자산 카운트업: initialAsset → finalAsset
    _assetAnim = Tween<double>(
      begin: widget.session.initialAsset.toDouble(),
      end: _finalAsset,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.8, curve: Curves.easeOut),
    ));

    // 수익률 카운트업: 0 → finalReturnRate
    _returnAnim = Tween<double>(
      begin: 0,
      end: _finalReturnRate,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.8, curve: Curves.easeOut),
    ));

    // 화면 진입 후 0.3초 딜레이 후 시작
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _controller.forward();
    });

    // 사후 분석: 결과 화면 진입 시 1회 호출 (v6.1 합의 2번)
    _loadAnalysis();
  }

  Future<void> _loadAnalysis() async {
    final result = await _gameService.getResultAnalysis(
      sessionId: widget.session.sessionId,
    );
    if (!mounted) return;
    setState(() {
      _analysis        = result;
      _analysisLoading = false;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _formatNumber(double value) {
    return value
        .toStringAsFixed(0)
        .replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]},',
        );
  }

  String _formatRate(double v) =>
      '${v >= 0 ? '+' : ''}${v.toStringAsFixed(2)}%';

  Color _rateColor(double v) => v >= 0 ? _profitRed : _lossBlue;

  // 상위 % 표기 (0.1 미만이면 "상위 0.1% 이내")
  String _formatTopPercent(double p) =>
      p < 0.1 ? '상위 0.1% 이내' : '상위 ${p.toStringAsFixed(1)}%';

  String _cardEmoji(int cardId) => CardInfo.fromId(cardId)?.emoji ?? '🃏';

  String _cardName(AnalysisCard c) => c.cardName.isNotEmpty
      ? c.cardName
      : (CardInfo.fromId(c.cardId)?.name ?? '카드 ${c.cardId}');

  @override
  Widget build(BuildContext context) {
    final profit     = _finalReturnRate >= 0;
    final color      = profit ? _profitRed : _lossBlue;

    return Scaffold(
      backgroundColor: const Color(0xFFFAF9F5),
      body: SafeArea(
        child: Column(
          children: [
            // 스크롤 영역 (사후 분석 섹션이 추가되어 화면을 넘칠 수 있음)
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 40, 24, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 태그
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _purpleSoft,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text('게임 종료',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _purple)),
                    ),
                    const SizedBox(height: 12),

                    // 시나리오 제목
                    Text(
                      widget.session.scenarioTitle,
                      style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF111111)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${widget.session.totalRounds}라운드 완료',
                      style: const TextStyle(fontSize: 14, color: _gray),
                    ),

                    const SizedBox(height: 28),

                    _buildAssetCard(profit, color),
                    const SizedBox(height: 16),
                    _buildReturnBadge(profit, color),

                    const SizedBox(height: 28),

                    _buildAnalysisSection(),
                  ],
                ),
              ),
            ),

            // 다시 하기 버튼 (하단 고정)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context)
                        .popUntil((route) => route.isFirst);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF111111),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('다시 시작하기',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =============================================
  // 기존: 자산 변화 카드
  // =============================================
  Widget _buildAssetCard(bool profit, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border, width: 1),
      ),
      child: Column(
        children: [
          // 시작 자산
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('시작 자산',
                  style: TextStyle(fontSize: 14, color: _gray)),
              Text(
                '₩${_formatNumber(widget.session.initialAsset.toDouble())}',
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF111111)),
              ),
            ],
          ),

          // 화살표
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              children: [
                Expanded(child: Container(height: 1, color: _border)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Icon(
                    profit
                        ? Icons.arrow_upward_rounded
                        : Icons.arrow_downward_rounded,
                    color: color,
                    size: 28,
                  ),
                ),
                Expanded(child: Container(height: 1, color: _border)),
              ],
            ),
          ),

          // 최종 자산 (카운트업)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('최종 자산',
                  style: TextStyle(fontSize: 14, color: _gray)),
              AnimatedBuilder(
                animation: _assetAnim,
                builder: (_, __) => Text(
                  '₩${_formatNumber(_assetAnim.value)}',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: color),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // =============================================
  // 기존: 수익률 뱃지 (카운트업)
  // =============================================
  Widget _buildReturnBadge(bool profit, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2), width: 1),
      ),
      child: Column(
        children: [
          AnimatedBuilder(
            animation: _returnAnim,
            builder: (_, __) {
              final val = _returnAnim.value;
              return Text(
                _formatRate(val),
                style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w800,
                    color: _rateColor(val)),
              );
            },
          ),
          const SizedBox(height: 4),
          Text(
            profit ? '수익을 달성했어요 🎉' : '손실이 발생했어요',
            style: TextStyle(
                fontSize: 14,
                color: color.withValues(alpha: 0.8),
                fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  // =============================================
  // 신규: 사후 분석 섹션 (백테스팅, API v6.1)
  // =============================================
  Widget _buildAnalysisSection() {
    if (_analysisLoading) return _buildAnalysisLoading();

    // 실패·데이터 없음 → 섹션 자체를 표시하지 않음 (명세서 4장)
    final a = _analysis;
    if (a == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 제목 + 기준 범위
        Row(
          children: [
            const Text('사후 분석',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF111111))),
            const Spacer(),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _purpleSoft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text('11장 전체 조합 기준',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: _purple)),
            ),
          ],
        ),
        const SizedBox(height: 10),

        _buildRankCard(a),
        const SizedBox(height: 12),

        if (a.best != null) ...[
          _buildCompareCard(a, a.best!),
          const SizedBox(height: 12),
        ],

        if (a.topCombos.isNotEmpty) ...[
          _buildTopCombosCard(a),
          const SizedBox(height: 10),
        ],

        // 계산 근거 (명세서 6장)
        const Text(
          '게임 종료 후 100라운드 시장 데이터를 모두 사용하여 계산한 결과로, '
          '게임 중에는 알 수 없는 정보입니다. 라운드마다 카드가 3장씩만 '
          '제시되므로, 최적 조합에는 이번 게임에서 보지 못한 카드가 포함될 수 있어요.',
          style: TextStyle(fontSize: 10.5, color: _gray, height: 1.5),
        ),
      ],
    );
  }

  // 로딩 (서버 계산 약 3.7초)
  Widget _buildAnalysisLoading() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border, width: 1),
      ),
      child: const Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(_purple),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text('7,920개 카드 조합을 모두 계산하는 중이에요...',
                style: TextStyle(fontSize: 12, color: _gray)),
          ),
        ],
      ),
    );
  }

  // ① 내 조합 순위
  Widget _buildRankCard(ResultAnalysis a) {
    final p        = a.playerResult;
    final isBest   = p.rank == 1;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('내 조합 순위',
              style: TextStyle(fontSize: 12, color: _gray)),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${_formatNumber(p.rank.toDouble())}위',
                style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: _purple),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(
                  '/ ${_formatNumber(a.totalCombinations.toDouble())}개 조합',
                  style: const TextStyle(fontSize: 12, color: _gray),
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _purple,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _formatTopPercent(p.topPercent),
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white),
                ),
              ),
            ],
          ),
          if (isBest) ...[
            const SizedBox(height: 8),
            const Text('가능한 조합 중 가장 좋은 선택이었어요 🎉',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _purple)),
          ],
        ],
      ),
    );
  }

  // ② 내 조합 vs 1위 조합 (라운드별 비교)
  Widget _buildCompareCard(ResultAnalysis a, ComboResult best) {
    final p = a.playerResult;
    final matchCount = _selectRounds.where((r) {
      final mine = p.cardAt(r);
      final top  = best.cardAt(r);
      return mine != null && top != null && mine.cardId == top.cardId;
    }).length;
    final bestLabel = a.isTied(best.rank) ? '공동 1위 중 하나' : '1위 조합';
    final diff      = best.finalReturnRate - p.finalReturnRate;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('내 조합 vs 1위 조합',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF111111))),
              const Spacer(),
              Text('4장 중 $matchCount장 일치',
                  style: const TextStyle(fontSize: 11, color: _gray)),
            ],
          ),
          const SizedBox(height: 12),

          // 헤더
          Row(
            children: [
              const SizedBox(
                  width: 36,
                  child: Text('라운드',
                      style: TextStyle(fontSize: 10, color: _gray))),
              const Expanded(
                  child: Text('내 선택',
                      style: TextStyle(fontSize: 10, color: _gray))),
              const SizedBox(width: 20),
              Expanded(
                  child: Text(bestLabel,
                      style: const TextStyle(fontSize: 10, color: _gray))),
            ],
          ),
          const SizedBox(height: 6),

          ..._selectRounds.map((r) {
            final mine = p.cardAt(r);
            final top  = best.cardAt(r);
            final same = mine != null && top != null && mine.cardId == top.cardId;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 36,
                    child: Text('${r}R',
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _gray)),
                  ),
                  Expanded(child: _buildCardChip(mine, highlight: same)),
                  SizedBox(
                    width: 20,
                    child: Icon(
                      same ? Icons.check_rounded : Icons.chevron_right_rounded,
                      size: 14,
                      color: same ? const Color(0xFF0F6E56) : _gray,
                    ),
                  ),
                  Expanded(child: _buildCardChip(top, highlight: same)),
                ],
              ),
            );
          }),

          const SizedBox(height: 10),
          Container(height: 1, color: _border),
          const SizedBox(height: 10),

          // 수익률 비교
          Row(
            children: [
              Expanded(
                child: _buildRateColumn('내 수익률', p.finalReturnRate),
              ),
              Expanded(
                child: _buildRateColumn('1위 수익률', best.finalReturnRate),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('차이',
                      style: TextStyle(fontSize: 10, color: _gray)),
                  const SizedBox(height: 2),
                  Text('${diff.toStringAsFixed(2)}%p',
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF111111))),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRateColumn(String label, double rate) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: _gray)),
        const SizedBox(height: 2),
        Text(_formatRate(rate),
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _rateColor(rate))),
      ],
    );
  }

  Widget _buildCardChip(AnalysisCard? card, {bool highlight = false}) {
    if (card == null) {
      return const Text('-', style: TextStyle(fontSize: 11, color: _gray));
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: highlight ? _purpleSoft : const Color(0xFFF7F7F9),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Text(_cardEmoji(card.cardId), style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              _cardName(card),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: highlight ? FontWeight.w700 : FontWeight.w500,
                  color: highlight ? _purple : const Color(0xFF333333)),
            ),
          ),
        ],
      ),
    );
  }

  // ③ 이 시나리오의 최적 조합 Top N
  Widget _buildTopCombosCard(ResultAnalysis a) {
    // 상위 조합이 모두 같은 순위면 "발동하지 않은 카드만 다른" 경우라 안내
    final allTied = a.topCombos.length > 1 &&
        a.topCombos.every((c) => c.rank == a.topCombos.first.rank);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('이 시나리오의 최적 조합 Top ${a.topCombos.length}',
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111111))),
          const SizedBox(height: 12),
          ...a.topCombos.map((c) => _buildComboRow(a, c)),
          if (allTied) ...[
            const SizedBox(height: 4),
            const Text(
              '결과가 똑같은 조합이 여러 개예요. 한 번도 발동하지 않은 카드만 '
              '다른 경우 최종 자산이 같아요.',
              style: TextStyle(fontSize: 10.5, color: _gray, height: 1.5),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildComboRow(ResultAnalysis a, ComboResult c) {
    final rankLabel = a.isTied(c.rank) ? '공동 ${c.rank}위' : '${c.rank}위';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: c.rank == 1 ? _purple : _purpleSoft,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(rankLabel,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: c.rank == 1 ? Colors.white : _purple)),
              ),
              const Spacer(),
              Text(_formatRate(c.finalReturnRate),
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _rateColor(c.finalReturnRate))),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: c.cards.map((card) {
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F7F9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${card.round}R ${_cardEmoji(card.cardId)} ${_cardName(card)}',
                  style: const TextStyle(
                      fontSize: 10.5, color: Color(0xFF333333)),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}