package com.capstone.survival.controller;

import com.capstone.survival.dto.ApiResponse;
import com.capstone.survival.entity.Scenario;
import com.capstone.survival.repository.ScenarioRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@CrossOrigin(origins = "*")
@RequestMapping("/game")
@RequiredArgsConstructor
public class GameController {

    private final ScenarioRepository scenarioRepository;

    // GET /game/scenarios
    @GetMapping("/scenarios")
    public ApiResponse<List<Scenario>> getScenarios() {
        return ApiResponse.ok(scenarioRepository.findAll());
    }
}