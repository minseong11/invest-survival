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
    private static final long INITIAL_ASSET = 10_000_000L;

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
        response.put("initialAsset", INITIAL_ASSET);
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

        List<Integer> appliedCardIds = getAppliedCardIds(session);
        if (appliedCardIds.contains(cardId)) {
            throw new IllegalArgumentException("이미 선택한 카드입니다");
        }

        appliedCardIds.add(cardId);
        String newAppliedCards = appliedCardIds.stream()
                .map(String::valueOf)
                .collect(Collectors.joining(","));

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

        Integer nextEventRound = CARD_SELECT_ROUNDS.stream()
                .filter(r -> r > round)
                .findFirst()
                .orElse(null);

        int endRound = nextEventRound != null ? nextEventRound - 1 : 100;

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

        session.update(
                finalCash, finalSpx, finalNdx, finalXauusd,
                finalUso, finalAapl, finalTlt,
                endRound + 1, newAppliedCards, finalTriggerCount
        );
        sessionRepository.save(session);

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
    // 검증용 게임 실행 (DB 저장 없이 start_date 직접 지정)
    // Python 결과와 1:1 비교용
    // =============================================
    public Map<String, Object> validateGame(String startDate, Map<Integer, Integer> cardSelections) {

        // 임시 세션 생성 (DB 저장 안 함)
        GameSession session = new GameSession(
                "validate", 1, "lehman", "^SPX", startDate
        );

        long cash = INITIAL_ASSET;
        double spxShares = 0, ndxShares = 0, xauusdShares = 0;
        double usoShares = 0, aaplShares = 0, tltShares = 0;
        List<Integer> appliedCardIds = new ArrayList<>();
        String triggerCount = "";

        List<Map<String, Object>> allRounds = new ArrayList<>();

        // 카드 선택 라운드 순서대로 처리
        List<Integer> sortedRounds = new ArrayList<>(cardSelections.keySet());
        Collections.sort(sortedRounds);

        for (int idx = 0; idx < sortedRounds.size(); idx++) {
            int selectRound = sortedRounds.get(idx);
            int cardId = cardSelections.get(selectRound);

            appliedCardIds.add(cardId);
            Card card = cardRepository.findById(cardId)
                    .orElseThrow(() -> new IllegalArgumentException("존재하지 않는 카드: " + cardId));

            // BUY_ONCE 즉시 매수
            if ("BUY_ONCE".equals(card.getType())) {
                double price = getPriceAtRound(session, selectRound, card.getTicker());
                if (price > 0) {
                    double buyAmount = cash * card.getRatio();
                    cash -= (long) buyAmount;
                    double shares = buyAmount / price;
                    if ("^SPX".equals(card.getTicker()))       spxShares    += shares;
                    else if ("^NDX".equals(card.getTicker()))   ndxShares    += shares;
                    else if ("XAUUSD".equals(card.getTicker())) xauusdShares += shares;
                    else if ("USO".equals(card.getTicker()))    usoShares    += shares;
                    else if ("AAPL".equals(card.getTicker()))   aaplShares   += shares;
                    else if ("TLT".equals(card.getTicker()))    tltShares    += shares;
                }
            }

            // 다음 선택 라운드 직전까지 계산
            int endRound = (idx + 1 < sortedRounds.size())
                    ? sortedRounds.get(idx + 1) - 1
                    : 100;

            Map<String, Object> calcResult = calculateRounds(
                    session, selectRound, endRound,
                    cash, spxShares, ndxShares, xauusdShares,
                    usoShares, aaplShares, tltShares,
                    new ArrayList<>(appliedCardIds), triggerCount
            );

            List<Map<String, Object>> segmentRounds = (List<Map<String, Object>>) calcResult.get("rounds");
            allRounds.addAll(segmentRounds);

            // 다음 구간을 위해 상태 업데이트
            cash         = (long)   calcResult.get("finalCash");
            spxShares    = (double) calcResult.get("finalSpx");
            ndxShares    = (double) calcResult.get("finalNdx");
            xauusdShares = (double) calcResult.get("finalXauusd");
            usoShares    = (double) calcResult.get("finalUso");
            aaplShares   = (double) calcResult.get("finalAapl");
            tltShares    = (double) calcResult.get("finalTlt");
            triggerCount = (String) calcResult.get("triggerCount");
        }

        Map<String, Object> lastRound = allRounds.isEmpty() ? new HashMap<>() : allRounds.get(allRounds.size() - 1);

        Map<String, Object> result = new LinkedHashMap<>();
        result.put("scenario", "lehman");
        result.put("start_date", startDate);
        result.put("card_selections", cardSelections);
        result.put("initial_asset", INITIAL_ASSET);
        result.put("rounds", allRounds);
        result.put("final_asset", lastRound.getOrDefault("roundAsset", INITIAL_ASSET));
        result.put("final_return_rate", lastRound.getOrDefault("returnRate", 0.0));
        return result;
    }

    // =============================================
    // 라운드별 자산 계산
    // =============================================
    private Map<String, Object> calculateRounds(
            GameSession session, int startRound, int endRound,
            long cash, double spxShares, double ndxShares, double xauusdShares,
            double usoShares, double aaplShares, double tltShares,
            List<Integer> appliedCardIds, String triggerCountStr) {

        List<StockPrice> spxList    = loadPriceList(session, "^SPX");
        List<StockPrice> ndxList    = loadPriceList(session, "^NDX");
        List<StockPrice> xauusdList = loadPriceList(session, "XAUUSD");
        List<StockPrice> usoList    = loadPriceList(session, "USO");
        List<StockPrice> aaplList   = loadPriceList(session, "AAPL");
        List<StockPrice> tltList    = loadPriceList(session, "TLT");

        List<Card> appliedCards = cardRepository.findAllById(appliedCardIds);
        appliedCards.sort(Comparator.comparing(Card::getPriority));

        Map<Integer, Integer> triggerMap = parseTriggerCount(triggerCountStr);
        List<Map<String, Object>> rounds = new ArrayList<>();

        for (int i = startRound - 1; i < endRound; i++) {
            if (i >= spxList.size()) break;

            int roundNumber = i + 1;

            StockPrice spxCurrent   = spxList.get(i);
            StockPrice spxPrev      = i > 0 ? spxList.get(i - 1) : null;
            StockPrice ndxCurrent   = i < ndxList.size()    ? ndxList.get(i)    : null;
            StockPrice ndxPrev      = (i > 0 && i < ndxList.size()) ? ndxList.get(i - 1) : null;
            StockPrice xauusdCurrent= i < xauusdList.size() ? xauusdList.get(i) : null;
            StockPrice usoCurrent   = i < usoList.size()    ? usoList.get(i)    : null;
            StockPrice usoPrev      = (i > 0 && i < usoList.size())  ? usoList.get(i - 1)  : null;
            StockPrice aaplCurrent  = i < aaplList.size()   ? aaplList.get(i)   : null;
            StockPrice aaplPrev     = (i > 0 && i < aaplList.size()) ? aaplList.get(i - 1) : null;
            StockPrice tltCurrent   = i < tltList.size()    ? tltList.get(i)    : null;

            double spxChangeRate  = calcChangeRate(spxPrev, spxCurrent);
            double ndxChangeRate  = calcChangeRate(ndxPrev, ndxCurrent);
            double aaplChangeRate = calcChangeRate(aaplPrev, aaplCurrent);

            double spxValue    = spxShares    * spxCurrent.getClose();
            double ndxValue    = ndxCurrent    != null ? ndxShares    * ndxCurrent.getClose()    : 0;
            double xauusdValue = xauusdCurrent != null ? xauusdShares * xauusdCurrent.getClose() : 0;
            double usoValue    = usoCurrent    != null ? usoShares    * usoCurrent.getClose()    : 0;
            double aaplValue   = aaplCurrent   != null ? aaplShares   * aaplCurrent.getClose()   : 0;
            double tltValue    = tltCurrent    != null ? tltShares    * tltCurrent.getClose()    : 0;
            long totalAsset = cash + (long)(spxValue + ndxValue + xauusdValue + usoValue + aaplValue + tltValue);

            List<Integer> triggeredCardIds = new ArrayList<>();

            if (totalAsset > session.getInitialAsset() * 0.01) {
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

                    if (card.getMaxTrigger() != null) {
                        int count = triggerMap.getOrDefault(card.getId(), 0);
                        if (count >= card.getMaxTrigger()) continue;
                        triggerMap.put(card.getId(), count + 1);
                    }

                    if ("SELL_ON_CONDITION".equals(card.getType())) {
                        if ("^SPX".equals(card.getTicker())) {
                            double sellShares = spxShares * card.getRatio();
                            cash += (long)(sellShares * spxCurrent.getClose());
                            spxShares -= sellShares;
                        }
                        triggeredCardIds.add(card.getId());
                        continue;
                    }

                    if (cash < totalAsset * 0.05) continue;

                    double amount = cash * card.getRatio();
                    double price  = getTickerPrice(card.getTicker(), spxCurrent, ndxCurrent, xauusdCurrent, usoCurrent, aaplCurrent, tltCurrent);
                    if (price <= 0) continue;

                    cash -= (long) amount;
                    double shares = amount / price;
                    if ("^SPX".equals(card.getTicker()))       spxShares    += shares;
                    else if ("^NDX".equals(card.getTicker()))   ndxShares    += shares;
                    else if ("XAUUSD".equals(card.getTicker())) xauusdShares += shares;
                    else if ("USO".equals(card.getTicker()))    usoShares    += shares;
                    else if ("AAPL".equals(card.getTicker()))   aaplShares   += shares;
                    else if ("TLT".equals(card.getTicker()))    tltShares    += shares;

                    triggeredCardIds.add(card.getId());
                }
            }

            spxValue    = spxShares    * spxCurrent.getClose();
            ndxValue    = ndxCurrent    != null ? ndxShares    * ndxCurrent.getClose()    : 0;
            xauusdValue = xauusdCurrent != null ? xauusdShares * xauusdCurrent.getClose() : 0;
            usoValue    = usoCurrent    != null ? usoShares    * usoCurrent.getClose()    : 0;
            aaplValue   = aaplCurrent   != null ? aaplShares   * aaplCurrent.getClose()   : 0;
            tltValue    = tltCurrent    != null ? tltShares    * tltCurrent.getClose()    : 0;
            long roundAsset = cash + (long)(spxValue + ndxValue + xauusdValue + usoValue + aaplValue + tltValue);
            double returnRate = (double)(roundAsset - session.getInitialAsset()) / session.getInitialAsset() * 100;

            List<Map<String, Object>> priceDataList = new ArrayList<>();
            Map<String, Object> spxData = new LinkedHashMap<>();
            spxData.put("ticker", "^SPX"); spxData.put("open", spxCurrent.getOpen());
            spxData.put("close", spxCurrent.getClose()); spxData.put("high", spxCurrent.getHigh());
            spxData.put("low", spxCurrent.getLow()); spxData.put("changeRate", spxChangeRate);
            priceDataList.add(spxData);

            if (ndxShares > 0 && ndxCurrent != null) {
                Map<String, Object> ndxData = new LinkedHashMap<>();
                ndxData.put("ticker", "^NDX"); ndxData.put("open", ndxCurrent.getOpen());
                ndxData.put("close", ndxCurrent.getClose()); ndxData.put("high", ndxCurrent.getHigh());
                ndxData.put("low", ndxCurrent.getLow()); ndxData.put("changeRate", ndxChangeRate);
                priceDataList.add(ndxData);
            }
            if (xauusdShares > 0 && xauusdCurrent != null) {
                double xauusdChangeRate = calcChangeRate(i > 0 && i < xauusdList.size() ? xauusdList.get(i-1) : null, xauusdCurrent);
                Map<String, Object> xauusdData = new LinkedHashMap<>();
                xauusdData.put("ticker", "XAUUSD"); xauusdData.put("open", xauusdCurrent.getOpen());
                xauusdData.put("close", xauusdCurrent.getClose()); xauusdData.put("high", xauusdCurrent.getHigh());
                xauusdData.put("low", xauusdCurrent.getLow()); xauusdData.put("changeRate", xauusdChangeRate);
                priceDataList.add(xauusdData);
            }
            if (usoShares > 0 && usoCurrent != null) {
                double usoChangeRate = calcChangeRate(usoPrev, usoCurrent);
                Map<String, Object> usoData = new LinkedHashMap<>();
                usoData.put("ticker", "USO"); usoData.put("open", usoCurrent.getOpen());
                usoData.put("close", usoCurrent.getClose()); usoData.put("high", usoCurrent.getHigh());
                usoData.put("low", usoCurrent.getLow()); usoData.put("changeRate", usoChangeRate);
                priceDataList.add(usoData);
            }
            if (aaplShares > 0 && aaplCurrent != null) {
                Map<String, Object> aaplData = new LinkedHashMap<>();
                aaplData.put("ticker", "AAPL"); aaplData.put("open", aaplCurrent.getOpen());
                aaplData.put("close", aaplCurrent.getClose()); aaplData.put("high", aaplCurrent.getHigh());
                aaplData.put("low", aaplCurrent.getLow()); aaplData.put("changeRate", aaplChangeRate);
                priceDataList.add(aaplData);
            }
            if (tltShares > 0 && tltCurrent != null) {
                double tltChangeRate = calcChangeRate(i > 0 && i < tltList.size() ? tltList.get(i-1) : null, tltCurrent);
                Map<String, Object> tltData = new LinkedHashMap<>();
                tltData.put("ticker", "TLT"); tltData.put("open", tltCurrent.getOpen());
                tltData.put("close", tltCurrent.getClose()); tltData.put("high", tltCurrent.getHigh());
                tltData.put("low", tltCurrent.getLow()); tltData.put("changeRate", tltChangeRate);
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

    private double calcChangeRate(StockPrice prev, StockPrice current) {
        if (prev == null || current == null || prev.getClose() <= 0) return 0.0;
        double rate = (current.getClose() - prev.getClose()) / prev.getClose() * 100;
        return Math.round(rate * 100.0) / 100.0;
    }

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

    private List<StockPrice> loadPriceList(GameSession session, String ticker) {
        return stockPriceRepository
                .findByTickerAndTradeDateGreaterThanEqualOrderByTradeDate(
                        ticker, LocalDate.parse(session.getGameStartDate())
                );
    }

    private double getPriceAtRound(GameSession session, int round, String ticker) {
        List<StockPrice> list = loadPriceList(session, ticker);
        if (round - 1 >= list.size()) return 0;
        return list.get(round - 1).getClose();
    }

    private List<Integer> getRandomCards(List<Integer> appliedCardIds) {
        List<Integer> available = new ArrayList<>(ALL_CARD_IDS);
        available.removeAll(appliedCardIds);
        Collections.shuffle(available);
        int count = Math.min(3, available.size());
        return new ArrayList<>(available.subList(0, count));
    }

    private List<Integer> getAppliedCardIds(GameSession session) {
        if (session.getAppliedCards() == null || session.getAppliedCards().isEmpty()) {
            return new ArrayList<>();
        }
        return Arrays.stream(session.getAppliedCards().split(","))
                .map(Integer::parseInt)
                .collect(Collectors.toList());
    }

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

    private String serializeTriggerCount(Map<Integer, Integer> map) {
        return map.entrySet().stream()
                .map(e -> e.getKey() + ":" + e.getValue())
                .collect(Collectors.joining(","));
    }
}
