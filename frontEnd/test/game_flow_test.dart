import 'package:flutter/material.dart';
import 'package:flutter_application_1/screens/scenario_screen.dart';
import 'package:flutter_application_1/theme/toss_theme.dart';
import 'package:flutter_application_1/widgets/decision_selector.dart';
import 'package:flutter_application_1/widgets/toss/toss_widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_game_service.dart';

// =============================================
// 화면 흐름 테스트 (#125)
// 가짜 서버(FakeGameService)를 넣고 휴대폰 크기 화면에서 한 판을 끝까지 진행한다.
//   시나리오 선택 → 시작 전 브리핑·첫 카드 → 위기 대응 → 25라운드 AI 예측·설명 → … → 결과 화면
// 화면이 넘치거나(overflow) 예외가 나면 테스트가 실패하므로, 새 화면 요소가 깨지지 않는지도 함께 확인된다.
// =============================================

const _tick = Duration(milliseconds: 500);   // 자동 진행 한 라운드 (배속 ×1)

Future<void> _pumpApp(WidgetTester tester, FakeGameService fake) async {
  tester.view.physicalSize = const Size(412 * 3, 892 * 3);   // 412×892 논리 픽셀
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    theme: buildTossTheme(),
    home: ScenarioScreen(service: fake),
  ));
  await tester.pump();          // 시나리오 목록 응답
  await tester.pump(_tick);     // 등장 애니메이션
}

// 화면이 바뀔 때까지 기다림 (애니메이션·응답 처리)
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

// 자동 진행을 한 라운드씩 넘기며 finder가 나타날 때까지 기다림
Future<void> _playUntil(WidgetTester tester, Finder finder, {int maxTicks = 60}) async {
  for (int i = 0; i < maxTicks; i++) {
    if (finder.evaluate().isNotEmpty) break;
    await tester.pump(_tick);
  }
  await _settle(tester);
  expect(finder, findsWidgets);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder.first);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(finder.first);
  await _settle(tester);
}

