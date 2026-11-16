import 'package:flutter/material.dart';
import '../models/scenario.dart';
import '../theme/toss_theme.dart';
import 'toss/toss_widgets.dart';

// 시나리오 한 줄 (토스 ListRow 스타일)
//  왼쪽: 서버가 준 colorHex 타일에 연도 / 가운데: 제목·난이도 / 오른쪽: 화살표
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

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      scale: 0.98,
      child: Container(
        color: Colors.transparent,
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _tileColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text('${scenario.year}',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _tileTextColor)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(scenario.title, style: TossText.body2.copyWith(fontSize: 17)),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      _DifficultyDots(level: scenario.difficulty),
                      const SizedBox(width: 6),
                      Text(_difficultyLabel, style: TossText.caption),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: TossColors.grey400, size: 24),
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
