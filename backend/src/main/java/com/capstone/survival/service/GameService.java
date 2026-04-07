package com.capstone.survival.service;

import com.capstone.survival.entity.Card;
import com.capstone.survival.entity.GameSession;
import com.capstone.survival.entity.Scenario;
import com.capstone.survival.entity.StockPrice;
import com.capstone.survival.repository.CardRepository;
import com.capstone.survival.repository.GameSessionRepository;
import com.capstone.survival.repository.ScenarioRepository;
import com.capstone.survival.repository.StockPriceRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

import java.time.LocalDate;
import java.util.*;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
public class GameService {

    private final GameSessionRepository sessionRepository;
    private final ScenarioRepository scenarioRepository;
    private final StockPriceRepository stockPriceRepository;
    private final CardRepository cardRepository;

    // 카드 선택 라운드 고정
    private static final List<Integer> CARD_SELECT_ROUNDS = List.of(1, 25, 50, 75);

    // =============================================
    // 게임 시작
    // =============================================
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

        if (priceList.size() < 100) {
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

        // 4. 1라운드 데이터만 반환 (카드 선택해야 하니까)
        StockPrice first = priceList.get(0);

        Map<String, Object> priceData = new LinkedHashMap<>();
        priceData.put("ticker", first.getTicker());
        priceData.put("open", first.getOpen());
        priceData.put("close", first.getClose());
        priceData.put("high", first.getHigh());
        priceData.put("low", first.getLow());
        priceData.put("changeRate", 0.0); // 첫 라운드는 비교 대상 없음

        Map<String, Object> firstRound = new LinkedHashMap<>();
        firstRound.put("round", 1);
        firstRound.put("date", first.getTradeDate().toString());
        firstRound.put("priceData", List.of(priceData));

        // 5. 응답 반환
        Map<String, Object> response = new LinkedHashMap<>();
        response.put("sessionId", sessionId);
        response.put("scenarioTitle", scenario.getTitle());
        response.put("totalRounds", 100);
        response.put("initialAsset", 10_000_000L);
        response.put("cardSelectRounds", CARD_SELECT_ROUNDS);
        response.put("rounds", List.of(firstRound));

        return response;
    }

    // =============================================
    // 카드 선택
    // =============================================
    public Map<String, Object> selectCard(
            String sessionId, Integer round, Integer cardId) {

        // 1. 세션 조회
        GameSession session = sessionRepository.findById(sessionId)
                .orElseThrow(() -> new IllegalArgumentException("존재하지 않는 세션입니다"));

        // 2. 카드 조회
        Card card = cardRepository.findById(cardId)
                .orElseThrow(() -> new IllegalArgumentException("존재하지 않는 카드입니다"));

        // 3. 중복 카드 체크
        List<Integer> appliedCardIds = getAppliedCardIds(session);
        if (appliedCardIds.contains(cardId)) {
            throw new IllegalArgumentException("이미 선택한 카드입니다");
        }

        // 4. 카드 효과 적용 (매수)
        double currentClose = getPriceAtRound(session, round);
        double buyAmount = session.getCash() * card.getRatio();
        double newShares = session.getSpxShares() + (buyAmount / currentClose);
        long newCash = (long)(session.getCash() - buyAmount);

        // 5. 적용된 카드 목록 업데이트
        appliedCardIds.add(cardId);
        String newAppliedCards = appliedCardIds.stream()
                .map(String::valueOf)
                .collect(Collectors.joining(","));

        // 6. 다음 증강 라운드 계산
        Integer nextEventRound = CARD_SELECT_ROUNDS.stream()
                .filter(r -> r > round)
                .findFirst()
                .orElse(null);

        // 7. 현재 라운드부터 다음 증강 직전까지 계산
        int endRound = nextEventRound != null ? nextEventRound - 1 : 100;
        List<Map<String, Object>> rounds = calculateRounds(
                session, round, endRound, newCash, newShares
        );

        // 8. 세션 업데이트
        session.update(newCash, newShares, endRound + 1, newAppliedCards);
        sessionRepository.save(session);

        // 9. 응답 반환
        Map<String, Object> response = new LinkedHashMap<>();
        response.put("selectedCard", card.getName());
        response.put("nextEventRound", nextEventRound);
        response.put("rounds", rounds);

        return response;
    }

    // =============================================
    // 라운드별 자산 계산
    // =============================================
    private List<Map<String, Object>> calculateRounds(
            GameSession session, int startRound, int endRound,
            long cash, double shares) {

        List<StockPrice> priceList = stockPriceRepository
                .findByTickerAndTradeDateGreaterThanEqualOrderByTradeDate(
                        session.getTicker(),
                        LocalDate.parse(session.getGameStartDate())
                );

        List<Map<String, Object>> rounds = new ArrayList<>();

        for (int i = startRound - 1; i < endRound; i++) {
            if (i >= priceList.size()) break;

            StockPrice current = priceList.get(i);
            StockPrice prev = i > 0 ? priceList.get(i - 1) : null;

            // 등락률 계산
            double changeRate = 0.0;
            if (prev != null && prev.getClose() > 0) {
                changeRate = (current.getClose() - prev.getClose())
                        / prev.getClose() * 100;
                changeRate = Math.round(changeRate * 100.0) / 100.0;
            }

            // 자산 계산
            long roundAsset = (long)(cash + shares * current.getClose());
            double returnRate = (double)(roundAsset - session.getInitialAsset())
                    / session.getInitialAsset() * 100;
            returnRate = Math.round(returnRate * 100.0) / 100.0;

            // priceData
            Map<String, Object> priceData = new LinkedHashMap<>();
            priceData.put("ticker", current.getTicker());
            priceData.put("open", current.getOpen());
            priceData.put("close", current.getClose());
            priceData.put("high", current.getHigh());
            priceData.put("low", current.getLow());
            priceData.put("changeRate", changeRate);

            // round
            Map<String, Object> roundMap = new LinkedHashMap<>();
            roundMap.put("round", i + 1);
            roundMap.put("date", current.getTradeDate().toString());
            roundMap.put("priceData", List.of(priceData));
            roundMap.put("roundAsset", roundAsset);
            roundMap.put("returnRate", returnRate);

            rounds.add(roundMap);
        }

        return rounds;
    }

    // =============================================
    // 유틸 메서드
    // =============================================

    // 특정 라운드 종가 조회
    private double getPriceAtRound(GameSession session, int round) {
        List<StockPrice> priceList = stockPriceRepository
                .findByTickerAndTradeDateGreaterThanEqualOrderByTradeDate(
                        session.getTicker(),
                        LocalDate.parse(session.getGameStartDate())
                );
        return priceList.get(round - 1).getClose();
    }

    // 적용된 카드 ID 목록 파싱
    private List<Integer> getAppliedCardIds(GameSession session) {
        if (session.getAppliedCards() == null
                || session.getAppliedCards().isEmpty()) {
            return new ArrayList<>();
        }
        return Arrays.stream(session.getAppliedCards().split(","))
                .map(Integer::parseInt)
                .collect(Collectors.toList());
    }
}