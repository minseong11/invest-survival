import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/toss_theme.dart';

// =============================================
// Pressable — 누르면 살짝 작아졌다가 스프링처럼 돌아옴 (+ 가벼운 햅틱)
// =============================================
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  final bool haptic;

  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.scale = 0.96,
    this.haptic = true,
  });

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (widget.onTap == null) return;
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap == null
          ? null
          : () {
              if (widget.haptic) HapticFeedback.lightImpact();
              widget.onTap!();
            },
      child: AnimatedScale(
        scale: _down ? widget.scale : 1.0,
        duration: _down ? TossMotion.fast : const Duration(milliseconds: 320),
        curve: _down ? Curves.easeOut : Curves.elasticOut,
        child: widget.child,
      ),
    );
  }
}

// =============================================
// FadeInUp — 화면에 들어올 때 아래에서 살짝 떠오르며 나타남
//  delay를 조금씩 늘려 주면 위에서부터 순차 등장
// =============================================
class FadeInUp extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final double offset;

  const FadeInUp({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offset = 16,
  });

  @override
  State<FadeInUp> createState() => _FadeInUpState();
}

class _FadeInUpState extends State<FadeInUp>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: TossMotion.slow,
  );
  late final Animation<double> _t =
      CurvedAnimation(parent: _c, curve: TossMotion.enter);
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _c.forward();
    } else {
      _timer = Timer(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      child: widget.child,
      builder: (_, child) => Opacity(
        opacity: _t.value,
        child: Transform.translate(
          offset: Offset(0, widget.offset * (1 - _t.value)),
          child: child,
        ),
      ),
    );
  }
}

// =============================================
// RollingText — 바뀐 글자만 위/아래로 굴러가며 바뀜 (토스 금액 연출)
//  숫자가 커지면 아래에서 위로, 작아지면 위에서 아래로 굴러감
//  자릿수가 바뀌어도 오른쪽(일의 자리)부터 맞춰서 비교
// =============================================
class RollingText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final double? value; // 방향 판단용 (없으면 항상 위로)
  final Duration duration;

  const RollingText(
    this.text, {
    super.key,
    required this.style,
    this.value,
    this.duration = const Duration(milliseconds: 420),
  });

  @override
  State<RollingText> createState() => _RollingTextState();
}

class _RollingTextState extends State<RollingText> {
  bool _up = true;

  @override
  void didUpdateWidget(RollingText old) {
    super.didUpdateWidget(old);
    final a = old.value, b = widget.value;
    if (a != null && b != null && a != b) _up = b > a;
  }

  @override
  Widget build(BuildContext context) {
    final chars = widget.text.characters.toList();
    final n = chars.length;
    final dir = _up ? 1.0 : -1.0;
    return ClipRect(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(n, (i) {
          final ch = chars[i];
          final fromRight = n - 1 - i; // 오른쪽 기준 자리 → 자리수 변해도 안정적
          return AnimatedSwitcher(
            key: ValueKey(fromRight),
            duration: widget.duration,
            switchInCurve: TossMotion.enter,
            switchOutCurve: Curves.easeIn,
            layoutBuilder: (current, previous) => Stack(
              alignment: Alignment.center,
              children: [...previous, if (current != null) current],
            ),
            transitionBuilder: (child, anim) {
              final incoming = child.key == ValueKey('$fromRight:$ch');
              final begin = Offset(0, incoming ? 0.7 * dir : -0.7 * dir);
              return FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween(begin: begin, end: Offset.zero)
                      .animate(anim),
                  child: child,
                ),
              );
            },
            child: Text(ch,
                key: ValueKey('$fromRight:$ch'), style: widget.style),
          );
        }),
      ),
    );
  }
}

// =============================================
// TossSection — 흰 섹션 (회색 배경 위에 쌓음)
// =============================================
class TossSection extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  const TossSection({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(20, 20, 20, 20),
    this.radius = TossRadius.xl,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: TossColors.white,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: child,
    );
  }
}

