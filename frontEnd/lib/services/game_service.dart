import '../models/scenario.dart';
import '../models/game_session.dart';
import '../models/action_result.dart';
import '../models/v1_recommend_result.dart';
import '../models/v2_recommend_result.dart';
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

  // ── POST /game/recommend/v1 ─────────────────
  // V1.5 사전 추천: 게임 시작 후 백그라운드 호출
  // 전체 100라운드 SPX 기준, 4개 라운드 추천
  // 응답 시간: 약 1~2분 (7,920개 순열 계산)
  Future<V1RecommendResult> getV1Recommendation({
    required String sessionId,
  }) async {
    final data = await _client.post(
      '/game/recommend/v1',
      body: {'sessionId': sessionId},
    );
    return V1RecommendResult.fromJson(data as Map<String, dynamic>);
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
    );
    return V2RecommendResult.fromJson(data as Map<String, dynamic>);
  }
}