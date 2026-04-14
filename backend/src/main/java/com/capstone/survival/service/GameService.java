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

    private static final List<Integer> CARD_SELECT_ROUNDS = List.of(1, 25, 50, 75);
    private static final List<Integer> ALL_CARD_IDS = List.of(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11);

    // =============================================
    // 게임 시작
    // =============================================
    public Map<String, Object> startGame(Integer scenarioId) {

        Scenario scenario = scenarioRepository.findById(scenarioId)
                .orElseThrow(() -> new IllegalArgumentException("존재하지 않는 시나리오입니다"));

        List<StockPrice> priceList = stockPriceRepository
                .findByTickerAndTradeDateBetweenOrderByTradeDate(
                        scenario.getTicker(),
                        LocalDate.parse(scenario.getStartDate()),
                        LocalDate.parse(scenario.getEndDate())
                );

        if (priceList.size() < 100) {
            throw new IllegalStateException("주가 데이터가 부족합니다");
        }

        String sessionId = UUID.randomUUID().toString().substring(0, 8);
        GameSession session = new GameSession(
                sessionId, scenarioId, scenario.getTitle(),
                scenario.getTicker(), priceList.get(0).getTradeDate().toString()
        );
        sessionRepository.save(session);

        // 1라운드 데이터
        StockPrice first = priceList.get(0);
        Map<String, Object> priceData = new LinkedHashMap<>();
        priceData.put("ticker", first.getTicker());
        priceData.put("open", first.getOpen());
        priceData.put("close", first.getClose());
        priceData.put("high", first.getHigh());
        priceData.put("low", first.getLow());
        priceData.put("changeRate", 0.0);

        Map<String, Object> firstRound = new LinkedHashMap<>();
        firstRound.put("round", 1);
        firstRound.put("date", first.getTradeDate().toString());
        firstRound.put("priceData", List.of(priceData));

        Map<String, Object> response = new LinkedHashMap<>();
        response.put("sessionId", sessionId);
        response.put("scenarioTitle", scenario.getTitle());
        response.put("totalRounds", 100);
        response.put("initialAsset", 10_000_000L);
        response.put("cardSelectRounds", CARD_SELECT_ROUNDS);
        response.put("firstCardOptions", getRandomCards(new ArrayList<>()));
        response.put("rounds", List.of(firstRound));

        return response;
    }

    // =============================================
    // 카드 선택
    // =============================================
    public Map<String, Object> selectCard(
            String sessionId, Integer round, Integer cardId) {

        GameSession session = sessionRepository.findById(sessionId)
                .orElseThrow(() -> new IllegalArgumentException("존재하지 않는 세션입니다"));

        Card card = cardRepository.findById(cardId)
                .orElseThrow(() -> new IllegalArgumentException("존재하지 않는 카드입니다"));

        // 중복 카드 체크
        List<Integer> appliedCardIds = getAppliedCardIds(session);
        if (appliedCardIds.contains(cardId)) {
            throw new IllegalArgumentException("이미 선택한 카드입니다");
        }

        // 적용 카드 목록 업데이트
        appliedCardIds.add(cardId);
        String newAppliedCards = appliedCardIds.stream()
                .map(String::valueOf)
                .collect(Collectors.joining(","));

        // BUY_ONCE 즉시 매수 처리
        double spxShares = session.getSpxShares();
        double ndxShares = session.getNdxShares();
        double xauusdShares = session.getXauusdShares();
        double usoShares = session.getUsoShares();
        double aaplShares = session.getAaplShares();
        double tltShares = session.getTltShares();
        long cash = session.getCash();

        if ("BUY_ONCE".equals(card.getType())) {
            double currentClose = getPriceAtRound(session, round, card.getTicker());
            double buyAmount = cash * card.getRatio();
            cash -= (long) buyAmount;
            double newShares = buyAmount / currentClose;
            if ("^SPX".equals(card.getTicker()))      spxShares += newShares;
            else if ("^NDX".equals(card.getTicker()))  ndxShares += newShares;
            else if ("XAUUSD".equals(card.getTicker())) xauusdShares += newShares;
            else if ("USO".equals(card.getTicker()))   usoShares += newShares;
            else if ("AAPL".equals(card.getTicker()))  aaplShares += newShares;
            else if ("TLT".equals(card.getTicker()))   tltShares += newShares;
        }

        // 다음 증강 라운드
        Integer nextEventRound = CARD_SELECT_ROUNDS.stream()
                .filter(r -> r > round)
                .findFirst()
                .orElse(null);

        int endRound = nextEventRound != null ? nextEventRound - 1 : 100;

        // 라운드 계산
        Map<String, Object> calcResult = calculateRounds(
                session, round, endRound,
                cash, spxShares, ndxShares, xauusdShares,
                usoShares, aaplShares, tltShares,
                appliedCardIds, session.getTriggerCount()
        );

        List<Map<String, Object>> rounds = (List<Map<String, Object>>) calcResult.get("rounds");
        long finalCash = (long) calcResult.get("finalCash");
        double finalSpx = (double) calcResult.get("finalSpx");
        double finalNdx = (double) calcResult.get("finalNdx");
        double finalXauusd = (double) calcResult.get("finalXauusd");
        double finalUso = (double) calcResult.get("finalUso");
        double finalAapl = (double) calcResult.get("finalAapl");
        double finalTlt = (double) calcResult.get("finalTlt");
        String finalTriggerCount = (String) calcResult.get("triggerCount");

        // 세션 업데이트
        session.update(
                finalCash, finalSpx, finalNdx, finalXauusd,
                finalUso, finalAapl, finalTlt,
                endRound + 1, newAppliedCards, finalTriggerCount
        );
        sessionRepository.save(session);

        // 다음 카드 옵션
        List<Integer> nextCardOptions = nextEventRound != null
                ? getRandomCards(appliedCardIds)
                : null;

        Map<String, Object> response = new LinkedHashMap<>();
        response.put("selectedCard", card.getName());
        response.put("nextEventRound", nextEventRound);
        response.put("nextCardOptions", nextCardOptions);
        response.put("rounds", rounds);

        return response;
    }

    // =============================================
    // 라운드별 자산 계산
    // =============================================
    private Map<String, Object> calculateRounds(
            GameSession session, int startRound, int endRound,
            long cash, double spxShares, double ndxShares, double xauusdShares,
            double  usoShares, double aaplShares, double tltShares,
            List<Integer> appliedCardIds, String triggerCountStr) {

        // 주가 데이터 로드
        List<StockPrice> spxList = loadPriceList(session, "^SPX");
        List<StockPrice> ndxList = loadPriceList(session, "^NDX");
        List<StockPrice> xauusdList = loadPriceList(session, "XAUUSD");
        List<StockPrice> usoList = loadPriceList(session, "USO");
        List<StockPrice> aaplList = loadPriceList(session, "AAPL");
        List<StockPrice> tltList = loadPriceList(session, "TLT");


        // 적용된 카드 목록
        List<Card> appliedCards = cardRepository.findAllById(appliedCardIds);
        appliedCards.sort(Comparator.comparing(Card::getPriority));

        // 발동 횟수 파싱
        Map<Integer, Integer> triggerMap = parseTriggerCount(triggerCountStr);

        List<Map<String, Object>> rounds = new ArrayList<>();

        for (int i = startRound - 1; i < endRound; i++) {
            if (i >= spxList.size()) break;

            int roundNumber = i + 1;

            StockPrice spxCurrent = spxList.get(i);
            StockPrice spxPrev = i > 0 ? spxList.get(i - 1) : null;
            StockPrice ndxCurrent = i < ndxList.size() ? ndxList.get(i) : null;
            StockPrice ndxPrev = (i > 0 && i < ndxList.size()) ? ndxList.get(i - 1) : null;
            StockPrice xauusdCurrent = i < xauusdList.size() ? xauusdList.get(i) : null;
            StockPrice usoCurrent = i < usoList.size() ? usoList.get(i) : null;
            StockPrice usoPrev = (i > 0 && i < usoList.size()) ? usoList.get(i - 1) : null;
            StockPrice aaplCurrent = i < aaplList.size() ? aaplList.get(i) : null;
            StockPrice aaplPrev = (i > 0 && i < aaplList.size()) ? aaplList.get(i - 1) : null;
            StockPrice tltCurrent = i < tltList.size() ? tltList.get(i) : null;

            // 등락률 계산
            double spxChangeRate = calcChangeRate(spxPrev, spxCurrent);
            double ndxChangeRate = calcChangeRate(ndxPrev, ndxCurrent);
            double aaplChangeRate = calcChangeRate(aaplPrev, aaplCurrent);

            // 자산 계산 (파산 방지 체크용)
            double spxValue = spxShares * spxCurrent.getClose();
            double ndxValue = ndxCurrent != null ? ndxShares * ndxCurrent.getClose() : 0;
            double xauusdValue = xauusdCurrent != null ? xauusdShares * xauusdCurrent.getClose() : 0;
            double usoValue = usoCurrent != null ? usoShares * usoCurrent.getClose() : 0;
            double aaplValue = aaplCurrent != null ? aaplShares * aaplCurrent.getClose() : 0;
            double tltValue = tltCurrent != null ? tltShares * tltCurrent.getClose() : 0;
            long totalAsset = cash + (long) (spxValue + ndxValue + xauusdValue + usoValue + aaplValue + tltValue);

            List<Integer> triggeredCardIds = new ArrayList<>();

            if (totalAsset > session.getInitialAsset() * 0.01) { // 파산 방지 체크

                for (Card card : appliedCards) {
                    if ("BUY_ONCE".equals(card.getType())) continue;

                    boolean triggered = false;

                    if ("BUY_SPLIT".equals(card.getType())) {
                        triggered = true;
                    } else if ("BUY_ON_CONDITION".equals(card.getType())) {
                        triggered = checkCondition(card.getCondition(), spxChangeRate, ndxChangeRate, aaplChangeRate);
                    } else if ("SELL_ON_CONDITION".equals(card.getType())) {
                        triggered = checkCondition(card.getCondition(), spxChangeRate, ndxChangeRate, aaplChangeRate);
                    } else if ("BUY_EVERY_N".equals(card.getType())) {
                        triggered = (roundNumber % 5 == 0);
                    }

                    if (!triggered) continue;

                    // maxTrigger 체크
                    if (card.getMaxTrigger() != null) {
                        int count = triggerMap.getOrDefault(card.getId(), 0);
                        if (count >= card.getMaxTrigger()) continue;
                        triggerMap.put(card.getId(), count + 1);
                    }

                    // 매도 카드 처리 (SELL_ON_CONDITION)
                    if ("SELL_ON_CONDITION".equals(card.getType())) {
                        double sellShares = 0;
                        double sellPrice = 0;
                        if ("^SPX".equals(card.getTicker())) {
                            sellShares = spxShares * card.getRatio();
                            sellPrice = spxCurrent.getClose();
                            spxShares -= sellShares;
                        }
                        cash += (long) (sellShares * sellPrice);
                        triggeredCardIds.add(card.getId());
                        continue;
                    }

                    // 현금 부족 체크 (총자산의 5% 미만이면 매수 스킵)
                    if (cash < totalAsset * 0.05) continue;

                    // 매수 금액 계산 및 실행
                    double amount = cash * card.getRatio();
                    double price = getTickerPrice(card.getTicker(), spxCurrent, ndxCurrent, xauusdCurrent, usoCurrent, aaplCurrent, tltCurrent);
                    if (price <= 0) continue;

                    cash -= (long) amount;
                    double shares = amount / price;
                    if ("^SPX".equals(card.getTicker())) spxShares += shares;
                    else if ("^NDX".equals(card.getTicker())) ndxShares += shares;
                    else if ("XAUUSD".equals(card.getTicker())) xauusdShares += shares;
                    else if ("USO".equals(card.getTicker())) usoShares += shares;
                    else if ("AAPL".equals(card.getTicker())) aaplShares += shares;
                    else if ("TLT".equals(card.getTicker())) tltShares += shares;

                    triggeredCardIds.add(card.getId());
                }
            }

            // 자산 재계산
            spxValue = spxShares * spxCurrent.getClose();
            ndxValue = ndxCurrent != null ? ndxShares * ndxCurrent.getClose() : 0;
            xauusdValue = xauusdCurrent != null ? xauusdShares * xauusdCurrent.getClose() : 0;
            usoValue = usoCurrent != null ? usoShares * usoCurrent.getClose() : 0;
            aaplValue = aaplCurrent != null ? aaplShares * aaplCurrent.getClose() : 0;
            tltValue = tltCurrent != null ? tltShares * tltCurrent.getClose() : 0;
            long roundAsset = cash + (long) (spxValue + ndxValue + xauusdValue + usoValue + aaplValue + tltValue);
            double returnRate = (double) (roundAsset - session.getInitialAsset()) / session.getInitialAsset() * 100;

            // priceData 구성 (보유 종목만)
            List<Map<String, Object>> priceDataList = new ArrayList<>();

            Map<String, Object> spxData = new LinkedHashMap<>();
            spxData.put("ticker", "^SPX");
            spxData.put("open", spxCurrent.getOpen());
            spxData.put("close", spxCurrent.getClose());
            spxData.put("high", spxCurrent.getHigh());
            spxData.put("low", spxCurrent.getLow());
            spxData.put("changeRate", spxChangeRate);
            priceDataList.add(spxData);

            if (ndxShares > 0 && ndxCurrent != null) {
                Map<String, Object> ndxData = new LinkedHashMap<>();
                ndxData.put("ticker", "^NDX");
                ndxData.put("open", ndxCurrent.getOpen());
                ndxData.put("close", ndxCurrent.getClose());
                ndxData.put("high", ndxCurrent.getHigh());
                ndxData.put("low", ndxCurrent.getLow());
                ndxData.put("changeRate", ndxChangeRate);
                priceDataList.add(ndxData);
            }

            if (xauusdShares > 0 && xauusdCurrent != null) {
                double xauusdChangeRate = calcChangeRate(
                        i > 0 && i < xauusdList.size() ? xauusdList.get(i - 1) : null, xauusdCurrent);
                Map<String, Object> xauusdData = new LinkedHashMap<>();
                xauusdData.put("ticker", "XAUUSD");
                xauusdData.put("open", xauusdCurrent.getOpen());
                xauusdData.put("close", xauusdCurrent.getClose());
                xauusdData.put("high", xauusdCurrent.getHigh());
                xauusdData.put("low", xauusdCurrent.getLow());
                xauusdData.put("changeRate", xauusdChangeRate);
                priceDataList.add(xauusdData);
            }

            if (usoShares > 0 && usoCurrent != null) {
                double usoChangeRate = calcChangeRate(usoPrev, usoCurrent);
                Map<String, Object> usoData = new LinkedHashMap<>();
                usoData.put("ticker", "USO");
                usoData.put("open", usoCurrent.getOpen());
                usoData.put("close", usoCurrent.getClose());
                usoData.put("high", usoCurrent.getHigh());
                usoData.put("low", usoCurrent.getLow());
                usoData.put("changeRate", usoChangeRate);
                priceDataList.add(usoData);
            }

            if (aaplShares > 0 && aaplCurrent != null) {
                Map<String, Object> aaplData = new LinkedHashMap<>();
                aaplData.put("ticker", "AAPL");
                aaplData.put("open", aaplCurrent.getOpen());
                aaplData.put("close", aaplCurrent.getClose());
                aaplData.put("high", aaplCurrent.getHigh());
                aaplData.put("low", aaplCurrent.getLow());
                aaplData.put("changeRate", aaplChangeRate);
                priceDataList.add(aaplData);
            }

            if (tltShares > 0 && tltCurrent != null) {
                double tltChangeRate = calcChangeRate(
                        i > 0 && i < tltList.size() ? tltList.get(i - 1) : null, tltCurrent);
                Map<String, Object> tltData = new LinkedHashMap<>();
                tltData.put("ticker", "TLT");
                tltData.put("open", tltCurrent.getOpen());
                tltData.put("close", tltCurrent.getClose());
                tltData.put("high", tltCurrent.getHigh());
                tltData.put("low", tltCurrent.getLow());
                tltData.put("changeRate", tltChangeRate);
                priceDataList.add(tltData);
            }

            Map<String, Object> roundMap = new LinkedHashMap<>();
            roundMap.put("round", roundNumber);
            roundMap.put("date", spxCurrent.getTradeDate().toString());
            roundMap.put("priceData", priceDataList);
            roundMap.put("roundAsset", roundAsset);
            roundMap.put("returnRate", Math.round(returnRate * 100.0) / 100.0);
            roundMap.put("triggeredCards", triggeredCardIds);
            rounds.add(roundMap);
        }

// 결과 반환
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("rounds", rounds);
        result.put("finalCash", cash);
        result.put("finalSpx", spxShares);
        result.put("finalNdx", ndxShares);
        result.put("finalXauusd", xauusdShares);
        result.put("finalUso", usoShares);
        result.put("finalAapl", aaplShares);
        result.put("finalTlt", tltShares);
        result.put("triggerCount", serializeTriggerCount(triggerMap));
        return result;
    }

    // =============================================
    // 유틸 메서드
    // =============================================

    // 조건 체크
        private boolean checkCondition(String condition,
        double spxChangeRate, double ndxChangeRate, double aaplChangeRate) {
            return switch (condition) {
                case "SPX_CHANGE <= -3"  -> spxChangeRate  <= -3;
                case "SPX_CHANGE <= -5"  -> spxChangeRate  <= -5;
                case "SPX_CHANGE >= 3"   -> spxChangeRate  >= 3;
                case "NDX_CHANGE >= 2"   -> ndxChangeRate  >= 2;
                case "NDX_CHANGE <= -4"  -> ndxChangeRate  <= -4;
                case "AAPL_CHANGE <= -5" -> aaplChangeRate <= -5;
                default -> false;
            };
        }

    // 등락률 계산
    private double calcChangeRate(StockPrice prev, StockPrice current) {
        if (prev == null || current == null || prev.getClose() <= 0) return 0.0;
        double rate = (current.getClose() - prev.getClose()) / prev.getClose() * 100;
        return Math.round(rate * 100.0) / 100.0;
    }

    // ticker별 현재가 반환
    private double getTickerPrice(String ticker,
                                  StockPrice spx, StockPrice ndx, StockPrice xauusd,
                                  StockPrice uso, StockPrice aapl, StockPrice tlt) {
        return switch (ticker) {
            case "^SPX"   -> spx    != null ? spx.getClose()    : 0;
            case "^NDX"   -> ndx    != null ? ndx.getClose()    : 0;
            case "XAUUSD" -> xauusd != null ? xauusd.getClose() : 0;
            case "USO"    -> uso    != null ? uso.getClose()    : 0;
            case "AAPL"   -> aapl   != null ? aapl.getClose()   : 0;
            case "TLT"    -> tlt    != null ? tlt.getClose()    : 0;
            default -> 0;
        };
    }



    // 주가 데이터 로드
    private List<StockPrice> loadPriceList(GameSession session, String ticker) {
        return stockPriceRepository
                .findByTickerAndTradeDateGreaterThanEqualOrderByTradeDate(
                        ticker, LocalDate.parse(session.getGameStartDate())
                );
    }

    // 특정 라운드 종가 조회
    private double getPriceAtRound(GameSession session, int round, String ticker) {
        List<StockPrice> list = loadPriceList(session, ticker);
        if (round - 1 >= list.size()) return 0;
        return list.get(round - 1).getClose();
    }

    // 랜덤 카드 3개 뽑기 (이미 선택한 카드 제외)
    private List<Integer> getRandomCards(List<Integer> appliedCardIds) {
        List<Integer> available = new ArrayList<>(ALL_CARD_IDS);
        available.removeAll(appliedCardIds);
        Collections.shuffle(available);
        int count = Math.min(3, available.size());
        return new ArrayList<>(available.subList(0, count));
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

    // 발동 횟수 파싱 "6:2,3:1" → {6: 2, 3: 1}
    private Map<Integer, Integer> parseTriggerCount(String str) {
        Map<Integer, Integer> map = new HashMap<>();
        if (str == null || str.isEmpty()) return map;
        for (String entry : str.split(",")) {
            String[] parts = entry.split(":");
            if (parts.length == 2) {
                map.put(Integer.parseInt(parts[0]), Integer.parseInt(parts[1]));
            }
        }
        return map;
    }

    // 발동 횟수 직렬화 {6: 2, 3: 1} → "6:2,3:1"
    private String serializeTriggerCount(Map<Integer, Integer> map) {
        return map.entrySet().stream()
                .map(e -> e.getKey() + ":" + e.getValue())
                .collect(Collectors.joining(","));
    }
}