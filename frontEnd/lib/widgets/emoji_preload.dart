import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/scheduler.dart' show SchedulerBinding;

// =============================================
// 이모지 글꼴 미리 받기 (웹)
//  Flutter 웹은 이모지를 처음 그리는 순간에 이모지 글꼴을 인터넷에서 받아 온다.
//  그동안 1~2초 네모(□)로 보였다 — 실제 플레이 영상에서 시작 브리핑의 날씨 그림·📅·🗺️가 네모였고,
//  하필 심사위원이 처음 보는 화면이었다.
//  → 첫 화면이 그려진 직후 앱에서 쓰는 이모지를 한 번 조판해, 시나리오를 고르기 전에 글꼴을 받아 둔다.
//    (조판할 때 없는 글자가 있으면 웹 엔진이 그 글자에 맞는 글꼴을 내려받는다)
//  앱 코드에 이모지를 새로 쓰면 이 목록에도 넣어야 한다 — test/emoji_preload_test.dart가 확인한다.
// =============================================
const String kAppEmojis =
    // 시작 브리핑·오늘 시장 날씨
    '☀️🌤️☁️🌧️⛈️📅🗺️🗞️📰📈📉💹'
    // 종목
    '💻🪙🛢️🍎🏦'
    // 카드
    '🏛️😱🛡️🎯🔄📜📊🌊'
    // 장면·위기 대응
    '🃏🚨📣⚡🧘🏃🛒✨🤖💡🥇🥈🥉'
    // 결과
    '🏆🌱🎉⏳🏁🗓️📌👍🤔😥💬'
    // 처음 화면
    '💰📡🔍'
    // 기호
    '✓●';

/// 웹에서만: 첫 화면이 그려진 직후 [kAppEmojis]를 한 번 조판해 이모지 글꼴을 미리 받는다.
void preloadEmojiFonts() {
  if (!kIsWeb) return;
  SchedulerBinding.instance.addPostFrameCallback((_) {
    final builder = ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: 16))
      ..addText(kAppEmojis);
    builder.build()
      ..layout(const ui.ParagraphConstraints(width: 4000))
      ..dispose();
  });
}
