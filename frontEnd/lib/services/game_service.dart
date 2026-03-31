import '../models/scenario.dart';
import '../models/game_session.dart';
import '../models/action_result.dart';
import 'api_client.dart';

class GameService {
  final ApiClient _client = ApiClient();

  // GET /game/scenarios
  Future<List<Scenario>> getScenarios() async {
    final data = await _client.get('/game/scenarios');
    final List<dynamic> list = data as List<dynamic>;
    return list.map((json) => Scenario.fromJson(json)).toList();
  }

  // POST /game/start
  Future<GameSession> startGame(int scenarioId) async {
    final data = await _client.post(
      '/game/start',
      body: {'scenarioId': scenarioId},
    );
    return GameSession.fromJson(data as Map<String, dynamic>);
  }

  // POST /game/round/action
  // 카드 선택 → 해당 라운드 ~ 다음 증강 직전까지 계산된 결과 받기
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
}