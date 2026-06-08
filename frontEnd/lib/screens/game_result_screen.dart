import 'package:flutter/material.dart';
import '../models/game_session.dart';

class GameResultScreen extends StatefulWidget {
  final GameSession session;

  const GameResultScreen({super.key, required this.session});

  @override
  State<GameResultScreen> createState() => _GameResultScreenState();
}

class _GameResultScreenState extends State<GameResultScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _assetAnim;
  late Animation<double> _returnAnim;

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

  @override
  Widget build(BuildContext context) {
    final profit     = _finalReturnRate >= 0;
    final returnRate = _finalReturnRate;
    final color      = profit
        ? const Color(0xFFE03131)
        : const Color(0xFF1971C2);

    return Scaffold(
      backgroundColor: const Color(0xFFFAF9F5),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 40, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 태그
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEEDFE),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text('게임 종료',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF3C3489))),
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
                style: const TextStyle(
                    fontSize: 14, color: Color(0xFF6B7684)),
              ),

              const Spacer(),

              // 자산 변화 카드
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: const Color(0xFFEEEEEE), width: 1),
                ),
                child: Column(
                  children: [
                    // 시작 자산
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('시작 자산',
                            style: TextStyle(
                                fontSize: 14,
                                color: Color(0xFF6B7684))),
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
                          Expanded(
                              child: Container(
                                  height: 1,
                                  color: const Color(0xFFEEEEEE))),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12),
                            child: Icon(
                              profit
                                  ? Icons.arrow_upward_rounded
                                  : Icons.arrow_downward_rounded,
                              color: color,
                              size: 28,
                            ),
                          ),
                          Expanded(
                              child: Container(
                                  height: 1,
                                  color: const Color(0xFFEEEEEE))),
                        ],
                      ),
                    ),

                    // 최종 자산 (카운트업)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('최종 자산',
                            style: TextStyle(
                                fontSize: 14,
                                color: Color(0xFF6B7684))),
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
              ),

              const SizedBox(height: 16),

              // 수익률 뱃지 (카운트업)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 18),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: color.withValues(alpha: 0.2), width: 1),
                ),
                child: Column(
                  children: [
                    AnimatedBuilder(
                      animation: _returnAnim,
                      builder: (_, __) {
                        final val     = _returnAnim.value;
                        final animPos = val >= 0;
                        final animColor = animPos
                            ? const Color(0xFFE03131)
                            : const Color(0xFF1971C2);
                        return Text(
                          '${animPos ? '+' : ''}${val.toStringAsFixed(2)}%',
                          style: TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.w800,
                              color: animColor),
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
              ),

              const Spacer(),

              // 다시 하기 버튼
              SizedBox(
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
            ],
          ),
        ),
      ),
    );
  }


}