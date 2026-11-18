import '../models/scenario.dart';
import '../models/game_session.dart';
import '../models/action_result.dart';
import '../models/v2_recommend_result.dart';
import '../models/result_analysis.dart';
import '../models/coach_comment.dart';
import 'api_client.dart';

class GameService {
  final ApiClient _client = ApiClient();

  // ── GET /game/scenarios ─────────────────────
  Future<List<Scenario>> getScenarios() async {
    final data = await _client.get('/game/scenarios');
    final List<dynamic> list = data as List<dynamic>;
    return list.map((json) => Scenario.fromJson(json)).toList();
  }

  // ── POST /game/start ────────────────────────
  Future<GameSession> startGame(int scenarioId) async {
    final data = await _client.post(
      '/game/start',
      body: {'scenarioId': scenarioId},
    );
    return GameSession.fromJson(data as Map<String, dynamic>);
  }

  // ── POST /game/round/action ─────────────────
  Future<ActionResult> submitAction({
    required String sessionId,
    required int round,
    required int cardId,
  }) async {
    final data = await _client.post(
      '/game/round/action',
      body: {
        'sessionId': sessionId,
        'round': round,
        'cardId': cardId,
      },
    );
    return ActionResult.fromJson(data as Map<String, dynamic>);
  }

  // ── POST /game/round/decision ───────────────
  // (#125) 위기 대응 선택: choice = HOLD / SELL_HALF / BUY_MORE
  // 응답 형식은 카드 선택과 같다 (이번 라운드부터 다음 이벤트 라운드 직전까지)
  Future<ActionResult> submitDecision({
    required String sessionId,
    required int round,
    required String choice,
  }) async {
    final data = await _client.post(
      '/game/round/decision',
      body: {
        'sessionId': sessionId,
        'round': round,
        'choice': choice,
      },
    );
    return ActionResult.fromJson(data as Map<String, dynamic>);
  }

  // ※ POST /game/recommend/v1 (V1.5 사전 추천)은 v6.0부터 호출하지 않음
  //   100라운드 전체 시장을 미리 아는 구조라 게임 중 추천으로 부적절.
  //   서버 엔드포인트는 존치 (추후 V1.5 성능 검증용)

  // ── POST /game/result/analysis ──────────────
  // 게임 종료 후 사후 분석 (백테스팅, v6.1)
  // 7,920개 조합 전수 계산. (#125) 서버가 게임 중에 미리 계산해 두므로 보통 바로 오고, 처음 계산이면 1~2초
  // 실패하면 null 반환 → 결과 화면은 분석 섹션 없이 정상 표시
  //  - Python 실패 시 서버가 data: null 응답
  //  - 게임 미종료·목데이터 세션 등은 오류 응답 → 여기서 잡아서 null
  Future<ResultAnalysis?> getResultAnalysis({
    required String sessionId,
  }) async {
    try {
      final data = await _client.post(
        '/game/result/analysis',
        body: {'sessionId': sessionId},
        receiveTimeout: const Duration(seconds: 30),
      );
      if (data == null) return null;
      return ResultAnalysis.fromJson(data as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  // ── POST /game/result/coach ─────────────────
  // (#125) 사후 분석 AI 코치 한마디. 분석과 따로 호출한다 (AI 문장을 기다리느라 분석 표시가 늦어지지 않게)
  // 실패하면 null → 결과 화면은 해당 칸 없이 정상 표시
  Future<CoachComment?> getResultCoach({
    required String sessionId,
  }) async {
    try {
      final data = await _client.post(
        '/game/result/coach',
        body: {'sessionId': sessionId},
        receiveTimeout: const Duration(seconds: 30),
      );
      return CoachComment.fromJson(data);
    } catch (_) {
      return null;
    }
  }

  // ── POST /game/recommend/v2 ─────────────────
  // V2 실시간 추천: 25·50라운드 카드 선택 시
  // so_far 시장 지표 + 이미 선택한 카드 기반
  // 75라운드 제외 (스피어만 역상관 ρ=-0.12)
  // 응답에 feedback 필드가 함께 포함되어 옴 (v5.0)
  Future<V2RecommendResult> getV2Recommendation({
    required String sessionId,
    required int currentRound,
    required List<int> alreadyCards,
    required List<int> candidateCards,
  }) async {
    final data = await _client.post(
      '/game/recommend/v2',
      body: {
        'sessionId':      sessionId,
        'currentRound':   currentRound,
        'alreadyCards':   alreadyCards,
        'candidateCards': candidateCards,
      },
      // (#125) AI 설명 문장(LLM)까지 함께 오므로 기본 5초로는 부족할 수 있다.
      //        서버는 LLM을 8초 + 재시도 1회로 끊고 기본 문장으로 응답한다
      receiveTimeout: const Duration(seconds: 30),
    );
    return V2RecommendResult.fromJson(data as Map<String, dynamic>);
  }
}