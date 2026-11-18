package com.capstone.survival.controller;

import com.capstone.survival.dto.ApiResponse;
import com.capstone.survival.entity.Scenario;
import com.capstone.survival.repository.ScenarioRepository;
import com.capstone.survival.service.GameService;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Sort;
import org.springframework.web.bind.annotation.*;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;

@RestController
@CrossOrigin(origins = "*")
@RequestMapping("/game")
@RequiredArgsConstructor
public class GameController {

    private final ScenarioRepository scenarioRepository;
    private final GameService gameService;

    // GET /game/scenarios
    @GetMapping("/scenarios")
    public ApiResponse<List<Scenario>> getScenarios() {
        return ApiResponse.ok(scenarioRepository.findAll(Sort.by("id")));
    }

    // POST /game/start
    @PostMapping("/start")
    public ApiResponse<?> startGame(@RequestBody Map<String, Object> request) {
        return ApiResponse.ok(gameService.startGame(intValue(request, "scenarioId")));
    }

    // POST /game/round/action — 카드 선택 (1·25·50·75라운드)
    @PostMapping("/round/action")
    public ApiResponse<?> selectCard(@RequestBody Map<String, Object> request) {
        return ApiResponse.ok(gameService.selectCard(
                stringValue(request, "sessionId"), intValue(request, "round"), intValue(request, "cardId")));
    }

    // POST /game/round/decision — (#125) 위기 대응 선택 (뉴스 속보 라운드)
    //   choice: HOLD(버틴다) / SELL_HALF(절반 판다) / BUY_MORE(더 산다)
    @PostMapping("/round/decision")
    public ApiResponse<?> decide(@RequestBody Map<String, Object> request) {
        return ApiResponse.ok(gameService.decide(
                stringValue(request, "sessionId"), intValue(request, "round"), stringValue(request, "choice")));
    }

    // POST /game/validate (Python 결과와 비교용 검증 엔드포인트)
    //   (#125) decisions {"10": "SELL_HALF"}와 baseTicker("^SPX"/"^NDX")도 받을 수 있다
    @PostMapping("/validate")
    public ApiResponse<?> validateGame(@RequestBody Map<String, Object> request) {
        Map<Integer, Integer> cardSelections = new LinkedHashMap<>();
        mapValue(request, "cardSelections").forEach((k, v) ->
                cardSelections.put(roundKey(k), toInt("cardSelections", v)));

        Map<Integer, String> decisions = new TreeMap<>();
        mapValue(request, "decisions").forEach((k, v) -> decisions.put(roundKey(k), String.valueOf(v)));

        return ApiResponse.ok(gameService.validateGame(
                stringValue(request, "startDate"), cardSelections, decisions, stringValue(request, "baseTicker")));
    }

    // POST /game/recommend/v1 — V1.5 사전 추천
    @PostMapping("/recommend/v1")
    public ApiResponse<?> recommendV1(@RequestBody Map<String, Object> request) {
        return ApiResponse.ok(gameService.recommendV1(stringValue(request, "sessionId")));
    }

    // POST /game/recommend/v2 — V2 실시간 추천 (25·50라운드)
    @PostMapping("/recommend/v2")
    public ApiResponse<?> recommendV2(@RequestBody Map<String, Object> request) {
        return ApiResponse.ok(gameService.recommendV2(
                stringValue(request, "sessionId"), intValue(request, "currentRound"),
                intList(request, "alreadyCards"), intList(request, "candidateCards")));
    }

    // POST /game/result/analysis — 사후 분석 (백테스팅), 결과 화면 진입 시 1회 호출
    // 분석 실패(Python 서버 오류/타임아웃) 시 data=null → 클라이언트는 분석 섹션 미표시
    @PostMapping("/result/analysis")
    public ApiResponse<?> analyzeResult(@RequestBody Map<String, Object> request) {
        return ApiResponse.ok(gameService.analyzeResult(stringValue(request, "sessionId")));
    }

    // POST /game/result/coach — (#125) 사후 분석 AI 코치 한마디, 분석과 따로 호출
    // 실패 시 data=null → 클라이언트는 해당 칸 미표시
    @PostMapping("/result/coach")
    public ApiResponse<?> coachResult(@RequestBody Map<String, Object> request) {
        return ApiResponse.ok(gameService.coachResult(stringValue(request, "sessionId")));
    }

    // ── 요청 값 꺼내기 (#125) ─────────────────────────────────
    //   없는 값은 null로 넘기고 서비스에서 "~가 필요합니다" 400으로 응답한다.
    //   형식이 다른 값(숫자 자리에 글자 등)은 IllegalArgumentException → 400 + 어떤 값이 틀렸는지
    //   (기존에는 빈 요청·틀린 형식이 500 또는 내부 오류 문구로 나갔다)

    private static String stringValue(Map<String, Object> request, String key) {
        Object v = request.get(key);
        return v != null ? v.toString() : null;
    }

    private static Integer intValue(Map<String, Object> request, String key) {
        Object v = request.get(key);
        return v != null ? toInt(key, v) : null;
    }

    private static int toInt(String key, Object v) {
        if (v instanceof Number n) return n.intValue();
        throw new IllegalArgumentException(key + " 값은 숫자여야 합니다");
    }

    private static List<Integer> intList(Map<String, Object> request, String key) {
        Object v = request.get(key);
        if (v == null) return null;
        if (!(v instanceof List<?> list)) {
            throw new IllegalArgumentException(key + " 값은 목록이어야 합니다");
        }
        return list.stream().map(x -> toInt(key, x)).toList();
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> mapValue(Map<String, Object> request, String key) {
        Object v = request.get(key);
        if (v == null) return new LinkedHashMap<>();
        if (!(v instanceof Map)) {
            throw new IllegalArgumentException(key + " 값은 {라운드: 값} 형태여야 합니다");
        }
        return (Map<String, Object>) v;
    }

    private static int roundKey(String key) {
        try {
            return Integer.parseInt(key.trim());
        } catch (NumberFormatException e) {
            throw new IllegalArgumentException("라운드 번호가 올바르지 않습니다: " + key);
        }
    }
}
