import 'package:flutter/material.dart';
import '../models/game_session.dart';

class GameResultScreen extends StatelessWidget {
  final GameSession session;

  const GameResultScreen({super.key, required this.session});

  double get _finalAsset {
    // 마지막 라운드의 roundAsset, 없으면 initialAsset
    for (int i = session.rounds.length - 1; i >= 0; i--) {
      if (session.rounds[i].roundAsset != null) {
        return session.rounds[i].roundAsset!;
      }
    }
    return session.initialAsset;
  }

  double get _finalReturnRate {
    for (int i = session.rounds.length - 1; i >= 0; i--) {
      if (session.rounds[i].returnRate != null) {
        return session.rounds[i].returnRate!;
      }
    }
    return 0.0;
  }

  bool get _isProfit => _finalReturnRate >= 0;

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
    final profit = _isProfit;
    final returnRate = _finalReturnRate;
    final color = profit ? const Color(0xFFE03131) : const Color(0xFF1971C2);

    return Scaffold(
      backgroundColor: const Color(0xFFFAF9F5),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 40, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 타이틀
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEEDFE),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  '게임 종료',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF3C3489),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                session.scenarioTitle,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF111111),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${session.totalRounds}라운드 완료',
                style: const TextStyle(fontSize: 14, color: Color(0xFF6B7684)),
              ),

              const Spacer(),

              // 자산 변화 카드
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFEEEEEE), width: 1),
                ),
                child: Column(
                  children: [
                    // 시작 자산
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '시작 자산',
                          style: TextStyle(fontSize: 14, color: Color(0xFF6B7684)),
                        ),
                        Text(
                          '₩${_formatNumber(session.initialAsset)}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF111111),
                          ),
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
                              color: const Color(0xFFEEEEEE),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Icon(
                              profit
                                  ? Icons.arrow_downward_rounded
                                  : Icons.arrow_downward_rounded,
                              color: color,
                              size: 28,
                            ),
                          ),
                          Expanded(
                            child: Container(
                              height: 1,
                              color: const Color(0xFFEEEEEE),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // 최종 자산
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '최종 자산',
                          style: TextStyle(fontSize: 14, color: Color(0xFF6B7684)),
                        ),
                        Text(
                          '₩${_formatNumber(_finalAsset)}',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: color,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // 수익률 뱃지
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 18),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: color.withValues(alpha: 0.2), width: 1),
                ),
                child: Column(
                  children: [
                    Text(
                      '${profit ? '+' : ''}${returnRate.toStringAsFixed(2)}%',
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      profit ? '수익을 달성했어요 🎉' : '손실이 발생했어요',
                      style: TextStyle(
                        fontSize: 14,
                        color: color.withValues(alpha: 0.8),
                        fontWeight: FontWeight.w500,
                      ),
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
                    // 시나리오 선택 화면까지 전부 pop
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF111111),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    '다시 시작하기',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}