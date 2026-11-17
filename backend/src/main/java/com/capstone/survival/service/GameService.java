package com.capstone.survival.service;

import com.capstone.survival.entity.Card;
import com.capstone.survival.entity.GameSession;
import com.capstone.survival.entity.NewsEvent;
import com.capstone.survival.entity.Scenario;
import com.capstone.survival.entity.StockPrice;
import com.capstone.survival.exception.AiServerException;
import com.capstone.survival.repository.CardRepository;
import com.capstone.survival.repository.GameSessionRepository;
import com.capstone.survival.repository.NewsEventRepository;
import com.capstone.survival.repository.ScenarioRepository;
import com.capstone.survival.repository.StockPriceRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.*;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;

import java.time.LocalDate;
import java.util.*;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.Executor;
import java.util.concurrent.ForkJoinPool;
import java.util.stream.Collectors;

/**
 * 게임 진행·계산
 *
 * 게임은 "이벤트 라운드"에서 멈추고 플레이어의 선택을 받는다.
 *   - 카드 선택 라운드: 1·25·50·75 (후보 3장 중 1장)
 *   - (#125) 위기 대응 라운드: 뉴스 속보(news_event.decision = true)가 나온 라운드 (버틴다 / 절반 판다 / 더 산다)
 * 선택을 받으면 그 라운드부터 다음 이벤트 라운드 직전까지 한 번에 계산해 응답한다.
 *
 * 계산 규칙은 backend/python_simulation/game_logic.py의 run_game()과 연산 순서·버림까지 같다.
 * (사후 분석·학습 데이터가 Python으로 계산되므로, 두 계산이 원 단위까지 같아야 한다 — compare_java_python.py로 확인)
 * 계산 규칙을 바꿀 때는 두 파일을 함께 고친다.
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class GameService {

    private final GameSessionRepository sessionRepository;
    private final ScenarioRepository scenarioRepository;
    private final StockPriceRepository stockPriceRepository;
    private final CardRepository cardRepository;
    private final NewsEventRepository newsEventRepository;
    private final RestTemplate restTemplate;

    @Value("${ai.server.url:http://localhost:8000}")
    private String aiServerUrl;

    // (#125) 전체 조합 미리 계산 요청(prewarmAnalysis)을 보내는 곳 — 게임 응답이 기다리지 않도록 다른 스레드에서 보낸다.
    //        테스트에서는 바로 실행하는 실행기로 바꿔, 이 요청이 테스트의 가짜 AI 서버 설정과 동시에 일어나지 않게 한다
    private Executor prewarmExecutor = ForkJoinPool.commonPool();

    private static final List<Integer> CARD_SELECT_ROUNDS = List.of(1, 25, 50, 75);
    private static final List<Integer> AI_ROUNDS = List.of(25, 50);      // V2 예측을 제공하는 라운드
    private static final List<Integer> ALL_CARD_IDS = List.of(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11);
    private static final long INITIAL_ASSET = 10_000_000L;
    private static final int TOTAL_ROUNDS = 100;
    private static final int BRIEFING_DAYS = 20;                          // 시작 전 브리핑에 쓰는 거래일 수

    // (11주차) 보유 종목 표시용 — 순서 = 응답 holdings 순서 = 평가액을 더하는 순서
    private static final List<String> TICKERS = List.of("^SPX", "^NDX", "XAUUSD", "USO", "AAPL", "TLT");
    private static final Map<String, String> TICKER_NAMES = Map.of(
            "^SPX", "S&P500",
            "^NDX", "나스닥100",
            "XAUUSD", "금",
            "USO", "원유",
            "AAPL", "애플",
            "TLT", "미국 장기채"
    );

    private static final String EVENT_CARD = "CARD";
    private static final String EVENT_DECISION = "DECISION";

    // (#125) 위기 대응 선택 — game_logic.py와 같은 이름·비율
    private static final String DECISION_HOLD = "HOLD";             // 아무것도 하지 않음
    private static final String DECISION_SELL_HALF = "SELL_HALF";   // 보유 종목을 각각 절반씩 매도
    private static final String DECISION_BUY_MORE = "BUY_MORE";     // 현금의 30%로 시나리오 기준 지수 매수
    private static final List<String> DECISION_CHOICES = List.of(DECISION_HOLD, DECISION_SELL_HALF, DECISION_BUY_MORE);
    private static final double SELL_HALF_RATIO = 0.5;
    private static final double BUY_MORE_RATIO = 0.3;

    // (#125) 카드가 발동 조건은 맞았지만 실행되지 못한 이유
    private static final String SKIP_CASH_LOW = "CASH_LOW";         // 현금이 총자산의 5% 미만
    private static final String SKIP_MAX_REACHED = "MAX_REACHED";   // 최대 발동 횟수를 다 씀
    private static final String SKIP_NO_HOLDINGS = "NO_HOLDINGS";   // 매도 카드인데 팔 주식이 없음
    private static final String SKIP_NO_PRICE = "NO_PRICE";         // 그날 가격이 없음

    // =============================================
    // 계산용 자료 구조
    // =============================================

    /** 게임 100라운드의 가격표 — i번째(0부터) = (i+1)라운드 = S&P500의 i번째 거래일. 상장 전이면 null */
    private static class PriceTable {
        final List<StockPrice> spx;
        final Map<String, List<StockPrice>> byTicker;

        PriceTable(List<StockPrice> spx, Map<String, List<StockPrice>> byTicker) {
            this.spx = spx;
            this.byTicker = byTicker;
        }

        StockPrice at(String ticker, int index) {
            List<StockPrice> list = byTicker.get(ticker);
            if (list == null || index < 0 || index >= list.size()) return null;
            return list.get(index);
        }

        double closeAt(String ticker, int index) {
            StockPrice p = at(ticker, index);
            return p != null ? p.getClose() : 0;
        }
    }

    /** 계산 중인 포트폴리오 — 매매할 때마다 직접 바뀐다. 현금은 원 단위 정수(매매 금액의 소수점 아래는 버림) */
    private static class Portfolio {
        long cash;
        final Map<String, Double> shares = new LinkedHashMap<>();
        final Map<String, Double> costs = new LinkedHashMap<>();        // 종목별 원가 (평균 단가 = 원가 ÷ 수량)
        final Map<Integer, Integer> triggerCounts = new HashMap<>();    // 최대 횟수가 있는 카드의 발동 횟수

        Portfolio(long cash) {
            this.cash = cash;
            for (String t : TICKERS) {
                shares.put(t, 0.0);
                costs.put(t, 0.0);
            }
        }

        double shares(String ticker) {
            return shares.getOrDefault(ticker, 0.0);
        }

        // amount(원)만큼 매수. 현금은 소수점 아래를 버린 금액만 줄어든다
        void buy(String ticker, double amount, double price) {
            cash -= (long) amount;
            shares.merge(ticker, amount / price, Double::sum);
            costs.merge(ticker, amount, Double::sum);
        }

        // 보유 수량의 ratio만큼 매도 → 받은 금액(원). 원가도 같은 비율만큼 줄어 평균 단가는 그대로
        long sell(String ticker, double ratio, double price) {
            double sellShares = shares(ticker) * ratio;
            long proceeds = (long) (sellShares * price);
            cash += proceeds;
            shares.put(ticker, shares(ticker) - sellShares);
            costs.put(ticker, costs.getOrDefault(ticker, 0.0) * (1 - ratio));
            return proceeds;
        }
    }

    /** 시나리오 뉴스를 라운드에 배치한 결과 */
    private static class NewsPlan {
        final Map<Integer, List<Map<String, Object>>> byRound = new HashMap<>();   // 라운드 → 그날 뉴스
        final TreeMap<Integer, Map<String, Object>> decisions = new TreeMap<>();   // 위기 대응 라운드 → 그 뉴스
    }

    // =============================================
    // 게임 시작
    // =============================================
    public Map<String, Object> startGame(Integer scenarioId) {
        if (scenarioId == null) {
            throw new IllegalArgumentException("scenarioId가 필요합니다");
        }
        Scenario scenario = scenarioRepository.findById(scenarioId)
                .orElseThrow(() -> new IllegalArgumentException("존재하지 않는 시나리오입니다"));

        List<StockPrice> priceList = stockPriceRepository
                .findByTickerAndTradeDateBetweenOrderByTradeDate(
                        scenario.getTicker(),
                        LocalDate.parse(scenario.getStartDate()),
                        LocalDate.parse(scenario.getEndDate())
                );

        if (priceList.size() < TOTAL_ROUNDS) {
            throw new IllegalStateException("주가 데이터가 부족합니다");
        }

        String sessionId = UUID.randomUUID().toString().substring(0, 8);
        GameSession session = new GameSession(
                sessionId, scenarioId, scenario.getTitle(),
                scenario.getTicker(), priceList.get(0).getTradeDate().toString()
        );

        // 라운드 기준 날짜는 시나리오 기준 종목과 관계없이 S&P500 거래일
        // (2라운드 이후 계산과 같은 기준 — 닷컴(^NDX)에서 차트 첫 점이 빠지던 문제 수정)
        PriceTable prices = loadPrices(session.getGameStartDate());
        if (prices.spx.isEmpty()) {
            throw new IllegalStateException("주가 데이터가 부족합니다 (S&P500)");
        }
        NewsPlan news = loadNews(scenarioId, prices.spx);

        // 1라운드 후보를 만들고 세션에 저장 (카드 선택 시 검증 + 사후 분석에 사용)
        List<Integer> firstCardOptions = getRandomCards(new ArrayList<>(), getUnavailableCardIds(prices));
        recordOfferedCards(session, 1, firstCardOptions);
        sessionRepository.save(session);

        StockPrice first = prices.spx.get(0);
        // (#125) 1라운드 가격: 그날 가격이 있는 모든 종목 (기존: S&P500만)
        List<Map<String, Object>> firstPrices = new ArrayList<>();
        for (String ticker : TICKERS) {
            StockPrice p = "^SPX".equals(ticker) ? first : prices.at(ticker, 0);
            if (p != null) firstPrices.add(priceEntry(ticker, p, 0.0));
        }

        Map<String, Object> firstRound = new LinkedHashMap<>();
        firstRound.put("round", 1);
        firstRound.put("date", first.getTradeDate().toString());
        firstRound.put("priceData", firstPrices);
        firstRound.put("holdings", new ArrayList<>());   // 시작 시 보유 종목 없음
        firstRound.put("cash", INITIAL_ASSET);
        firstRound.put("cashWeight", 100.0);
        firstRound.put("news", news.byRound.getOrDefault(1, new ArrayList<>()));

        Map<String, Object> response = new LinkedHashMap<>();
        response.put("sessionId", sessionId);
        response.put("scenarioTitle", scenario.getTitle());
        response.put("totalRounds", TOTAL_ROUNDS);
        response.put("initialAsset", INITIAL_ASSET);
        response.put("cardSelectRounds", CARD_SELECT_ROUNDS);
        response.put("firstCardOptions", firstCardOptions);
        // (#125) 위기 대응 라운드(자동 진행이 멈추는 곳), '더 산다'에서 사는 지수 이름, 시작 전 브리핑
        response.put("decisionRounds", new ArrayList<>(news.decisions.keySet()));
        response.put("buyMoreTarget", TICKER_NAMES.get(baseTicker(session)));
        response.put("briefing", buildBriefing(scenario, prices.spx));
        response.put("rounds", List.of(firstRound));

        return response;
    }

    // =============================================
    // (#125) 시작 전 브리핑 — 게임 시작일 직전 20거래일의 종목별 등락 + 시나리오 배경
    //   1라운드는 게임 중 시장 흐름이 없어 가장 영향이 큰 첫 선택을 정보 없이 해야 했다.
    //   게임 시작 전의 정보만 쓰므로 게임 중에 알 수 없는 내용은 들어가지 않는다.
    // =============================================
    private Map<String, Object> buildBriefing(Scenario scenario, List<StockPrice> spxList) {
        LocalDate firstDate = spxList.get(0).getTradeDate();
        List<StockPrice> before = new ArrayList<>(stockPriceRepository
                .findTop21ByTickerAndTradeDateLessThanOrderByTradeDateDesc("^SPX", firstDate));
        Collections.reverse(before);   // 오래된 날짜 → 최근 날짜

        Map<String, Object> briefing = new LinkedHashMap<>();
        briefing.put("intro", scenario.getIntro() != null ? scenario.getIntro() : "");
        if (before.size() < 2) {       // 시작 전 데이터가 없으면 배경 설명만
            briefing.put("days", 0);
            briefing.put("assets", new ArrayList<>());
            briefing.put("spxSeries", new ArrayList<>());
            return briefing;
        }

        LocalDate from = before.get(0).getTradeDate();
        LocalDate to = before.get(before.size() - 1).getTradeDate();

        List<Map<String, Object>> assets = new ArrayList<>();
        for (String ticker : TICKERS) {
            Optional<StockPrice> start = stockPriceRepository
                    .findTopByTickerAndTradeDateLessThanEqualOrderByTradeDateDesc(ticker, from);
            Optional<StockPrice> end = stockPriceRepository
                    .findTopByTickerAndTradeDateLessThanEqualOrderByTradeDateDesc(ticker, to);
            if (start.isEmpty() || end.isEmpty() || start.get().getClose() <= 0) continue;   // 상장 전 종목은 생략
            double rate = (end.get().getClose() - start.get().getClose()) / start.get().getClose() * 100;
            Map<String, Object> a = new LinkedHashMap<>();
            a.put("ticker", ticker);
            a.put("name", TICKER_NAMES.getOrDefault(ticker, ticker));
            a.put("changeRate", round2(rate));
            assets.add(a);
        }

        List<Map<String, Object>> series = new ArrayList<>();
        for (StockPrice p : before) {
            Map<String, Object> point = new LinkedHashMap<>();
            point.put("date", p.getTradeDate().toString());
            point.put("close", p.getClose());
            series.add(point);
        }

        briefing.put("days", before.size() - 1);
        briefing.put("fromDate", from.toString());
        briefing.put("toDate", to.toString());
        briefing.put("assets", assets);
        briefing.put("spxSeries", series);
        return briefing;
    }

    // =============================================
    // V1.5 사전 추천
    // =============================================
    public Map<String, Object> recommendV1(String sessionId) {
        GameSession session = findSession(sessionId);

        // 100라운드 전체 SPX 지표 계산
        Map<String, Double> indicators = marketIndicators(loadPrices(session.getGameStartDate()), TOTAL_ROUNDS);

        // Python FastAPI 호출
        Map<String, Object> requestBody = new LinkedHashMap<>();
        requestBody.put("spxReturn", indicators.get("spxReturn"));
        requestBody.put("spxVolatility", indicators.get("spxVolatility"));
        requestBody.put("spxMdd", indicators.get("spxMdd"));

        Map<String, Object> body = postToAi("/ai/v1/recommend", requestBody);

        @SuppressWarnings("unchecked")
        List<Map<String, Object>> rawRecommendations = (List<Map<String, Object>>) body.get("recommendations");

        // cardName 추가
        Map<Integer, Card> cards = cardMap();
        List<Map<String, Object>> recommendations = new ArrayList<>();
        for (Map<String, Object> item : rawRecommendations) {
            Map<String, Object> enriched = new LinkedHashMap<>(item);
            Card card = cards.get(((Number) item.get("cardId")).intValue());
            if (card != null) enriched.put("cardName", card.getName());
            recommendations.add(enriched);
        }

        Map<String, Object> result = new LinkedHashMap<>();
        result.put("recommendations", recommendations);
        return result;
    }

    // =============================================
    // V2 실시간 추천 (+ LLM 피드백)
    // =============================================
    public Map<String, Object> recommendV2(String sessionId, Integer currentRound,
                                           List<Integer> alreadyCards,
                                           List<Integer> candidateCards) {
        GameSession session = findSession(sessionId);

        // (#125) 지원하지 않는 라운드는 AI 서버까지 가지 않고 400으로 응답 (기존에는 75라운드 요청이 500)
        if (currentRound == null || !AI_ROUNDS.contains(currentRound)) {
            throw new IllegalArgumentException(
                    "AI 예측은 25·50라운드에서만 제공돼요 (요청: " + currentRound + "라운드)");
        }
        if (!currentRound.equals(session.getCurrentRound())) {
            throw new IllegalArgumentException(
                    "지금은 " + session.getCurrentRound() + "라운드예요 (요청: " + currentRound + "라운드)");
        }

        // (#125) 보유 카드·후보 카드는 서버에 기록된 값을 쓴다 (앱이 보낸 목록은 기록이 없을 때만 사용)
        List<Integer> applied = getAppliedCardIds(session);
        List<Integer> offered = parseOfferedCards(session.getOfferedCards()).get(currentRound);
        if (offered != null && !offered.isEmpty()) {
            alreadyCards = applied;
            candidateCards = offered;
        }
        if (candidateCards == null || candidateCards.isEmpty()) {
            throw new IllegalArgumentException("후보 카드가 없습니다");
        }
        if (alreadyCards == null) {
            alreadyCards = new ArrayList<>();
        }

        // 현재 라운드까지 so_far 지표 계산
        Map<String, Double> indicators = marketIndicators(loadPrices(session.getGameStartDate()), currentRound);

        // Python FastAPI 호출
        Map<String, Object> requestBody = new LinkedHashMap<>();
        requestBody.put("spxReturnSoFar", indicators.get("spxReturn"));
        requestBody.put("spxVolatilitySoFar", indicators.get("spxVolatility"));
        requestBody.put("spxMddSoFar", indicators.get("spxMdd"));
        requestBody.put("currentRound", currentRound);
        requestBody.put("alreadyCards", alreadyCards);
        requestBody.put("candidateCards", candidateCards);
        requestBody.put("startDate", session.getGameStartDate()); // 모델 A/B 선택용 (v7.0)

        Map<String, Object> body = postToAi("/ai/v2/recommend", requestBody);

        Integer recommendedCardId = ((Number) body.get("recommendedCardId")).intValue();
        @SuppressWarnings("unchecked")
        List<Map<String, Object>> rawRankings = (List<Map<String, Object>>) body.get("rankings");
        Object mv = body.get("modelVersion");
        String modelVersion = mv != null ? mv.toString() : "";

        // rankings에 cardName 추가
        Map<Integer, Card> cards = cardMap();
        List<Map<String, Object>> rankings = new ArrayList<>();
        for (Map<String, Object> item : rawRankings) {
            Map<String, Object> enriched = new LinkedHashMap<>(item);
            Card card = cards.get(((Number) item.get("cardId")).intValue());
            if (card != null) enriched.put("cardName", card.getName());
            rankings.add(enriched);
        }

        // LLM 자연어 피드백 (실패해도 추천은 정상 반환)
        String feedback = requestV2Feedback(indicators, currentRound, alreadyCards, rawRankings);

        Card recommended = cards.get(recommendedCardId);
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("recommendedCardId", recommendedCardId);
        result.put("recommendedCardName", recommended != null ? recommended.getName() : "");
        result.put("rankings", rankings);
        result.put("feedback", feedback);
        result.put("modelVersion", modelVersion);
        return result;
    }

    // =============================================
    // LLM 피드백 요청 — 실패 시 빈 문자열 반환
    // =============================================
    private String requestV2Feedback(Map<String, Double> indicators, Integer currentRound,
                                     List<Integer> alreadyCards,
                                     List<Map<String, Object>> rawRankings) {
        try {
            Map<String, Object> body = new LinkedHashMap<>();
            body.put("spxReturnSoFar", indicators.get("spxReturn"));
            body.put("spxVolatilitySoFar", indicators.get("spxVolatility"));
            body.put("spxMddSoFar", indicators.get("spxMdd"));
            body.put("currentRound", currentRound);
            body.put("alreadyCards", alreadyCards);
            body.put("rankings", rawRankings);

            Object value = postToAi("/ai/v2/feedback", body).get("feedback");
            return value != null ? value.toString() : "";

        } catch (Exception e) {
            // 타임아웃·서버오류 등 어떤 이유로든 실패하면 게임 진행 막지 않고 빈 문자열
            return "";
        }
    }

    // =============================================
    // 시장 지표 계산 — 1라운드부터 rounds라운드까지의 S&P500
    //   V1.5는 100라운드 전체, V2는 현재 라운드까지(so_far)
    // =============================================
    private Map<String, Double> marketIndicators(PriceTable prices, int rounds) {
        int size = Math.min(rounds, prices.spx.size());
        if (size < 2) {
            Map<String, Double> empty = new LinkedHashMap<>();
            empty.put("spxReturn", 0.0);
            empty.put("spxVolatility", 0.0);
            empty.put("spxMdd", 0.0);
            return empty;
        }

        double[] closes = prices.spx.subList(0, size).stream()
                .mapToDouble(StockPrice::getClose)
                .toArray();

        return calcIndicators(closes);
    }

    // =============================================
    // 지표 계산 공통 로직
    // =============================================
    private Map<String, Double> calcIndicators(double[] closes) {
        // 수익률
        double spxReturn = (closes[closes.length - 1] - closes[0]) / closes[0] * 100;

        // 변동성 (일별 수익률 표준편차)
        double[] dailyReturns = new double[closes.length - 1];
        for (int i = 0; i < dailyReturns.length; i++) {
            dailyReturns[i] = (closes[i + 1] - closes[i]) / closes[i] * 100;
        }
        double mean = Arrays.stream(dailyReturns).average().orElse(0);
        double variance = Arrays.stream(dailyReturns)
                .map(r -> Math.pow(r - mean, 2))
                .average().orElse(0);
        double spxVolatility = Math.sqrt(variance);

        // MDD (최대낙폭률)
        double maxClose = closes[0];
        double mdd = 0.0;
        for (double close : closes) {
            if (close > maxClose) maxClose = close;
            double drawdown = (close - maxClose) / maxClose * 100;
            if (drawdown < mdd) mdd = drawdown;
        }

        Map<String, Double> result = new LinkedHashMap<>();
        result.put("spxReturn", Math.round(spxReturn * 10000.0) / 10000.0);
        result.put("spxVolatility", Math.round(spxVolatility * 10000.0) / 10000.0);
        result.put("spxMdd", Math.round(mdd * 10000.0) / 10000.0);
        return result;
    }

    // =============================================
    // 카드 선택
    // =============================================
    public Map<String, Object> selectCard(String sessionId, Integer round, Integer cardId) {

        GameSession session = findPlayingSession(sessionId);
        if (cardId == null) {
            throw new IllegalArgumentException("cardId가 필요합니다");
        }

        // (11주차) 지금 카드를 고를 차례인 라운드인지 확인 (같은 라운드 재선택·라운드 건너뛰기 방지)
        if (round == null || !round.equals(session.getCurrentRound())) {
            throw new IllegalArgumentException(
                    "지금은 " + session.getCurrentRound() + "라운드 카드를 고를 차례입니다 (요청: " + round + "라운드)");
        }
        // (#125) 위기 대응 라운드에는 카드를 고를 수 없음
        if (!CARD_SELECT_ROUNDS.contains(round)) {
            throw new IllegalArgumentException(round + "라운드는 카드 선택 라운드가 아닙니다 (위기 대응을 선택해 주세요)");
        }

        Map<Integer, Card> cards = cardMap();
        Card card = cards.get(cardId);
        if (card == null) {
            throw new IllegalArgumentException("존재하지 않는 카드입니다");
        }

        PriceTable prices = loadPrices(session.getGameStartDate());
        Set<Integer> unavailableCardIds = getUnavailableCardIds(prices);
        if (unavailableCardIds.contains(cardId)) {
            throw new IllegalArgumentException("이 시나리오에서는 사용할 수 없는 카드입니다 (상장 전 종목)");
        }

        List<Integer> appliedCardIds = getAppliedCardIds(session);
        if (appliedCardIds.contains(cardId)) {
            throw new IllegalArgumentException("이미 선택한 카드입니다");
        }

        // (11주차) 이 라운드에 제시한 후보 3장 중 하나인지 확인
        // 후보 기록이 아예 없는 세션(이 기능 배포 전에 시작한 게임)은 검사하지 않음
        Map<Integer, List<Integer>> offeredMap = parseOfferedCards(session.getOfferedCards());
        if (!offeredMap.isEmpty()) {
            List<Integer> offeredNow = offeredMap.get(round);
            if (offeredNow == null || !offeredNow.contains(cardId)) {
                throw new IllegalArgumentException(
                        "이번 라운드에 제시된 카드가 아닙니다 (제시된 후보: " + offeredNow + ")");
            }
        }

        appliedCardIds.add(cardId);
        Portfolio pf = loadPortfolio(session);
        applyCardSelection(card, round, pf, prices);

        Map<String, Object> response = new LinkedHashMap<>();
        response.put("selectedCard", card.getName());
        response.putAll(advance(session, round, pf, appliedCardIds, cards, prices, unavailableCardIds));
        return response;
    }

    // =============================================
    // (#125) 위기 대응 선택 — 뉴스 속보 라운드에서 버틴다 / 절반 판다 / 더 산다
    //   그 라운드 종가로 바로 매매하고(카드 발동보다 먼저), 다음 이벤트 라운드 직전까지 계산한다.
    // =============================================
    public Map<String, Object> decide(String sessionId, Integer round, String choice) {

        GameSession session = findPlayingSession(sessionId);

        if (round == null || !round.equals(session.getCurrentRound())) {
            throw new IllegalArgumentException(
                    "지금은 " + session.getCurrentRound() + "라운드 차례입니다 (요청: " + round + "라운드)");
        }
        if (choice == null || !DECISION_CHOICES.contains(choice)) {
            throw new IllegalArgumentException("알 수 없는 위기 대응 선택입니다 (가능: " + DECISION_CHOICES + ")");
        }

        PriceTable prices = loadPrices(session.getGameStartDate());
        NewsPlan news = loadNews(session.getScenarioId(), prices.spx);
        if (!news.decisions.containsKey(round)) {
            throw new IllegalArgumentException(round + "라운드는 위기 대응 라운드가 아닙니다");
        }

        Portfolio pf = loadPortfolio(session);
        long traded = applyDecision(choice, round, pf, prices, baseTicker(session));

        Map<Integer, String> decisions = parseDecisions(session.getDecisions());
        decisions.put(round, choice);
        session.updateDecisions(serializeDecisions(decisions));

        Map<String, Object> response = new LinkedHashMap<>();
        response.put("decision", choice);
        response.put("tradeAmount", traded);     // 그때 팔거나 산 금액 (원). 버틴다는 0
        response.putAll(advance(session, round, pf, getAppliedCardIds(session), cardMap(), prices,
                getUnavailableCardIds(prices)));
        return response;
    }

    // =============================================
    // 이벤트 처리 공통: 이번 이벤트 라운드부터 다음 이벤트 라운드 직전까지 계산하고 세션을 저장
    // =============================================
    private Map<String, Object> advance(GameSession session, int round, Portfolio pf,
                                        List<Integer> appliedCardIds, Map<Integer, Card> cards,
                                        PriceTable prices, Set<Integer> unavailableCardIds) {

        NewsPlan news = loadNews(session.getScenarioId(), prices.spx);
        TreeSet<Integer> eventRounds = new TreeSet<>(CARD_SELECT_ROUNDS);
        eventRounds.addAll(news.decisions.keySet());

        Integer nextEventRound = eventRounds.higher(round);
        int endRound = nextEventRound != null ? nextEventRound - 1 : TOTAL_ROUNDS;

        List<Map<String, Object>> rounds = calculateRounds(
                session.getInitialAsset(), round, endRound, pf,
                sortedCards(appliedCardIds, cards), prices, news.byRound);

        storePortfolio(session, pf, endRound + 1, appliedCardIds);
        if (nextEventRound == null) {   // 마지막 이벤트 → 100라운드까지 계산 완료
            session.finish();
        }

        String nextEventType = nextEventRound == null ? null
                : (news.decisions.containsKey(nextEventRound) ? EVENT_DECISION : EVENT_CARD);

        // 다음 카드 선택 라운드의 후보를 만들고 세션에 저장한 뒤 한 번에 save
        List<Integer> nextCardOptions = null;
        if (EVENT_CARD.equals(nextEventType)) {
            nextCardOptions = getRandomCards(appliedCardIds, unavailableCardIds);
            recordOfferedCards(session, nextEventRound, nextCardOptions);
        }
        sessionRepository.save(session);

        // (#125) 남은 위기 대응이 없으면 사후 분석용 전체 조합 계산을 미리 시작해 둔다 (결과 화면이 바로 뜨도록)
        boolean decisionsDone = news.decisions.isEmpty() || news.decisions.lastKey() <= round;
        boolean justDecided = news.decisions.containsKey(round) || (news.decisions.isEmpty() && round == 1);
        if (decisionsDone && justDecided) {
            prewarmAnalysis(session);
        }

        Map<String, Object> response = new LinkedHashMap<>();
        response.put("nextEventRound", nextEventRound);
        response.put("nextEventType", nextEventType);
        response.put("nextCardOptions", nextCardOptions);
        // (#125) 다음이 위기 대응 라운드면 그 속보
        response.put("nextDecision", EVENT_DECISION.equals(nextEventType)
                ? decisionInfo(nextEventRound, news, session) : null);
        // (11주차) 다음 이벤트 라운드의 뉴스 — 선택 화면 표시용
        //   같은 뉴스가 다음 응답의 rounds[].news에도 다시 옴 (앱에서 날짜+헤드라인으로 중복 제거)
        response.put("nextRoundNews", nextEventRound != null
                ? news.byRound.getOrDefault(nextEventRound, new ArrayList<>())
                : new ArrayList<>());
        response.put("rounds", rounds);
        return response;
    }

    private Map<String, Object> decisionInfo(int round, NewsPlan news, GameSession session) {
        Map<String, Object> info = new LinkedHashMap<>();
        info.put("round", round);
        info.put("news", news.decisions.get(round));
        info.put("choices", DECISION_CHOICES);
        info.put("buyMoreTarget", TICKER_NAMES.get(baseTicker(session)));
        return info;
    }

    // 카드 선택 즉시 한 번 사는 카드(BUY_ONCE)는 고른 라운드 종가로 매수. 상장 전(가격 없음)이면 건너뜀
    private void applyCardSelection(Card card, int round, Portfolio pf, PriceTable prices) {
        if (!"BUY_ONCE".equals(card.getType())) return;
        double price = prices.closeAt(card.getTicker(), round - 1);
        if (price > 0) {
            pf.buy(card.getTicker(), pf.cash * card.getRatio(), price);
        }
    }

    // 위기 대응 매매 → 팔거나 산 금액(원)
    private long applyDecision(String choice, int round, Portfolio pf, PriceTable prices, String baseTicker) {
        int i = round - 1;
        long traded = 0;
        if (DECISION_SELL_HALF.equals(choice)) {
            for (String ticker : TICKERS) {
                double price = prices.closeAt(ticker, i);
                if (pf.shares(ticker) > 0 && price > 0) {
                    traded += pf.sell(ticker, SELL_HALF_RATIO, price);
                }
            }
        } else if (DECISION_BUY_MORE.equals(choice)) {
            double price = prices.closeAt(baseTicker, i);
            if (price > 0) {
                double amount = pf.cash * BUY_MORE_RATIO;
                pf.buy(baseTicker, amount, price);
                traded = (long) amount;
            }
        }
        return traded;
    }

    // '더 산다'에서 사는 종목 = 시나리오 기준 지수 (리먼·코로나 S&P500, 닷컴 나스닥100)
    private String baseTicker(GameSession session) {
        return "^NDX".equals(session.getTicker()) ? "^NDX" : "^SPX";
    }

    // =============================================
    // 사후 분석 (백테스팅) — 게임 종료 후 1회 호출
    // =============================================
    @SuppressWarnings("unchecked")
    public Map<String, Object> analyzeResult(String sessionId) {
        GameSession session = findSession(sessionId);
        Map<String, Object> requestBody = analysisRequest(session);

        // 사후 분석은 부가 정보 → 실패해도 결과 화면은 정상 표시되도록 null 반환
        try {
            Map<String, Object> body = postToAi("/ai/analysis/backtest", requestBody);
            Map<Integer, Card> cards = cardMap();

            List<Map<String, Object>> topCombos = new ArrayList<>();
            for (Map<String, Object> combo : (List<Map<String, Object>>) body.get("topCombos")) {
                topCombos.add(enrichCombo(combo, cards));
            }

            Map<String, Object> result = new LinkedHashMap<>();
            result.put("totalCombinations", body.get("totalCombinations"));
            result.put("cardPoolSize", body.get("cardPoolSize"));   // 사용 가능 카드 수 (상장 전 종목 제외)
            result.put("topCombos", topCombos);
            result.put("playerResult", enrichCombo((Map<String, Object>) body.get("playerResult"), cards));

            // (11주차) 받은 후보 안 분석 — 이 부분만 실패해도 기존 전체 조합 결과는 그대로 반환
            Map<String, Object> offeredAnalysis = null;
            try {
                Object oa = body.get("offeredAnalysis");
                if (oa instanceof Map) {
                    offeredAnalysis = enrichOfferedAnalysis((Map<String, Object>) oa, cards);
                }
            } catch (Exception ignored) {
                offeredAnalysis = null;
            }
            result.put("offeredAnalysis", offeredAnalysis);

            // (#125) 등급·최대 낙폭·카드별 성적표·그 후 이야기는 AI 서버 값을 그대로 전달
            result.put("grade", body.get("grade"));
            result.put("risk", body.get("risk"));
            result.put("cardReport", body.get("cardReport"));
            result.put("epilogue", body.get("epilogue"));
            // 위기 대응 돌아보기에는 그 라운드의 속보를 붙인다
            result.put("decisionReview", enrichDecisionReview(body.get("decisionReview"), session));
            return result;

        } catch (Exception e) {
            log.warn("[사후 분석 실패] sessionId={}, {}", sessionId, e.getMessage());
            return null;
        }
    }

    // =============================================
    // (#125) 사후 분석 AI 코치 한마디 — 결과 화면에서 분석과 따로 호출 (LLM 응답을 기다리느라 분석이 늦어지지 않게)
    //   실패하면 null → 앱은 해당 칸을 표시하지 않음
    // =============================================
    public Map<String, Object> coachResult(String sessionId) {
        GameSession session = findSession(sessionId);
        Map<String, Object> requestBody = analysisRequest(session);
        try {
            Map<String, Object> body = postToAi("/ai/analysis/coach", requestBody);
            Map<String, Object> result = new LinkedHashMap<>();
            result.put("comment", body.get("comment"));
            result.put("status", body.get("status"));       // llm / fallback / failed
            result.put("verified", body.get("verified"));
            return result;
        } catch (Exception e) {
            log.warn("[AI 코치 실패] sessionId={}, {}", sessionId, e.getMessage());
            return null;
        }
    }

    // 사후 분석·AI 코치 공통 요청 (게임이 끝난 세션만)
    private Map<String, Object> analysisRequest(GameSession session) {
        if (!"FINISHED".equals(session.getStatus())) {
            throw new IllegalArgumentException("아직 종료되지 않은 게임입니다");
        }

        List<Integer> appliedCardIds = getAppliedCardIds(session);
        if (appliedCardIds.size() < CARD_SELECT_ROUNDS.size()) {
            throw new IllegalArgumentException("카드 선택이 완료되지 않은 게임입니다");
        }

        // "1,4,5,9" → {"1": 1, "25": 4, "50": 5, "75": 9}
        Map<String, Integer> playerSelections = new LinkedHashMap<>();
        for (int i = 0; i < CARD_SELECT_ROUNDS.size(); i++) {
            playerSelections.put(String.valueOf(CARD_SELECT_ROUNDS.get(i)), appliedCardIds.get(i));
        }

        Map<String, Object> requestBody = new LinkedHashMap<>();
        requestBody.put("startDate", session.getGameStartDate());
        requestBody.put("playerCardSelections", playerSelections);
        requestBody.put("topN", 3);
        requestBody.putAll(decisionRequestPart(session));

        // (11주차) 라운드별 제시 후보 → "받은 후보 안에서의 최선" 분석용
        // 4개 라운드 후보가 모두 기록된 세션만 보냄 (이전 세션은 기존 분석만)
        Map<Integer, List<Integer>> offeredMap = parseOfferedCards(session.getOfferedCards());
        if (offeredMap.keySet().containsAll(CARD_SELECT_ROUNDS)) {
            Map<String, List<Integer>> offeredJson = new LinkedHashMap<>();
            for (Integer r : CARD_SELECT_ROUNDS) {
                offeredJson.put(String.valueOf(r), offeredMap.get(r));
            }
            requestBody.put("offeredCards", offeredJson);
        }
        return requestBody;
    }

    // (#125) AI 서버에 보내는 위기 대응 정보: {"decisions": {"10": "SELL_HALF"}, "baseTicker": "^SPX"}
    private Map<String, Object> decisionRequestPart(GameSession session) {
        Map<String, String> decisionsJson = new LinkedHashMap<>();
        parseDecisions(session.getDecisions()).forEach((r, c) -> decisionsJson.put(String.valueOf(r), c));
        Map<String, Object> part = new LinkedHashMap<>();
        part.put("decisions", decisionsJson);
        part.put("baseTicker", baseTicker(session));
        return part;
    }

    // (#125) 전체 조합 계산을 AI 서버에서 미리 시작 — 응답을 기다리지 않고, 실패해도 게임에는 영향 없음
    private void prewarmAnalysis(GameSession session) {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("startDate", session.getGameStartDate());
        body.putAll(decisionRequestPart(session));
        CompletableFuture.runAsync(() -> {
            try {
                postToAi("/ai/analysis/prewarm", body);
            } catch (Exception ignored) {
                // 미리 계산은 선택 사항 — 결과 화면 요청에서 다시 계산한다
            }
        }, prewarmExecutor);
    }

    // 받은 후보 안 분석 결과에 카드 이름 붙이기
    @SuppressWarnings("unchecked")
    private Map<String, Object> enrichOfferedAnalysis(Map<String, Object> src, Map<Integer, Card> cards) {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("totalCombinations", src.get("totalCombinations"));   // 받은 후보로 만들 수 있는 조합 수 (최대 81)
        out.put("bestCombo", enrichCombo((Map<String, Object>) src.get("bestCombo"), cards));
        out.put("playerResult", enrichCombo((Map<String, Object>) src.get("playerResult"), cards));

        List<Map<String, Object>> roundAlternatives = new ArrayList<>();
        for (Map<String, Object> ra : (List<Map<String, Object>>) src.get("roundAlternatives")) {
            Integer playerCardId = ((Number) ra.get("playerCardId")).intValue();

            List<Map<String, Object>> alternatives = new ArrayList<>();
            for (Map<String, Object> alt : (List<Map<String, Object>>) ra.get("alternatives")) {
                Integer altCardId = ((Number) alt.get("cardId")).intValue();
                Map<String, Object> a = new LinkedHashMap<>();
                a.put("cardId", altCardId);
                a.put("cardName", cardName(altCardId, cards));
                a.put("finalAsset", alt.get("finalAsset"));
                a.put("finalReturnRate", alt.get("finalReturnRate"));
                a.put("diffReturnRate", alt.get("diffReturnRate"));   // 대안 - 내 결과 (%p, +면 대안이 더 좋음)
                alternatives.add(a);
            }

            Map<String, Object> r = new LinkedHashMap<>();
            r.put("round", ra.get("round"));
            r.put("offeredCards", ra.get("offeredCards"));
            r.put("playerCardId", playerCardId);
            r.put("playerCardName", cardName(playerCardId, cards));
            r.put("alternatives", alternatives);
            roundAlternatives.add(r);
        }
        out.put("roundAlternatives", roundAlternatives);
        return out;
    }

    // (#125) 위기 대응 돌아보기의 각 라운드에 그때의 속보(헤드라인·level)를 붙인다
    @SuppressWarnings("unchecked")
    private Object enrichDecisionReview(Object raw, GameSession session) {
        if (!(raw instanceof Map)) return null;
        try {
            Map<String, Object> review = new LinkedHashMap<>((Map<String, Object>) raw);
            NewsPlan news = loadNews(session.getScenarioId(), loadPrices(session.getGameStartDate()).spx);
            List<Map<String, Object>> rounds = new ArrayList<>();
            for (Map<String, Object> r : (List<Map<String, Object>>) review.get("rounds")) {
                Map<String, Object> enriched = new LinkedHashMap<>(r);
                Map<String, Object> n = news.decisions.get(((Number) r.get("round")).intValue());
                enriched.put("headline", n != null ? n.get("headline") : "");
                enriched.put("level", n != null ? n.get("level") : "caution");
                rounds.add(enriched);
            }
            review.put("rounds", rounds);
            return review;
        } catch (Exception e) {
            return raw;   // 속보를 못 붙여도 숫자는 그대로 전달
        }
    }

    private String cardName(Integer cardId, Map<Integer, Card> cards) {
        Card card = cards.get(cardId);
        return card != null ? card.getName() : "";
    }

    // cardSelections {"1":7,"25":3,...} → cards [{round, cardId, cardName}, ...]
    @SuppressWarnings("unchecked")
    private Map<String, Object> enrichCombo(Map<String, Object> src, Map<Integer, Card> cards) {
        Map<String, Object> selections = (Map<String, Object>) src.get("cardSelections");

        List<Map<String, Object>> comboCards = new ArrayList<>();
        for (Integer round : CARD_SELECT_ROUNDS) {
            Integer cardId = ((Number) selections.get(String.valueOf(round))).intValue();
            Map<String, Object> c = new LinkedHashMap<>();
            c.put("round", round);
            c.put("cardId", cardId);
            c.put("cardName", cardName(cardId, cards));
            comboCards.add(c);
        }

        Map<String, Object> out = new LinkedHashMap<>();
        out.put("rank", src.get("rank"));
        out.put("tiedCount", src.get("tiedCount"));   // 같은 결과를 내는 조합 수 (동점 묶기)
        out.put("cards", comboCards);
        out.put("finalAsset", src.get("finalAsset"));
        out.put("finalReturnRate", src.get("finalReturnRate"));
        if (src.containsKey("topPercent")) {
            out.put("topPercent", src.get("topPercent"));
        }
        return out;
    }

    // =============================================
    // 검증용 게임 실행 — Python run_game()과 같은 입력으로 100라운드를 한 번에 계산
    //   (#125) 위기 대응(decisions)·기준 종목(baseTicker)도 받는다. 카드가 없는 라운드도 1라운드부터 모두 반환
    // =============================================
    public Map<String, Object> validateGame(String startDate, Map<Integer, Integer> cardSelections,
                                            Map<Integer, String> decisions, String baseTicker) {
        if (startDate == null || cardSelections == null) {
            throw new IllegalArgumentException("startDate와 cardSelections가 필요합니다");
        }
        if (decisions == null) decisions = new TreeMap<>();
        String base = "^NDX".equals(baseTicker) ? "^NDX" : "^SPX";

        for (Map.Entry<Integer, String> d : decisions.entrySet()) {
            int r = d.getKey();
            if (!DECISION_CHOICES.contains(d.getValue())) {
                throw new IllegalArgumentException("알 수 없는 위기 대응 선택입니다: " + d.getValue());
            }
            if (CARD_SELECT_ROUNDS.contains(r) || r < 2 || r > TOTAL_ROUNDS - 1) {
                throw new IllegalArgumentException("위기 대응은 2~99라운드 중 카드 선택 라운드가 아닌 라운드에서만 가능합니다: " + r);
            }
        }

        PriceTable prices = loadPrices(startDate);
        Map<Integer, Card> cards = cardMap();
        Set<Integer> unavailableCardIds = getUnavailableCardIds(prices);
        for (Integer cid : cardSelections.values()) {
            if (!cards.containsKey(cid)) {
                throw new IllegalArgumentException("존재하지 않는 카드: " + cid);
            }
            if (unavailableCardIds.contains(cid)) {
                throw new IllegalArgumentException("이 시작일에는 사용할 수 없는 카드입니다 (상장 전 종목): " + cid);
            }
        }

        Portfolio pf = new Portfolio(INITIAL_ASSET);
        List<Integer> appliedCardIds = new ArrayList<>();
        List<Map<String, Object>> allRounds = new ArrayList<>();
        Map<Integer, List<Map<String, Object>>> noNews = new HashMap<>();

        // 구간 경계 = 1라운드 + 카드 선택 라운드 + 위기 대응 라운드
        TreeSet<Integer> boundaries = new TreeSet<>(cardSelections.keySet());
        boundaries.addAll(decisions.keySet());
        boundaries.add(1);

        for (Integer startRound : boundaries) {
            if (startRound < 1 || startRound > TOTAL_ROUNDS) continue;

            Integer cardId = cardSelections.get(startRound);
            if (cardId != null && !appliedCardIds.contains(cardId)) {
                appliedCardIds.add(cardId);
                applyCardSelection(cards.get(cardId), startRound, pf, prices);
            }
            String choice = decisions.get(startRound);
            if (choice != null) {
                applyDecision(choice, startRound, pf, prices, base);
            }

            Integer next = boundaries.higher(startRound);
            int endRound = (next != null && next <= TOTAL_ROUNDS) ? next - 1 : TOTAL_ROUNDS;

            allRounds.addAll(calculateRounds(INITIAL_ASSET, startRound, endRound, pf,
                    sortedCards(appliedCardIds, cards), prices, noNews));
        }

        Map<String, Object> lastRound = allRounds.isEmpty() ? new HashMap<>() : allRounds.get(allRounds.size() - 1);

        Map<String, Object> result = new LinkedHashMap<>();
        result.put("scenario", "lehman");
        result.put("start_date", startDate);
        result.put("card_selections", cardSelections);
        result.put("decisions", decisions);
        result.put("initial_asset", INITIAL_ASSET);
        result.put("rounds", allRounds);
        result.put("final_asset", lastRound.getOrDefault("roundAsset", INITIAL_ASSET));
        result.put("final_return_rate", lastRound.getOrDefault("returnRate", 0.0));
        return result;
    }

    // =============================================
    // 라운드별 자산 계산 — startRound부터 endRound까지 (pf는 계산하면서 직접 바뀐다)
    //   appliedCards: 지금까지 고른 카드 (priority 순)
    // =============================================
    private List<Map<String, Object>> calculateRounds(
            long initialAsset, int startRound, int endRound, Portfolio pf,
            List<Card> appliedCards, PriceTable prices,
            Map<Integer, List<Map<String, Object>>> newsMap) {

        List<Map<String, Object>> rounds = new ArrayList<>();

        for (int i = startRound - 1; i < endRound; i++) {
            if (i >= prices.spx.size()) break;

            int roundNumber = i + 1;
            StockPrice spxCurrent = prices.spx.get(i);

            // 조건 판정용 등락률: 가격이 없으면 null (결측을 0%로 취급하지 않음)
            Double spxChange  = changeRateOrNull(prices.at("^SPX", i - 1), spxCurrent);
            Double ndxChange  = changeRateOrNull(prices.at("^NDX", i - 1), prices.at("^NDX", i));
            Double aaplChange = changeRateOrNull(prices.at("AAPL", i - 1), prices.at("AAPL", i));

            long totalAsset = pf.cash + (long) holdingsValue(pf, prices, i);

            List<Integer> triggeredCardIds = new ArrayList<>();
            List<Map<String, Object>> skippedCards = new ArrayList<>();   // (#125) 조건은 맞았지만 실행되지 못한 카드

            // 파산 방지: 총자산이 초기 자산의 1% 이하면 카드 발동 중지
            if (totalAsset > initialAsset * 0.01) {
                for (Card card : appliedCards) {
                    if ("BUY_ONCE".equals(card.getType())) continue;

                    boolean triggered = false;
                    if ("BUY_SPLIT".equals(card.getType())) {
                        triggered = true;
                    } else if ("BUY_ON_CONDITION".equals(card.getType())
                            || "SELL_ON_CONDITION".equals(card.getType())) {
                        triggered = checkCondition(card.getCondition(), spxChange, ndxChange, aaplChange);
                    } else if ("BUY_EVERY_N".equals(card.getType())) {
                        triggered = (roundNumber % 5 == 0);
                    }

                    if (!triggered) continue;

                    if (card.getMaxTrigger() != null) {
                        int count = pf.triggerCounts.getOrDefault(card.getId(), 0);
                        if (count >= card.getMaxTrigger()) {
                            skippedCards.add(skip(card, SKIP_MAX_REACHED));
                            continue;
                        }
                        pf.triggerCounts.put(card.getId(), count + 1);
                    }

                    double price = prices.closeAt(card.getTicker(), i);

                    if ("SELL_ON_CONDITION".equals(card.getType())) {
                        if (price <= 0) {
                            skippedCards.add(skip(card, SKIP_NO_PRICE));
                        } else if (pf.shares(card.getTicker()) > 0) {
                            pf.sell(card.getTicker(), card.getRatio(), price);
                            triggeredCardIds.add(card.getId());
                        } else {
                            // 팔 주식이 없음 — 기존에는 0주를 팔고 '발동'으로 세었다 (자산 계산 결과는 같음)
                            skippedCards.add(skip(card, SKIP_NO_HOLDINGS));
                        }
                        continue;
                    }

                    // 현금 부족 스킵 (총자산의 5% 미만)
                    if (pf.cash < totalAsset * 0.05) {
                        skippedCards.add(skip(card, SKIP_CASH_LOW));
                        continue;
                    }

                    if (price <= 0) {
                        skippedCards.add(skip(card, SKIP_NO_PRICE));
                        continue;
                    }

                    pf.buy(card.getTicker(), pf.cash * card.getRatio(), price);
                    triggeredCardIds.add(card.getId());
                }
            }

            long roundAsset = pf.cash + (long) holdingsValue(pf, prices, i);
            double returnRate = (double) (roundAsset - initialAsset) / initialAsset * 100;

            // 화면 표시용 가격: 그날 가격이 있는 모든 종목 (상장 전 종목은 빠진다)
            // (#125) 기존에는 S&P500과 보유 중인 종목만 보내, 갖고 있지 않은 종목은 흐름을 보고 고를 수 없었다
            List<Map<String, Object>> priceDataList = new ArrayList<>();
            for (String ticker : TICKERS) {
                StockPrice current = prices.at(ticker, i);
                if (current == null) continue;
                // 등락률은 기존 응답 형식 유지: 계산할 수 없으면 0.0
                priceDataList.add(priceEntry(ticker, current, calcChangeRate(prices.at(ticker, i - 1), current)));
            }

            Map<String, Object> roundMap = new LinkedHashMap<>();
            roundMap.put("round", roundNumber);
            roundMap.put("date", spxCurrent.getTradeDate().toString());
            roundMap.put("priceData", priceDataList);
            roundMap.put("roundAsset", roundAsset);
            roundMap.put("returnRate", round2(returnRate));
            roundMap.put("triggeredCards", triggeredCardIds);
            roundMap.put("skippedCards", skippedCards);

            // (11주차) 보유 종목 평균 단가·누적 수익률·비중 + 현금 비중
            putPortfolio(roundMap, pf, roundAsset, prices, i);
            roundMap.put("news", newsMap.getOrDefault(roundNumber, new ArrayList<>()));
            rounds.add(roundMap);
        }

        return rounds;
    }

    private Map<String, Object> skip(Card card, String reason) {
        Map<String, Object> s = new LinkedHashMap<>();
        s.put("cardId", card.getId());
        s.put("reason", reason);
        return s;
    }

    // 보유 자산 평가액 — 종목 순서대로 하나씩 더한다 (Python과 같은 순서라 끝자리까지 같다)
    private double holdingsValue(Portfolio pf, PriceTable prices, int index) {
        double value = 0;
        for (String ticker : TICKERS) {
            StockPrice p = prices.at(ticker, index);
            if (p != null) {
                value += pf.shares(ticker) * p.getClose();
            }
        }
        return value;
    }

    // =============================================
    // 유틸 메서드
    // =============================================
    // 조건에 쓰이는 등락률이 null(가격 없음)이면 발동하지 않음
    private boolean checkCondition(String condition,
                                   Double spxChange, Double ndxChange, Double aaplChange) {
        if (condition == null) return false;
        return switch (condition) {
            case "SPX_CHANGE <= -3"  -> spxChange  != null && spxChange  <= -3;
            case "SPX_CHANGE <= -5"  -> spxChange  != null && spxChange  <= -5;
            case "SPX_CHANGE >= 3"   -> spxChange  != null && spxChange  >= 3;
            case "NDX_CHANGE >= 2"   -> ndxChange  != null && ndxChange  >= 2;
            case "NDX_CHANGE <= -4"  -> ndxChange  != null && ndxChange  <= -4;
            case "AAPL_CHANGE <= -5" -> aaplChange != null && aaplChange <= -5;
            default -> false;
        };
    }

    // 등락률(%) — 전일 또는 당일 가격이 없으면 null
    private Double changeRateOrNull(StockPrice prev, StockPrice current) {
        if (prev == null || current == null || prev.getClose() <= 0) return null;
        double rate = (current.getClose() - prev.getClose()) / prev.getClose() * 100;
        return round2(rate);
    }

    // 화면 표시용 가격 한 줄 (라운드 응답의 priceData 항목)
    private Map<String, Object> priceEntry(String ticker, StockPrice p, double changeRate) {
        Map<String, Object> data = new LinkedHashMap<>();
        data.put("ticker", ticker);
        data.put("open", p.getOpen());
        data.put("close", p.getClose());
        data.put("high", p.getHigh());
        data.put("low", p.getLow());
        data.put("changeRate", changeRate);
        return data;
    }

    private double calcChangeRate(StockPrice prev, StockPrice current) {
        Double rate = changeRateOrNull(prev, current);
        return rate != null ? rate : 0.0;
    }

    private double round2(double v) {
        return Math.round(v * 100.0) / 100.0;
    }

    private GameSession findSession(String sessionId) {
        if (sessionId == null || sessionId.isBlank()) {
            throw new IllegalArgumentException("sessionId가 필요합니다");
        }
        return sessionRepository.findById(sessionId)
                .orElseThrow(() -> new IllegalArgumentException("존재하지 않는 세션입니다"));
    }

    private GameSession findPlayingSession(String sessionId) {
        GameSession session = findSession(sessionId);
        if ("FINISHED".equals(session.getStatus())) {
            throw new IllegalArgumentException("이미 종료된 게임입니다");
        }
        return session;
    }

    private Map<Integer, Card> cardMap() {
        Map<Integer, Card> map = new HashMap<>();
        for (Card card : cardRepository.findAll()) {
            map.put(card.getId(), card);
        }
        return map;
    }

    // 고른 카드를 priority 순으로 (같은 라운드에 여러 카드가 발동할 때의 실행 순서)
    private List<Card> sortedCards(List<Integer> cardIds, Map<Integer, Card> cards) {
        List<Card> list = new ArrayList<>();
        for (Integer id : cardIds) {
            Card card = cards.get(id);
            if (card != null) list.add(card);
        }
        list.sort(Comparator.comparing(Card::getPriority));
        return list;
    }

    // AI 서버 호출 공통 — 연결 실패·오류 응답은 AiServerException(503)으로 바꾼다
    @SuppressWarnings("unchecked")
    private Map<String, Object> postToAi(String path, Map<String, Object> requestBody) {
        try {
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            HttpEntity<Map<String, Object>> entity = new HttpEntity<>(requestBody, headers);

            ResponseEntity<Map> response = restTemplate.exchange(
                    aiServerUrl + path, HttpMethod.POST, entity, Map.class);

            Map<String, Object> body = response.getBody();
            if (body == null) {
                throw new AiServerException("AI 서버가 빈 응답을 보냈습니다");
            }
            return body;
        } catch (AiServerException e) {
            throw e;
        } catch (Exception e) {
            throw new AiServerException("AI 서버에 연결할 수 없습니다: " + e.getMessage());
        }
    }

    // =============================================
    // 세션 ↔ 포트폴리오
    // =============================================
    private Portfolio loadPortfolio(GameSession session) {
        Portfolio pf = new Portfolio(session.getCash());
        pf.shares.put("^SPX",   orZero(session.getSpxShares()));
        pf.shares.put("^NDX",   orZero(session.getNdxShares()));
        pf.shares.put("XAUUSD", orZero(session.getXauusdShares()));
        pf.shares.put("USO",    orZero(session.getUsoShares()));
        pf.shares.put("AAPL",   orZero(session.getAaplShares()));
        pf.shares.put("TLT",    orZero(session.getTltShares()));
        // 종목별 원가 (배포 전 세션은 null → 0)
        pf.costs.put("^SPX",   orZero(session.getSpxCost()));
        pf.costs.put("^NDX",   orZero(session.getNdxCost()));
        pf.costs.put("XAUUSD", orZero(session.getXauusdCost()));
        pf.costs.put("USO",    orZero(session.getUsoCost()));
        pf.costs.put("AAPL",   orZero(session.getAaplCost()));
        pf.costs.put("TLT",    orZero(session.getTltCost()));
        pf.triggerCounts.putAll(parseTriggerCount(session.getTriggerCount()));
        return pf;
    }

    private void storePortfolio(GameSession session, Portfolio pf, int currentRound, List<Integer> appliedCardIds) {
        String appliedCards = appliedCardIds.stream()
                .map(String::valueOf)
                .collect(Collectors.joining(","));
        session.update(
                pf.cash, pf.shares("^SPX"), pf.shares("^NDX"), pf.shares("XAUUSD"),
                pf.shares("USO"), pf.shares("AAPL"), pf.shares("TLT"),
                currentRound, appliedCards, serializeTriggerCount(pf.triggerCounts)
        );
        session.updateCosts(pf.costs.get("^SPX"), pf.costs.get("^NDX"), pf.costs.get("XAUUSD"),
                pf.costs.get("USO"), pf.costs.get("AAPL"), pf.costs.get("TLT"));
    }

    private double orZero(Double v) {
        return v != null ? v : 0.0;
    }

    // =============================================
    // 뉴스 이벤트 (11주차) + 위기 대응 라운드 (#125)
    // =============================================
    // 뉴스 날짜 → 라운드 번호 (그날 또는 그 다음 S&P500 거래일). 게임 시작 전이거나 100라운드 뒤면 -1
    private int roundOfDate(List<StockPrice> spxList, LocalDate date) {
        if (spxList.isEmpty() || date.isBefore(spxList.get(0).getTradeDate())) return -1;
        int limit = Math.min(TOTAL_ROUNDS, spxList.size());
        for (int i = 0; i < limit; i++) {
            if (!spxList.get(i).getTradeDate().isBefore(date)) return i + 1;
        }
        return -1;
    }

    // 시나리오 뉴스를 라운드에 배치
    // - 게임 시작일 이전·100라운드 이후 뉴스는 제외 (검증용 실행처럼 다른 시작일이면 자연히 빠짐)
    // - decision 뉴스는 위기 대응 라운드를 만든다. 단, 카드 선택 라운드·1라운드·마지막 라운드에 걸리면 일반 뉴스로만 표시
    private NewsPlan loadNews(Integer scenarioId, List<StockPrice> spxList) {
        NewsPlan plan = new NewsPlan();
        if (scenarioId == null || spxList.isEmpty()) return plan;

        for (NewsEvent e : newsEventRepository.findByScenarioIdOrderByEventDate(scenarioId)) {
            int round = roundOfDate(spxList, e.getEventDate());
            if (round < 0) continue;

            Map<String, Object> n = new LinkedHashMap<>();
            n.put("date", e.getEventDate().toString());
            n.put("headline", e.getHeadline());
            n.put("level", e.getLevel());
            n.put("source", e.getSource());
            n.put("sourceUrl", e.getSourceUrl());
            plan.byRound.computeIfAbsent(round, k -> new ArrayList<>()).add(n);

            if (e.isDecisionNews() && isDecisionRound(round)) {
                plan.decisions.putIfAbsent(round, n);   // 같은 라운드에 속보가 둘이면 첫 번째만
            }
        }
        return plan;
    }

    private boolean isDecisionRound(int round) {
        return round >= 2 && round <= TOTAL_ROUNDS - 1 && !CARD_SELECT_ROUNDS.contains(round);
    }

    // =============================================
    // 보유 종목 (11주차)
    // =============================================
    // roundMap에 holdings, cash, cashWeight 추가
    // - holdings: 수량이 있는 종목만, TICKERS 순서
    // - returnRate: 평균 단가 대비 누적 수익률 (%)
    // - weight: 총자산 중 비중 (%), cashWeight = 100 - 종목 비중 합 (합계가 정확히 100이 되도록)
    private void putPortfolio(Map<String, Object> roundMap, Portfolio pf, long roundAsset,
                              PriceTable prices, int index) {
        List<Map<String, Object>> holdings = new ArrayList<>();
        double weightSum = 0.0;

        for (String ticker : TICKERS) {
            double shares = pf.shares(ticker);
            StockPrice price = prices.at(ticker, index);
            if (shares <= 1e-9 || price == null) continue;

            double currentPrice = price.getClose();
            double cost = pf.costs.getOrDefault(ticker, 0.0);
            double value = shares * currentPrice;
            double avgPrice = cost / shares;
            double returnRate = cost > 0 ? (value - cost) / cost * 100 : 0.0;
            double weight = roundAsset > 0 ? round2(value / roundAsset * 100) : 0.0;
            weightSum += weight;

            Map<String, Object> h = new LinkedHashMap<>();
            h.put("ticker", ticker);
            h.put("name", TICKER_NAMES.getOrDefault(ticker, ticker));
            h.put("shares", Math.round(shares * 10000.0) / 10000.0);
            h.put("avgPrice", round2(avgPrice));
            h.put("currentPrice", round2(currentPrice));
            h.put("costAmount", Math.round(cost));
            h.put("value", Math.round(value));
            h.put("returnRate", round2(returnRate));
            h.put("weight", weight);
            holdings.add(h);
        }

        roundMap.put("holdings", holdings);
        roundMap.put("cash", pf.cash);
        roundMap.put("cashWeight", round2(100.0 - weightSum));
    }

    // =============================================
    // 가격표
    // =============================================
    // 시작일부터 S&P500 100거래일 + 나머지 종목을 그 날짜에 맞춘 가격표
    // (#125) 요청마다 필요한 100라운드만 읽는다 (기존: 시작일부터 데이터 끝까지 전부)
    private PriceTable loadPrices(String gameStartDate) {
        List<StockPrice> spx = stockPriceRepository
                .findTop100ByTickerAndTradeDateGreaterThanEqualOrderByTradeDate(
                        "^SPX", LocalDate.parse(gameStartDate));
        Map<String, List<StockPrice>> byTicker = new HashMap<>();
        byTicker.put("^SPX", spx);
        for (String ticker : TICKERS) {
            if (!"^SPX".equals(ticker)) {
                byTicker.put(ticker, alignToSpx(ticker, spx));
            }
        }
        return new PriceTable(spx, byTicker);
    }

    // SPX 거래일 기준으로 종목 가격을 맞춘 리스트 (Python game_logic.load_price_data()와 같은 규칙)
    // - i번째 = SPX의 i번째 거래일 날짜의 종가
    // - 그날 거래가 없으면 직전 거래일 가격 (기간 제한 없음), 그 이전 데이터가 전혀 없으면(상장 전) null
    private List<StockPrice> alignToSpx(String ticker, List<StockPrice> spxList) {
        if (spxList.isEmpty()) return new ArrayList<>();

        LocalDate firstDate = spxList.get(0).getTradeDate();
        LocalDate lastDate = spxList.get(spxList.size() - 1).getTradeDate();
        // 첫 거래일 당일 또는 그 이전의 가장 최근 가격 (없으면 상장 전)
        StockPrice current = stockPriceRepository
                .findTopByTickerAndTradeDateLessThanEqualOrderByTradeDateDesc(ticker, firstDate)
                .orElse(null);
        List<StockPrice> raw = stockPriceRepository
                .findByTickerAndTradeDateBetweenOrderByTradeDate(ticker, firstDate, lastDate);

        List<StockPrice> aligned = new ArrayList<>(spxList.size());
        int p = 0;
        for (StockPrice spx : spxList) {
            LocalDate d = spx.getTradeDate();
            while (p < raw.size() && !raw.get(p).getTradeDate().isAfter(d)) {
                current = raw.get(p);
                p++;
            }
            aligned.add(current);
        }
        return aligned;
    }

    // 시작일(1라운드)에 종목 가격이 없는 카드 = 상장 전 종목 카드 → 이 세션에서 사용 불가
    // (Python game_logic.available_card_ids()와 같은 규칙)
    private Set<Integer> getUnavailableCardIds(PriceTable prices) {
        Set<Integer> unavailable = new HashSet<>();
        if (prices.spx.isEmpty()) return unavailable;
        for (Card card : cardRepository.findAll()) {
            // 1라운드 날짜 이전(포함)에 데이터가 하나라도 있으면 상장 (기간 제한 없음, Python과 동일)
            if (prices.at(card.getTicker(), 0) == null) {
                unavailable.add(card.getId());
            }
        }
        return unavailable;
    }

    private List<Integer> getRandomCards(List<Integer> appliedCardIds, Set<Integer> unavailableCardIds) {
        List<Integer> available = new ArrayList<>(ALL_CARD_IDS);
        available.removeAll(appliedCardIds);
        available.removeAll(unavailableCardIds);   // 상장 전 종목 카드는 제시하지 않음
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

    // =============================================
    // 라운드별 제시 후보 (11주차)
    // =============================================
    // "1:3,4,10|25:7,8,2" → {1: [3,4,10], 25: [7,8,2]}
    private Map<Integer, List<Integer>> parseOfferedCards(String str) {
        Map<Integer, List<Integer>> map = new LinkedHashMap<>();
        if (str == null || str.isBlank()) return map;
        for (String entry : str.split("\\|")) {
            String[] parts = entry.split(":");
            if (parts.length != 2 || parts[1].isBlank()) continue;
            List<Integer> ids = Arrays.stream(parts[1].split(","))
                    .map(String::trim)
                    .map(Integer::parseInt)
                    .collect(Collectors.toList());
            map.put(Integer.parseInt(parts[0].trim()), ids);
        }
        return map;
    }

    private String serializeOfferedCards(Map<Integer, List<Integer>> map) {
        return map.entrySet().stream()
                .sorted(Map.Entry.comparingByKey())
                .map(e -> e.getKey() + ":" + e.getValue().stream()
                        .map(String::valueOf)
                        .collect(Collectors.joining(",")))
                .collect(Collectors.joining("|"));
    }

    // 해당 라운드 후보를 세션에 기록 (같은 라운드가 이미 있으면 덮어씀)
    private void recordOfferedCards(GameSession session, int round, List<Integer> cardIds) {
        Map<Integer, List<Integer>> map = parseOfferedCards(session.getOfferedCards());
        map.put(round, new ArrayList<>(cardIds));
        session.updateOfferedCards(serializeOfferedCards(map));
    }

    // =============================================
    // 위기 대응 기록 (#125)
    // =============================================
    // "10:SELL_HALF|20:HOLD" → {10: "SELL_HALF", 20: "HOLD"}
    private Map<Integer, String> parseDecisions(String str) {
        Map<Integer, String> map = new TreeMap<>();
        if (str == null || str.isBlank()) return map;
        for (String entry : str.split("\\|")) {
            String[] parts = entry.split(":");
            if (parts.length != 2 || parts[1].isBlank()) continue;
            map.put(Integer.parseInt(parts[0].trim()), parts[1].trim());
        }
        return map;
    }

    private String serializeDecisions(Map<Integer, String> map) {
        return map.entrySet().stream()
                .sorted(Map.Entry.comparingByKey())
                .map(e -> e.getKey() + ":" + e.getValue())
                .collect(Collectors.joining("|"));
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
