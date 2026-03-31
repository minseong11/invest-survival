package com.capstone.survival.service;

import com.capstone.survival.entity.GameSession;
import com.capstone.survival.entity.Scenario;
import com.capstone.survival.entity.StockPrice;
import com.capstone.survival.repository.GameSessionRepository;
import com.capstone.survival.repository.ScenarioRepository;
import com.capstone.survival.repository.StockPriceRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

import java.time.LocalDate;
import java.util.*;

@Service
@RequiredArgsConstructor
public class GameService {

    private final GameSessionRepository sessionRepository;
    private final ScenarioRepository scenarioRepository;
    private final StockPriceRepository stockPriceRepository;

    public Map<String, Object> startGame(Integer scenarioId) {
        // 1. 시나리오 조회
        Scenario scenario = scenarioRepository.findById(scenarioId)
                .orElseThrow(() -> new IllegalArgumentException("존재하지 않는 시나리오입니다"));

        // 2. 주가 데이터 조회
        List<StockPrice> priceList = stockPriceRepository
                .findByTickerAndTradeDateBetweenOrderByTradeDate(
                        scenario.getTicker(),
                        LocalDate.parse(scenario.getStartDate()),
                        LocalDate.parse(scenario.getEndDate())
                );

        if (priceList.size() < 10) {
            throw new IllegalStateException("주가 데이터가 부족합니다");
        }

        // 3. 세션 생성
        String sessionId = UUID.randomUUID().toString().substring(0, 8);
        GameSession session = new GameSession(
                sessionId,
                scenarioId,
                scenario.getTitle(),
                scenario.getTicker(),
                priceList.get(0).getTradeDate().toString()
        );
        sessionRepository.save(session);

        // 4. 10라운드 데이터 생성
        List<Map<String, Object>> rounds = new ArrayList<>();
        for (int i = 0; i < 10; i++) {
            StockPrice current = priceList.get(i);
            StockPrice prev = i > 0 ? priceList.get(i - 1) : null;

            // 등락률 계산
            double changeRate = 0.0;
            if (prev != null && prev.getClose() != null && prev.getClose() > 0) {
                changeRate = (current.getClose() - prev.getClose()) / prev.getClose() * 100;
                changeRate = Math.round(changeRate * 100.0) / 100.0;
            }

            Map<String, Object> priceData = new LinkedHashMap<>();
            priceData.put("ticker", current.getTicker());
            priceData.put("open", current.getOpen());
            priceData.put("close", current.getClose());
            priceData.put("high", current.getHigh());
            priceData.put("low", current.getLow());
            priceData.put("changeRate", changeRate);

            Map<String, Object> round = new LinkedHashMap<>();
            round.put("round", i + 1);
            round.put("date", current.getTradeDate().toString());
            round.put("priceData", List.of(priceData));

            rounds.add(round);
        }

        // 5. 응답 반환
        Map<String, Object> response = new LinkedHashMap<>();
        response.put("sessionId", sessionId);
        response.put("scenarioTitle", scenario.getTitle());
        response.put("totalRounds", 10);
        response.put("initialAsset", 10_000_000L);
        response.put("rounds", rounds);

        return response;
    }
}