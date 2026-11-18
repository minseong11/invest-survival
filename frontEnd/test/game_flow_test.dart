import 'package:flutter/material.dart';
import 'package:flutter_application_1/models/coach_comment.dart';
import 'package:flutter_application_1/models/result_analysis.dart';
import 'package:flutter_application_1/models/v2_recommend_result.dart';
import 'package:flutter_application_1/screens/game_screen.dart';
import 'package:flutter_application_1/screens/scenario_screen.dart';
import 'package:flutter_application_1/theme/toss_theme.dart';
import 'package:flutter_application_1/widgets/decision_selector.dart';
import 'package:flutter_application_1/widgets/market_chips.dart';
import 'package:flutter_application_1/widgets/stock_chart.dart';
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

// 시나리오를 눌러 게임을 시작하고 시작 브리핑은 건너뛴다 (브리핑 자체는 첫 번째 테스트에서 확인)
Future<void> _startSkippingBriefing(WidgetTester tester) async {
  await _tap(tester, find.text('테스트 위기'));
  await _tap(tester, find.text('건너뛰기'));
}

// 결과 화면: '다음'을 눌러 finder가 있는 장면까지 넘긴다
Future<void> _pageUntil(WidgetTester tester, Finder finder, {int max = 10}) async {
  for (int i = 0; i < max; i++) {
    if (finder.evaluate().isNotEmpty) break;
    await _tap(tester, find.text('다음'));
  }
  expect(finder, findsWidgets);
}

