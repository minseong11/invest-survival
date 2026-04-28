package com.capstone.survival.controller;

import com.capstone.survival.dto.ApiResponse;
import com.capstone.survival.entity.Scenario;
import com.capstone.survival.repository.ScenarioRepository;
import com.capstone.survival.service.GameService;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.*;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

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
        return ApiResponse.ok(scenarioRepository.findAll());
    }

    // POST /game/start
    @PostMapping("/start")
    public ApiResponse<?> startGame(@RequestBody Map<String, Integer> request) {
        return ApiResponse.ok(gameService.startGame(request.get("scenarioId")));
    }

    // POST /game/round/action
    @PostMapping("/round/action")
    public ApiResponse<?> selectCard(
            @RequestBody Map<String, Object> request) {
        String sessionId = (String) request.get("sessionId");
        Integer round = (Integer) request.get("round");
        Integer cardId = (Integer) request.get("cardId");

        return ApiResponse.ok(
                gameService.selectCard(sessionId, round, cardId)
        );
    }

    // POST /game/validate (Python 결과와 비교용 검증 엔드포인트)
    @PostMapping("/validate")
    public ApiResponse<?> validateGame(@RequestBody Map<String, Object> request) {
        String startDate = (String) request.get("startDate");

        // cardSelections: {"1": 1, "25": 2, "50": 3, "75": 4}
        @SuppressWarnings("unchecked")
        Map<String, Object> rawSelections = (Map<String, Object>) request.get("cardSelections");
        Map<Integer, Integer> cardSelections = new LinkedHashMap<>();
        rawSelections.forEach((k, v) -> cardSelections.put(Integer.parseInt(k), (Integer) v));

        return ApiResponse.ok(gameService.validateGame(startDate, cardSelections));
    }
}
