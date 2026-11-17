import 'dart:math';

import 'package:flutter_application_1/models/action_result.dart';
import 'package:flutter_application_1/models/coach_comment.dart';
import 'package:flutter_application_1/models/game_session.dart';
import 'package:flutter_application_1/models/result_analysis.dart';
import 'package:flutter_application_1/models/scenario.dart';
import 'package:flutter_application_1/models/v2_recommend_result.dart';
import 'package:flutter_application_1/services/game_service.dart';

// =============================================
// 테스트용 가짜 게임 서버 (#125)
// 서버 없이 화면 흐름을 끝까지 돌려 보기 위한 것. 응답은 실제 서버와 같은 JSON 모양으로 만들고
// 앱의 fromJson을 그대로 거치게 한다 (형식이 바뀌면 여기서 먼저 드러난다).
// 가격·자산은 정해진 규칙으로 만든 가상의 값이다 (실제 게임 계산이 아님).
// =============================================
class FakeGameService extends GameService {
  static const cardRounds = [1, 25, 50, 75];
  final List<int> decisionRounds;

  // 화면이 실제로 호출한 내용 (테스트에서 확인)
  final List<String> calls = [];
  final Map<int, int> selections = {};
  final Map<int, String> decisions = {};

  // 카드를 고른 뒤 라운드의 현금 비중(%) — 5보다 작으면 앱이 '현금 부족' 안내를 띄운다
  final double heldCashWeight;

  FakeGameService({this.decisionRounds = const [10, 60], this.heldCashWeight = 70.0});

  List<int> get _events => [...cardRounds, ...decisionRounds]..sort();

  double _spx(int round) => 1000 * (1 - 0.3 * sin(round / 100 * pi / 2)); // 100라운드 동안 30% 하락

  // 실제 서버처럼 라운드마다 모든 종목 가격을 보낸다 (갖고 있지 않은 종목 포함)
  //   금은 라운드마다 0.2%씩 오르게 해 두어 24라운드에 +4.6%
  Map<String, double> _closes(int round) => {
        '^SPX': _spx(round),
        '^NDX': 2000 * (1 - 0.4 * sin(round / 100 * pi / 2)),
        'XAUUSD': 800 * (1 + 0.002 * (round - 1)),
        'USO': 100 * (1 - 0.005 * (round - 1)),
        'AAPL': 150 * (1 - 0.003 * (round - 1)),
        'TLT': 90 * (1 + 0.001 * (round - 1)),
      };

  List<Map<String, dynamic>> _prices(int round) => [
        for (final e in _closes(round).entries)
          {
            'ticker': e.key,
            'open': e.value,
            'close': e.value,
            'high': e.value,
            'low': e.value,
            'changeRate': -0.5,
          }
      ];

  Map<String, dynamic> _news(int round, String level, String headline) => {
        'date': _date(round),
        'headline': headline,
        'level': level,
        'source': '테스트',
        'sourceUrl': 'https://example.com',
      };

