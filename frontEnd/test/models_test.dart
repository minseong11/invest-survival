import 'package:flutter_application_1/models/action_result.dart';
import 'package:flutter_application_1/models/card_info.dart';
import 'package:flutter_application_1/models/coach_comment.dart';
import 'package:flutter_application_1/models/decision.dart';
import 'package:flutter_application_1/models/game_session.dart';
import 'package:flutter_application_1/models/result_analysis.dart';
import 'package:flutter_application_1/models/round_data.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_game_service.dart';

// 서버 응답 파싱 — 새 필드(#125)와, 새 필드가 없는 예전 서버 응답 모두
void main() {
  group('GameSession', () {
    test('위기 대응 라운드·브리핑을 읽고 이벤트 라운드를 구분한다', () async {
      final session = await FakeGameService().startGame(1);
      expect(session.decisionRounds, [10, 60]);
      expect(session.isEventRound(1), isTrue);     // 카드 선택
      expect(session.isEventRound(10), isTrue);    // 위기 대응
      expect(session.isDecisionRound(25), isFalse);
      expect(session.isEventRound(11), isFalse);
      expect(session.briefing!.assets.length, 2);
      expect(session.briefing!.spxSeries.length, 21);
      expect(session.buyMoreTarget, 'S&P500');
    });

    test('예전 서버 응답(새 필드 없음)도 읽는다', () {
      final session = GameSession.fromJson({
        'sessionId': 'old',
        'scenarioTitle': '예전',
        'totalRounds': 100,
        'initialAsset': 10000000,
        'cardSelectRounds': [1, 25, 50, 75],
        'firstCardOptions': [1, 2, 3],
        'rounds': [],
      });
      expect(session.decisionRounds, isEmpty);
      expect(session.briefing, isNull);
      expect(session.isEventRound(10), isFalse);
      expect(session.buyMoreTarget, 'S&P500');
    });

    test('copyWithRounds는 나머지 값을 그대로 둔다', () async {
      final session = await FakeGameService().startGame(1);
      final copy = session.copyWithRounds([]);
      expect(copy.rounds, isEmpty);
      expect(copy.decisionRounds, session.decisionRounds);
      expect(copy.briefing, same(session.briefing));
      expect(copy.sessionId, session.sessionId);
    });
  });

  group('RoundData / ActionResult', () {
    test('건너뛴 카드와 이유를 읽는다', () {
      final round = RoundData.fromJson({
        'round': 30,
        'date': '2008-10-13',
        'priceData': [],
        'triggeredCards': [2],
        'skippedCards': [
          {'cardId': 11, 'reason': 'CASH_LOW'},
          {'cardId': 8, 'reason': 'NO_HOLDINGS'},
        ],
      });
      expect(round.skippedCards.map((s) => s.cardId), [11, 8]);
      expect(SkippedCard.label(round.skippedCards[0].reason), '현금 부족');
      expect(SkippedCard.label('MAX_REACHED'), '횟수 소진');
      expect(SkippedCard.label('???'), '건너뜀');
    });

    test('skippedCards가 없으면 빈 목록', () {
      final round = RoundData.fromJson({'round': 1, 'date': '', 'priceData': []});
      expect(round.skippedCards, isEmpty);
    });

    test('다음 이벤트가 위기 대응이면 속보를 읽는다', () async {
      final fake = FakeGameService();
      final result = await fake.submitAction(sessionId: 'fake', round: 1, cardId: 1);
      expect(result.nextEventRound, 10);
      expect(result.nextEventType, 'DECISION');
      expect(result.nextDecision!.round, 10);
      expect(result.nextDecision!.news.headline, contains('10라운드'));
      expect(result.rounds.first.round, 1);
      expect(result.rounds.last.round, 9);
    });

    test('마지막 이벤트 뒤에는 100라운드까지 온다', () async {
      final fake = FakeGameService();
      final result = await fake.submitAction(sessionId: 'fake', round: 75, cardId: 4);
      expect(result.nextEventRound, isNull);
      expect(result.nextDecision, isNull);
      expect(result.rounds.last.round, 100);
    });

    test('예전 서버 응답(nextEventType·nextDecision 없음)도 읽는다', () {
      final result = ActionResult.fromJson({
        'selectedCard': '거인의 어깨',
        'nextEventRound': 25,
        'nextCardOptions': [2, 3, 4],
        'rounds': [],
      });
      expect(result.nextEventType, isNull);
      expect(result.nextDecision, isNull);
      expect(result.tradeAmount, 0);
    });
  });

  group('ResultAnalysis', () {
    test('위기 대응: 더 좋았던 다른 선택을 고른다', () {
      final fake = FakeGameService()..decisions[10] = 'SELL_HALF';
      final review = ResultAnalysis.fromJson(fake.analysisJson()).decisionReview!;
      final r = review.rounds.single;
      expect(r.choice, 'SELL_HALF');
      expect(r.better!.choice, 'HOLD');           // +2.0%p
      expect(r.better!.diffReturnRate, 2.0);
      expect(review.allHold, isFalse);
    });

    test('다른 선택이 모두 나빴으면 better는 null', () {
      final review = DecisionRoundReview.fromJson({
        'round': 10,
        'date': '2008-09-15',
        'choice': 'HOLD',
        'tradeAmount': 0,
        'alternatives': [
          {'choice': 'SELL_HALF', 'finalReturnRate': -3.0, 'diffReturnRate': -1.0},
          {'choice': 'BUY_MORE', 'finalReturnRate': -9.0, 'diffReturnRate': -7.0},
        ],
      });
      expect(review.better, isNull);
      expect(review.headline, '');
    });

    test('등급·성적표·그 후 이야기 파싱', () {
      final a = ResultAnalysis.fromJson(FakeGameService().analysisJson());
      expect(a.grade, 'C');
      expect(a.risk!.playerMdd, -21.5);
      expect(a.risk!.marketMdd, -30.0);
      expect(a.cardReport.length, 4);
      expect(a.cardReport.last.mainSkipReason, 'CASH_LOW');
      expect(a.cardReport.last.skipTotal, 2);
      expect(a.cardReport.first.mainSkipReason, isNull);
      expect(a.decisionReview, isNull);           // 위기 대응을 하지 않은 게임
      expect(a.epilogue!.points.map((p) => p.label), ['6개월 뒤', '1년 뒤']);
      expect(a.epilogue!.points.last.bestReturnRate, 53.0);
    });

    test('예전 서버 응답(새 필드 없음)도 읽는다', () {
      final json = FakeGameService().analysisJson()
        ..remove('grade')
        ..remove('risk')
        ..remove('cardReport')
        ..remove('decisionReview')
        ..remove('epilogue');
      final a = ResultAnalysis.fromJson(json);
      expect(a.grade, '');
      expect(a.risk, isNull);
      expect(a.cardReport, isEmpty);
      expect(a.epilogue, isNull);
      expect(a.playerResult.rank, 6000);
      expect(a.offered, isNotNull);
    });

    test('새 필드 하나의 형식이 틀려도 나머지는 읽는다', () {
      final json = FakeGameService().analysisJson()..['risk'] = 'oops';
      final a = ResultAnalysis.fromJson(json);
      expect(a.risk, isNull);
      expect(a.grade, 'C');
      expect(a.cardReport.length, 4);
    });
  });

  group('CoachComment', () {
    test('줄 머리말로 나눈다', () {
      final c = CoachComment.fromJson({
        'comment': '요약: 시장은 떨어졌어요.\n아쉬운 점: 원유 베팅 — 손실이 컸어요.\n다음엔: 나눠 사 보세요.',
        'status': 'fallback',
      })!;
      expect(c.lines.map((l) => l.head), ['요약', '아쉬운 점', '다음엔']);
      expect(c.lines.last.body, '나눠 사 보세요.');
      expect(c.byAi, isFalse);
    });

    test('빈 응답은 null', () {
      expect(CoachComment.fromJson(null), isNull);
      expect(CoachComment.fromJson({'comment': '  '}), isNull);
    });
  });

  group('카드·위기 대응 문구', () {
    test('카드는 11장이고 설명에 종목 코드가 없다', () {
      expect(CardInfo.all.length, 11);
      expect(CardInfo.all.map((c) => c.id).toSet().length, 11);
      for (final card in CardInfo.all) {
        expect(card.description, isNot(contains('SPX')), reason: card.name);
        expect(card.description, isNot(contains('NDX')), reason: card.name);
        expect(card.description, isNot(contains('AAPL')), reason: card.name);
        expect(card.description, isNot(contains('\n')), reason: card.name);
      }
    });

    test('위기 대응 선택지는 3개이고 문구가 모두 있다', () {
      expect(DecisionChoice.all, ['HOLD', 'SELL_HALF', 'BUY_MORE']);
      for (final c in DecisionChoice.all) {
        expect(DecisionChoice.label(c), isNotEmpty);
        expect(DecisionChoice.done(c), isNotEmpty);
        expect(DecisionChoice.ifDone(c), isNotEmpty);
      }
      expect(DecisionChoice.description('BUY_MORE', target: '나스닥100'), contains('나스닥100'));
    });
  });
}