void main() {
  testWidgets('한 판을 끝까지: 브리핑 장면 → 카드 → 속보 장면 → AI 예측 → 넘겨 보는 결과', (tester) async {
    final fake = FakeGameService();
    await _pumpApp(tester, fake);

    // ── 홈: 시나리오 설명, 게임 방법 ──
    expect(find.text('테스트 위기'), findsOneWidget);
    expect(find.text('테스트용 시나리오 설명이에요.'), findsOneWidget);
    await _tap(tester, find.text('게임 방법'));
    expect(find.text('이렇게 진행돼요'), findsOneWidget);
    expect(find.text('속보가 나오면 위기 대응'), findsOneWidget);
    await _tap(tester, find.text('확인했어요'));

    // ── 시작 브리핑: 넘겨 보는 3장면 ──
    await _tap(tester, find.text('테스트 위기'));
    // ① 시장 날씨 (직전 20거래일 S&P500 +1.79% → 대체로 맑음)
    expect(find.text('오늘의 시장 날씨는 ‘대체로 맑음’'), findsOneWidget);
    expect(find.text('📅 2008년 9월 2일'), findsOneWidget);
    // ② 무슨 일이 있었나요
    await _tap(tester, find.text('다음'));
    expect(find.text('테스트 배경 설명이에요.'), findsOneWidget);
    // ③ 시장 지도
    await _tap(tester, find.text('다음'));
    expect(find.text('시작 전 시장 지도'), findsOneWidget);
    expect(find.text('-7.6%'), findsOneWidget);                       // 원유 직전 20거래일 등락
    await _tap(tester, find.text('첫 전략 고르기'));

    // ── 1라운드: 카드 선택 장면 ──
    expect(find.text('첫 번째 전략을\n골라주세요'), findsOneWidget);
    expect(find.text('오늘 9월 2일 시장'), findsOneWidget);           // 1라운드도 그날 종가로 매매
    expect(find.text('전략을 골라주세요'), findsOneWidget);            // 아래 고정 버튼
    // 팔 주식이 없을 때 매도 카드에는 안내가 붙는다
    expect(find.textContaining('지금은 가진 S&P500이 없어요'), findsOneWidget);

    await _tap(tester, find.text('황금 적립'));
    await _tap(tester, find.text('이 전략으로 할게요'));
    expect(fake.calls, contains('card:1:2'));
    expect(find.text('첫 번째 전략을\n골라주세요'), findsNothing);      // 고르면 장면이 내려감
    expect(find.text('시작 전 시장 지도'), findsNothing);

    // ── 10라운드: 속보 장면 (나쁜 소식) ──
    await _playUntil(tester, find.text('대응을 골라주세요'));
    expect(find.text('⚡ 속보'), findsOneWidget);
    expect(find.text('어떻게 대응할까요?'), findsOneWidget);
    expect(find.text('테스트 속보 10라운드'), findsOneWidget);
    expect(find.text('오늘 9월 11일 시장'), findsOneWidget);          // 고르기 전에 그날 움직임 (AI와 같은 정보)
    expect(find.textContaining('🚨 10라운드 · 9월 11일'), findsOneWidget); // 전체 화면 장면 위쪽에 라운드·날짜
    await _tap(tester, find.text('절반 판다'));
    await _tap(tester, find.text('이렇게 할게요'));
    expect(fake.calls, contains('decision:10:SELL_HALF'));
    expect(find.textContaining('절반을 팔았어요'), findsOneWidget);    // 차트 위 알림
    expect(find.text('어떻게 대응할까요?'), findsNothing);

    // ── 25라운드: AI 예측·설명 ──
    await _playUntil(tester, find.text('AI 예측'));
    expect(find.text('두 번째 전략을\n골라주세요'), findsOneWidget);
    expect(find.text('오늘 9월 26일 시장'), findsOneWidget);
    expect(find.textContaining('AI 예측도 오늘 종가까지'), findsOneWidget);
    await _tap(tester, find.text('AI 예측'));
    expect(fake.calls, contains('ai:25'));
    expect(find.text('AI 1위'), findsOneWidget);
    // 예측값은 기대수익률이 아니라 카드 평균(아직 고르지 않은 카드 전체)과의 차이로 표기
    expect(find.text('AI 예측: 카드 평균보다 +1.4%p'), findsOneWidget);
    expect(find.text('AI 예측: 카드 평균보다 -1.2%p'), findsOneWidget);
    await _tap(tester, find.text('AI 설명'));
    expect(find.text('후보 카드 예측 비교'), findsOneWidget);
    expect(find.textContaining('아직 고르지 않은 카드 전체의 평균과 비교한 예상 차이'), findsOneWidget);
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
    expect(find.text('📣 희소식'), findsOneWidget);
    expect(find.textContaining('60라운드 · '), findsWidgets);           // 장면 위쪽: 라운드·날짜
    expect(find.textContaining('· 기회'), findsOneWidget);
    await _tap(tester, find.text('버틴다'));
    await _tap(tester, find.text('이렇게 할게요'));
    expect(fake.calls, contains('decision:60:HOLD'));

    // ── 75라운드: 마지막 카드 → 100라운드 ──
    await _playUntil(tester, find.text('전략을 골라주세요'));
    expect(find.text('마지막 전략을\n골라주세요'), findsOneWidget);
    await _tap(tester, find.text('기술의 파도'));
    await _tap(tester, find.text('이 전략으로 할게요'));
    await _playUntil(tester, find.text('결과 보기'));
    expect(find.text('100'), findsWidgets);

    // ── 결과: 한 장씩 넘겨 본다 ──
    await _tap(tester, find.text('결과 보기'));
    await tester.pump(const Duration(seconds: 1));
    await _settle(tester);
    expect(fake.calls, containsAll(['analysis', 'coach']));
    // ① 결과
    expect(find.text('C등급'), findsOneWidget);
    expect(find.textContaining('하위 24.2%'), findsWidgets);           // 상위 75.8% → 하위 24.2%
    // 손실에도 부호가 붙는다 (금액 줄은 글자마다 따로 그려지므로 위젯의 text로 확인)
    expect(
      find.byWidgetPredicate(
          (w) => w is RollingText && w.text.contains('(-20.00%)')),
      findsOneWidget,
    );
    expect(find.text('카드별 성적표'), findsNothing);                  // 아직 다음 장면
    // ② ~ ⑧
    await _pageUntil(tester, find.text('수익률 비교'));
    await _pageUntil(tester, find.text('받은 카드 안에서 내 순위'));
    await _pageUntil(tester, find.text('라운드별로 돌아보기'));
    await _pageUntil(tester, find.text('카드별 성적표'));
    await _pageUntil(tester, find.text('위기 대응 돌아보기'));
    expect(find.text('✓ 가장 좋은 대응'), findsNothing);               // 가짜 응답: 두 번 모두 더 좋은 대응이 있었음
    expect(find.text('+2.0%p 놓침'), findsNWidgets(2));
    await _pageUntil(tester, find.text('AI 코치 한마디'));
    expect(find.text('테스트 코치 문장이에요.'), findsOneWidget);
    await _pageUntil(tester, find.text('그 후 이야기'));
    expect(find.text('+34.2%'), findsOneWidget);                      // 1년 뒤 S&P500
    expect(find.text('처음으로 돌아가기'), findsOneWidget);            // 마지막 장면
    expect(find.text('다음'), findsNothing);

    // 한 번에 보기: 모든 장면이 한 페이지에. 게임 중 고를 수 없던 '전체 1위 전략'은 없다
    await _tap(tester, find.text('한 번에 보기'));
    expect(find.text('카드별 성적표'), findsOneWidget);
    expect(find.text('그 후 이야기'), findsOneWidget);
    expect(find.textContaining('가장 잘 통한 전략'), findsNothing);
    expect(find.text('한 장씩 보기'), findsOneWidget);

    // 남은 타이머(뉴스 알림·알림 칸) 정리
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('갖고 있지 않은 종목도 흐름을 보고, 눌러서 차트에 겹쳐 볼 수 있다', (tester) async {
    final fake = FakeGameService();
    await _pumpApp(tester, fake);
    await _startSkippingBriefing(tester);
    await _tap(tester, find.text('황금 적립'));
    await _tap(tester, find.text('이 전략으로 할게요'));
    await _playUntil(tester, find.text('대응을 골라주세요'));           // 10라운드
    await _tap(tester, find.text('버틴다'));
    await _tap(tester, find.text('이렇게 할게요'));
    await _tap(tester, find.text('잠시 멈추기'));                      // 장면이 내려간 게임 화면에서 멈춤

    // 차트 아래 종목 칩: 금만 샀지만 나머지 종목도 게임 시작 후 등락이 보인다
    Finder chip(String name) =>
        find.descendant(of: find.byType(MarketChips), matching: find.text(name));
    for (final name in ['S&P500', '나스닥100', '금', '원유', '애플', '미국 장기채']) {
      expect(chip(name), findsOneWidget, reason: name);
    }

    // 칩을 누르면 그 종목 선이 차트에 겹쳐지고, 다시 누르면 사라진다
    StockChart chart() => tester.widget<StockChart>(find.byType(StockChart));
    expect(chart().extraTickers, isEmpty);
    await _tap(tester, chip('금'));
    await _tap(tester, chip('원유'));
    expect(chart().extraTickers, {'XAUUSD', 'USO'});
    await _tap(tester, chip('금'));
    expect(chart().extraTickers, {'USO'});

    // 25라운드 카드 선택 장면: 카드가 사고파는 종목의 게임 시작 후 등락 (금 카드는 GLD → 서버 가격 XAUUSD)
    await _tap(tester, find.text('이어서 진행하기'));
    await _playUntil(tester, find.text('전략을 골라주세요'));
    expect(find.text('금 · 게임 시작 후 '), findsOneWidget);           // 금 피난처
    expect(find.text('S&P500 · 게임 시작 후 '), findsNWidgets(2));     // 거인의 어깨, 공포탐욕
    expect(find.text('+4.8%'), findsWidgets);                          // 금 피난처 (1→25라운드, 그날까지)

    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('게임 중에 뒤로 가면 한 번 묻는다 (헤더 버튼·브라우저 뒤로 가기)', (tester) async {
    final fake = FakeGameService();
    await _pumpApp(tester, fake);
    await _startSkippingBriefing(tester);
    await _tap(tester, find.text('황금 적립'));
    await _tap(tester, find.text('이 전략으로 할게요'));
    await tester.pump(_tick);

    // 헤더의 뒤로 버튼 → 확인 → 계속하기: 게임 화면에 그대로
    await _tap(tester, find.byIcon(Icons.arrow_back_ios_new_rounded));
    expect(find.text('게임을 그만둘까요?'), findsOneWidget);
    await _tap(tester, find.text('계속하기'));
    expect(find.text('게임을 그만둘까요?'), findsNothing);
    expect(find.byType(GameScreen), findsOneWidget);

    // 브라우저·트랙패드·안드로이드의 뒤로 가기도 같은 확인 → 그만두기: 처음 화면으로
    await tester.binding.handlePopRoute();
    await _settle(tester);
    expect(find.text('게임을 그만둘까요?'), findsOneWidget);
    await _tap(tester, find.text('그만두기'));
    expect(find.byType(GameScreen), findsNothing);
    expect(find.text('게임 방법'), findsOneWidget);

    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('현금이 총자산의 5%보다 적으면 카드를 고르기 전에 알려 준다', (tester) async {
    final fake = FakeGameService(heldCashWeight: 4.2);
    await _pumpApp(tester, fake);
    await _startSkippingBriefing(tester);
    expect(find.textContaining('현금이 총자산의 5%보다 적어요'), findsNothing);   // 1라운드는 현금 100%

    await _tap(tester, find.text('황금 적립'));
    await _tap(tester, find.text('이 전략으로 할게요'));
    await _playUntil(tester, find.text('대응을 골라주세요'));
    await _tap(tester, find.text('버틴다'));
    await _tap(tester, find.text('이렇게 할게요'));
    await _playUntil(tester, find.text('전략을 골라주세요'));             // 25라운드
    expect(find.textContaining('현금이 총자산의 5%보다 적어요 (지금 4.2%)'), findsOneWidget);

    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('카드 선택 바로 다음 라운드에 위기 대응이 와도 진행된다', (tester) async {
    final fake = FakeGameService(decisionRounds: const [2]);
    await _pumpApp(tester, fake);
    await _startSkippingBriefing(tester);
    await _tap(tester, find.text('거인의 어깨'));
    await _tap(tester, find.text('이 전략으로 할게요'));
    await _playUntil(tester, find.text('대응을 골라주세요'));

    await _tap(tester, find.text('더 산다'));
    await _tap(tester, find.text('이렇게 할게요'));
    expect(fake.calls, contains('decision:2:BUY_MORE'));
    expect(find.textContaining('더 샀어요'), findsOneWidget);

    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('AI 서버가 응답하지 않으면 화면에 안내가 뜨고 다시 시도할 수 있다', (tester) async {
    final fake = _AiDownService();
    await _pumpApp(tester, fake);
    await _startSkippingBriefing(tester);
    await _tap(tester, find.text('황금 적립'));
    await _tap(tester, find.text('이 전략으로 할게요'));

    // 25라운드: 평소 순위는 AI 없이도 보이고, AI 예측 실패는 안내 + 다시 시도
    await _playUntil(tester, find.text('AI 예측'));
    expect(find.text('📊 평소 순위'), findsOneWidget);
    expect(find.textContaining('처음 보는 시장 테스트에서 평소 순위보다 낫지 않았어요'), findsOneWidget);
    await _tap(tester, find.text('AI 예측'));
    expect(find.text('예측을 받지 못했어요'), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);
    // AI 없이도 카드는 고를 수 있다
    await _tap(tester, find.text('금 피난처'));
    await _tap(tester, find.text('이 전략으로 할게요'));

    await _playUntil(tester, find.text('전략을 골라주세요'));          // 50라운드
    await _tap(tester, find.text('거인의 어깨'));
    await _tap(tester, find.text('이 전략으로 할게요'));
    await _playUntil(tester, find.text('전략을 골라주세요'));          // 75라운드
    await _tap(tester, find.text('기술의 파도'));
    await _tap(tester, find.text('이 전략으로 할게요'));
    await _playUntil(tester, find.text('결과 보기'));
    await _tap(tester, find.text('결과 보기'));
    await tester.pump(const Duration(seconds: 1));
    await _settle(tester);

    // 결과: 사후 분석 실패 → 안내 + 다시 시도 → 성공하면 분석이 나오고, AI 코치 실패는 따로 안내
    await _pageUntil(tester, find.text('사후 분석을 불러오지 못했어요'));
    await _tap(tester, find.text('다시 시도'));
    await _settle(tester);
    expect(find.text('사후 분석을 불러오지 못했어요'), findsNothing);
    expect(fake.analysisTries, 2);
    await _pageUntil(tester, find.text('AI 코치 한마디를 받지 못했어요'));
    fake.coachDown = false;
    await _tap(tester, find.text('다시 시도'));
    await _settle(tester);
    expect(find.text('AI 코치 한마디'), findsOneWidget);
    expect(find.text('테스트 코치 문장이에요.'), findsOneWidget);

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

// AI 서버가 꺼진 상황: 예측은 실패, 사후 분석은 처음 한 번 실패, AI 코치는 coachDown 동안 실패
class _AiDownService extends FakeGameService {
  _AiDownService() : super(decisionRounds: const []);

  int analysisTries = 0;
  bool coachDown = true;

  @override
  Future<V2RecommendResult> getV2Recommendation({
    required String sessionId,
    required int currentRound,
    required List<int> alreadyCards,
    required List<int> candidateCards,
  }) async {
    calls.add('ai:$currentRound');
    throw Exception('AI 서버에 연결할 수 없어요');
  }

  @override
  Future<ResultAnalysis?> getResultAnalysis({required String sessionId}) async {
    analysisTries++;
    if (analysisTries == 1) {
      calls.add('analysis');
      return null;
    }
    return super.getResultAnalysis(sessionId: sessionId);
  }

  @override
  Future<CoachComment?> getResultCoach({required String sessionId}) async {
    if (coachDown) {
      calls.add('coach');
      return null;
    }
    return super.getResultCoach(sessionId: sessionId);
  }
}
