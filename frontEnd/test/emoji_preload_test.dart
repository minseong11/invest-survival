import 'dart:io';

import 'package:flutter_application_1/widgets/emoji_preload.dart';
import 'package:flutter_test/flutter_test.dart';

// 앱 코드(lib/)에 쓰인 이모지가 모두 미리 받는 목록(kAppEmojis)에 들어 있는지
//  목록에 없으면 웹에서 그 이모지가 처음 나오는 순간 잠깐 네모로 보인다
bool _isEmoji(int cp) =>
    (cp >= 0x1F000 && cp <= 0x1FAFF) ||   // 대부분의 그림 이모지 (🃏 🥇 🪙 …)
    (cp >= 0x2600 && cp <= 0x27BF) ||     // ☀ ☁ ⛈ ⚡ ✓ ✨
    (cp >= 0x2300 && cp <= 0x23FF) ||     // ⏳
    (cp >= 0x25A0 && cp <= 0x25FF);       // ●

String _withoutLineComments(String source) => source
    .split('\n')
    .map((line) {
      final i = line.indexOf('//');
      return i < 0 ? line : line.substring(0, i);
    })
    .join('\n');

void main() {
  test('앱 코드에 쓰인 이모지는 모두 미리 받는 목록에 있다', () {
    final preloaded = kAppEmojis.runes.toSet();
    final missing = <String, Set<String>>{};
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    for (final file in files) {
      final code = _withoutLineComments(file.readAsStringSync());
      for (final cp in code.runes) {
        if (_isEmoji(cp) && !preloaded.contains(cp)) {
          missing.putIfAbsent(String.fromCharCode(cp), () => {}).add(file.path);
        }
      }
    }
    expect(missing, isEmpty, reason: 'kAppEmojis에 넣어 주세요: $missing');
  });
}