// =============================================
// TossButton — 큰 버튼 (primary: 파랑 / secondary: 연한 회색)
// =============================================
enum TossButtonType { primary, secondary, dark }

class TossButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final TossButtonType type;
  final bool loading;
  final double height;
  final Widget? icon;

  const TossButton({
    super.key,
    required this.label,
    this.onTap,
    this.type = TossButtonType.primary,
    this.loading = false,
    this.height = 56,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null && !loading;
    final (bg, fg) = switch (type) {
      TossButtonType.primary   => (TossColors.blue500, TossColors.white),
      TossButtonType.secondary => (TossColors.grey100, TossColors.grey700),
      TossButtonType.dark      => (TossColors.grey800, TossColors.white),
    };
    return Pressable(
      onTap: enabled ? onTap : null,
      scale: 0.97,
      child: AnimatedOpacity(
        duration: TossMotion.base,
        opacity: enabled || loading ? 1 : 0.4,
        child: Container(
          height: height,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(TossRadius.lg),
          ),
          child: loading
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      valueColor: AlwaysStoppedAnimation(fg)),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[icon!, const SizedBox(width: 6)],
                    Flexible(
                      child: Text(label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: fg)),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

// =============================================
// TossChipButton — 섹션 오른쪽 위의 작은 버튼 (weak 스타일)
// =============================================
class TossChipButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final Color bg;
  final Color fg;
  final Widget? leading;

  const TossChipButton({
    super.key,
    required this.label,
    this.onTap,
    this.bg = TossColors.blue50,
    this.fg = TossColors.blue600,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: TossMotion.base,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(TossRadius.sm),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 4)],
            Text(label,
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: fg)),
          ],
        ),
      ),
    );
  }
}

// =============================================
// TossBadge — 작은 상태 배지
// =============================================
class TossBadge extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;

  const TossBadge({
    super.key,
    required this.label,
    this.bg = TossColors.blue50,
    this.fg = TossColors.blue600,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
    );
  }
}

// =============================================
// EmojiTile — 목록 왼쪽의 둥근 사각형 아이콘 칸
// =============================================
class EmojiTile extends StatelessWidget {
  final String emoji;
  final Color bg;
  final double size;

  const EmojiTile({
    super.key,
    required this.emoji,
    this.bg = TossColors.grey100,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Text(emoji, style: TextStyle(fontSize: size * 0.48)),
    );
  }
}

// =============================================
// InfoBox — 회색 안내 문구 상자
// =============================================
class InfoBox extends StatelessWidget {
  final Widget child;
  const InfoBox({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: TossColors.grey50,
        borderRadius: BorderRadius.circular(TossRadius.md),
      ),
      child: child,
    );
  }
}

// =============================================
// 공용 포맷·알림
// =============================================
String formatWon(double value) {
  final s = value.abs().toStringAsFixed(0).replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
        (m) => '${m[1]},',
      );
  return value < 0 ? '-$s' : s;
}

String formatRate(double v) => '${v >= 0 ? '+' : ''}${v.toStringAsFixed(2)}%';

void showTossToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    ));
}

// 아래에서 올라오는 시트 (팝업 대신)
Future<void> showTossSheet(
  BuildContext context, {
  required String title,
  required Widget body,
  String confirmLabel = '확인했어요',
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: TossColors.white,
    barrierColor: Colors.black.withValues(alpha: 0.4),
    shape: const RoundedRectangleBorder(
      borderRadius:
          BorderRadius.vertical(top: Radius.circular(TossRadius.sheet)),
    ),
    builder: (ctx) => SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TossText.title2),
              const SizedBox(height: 12),
              Flexible(child: SingleChildScrollView(child: body)),
              const SizedBox(height: 24),
              TossButton(
                label: confirmLabel,
                onTap: () => Navigator.of(ctx).pop(),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
