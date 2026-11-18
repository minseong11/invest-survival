import 'package:flutter/material.dart';
import '../theme/toss_theme.dart';

// =============================================
// (#125) 넓은 화면에서는 휴대폰 폭으로 가운데에 보여준다 (노트북 브라우저·태블릿)
//  화면 설계가 휴대폰 폭 기준이라, 폭 제한 없이 늘어나면 글이 한 줄로 길게 늘어지고
//  차트가 가로로만 길어져 납작해졌다 (크롬에서 실제로 플레이한 영상에서 확인).
//  안쪽 화면이 실제 폭을 알도록 MediaQuery의 size도 같은 폭으로 바꿔 준다.
// =============================================
const double kMaxAppWidth = 520;

class AppFrame extends StatelessWidget {
  final Widget child;
  const AppFrame({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    if (mq.size.width <= kMaxAppWidth) return child;

    return ColoredBox(
      color: TossColors.grey200,
      child: Center(
        child: SizedBox(
          width: kMaxAppWidth,
          child: MediaQuery(
            data: mq.copyWith(size: Size(kMaxAppWidth, mq.size.height)),
            child: ClipRect(child: child),
          ),
        ),
      ),
    );
  }
}