void main() {
  testWidgets('한 판을 끝까지: 브리핑 → 카드 → 위기 대응 → AI 예측 → 결과', (tester) async {
    final fake = FakeGameService();
    await _pumpApp(tester, fake);

    // ── 홈: 시나리오 설명, 게임 방법 ──
    expect(find.text('테스트 위기'), findsOneWidget);
    expect(find.text('테스트용 시나리오 설명이에요.'), findsOneWidget);
    await _tap(tester, find.text('게임 방법'));
    expect(find.text('이렇게 진행돼요'), findsOneWidget);
    expect(find.text('속보가 나오면 위기 대응'), findsOneWidget);
    await _tap(tester, find.text('확인했어요'));

    // ── 1라운드: 시작 전 브리핑 + 첫 카드 ──
    await _tap(tester, find.text('테스트 위기'));
    expect(find.text('시작 전 시장 브리핑'), findsOneWidget);
    expect(find.text('테스트 배경 설명이에요.'), findsOneWidget);
    expect(find.text('-7.6%'), findsOneWidget);                       // 원유 직전 20거래일 등락
    expect(find.text('전략을 골라주세요'), findsOneWidget);
    // 팔 주식이 없을 때 매도 카드에는 안내가 붙는다
    expect(find.textContaining('지금은 가진 S&P500이 없어요'), findsOneWidget);

    await _tap(tester, find.text('황금 적립'));
    await _tap(tester, find.text('이 전략으로 할게요'));
    expect(fake.calls, contains('card:1:2'));
    expect(find.text('시작 전 시장 브리핑'), findsNothing);            // 고른 뒤에는 브리핑이 사라짐

    // ── 10라운드: 위기 대응 (나쁜 소식) ──
    await _playUntil(tester, find.text('대응을 골라주세요'));
    expect(find.text('속보가 나왔어요\n어떻게 대응할까요?'), findsOneWidget);
    expect(find.text('테스트 속보 10라운드'), findsOneWidget);
    expect(find.text('10'), findsWidgets);                            // 헤더 라운드
    await _tap(tester, find.text('절반 판다'));
    await _tap(tester, find.text('이렇게 할게요'));
    expect(fake.calls, contains('decision:10:SELL_HALF'));
    expect(find.textContaining('절반을 팔았어요'), findsOneWidget);    // 차트 위 알림 (아래 버튼을 가리지 않음)

    // ── 25라운드: AI 예측·설명 ──
    await _playUntil(tester, find.text('AI 예측'));
    await _tap(tester, find.text('AI 예측'));
    expect(fake.calls, contains('ai:25'));
    expect(find.text('AI 1위'), findsOneWidget);
    // 예측값은 기대수익률이 아니라 후보 평균과의 차이로 표기
    expect(find.text('AI 예측: 후보 평균보다 +1.4%p'), findsOneWidget);
    expect(find.text('AI 예측: 후보 평균보다 -1.2%p'), findsOneWidget);
    await _tap(tester, find.text('AI 설명'));
    expect(find.text('후보 카드 예측 비교'), findsOneWidget);
    expect(find.textContaining('최종 수익률을 예측한 값이 아니에요'), findsOneWidget);
    await _tap(tester, find.text('확인했어요'));
    await _tap(tester, find.text('AI 1위'));
    await _tap(tester, find.text('이 전략으로 할게요'));
    expect(fake.calls.where((c) => c.startsWith('card:25:')).length, 1);

    // ── 30라운드에 건너뛴 카드가 있으면 카드 칩에 이유가 남는다 ──
    await _playUntil(tester, find.text('전략을 골라주세요'));          // 50라운드
    expect(find.textContaining('현금 부족'), findsWidgets);
    await _tap(tester, find.text('금 피난처'));
    await _tap(tester, find.text('이 전략으로 할게요'));

    // ── 60라운드: 위기 대응 (좋은 소식) ──
    await _playUntil(tester, find.text('대응을 골라주세요'));
    expect(find.text('좋은 소식이 나왔어요\n어떻게 할까요?'), findsOneWidget);
    await _tap(tester, find.text('버틴다'));
    await _tap(tester, find.text('이렇게 할게요'));
    expect(fake.calls, contains('decision:60:HOLD'));

    // ── 75라운드: 마지막 카드 → 100라운드 ──
    await _playUntil(tester, find.text('전략을 골라주세요'));
    await _tap(tester, find.text('기술의 파도'));
    await _tap(tester, find.text('이 전략으로 할게요'));
    await _playUntil(tester, find.text('결과 보기'));
    expect(find.text('100'), findsWidgets);

    // ── 결과 화면 ──
    await _tap(tester, find.text('결과 보기'));
    await tester.pump(const Duration(seconds: 1));
    await _settle(tester);
    expect(fake.calls, containsAll(['analysis', 'coach']));
    expect(find.text('C등급'), findsOneWidget);
    expect(find.textContaining('하위 24.2%'), findsWidgets);           // 상위 75.8% → 하위 24.2%
    expect(find.text('AI 코치 한마디'), findsOneWidget);
    expect(find.text('테스트 코치 문장이에요.'), findsOneWidget);
    expect(find.text('카드별 성적표'), findsOneWidget);
    expect(find.text('위기 대응 돌아보기'), findsOneWidget);
    expect(find.text('✓ 가장 좋은 대응'), findsNothing);               // 가짜 응답: 두 번 모두 더 좋은 대응이 있었음
    expect(find.text('+2.0%p 놓침'), findsNWidgets(2));
    expect(find.text('그 후 이야기'), findsOneWidget);
    expect(find.text('+34.2%'), findsOneWidget);                      // 1년 뒤 S&P500
    expect(find.text('라운드별로 돌아보기'), findsOneWidget);
    // 손실에도 부호가 붙는다 (금액 줄은 글자마다 따로 그려지므로 위젯의 text로 확인)
    expect(
      find.byWidgetPredicate(
          (w) => w is RollingText && w.text.contains('(-20.00%)')),
      findsOneWidget,
    );

    // 남은 타이머(뉴스 알림·알림 칸) 정리
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('카드 선택 바로 다음 라운드에 위기 대응이 와도 진행된다', (tester) async {
    final fake = FakeGameService(decisionRounds: const [2]);
    await _pumpApp(tester, fake);
    await _tap(tester, find.text('테스트 위기'));
    await _tap(tester, find.text('거인의 어깨'));
    await _tap(tester, find.text('이 전략으로 할게요'));
    await _playUntil(tester, find.text('대응을 골라주세요'));

    await _tap(tester, find.text('더 산다'));
    await _tap(tester, find.text('이렇게 할게요'));
    expect(fake.calls, contains('decision:2:BUY_MORE'));
    expect(find.textContaining('더 샀어요'), findsOneWidget);

    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('가진 자산·현금이 없으면 그 대응은 고를 수 없다', (tester) async {
    String? picked;
    await tester.pumpWidget(MaterialApp(
      theme: buildTossTheme(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: DecisionSelector(
            prompt: null,
            selected: null,
            hasHoldings: false,
            hasCash: false,
            onSelect: (c) => picked = c,
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('아직 가진 자산이 없어요'), findsOneWidget);
    expect(find.text('남은 현금이 없어요'), findsOneWidget);
    await tester.tap(find.text('절반 판다'));
    await tester.tap(find.text('더 산다'));
    expect(picked, isNull);                 // 눌러도 선택되지 않음
    await tester.tap(find.text('버틴다'));
    expect(picked, 'HOLD');
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('서버에 연결하지 못하면 다시 시도 화면', (tester) async {
    await _pumpApp(tester, _FailingService());
    expect(find.text('서버에 연결하지 못했어요'), findsOneWidget);
    expect(find.text('다시 시도하기'), findsOneWidget);
  });
}

class _FailingService extends FakeGameService {
  @override
  Future<List<Never>> getScenarios() async => throw Exception('서버에 연결할 수 없어요');
}
