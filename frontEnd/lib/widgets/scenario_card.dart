import 'package:flutter/material.dart';
import '../models/scenario.dart';
import '../theme/toss_theme.dart';
import 'toss/toss_widgets.dart';

// 시나리오 한 줄 (토스 ListRow 스타일)
//  왼쪽: 서버가 준 colorHex 타일에 연도 / 가운데: 제목·난이도·설명 / 오른쪽: 화살표
class ScenarioCard extends StatelessWidget {
  final Scenario scenario;
  final VoidCallback onTap;

  const ScenarioCard({
    super.key,
    required this.scenario,
    required this.onTap,
  });

  Color get _tileColor {
    final hex = scenario.colorHex.replaceAll('#', '');
    final v = int.tryParse('FF$hex', radix: 16);
    return v == null ? TossColors.blue50 : Color(v);
  }

  // 타일이 밝으면 진한 글자, 어두우면 흰 글자
  Color get _tileTextColor {
    final c = _tileColor;
    final luminance = (0.299 * c.r + 0.587 * c.g + 0.114 * c.b);
    return luminance > 0.5 ? TossColors.grey800 : TossColors.white;
  }

  String get _difficultyLabel => switch (scenario.difficulty) {
        >= 5 => '매우 어려움',
        4 => '어려움',
        3 => '보통',
        2 => '쉬움',
        _ => '매우 쉬움',
      };

  // (게임 장면 개편) 목록 한 줄 → '스테이지 카드': 위는 시나리오 색 띠에 연도를 크게, 아래는 제목·설명·난이도
  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      scale: 0.98,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: TossColors.white,
          borderRadius: BorderRadius.circular(TossRadius.xl),
          border: Border.all(color: TossColors.grey200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 72,
              color: _tileColor,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                children: [
                  Text('${scenario.year}',
                      style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -1,
                          color: _tileTextColor)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: TossColors.white.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _DifficultyDots(level: scenario.difficulty),
                        const SizedBox(width: 4),
                        Text(_difficultyLabel,
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: TossColors.grey800)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(scenario.title,
                            style: TossText.body2.copyWith(
                                fontSize: 18, fontWeight: FontWeight.w800)),
                        // (#125) 서버가 주는 한 줄 설명 (게임이 시작되는 시점)
                        if (scenario.description.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(scenario.description, style: TossText.caption),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: TossColors.blue50,
                      borderRadius: BorderRadius.circular(TossRadius.md),
                    ),
                    child: const Text('도전',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: TossColors.blue600)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DifficultyDots extends StatelessWidget {
  final int level;
  const _DifficultyDots({required this.level});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(5, (i) {
        final on = i < level;
        return Container(
          width: 6,
          height: 6,
          margin: const EdgeInsets.only(right: 3),
          decoration: BoxDecoration(
            color: on ? TossColors.red500 : TossColors.grey200,
            shape: BoxShape.circle,
          ),
        );
      }),
    );
  }
}
