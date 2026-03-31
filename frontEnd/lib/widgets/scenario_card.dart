import 'package:flutter/material.dart';
import '../models/scenario.dart';

class ScenarioCard extends StatelessWidget {
  final Scenario scenario;
  final VoidCallback onTap;

  const ScenarioCard({
    super.key,
    required this.scenario,
    required this.onTap,
  });

  Color get _cardColor {
    return Color(int.parse('FF${scenario.colorHex}', radix: 16));
  }

  Color get _textColor {
    final r = int.parse(scenario.colorHex.substring(0, 2), radix: 16);
    final g = int.parse(scenario.colorHex.substring(2, 4), radix: 16);
    final b = int.parse(scenario.colorHex.substring(4, 6), radix: 16);
    final luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255;
    return luminance > 0.5 ? const Color(0xFF2D1F00) : const Color(0xFFFFF8F0);
  }

  Widget _buildStars() {
    return Row(
      children: List.generate(5, (i) {
        return Icon(
          i < scenario.difficulty
              ? Icons.star_rounded
              : Icons.star_outline_rounded,
          size: 14,
          color:
              _textColor.withValues(alpha: i < scenario.difficulty ? 0.9 : 0.3),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          color: _cardColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    scenario.title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: _textColor,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        '${scenario.year}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: _textColor.withValues(alpha: 0.65),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '·',
                        style: TextStyle(
                          fontSize: 13,
                          color: _textColor.withValues(alpha: 0.4),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '난이도 ',
                        style: TextStyle(
                          fontSize: 13,
                          color: _textColor.withValues(alpha: 0.65),
                        ),
                      ),
                      _buildStars(),
                    ],
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: _textColor.withValues(alpha: 0.4),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