  String _date(int round) {
    final d = DateTime(2008, 9, 1).add(Duration(days: round));
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Map<String, dynamic> _round(int round) {
    final held = selections.length;
    final asset = (10000000 * (1 - 0.002 * round * held / 4)).roundToDouble();
    final rate = (asset - 10000000) / 10000000 * 100;
    final hasSpx = held > 0;
    return {
      'round': round,
      'date': _date(round),
      'priceData': _prices(round),
      'roundAsset': asset,
      'returnRate': double.parse(rate.toStringAsFixed(2)),
      'triggeredCards': round % 7 == 0 && held > 0 ? [selections.values.first] : <int>[],
      'skippedCards': round == 30 && held > 1
          ? [
              {'cardId': selections.values.elementAt(1), 'reason': 'CASH_LOW'}
            ]
          : <Map<String, dynamic>>[],
      'holdings': hasSpx
          ? [
              {
                'ticker': '^SPX',
                'name': 'S&P500',
                'shares': 1.5,
                'avgPrice': 1000.0,
                'currentPrice': _spx(round),
                'costAmount': 3000000,
                'value': 2700000,
                'returnRate': -10.0,
                'weight': 30.0,
              }
            ]
          : <Map<String, dynamic>>[],
      'cash': hasSpx ? 7000000 : 10000000,
      'cashWeight': hasSpx ? heldCashWeight : 100.0,
      'news': round == 5
          ? [_news(5, 'caution', '테스트 주의 뉴스')]
          : <Map<String, dynamic>>[],
    };
  }

  // 이번 이벤트 라운드부터 다음 이벤트 라운드 직전까지
  Map<String, dynamic> _advance(int round) {
    final next = _events.where((r) => r > round).cast<int?>().firstWhere(
          (r) => true,
          orElse: () => null,
        );
    final end = next == null ? 100 : next - 1;
    final isDecision = next != null && decisionRounds.contains(next);
    final used = selections.values.toSet();
    return {
      'nextEventRound': next,
      'nextEventType': next == null ? null : (isDecision ? 'DECISION' : 'CARD'),
      'nextCardOptions': (next != null && !isDecision)
          ? [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11].where((c) => !used.contains(c)).take(3).toList()
          : null,
      'nextDecision': isDecision
          ? {
              'round': next,
              'news': _news(next, next == 60 ? 'positive' : 'danger', '테스트 속보 $next라운드'),
              'buyMoreTarget': 'S&P500',
            }
          : null,
      'nextRoundNews': isDecision
          ? [_news(next, next == 60 ? 'positive' : 'danger', '테스트 속보 $next라운드')]
          : <Map<String, dynamic>>[],
      'rounds': [for (int r = round; r <= end; r++) _round(r)],
    };
  }

  @override
  Future<List<Scenario>> getScenarios() async {
    calls.add('scenarios');
    return [
      Scenario.fromJson({
        'id': 1,
        'title': '테스트 위기',
        'year': 2008,
        'difficulty': 5,
        'description': '테스트용 시나리오 설명이에요.',
        'colorHex': 'FAECE7',
      }),
    ];
  }

  @override
  Future<GameSession> startGame(int scenarioId) async {
    calls.add('start');
    return GameSession.fromJson({
      'sessionId': 'fake',
      'scenarioTitle': '테스트 위기',
      'totalRounds': 100,
      'initialAsset': 10000000,
      'cardSelectRounds': cardRounds,
      'firstCardOptions': [1, 2, 8],
      'decisionRounds': decisionRounds,
      'buyMoreTarget': 'S&P500',
      'briefing': {
        'intro': '테스트 배경 설명이에요.',
        'days': 20,
        'fromDate': '2008-08-01',
        'toDate': '2008-08-29',
        'assets': [
          {'ticker': '^SPX', 'name': 'S&P500', 'changeRate': 1.79},
          {'ticker': 'USO', 'name': '원유', 'changeRate': -7.58},
        ],
        'spxSeries': [
          for (int i = 0; i < 21; i++) {'date': '2008-08-$i', 'close': 1250.0 + i}
        ],
      },
      'rounds': [
        {
          'round': 1,
          'date': _date(1),
          'priceData': _prices(1),
          'holdings': [],
          'cash': 10000000,
          'cashWeight': 100.0,
          'news': [],
        }
      ],
    });
  }

  @override
  Future<ActionResult> submitAction({
    required String sessionId,
    required int round,
    required int cardId,
  }) async {
    calls.add('card:$round:$cardId');
    selections[round] = cardId;
    return ActionResult.fromJson({'selectedCard': '카드 $cardId', ..._advance(round)});
  }

  @override
  Future<ActionResult> submitDecision({
    required String sessionId,
    required int round,
    required String choice,
  }) async {
    calls.add('decision:$round:$choice');
    decisions[round] = choice;
    return ActionResult.fromJson({
      'decision': choice,
      'tradeAmount': choice == 'HOLD' ? 0 : 1350000,
      ..._advance(round),
    });
  }

  @override
  Future<V2RecommendResult> getV2Recommendation({
    required String sessionId,
    required int currentRound,
    required List<int> alreadyCards,
    required List<int> candidateCards,
  }) async {
    calls.add('ai:$currentRound');
    return V2RecommendResult.fromJson({
      'recommendedCardId': candidateCards[1],
      'recommendedCardName': '추천 카드',
      // 예측값은 아직 고르지 않은 카드 전체의 평균과의 차이라서 세 값의 합이 0일 필요는 없다
      'rankings': [
        {'rank': 1, 'cardId': candidateCards[1], 'cardName': 'A', 'contribution': 1.4},
        {'rank': 2, 'cardId': candidateCards[0], 'cardName': 'B', 'contribution': 0.3},
        {'rank': 3, 'cardId': candidateCards[2], 'cardName': 'C', 'contribution': -1.2},
      ],
      'feedback': '지금 시장: 시작 후 17.3% 하락 · 하루 등락은 크게 출렁이는 편\n'
          '이 카드는: 테스트 카드 설명\n'
          '그래서: 테스트 이유 문장이에요.\n'
          '카드 규칙 · 테스트 카드: 테스트 규칙',
    });
  }

  Map<String, dynamic> analysisJson() {
    final picked = [for (final r in cardRounds) selections[r] ?? 1];
    Map<String, dynamic> combo(List<int> cards, double rate, int rank) => {
          'rank': rank,
          'tiedCount': 1,
          'cards': [
            for (int i = 0; i < 4; i++) {'round': cardRounds[i], 'cardId': cards[i], 'cardName': ''}
          ],
          'finalAsset': 10000000 * (1 + rate / 100),
          'finalReturnRate': rate,
        };
    return {
      'totalCombinations': 7920,
      'cardPoolSize': 11,
      'topCombos': [combo([8, 2, 4, 7], 20.21, 1)],
      'playerResult': {...combo(picked, -20.0, 6000), 'topPercent': 75.8},
      'offeredAnalysis': {
        'totalCombinations': 60,
        'bestCombo': combo([2, 4, 5, 6], 4.3, 1),
        'playerResult': {...combo(picked, -20.0, 40), 'topPercent': 66.7},
        'roundAlternatives': [
          for (int i = 0; i < 4; i++)
            {
              'round': cardRounds[i],
              'offeredCards': [picked[i], 9, 10],
              'playerCardId': picked[i],
              'playerCardName': '',
              'alternatives': [
                {'cardId': 9, 'cardName': '애플 줍줍', 'finalAsset': 8100000, 'finalReturnRate': -19.0, 'diffReturnRate': i == 0 ? 1.0 : -0.5},
              ],
            }
        ],
      },
      'grade': 'C',
      'risk': {
        'playerMdd': -21.5,
        'playerMddDate': '2008-11-20',
        'marketMdd': -30.0,
        'marketMddDate': '2008-11-20',
        'marketReturnRate': -30.0,
      },
      'cardReport': [
        for (int i = 0; i < 4; i++)
          {
            'round': cardRounds[i],
            'cardId': picked[i],
            'cardName': '',
            'cardType': i == 0 ? 'BUY_ONCE' : 'BUY_ON_CONDITION',
            'triggerCount': i == 3 ? 0 : 3 + i,
            'tradeAmount': i == 3 ? 0 : 3000000 - i * 900000,
            'skips': i == 3 ? {'CASH_LOW': 2} : <String, int>{},
            'withoutFinalAsset': 9000000,
            'withoutFinalReturnRate': -10.0,
            'effectAsset': -1000000,
            'effectReturnRate': i == 3 ? 0.0 : (i == 1 ? 4.2 : -8.7),
          }
      ],
      'decisionReview': decisions.isEmpty
          ? null
          : {
              'rounds': [
                for (final e in decisions.entries)
                  {
                    'round': e.key,
                    'date': _date(e.key),
                    'headline': '테스트 속보 ${e.key}라운드',
                    'level': e.key == 60 ? 'positive' : 'danger',
                    'choice': e.value,
                    'tradeAmount': e.value == 'HOLD' ? 0 : 1350000,
                    'alternatives': [
                      {'choice': e.value == 'HOLD' ? 'SELL_HALF' : 'HOLD', 'finalAsset': 8200000, 'finalReturnRate': -18.0, 'diffReturnRate': 2.0},
                      {'choice': 'BUY_MORE', 'finalAsset': 7500000, 'finalReturnRate': -25.0, 'diffReturnRate': -5.0},
                    ],
                  }
              ],
              'allHoldFinalAsset': 7900000,
              'allHoldFinalReturnRate': -21.0,
              'effectReturnRate': 1.0,
            },
      'epilogue': {
        'endDate': _date(100),
        'points': [
          {'label': '6개월 뒤', 'tradingDays': 125, 'date': '2009-07-23', 'spxChangeRate': 17.35, 'playerAsset': 9000000, 'playerReturnRate': -10.0, 'bestAsset': 13600000, 'bestReturnRate': 36.0},
          {'label': '1년 뒤', 'tradingDays': 250, 'date': '2010-01-21', 'spxChangeRate': 34.2, 'playerAsset': 9900000, 'playerReturnRate': -1.0, 'bestAsset': 15300000, 'bestReturnRate': 53.0},
        ],
      },
    };
  }

  @override
  Future<ResultAnalysis?> getResultAnalysis({required String sessionId}) async {
    calls.add('analysis');
    return ResultAnalysis.fromJson(analysisJson());
  }

  @override
  Future<CoachComment?> getResultCoach({required String sessionId}) async {
    calls.add('coach');
    return CoachComment.fromJson({
      'comment': '요약: 같은 기간 S&P500은 30.0% 떨어졌고, 내 자산은 20.0% 줄었어요.\n'
          '잘한 점: 황금 적립 — 이 카드가 없었다면 수익률이 4.2%p 낮았을 거예요.\n'
          '다음엔: 테스트 코치 문장이에요.',
      'status': 'llm',
    });
  }
}
