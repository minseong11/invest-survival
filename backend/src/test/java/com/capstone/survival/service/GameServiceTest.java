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
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpMethod;
import org.springframework.http.ResponseEntity;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.web.client.ResourceAccessException;
import org.springframework.web.client.RestTemplate;

import java.time.DayOfWeek;
import java.time.LocalDate;
import java.util.*;
import java.util.concurrent.Executor;
import java.util.function.Function;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.contains;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.when;

/**
 * (#125) 게임 계산·진행 테스트 — DB·AI 서버 없이 실행
 *
 * 저장소(Repository)를 가짜로 바꾸고 손으로 만든 가격을 넣어, 규칙을 손계산한 값과 비교한다.
 * (Python 계산과 원 단위까지 같은지는 서버를 띄워서 compare_java_python.py --strict로 확인한다)
 *
 * 가격 설정: 모든 평일이 거래일, 기본 가격은 종목마다 100으로 고정.
 *           테스트마다 필요한 라운드에만 등락을 넣는다 (1라운드 = 2008-09-01).
 */
@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
class GameServiceTest {

    private static final LocalDate DATA_START = LocalDate.of(2008, 7, 1);
    private static final LocalDate GAME_START = LocalDate.of(2008, 9, 1);
    private static final List<String> TICKERS = List.of("^SPX", "^NDX", "XAUUSD", "USO", "AAPL", "TLT");

    @Mock GameSessionRepository sessionRepository;
    @Mock ScenarioRepository scenarioRepository;
    @Mock StockPriceRepository stockPriceRepository;
    @Mock CardRepository cardRepository;
    @Mock NewsEventRepository newsEventRepository;
    @Mock RestTemplate restTemplate;

    private GameService service;
    private final Map<String, List<StockPrice>> prices = new HashMap<>();
    private final Map<String, GameSession> sessions = new HashMap<>();
    private final List<NewsEvent> news = new ArrayList<>();
    private final List<Map<String, Object>> aiRequests = new ArrayList<>();   // AI 서버로 보낸 요청 본문
    private final List<String> aiPaths = new ArrayList<>();
    private Function<String, Map<String, Object>> aiResponse = path -> null;  // 경로 → 응답 (null이면 빈 응답)

    @BeforeEach
    void setUp() {
        service = new GameService(sessionRepository, scenarioRepository, stockPriceRepository,
                cardRepository, newsEventRepository, restTemplate);
        ReflectionTestUtils.setField(service, "aiServerUrl", "http://ai");
        // 미리 계산 요청을 다른 스레드가 아니라 그 자리에서 보낸다.
        // 다른 스레드가 가짜 AI 서버(restTemplate)를 부르는 동안 테스트가 when(...)으로 응답을 바꾸면
        // Mockito가 그 스레드의 호출에 응답을 붙여, 가끔 다른 응답이 돌아왔다 (CI에서 간헐적 실패)
        ReflectionTestUtils.setField(service, "prewarmExecutor", (Executor) Runnable::run);

        for (String ticker : TICKERS) {
            setPrices(ticker, Map.of());
        }

        when(stockPriceRepository.findTop100ByTickerAndTradeDateGreaterThanEqualOrderByTradeDate(anyString(), any()))
                .thenAnswer(inv -> list(inv.getArgument(0)).stream()
                        .filter(p -> !p.getTradeDate().isBefore(inv.getArgument(1)))
                        .limit(100).toList());
        when(stockPriceRepository.findByTickerAndTradeDateBetweenOrderByTradeDate(anyString(), any(), any()))
                .thenAnswer(inv -> list(inv.getArgument(0)).stream()
                        .filter(p -> !p.getTradeDate().isBefore(inv.getArgument(1))
                                && !p.getTradeDate().isAfter(inv.getArgument(2)))
                        .toList());
        when(stockPriceRepository.findTopByTickerAndTradeDateLessThanEqualOrderByTradeDateDesc(anyString(), any()))
                .thenAnswer(inv -> list(inv.getArgument(0)).stream()
                        .filter(p -> !p.getTradeDate().isAfter(inv.getArgument(1)))
                        .reduce((a, b) -> b));
        when(stockPriceRepository.findTop21ByTickerAndTradeDateLessThanOrderByTradeDateDesc(anyString(), any()))
                .thenAnswer(inv -> {
                    List<StockPrice> before = new ArrayList<>(list(inv.getArgument(0)).stream()
                            .filter(p -> p.getTradeDate().isBefore(inv.getArgument(1))).toList());
                    Collections.reverse(before);
                    return before.stream().limit(21).toList();
                });

        when(cardRepository.findAll()).thenReturn(cards());
        when(scenarioRepository.findById(1)).thenReturn(Optional.of(scenario()));
        when(newsEventRepository.findByScenarioIdOrderByEventDate(1)).thenAnswer(inv -> news);

        when(sessionRepository.save(any())).thenAnswer(inv -> {
            GameSession s = inv.getArgument(0);
            sessions.put(s.getSessionId(), s);
            return s;
        });
        when(sessionRepository.findById(anyString()))
                .thenAnswer(inv -> Optional.ofNullable(sessions.get(inv.<String>getArgument(0))));

        when(restTemplate.exchange(anyString(), eq(HttpMethod.POST), any(HttpEntity.class), eq(Map.class)))
                .thenAnswer(inv -> {
                    String path = inv.<String>getArgument(0).replace("http://ai", "");
                    @SuppressWarnings("unchecked")
                    Map<String, Object> body = (Map<String, Object>) inv.<HttpEntity<?>>getArgument(2).getBody();
                    synchronized (aiRequests) {
                        aiPaths.add(path);
                        aiRequests.add(body);
                    }
                    return ResponseEntity.ok(aiResponse.apply(path));
                });
    }

    // ── 가격·데이터 만들기 ──────────────────────────────────────

    /** 라운드 번호(1부터) → 그 라운드의 전일 대비 등락률(%). 나머지 날은 가격 그대로 */
    private void setPrices(String ticker, Map<Integer, Double> movesByRound) {
        List<StockPrice> list = new ArrayList<>();
        double price = 100.0;
        int round = 0;
        for (LocalDate d = DATA_START; d.isBefore(LocalDate.of(2009, 6, 1)); d = d.plusDays(1)) {
            if (d.getDayOfWeek() == DayOfWeek.SATURDAY || d.getDayOfWeek() == DayOfWeek.SUNDAY) continue;
            if (!d.isBefore(GAME_START)) round++;
            Double move = movesByRound.get(round);
            if (move != null && !d.isBefore(GAME_START)) price = price * (1 + move / 100);
            list.add(new StockPrice(ticker, d, price, price, price, price, null, 1L));
        }
        prices.put(ticker, list);
    }

    /** 게임 시작 전 가격을 따로 지정 (시작 전 브리핑 확인용) */
    private void setPreStartPrice(String ticker, double price) {
        List<StockPrice> list = new ArrayList<>();
        for (StockPrice p : prices.get(ticker)) {
            double v = p.getTradeDate().isBefore(GAME_START.minusDays(40)) ? price : p.getClose();
            list.add(new StockPrice(ticker, p.getTradeDate(), v, v, v, v, null, 1L));
        }
        prices.put(ticker, list);
    }

    private List<StockPrice> list(String ticker) {
        return prices.getOrDefault(ticker, List.of());
    }

    private LocalDate dateOfRound(int round) {
        return prices.get("^SPX").stream()
                .filter(p -> !p.getTradeDate().isBefore(GAME_START))
                .skip(round - 1).findFirst().orElseThrow().getTradeDate();
    }

    private void addNews(int id, int round, String level, boolean decision) {
        NewsEvent e = new NewsEvent();
        ReflectionTestUtils.setField(e, "id", id);
        ReflectionTestUtils.setField(e, "scenarioId", 1);
        ReflectionTestUtils.setField(e, "eventDate", dateOfRound(round));
        ReflectionTestUtils.setField(e, "headline", "테스트 뉴스 " + round + "라운드");
        ReflectionTestUtils.setField(e, "level", level);
        ReflectionTestUtils.setField(e, "source", "테스트");
        ReflectionTestUtils.setField(e, "sourceUrl", "https://example.com");
        ReflectionTestUtils.setField(e, "decision", decision);
        news.add(e);
    }

    private Scenario scenario() {
        Scenario s = new Scenario();
        ReflectionTestUtils.setField(s, "id", 1);
        ReflectionTestUtils.setField(s, "title", "테스트 위기");
        ReflectionTestUtils.setField(s, "ticker", "^SPX");
        ReflectionTestUtils.setField(s, "intro", "테스트 배경");
        ReflectionTestUtils.setField(s, "startDate", GAME_START.toString());
        ReflectionTestUtils.setField(s, "endDate", "2009-05-29");
        return s;
    }

    // data.sql의 카드 규칙과 같은 값
    private List<Card> cards() {
        return List.of(
                card(1, "거인의 어깨", "^SPX", 0.30, "BUY_ONCE", null, null, 1),
                card(2, "황금 적립", "XAUUSD", 0.05, "BUY_SPLIT", null, null, 2),
                card(3, "공포탐욕", "^SPX", 0.20, "BUY_ON_CONDITION", "SPX_CHANGE <= -3", null, 3),
                card(4, "금 피난처", "XAUUSD", 0.15, "BUY_ON_CONDITION", "SPX_CHANGE <= -5", null, 4),
                card(5, "기술의 파도", "^NDX", 0.10, "BUY_ON_CONDITION", "NDX_CHANGE >= 2", null, 5),
                card(6, "낙폭과대 사냥", "^NDX", 0.25, "BUY_ON_CONDITION", "NDX_CHANGE <= -4", 3, 6),
                card(7, "원유 베팅", "USO", 0.20, "BUY_ONCE", null, null, 7),
                card(8, "역발상 투자", "^SPX", 0.15, "SELL_ON_CONDITION", "SPX_CHANGE >= 3", null, 1),
                card(9, "애플 줍줍", "AAPL", 0.10, "BUY_ON_CONDITION", "AAPL_CHANGE <= -5", 5, 9),
                card(10, "채권 피난처", "TLT", 0.03, "BUY_SPLIT", null, null, 10),
                card(11, "분할매수 장인", "^NDX", 0.10, "BUY_EVERY_N", null, null, 11));
    }

    private Card card(int id, String name, String ticker, double ratio, String type,
                      String condition, Integer maxTrigger, int priority) {
        Card c = new Card();
        ReflectionTestUtils.setField(c, "id", id);
        ReflectionTestUtils.setField(c, "name", name);
        ReflectionTestUtils.setField(c, "ticker", ticker);
        ReflectionTestUtils.setField(c, "ratio", ratio);
        ReflectionTestUtils.setField(c, "type", type);
        ReflectionTestUtils.setField(c, "condition", condition);
        ReflectionTestUtils.setField(c, "maxTrigger", maxTrigger);
        ReflectionTestUtils.setField(c, "priority", priority);
        return c;
    }

    // ── 응답 읽기 ───────────────────────────────────────────────

    @SuppressWarnings("unchecked")
    private List<Map<String, Object>> rounds(Map<String, Object> response) {
        return (List<Map<String, Object>>) response.get("rounds");
    }

    private long asset(Map<String, Object> round) {
        return ((Number) round.get("roundAsset")).longValue();
    }

    @SuppressWarnings("unchecked")
    private List<Integer> triggered(Map<String, Object> round) {
        return (List<Integer>) round.get("triggeredCards");
    }

    @SuppressWarnings("unchecked")
    private List<Map<String, Object>> skipped(Map<String, Object> round) {
        return (List<Map<String, Object>>) round.get("skippedCards");
    }

    private List<Integer> roundsWhere(Map<String, Object> game, java.util.function.Predicate<Map<String, Object>> p) {
        return rounds(game).stream().filter(p).map(r -> (Integer) r.get("round")).toList();
    }

    private Map<String, Object> validate(Map<Integer, Integer> cards) {
        return service.validateGame(GAME_START.toString(), cards, new TreeMap<>(), "^SPX");
    }

    // =============================================
    // 카드 규칙 (validateGame: 100라운드를 한 번에 계산)
    // =============================================

    @Test
    void 카드가_없으면_현금_그대로() {
        setPrices("^SPX", Map.of(10, -8.0, 20, 6.0));
        Map<String, Object> game = validate(Map.of());

        assertThat(rounds(game)).hasSize(100);
        assertThat(rounds(game)).allMatch(r -> asset(r) == 10_000_000L);
        assertThat(game.get("final_asset")).isEqualTo(10_000_000L);
    }

    @Test
    void 즉시_매수_카드는_고른_라운드_종가로_현금의_30퍼센트를_산다() {
        setPrices("^SPX", Map.of(51, 100.0));            // 51라운드에 가격 2배
        Map<String, Object> game = validate(Map.of(1, 1));

        assertThat(asset(rounds(game).get(0))).isEqualTo(10_000_000L);
        assertThat(asset(rounds(game).get(49))).isEqualTo(10_000_000L);
        assertThat(game.get("final_asset")).isEqualTo(13_000_000L);    // 현금 700만 + 300만 × 2
        assertThat(game.get("final_return_rate")).isEqualTo(30.0);
    }

    @Test
    void 조건부_카드는_조건이_맞는_날에만_산다() {
        // 공포탐욕: S&P500 -3% 이하. -2.99%는 발동하지 않는다
        setPrices("^SPX", Map.of(10, -3.0, 20, -2.99, 30, -5.0, 40, 4.0));
        Map<String, Object> game = validate(Map.of(1, 3));

        assertThat(roundsWhere(game, r -> triggered(r).contains(3))).containsExactly(10, 30);
    }

    @Test
    void 최대_횟수를_다_쓰면_건너뛰고_이유를_남긴다() {
        // 낙폭과대 사냥: 나스닥 -4% 이하, 최대 3회
        setPrices("^NDX", Map.of(10, -4.0, 20, -5.0, 30, -4.5, 40, -6.0, 50, -4.0));
        Map<String, Object> game = validate(Map.of(1, 6));

        assertThat(roundsWhere(game, r -> triggered(r).contains(6))).containsExactly(10, 20, 30);
        assertThat(roundsWhere(game, r -> !skipped(r).isEmpty())).containsExactly(40, 50);
        assertThat(skipped(rounds(game).get(39)).get(0))
                .containsEntry("cardId", 6).containsEntry("reason", "MAX_REACHED");
    }

    @Test
    void 매도_카드는_팔_주식이_없으면_발동이_아니라_건너뜀() {
        // 역발상 투자: S&P500 +3% 이상인 날 보유 S&P500의 15% 매도
        setPrices("^SPX", Map.of(10, 3.5, 20, 4.0));
        Map<String, Object> game = validate(Map.of(1, 8));

        assertThat(roundsWhere(game, r -> triggered(r).contains(8))).isEmpty();
        assertThat(roundsWhere(game, r -> !skipped(r).isEmpty())).containsExactly(10, 20);
        assertThat(skipped(rounds(game).get(9)).get(0)).containsEntry("reason", "NO_HOLDINGS");
        assertThat(game.get("final_asset")).isEqualTo(10_000_000L);
    }

    @Test
    void 매도_카드는_보유_수량의_15퍼센트를_판다() {
        setPrices("^SPX", Map.of(30, 5.0));
        Map<String, Object> game = validate(Map.of(1, 1, 25, 8));

        assertThat(roundsWhere(game, r -> triggered(r).contains(8))).containsExactly(30);
        Map<String, Object> last = rounds(game).get(99);
        // 현금 = 700만 + 30,000주 × 15% × 105
        assertThat(((Number) last.get("cash")).longValue()).isEqualTo(7_000_000L + (long) (30_000 * 0.15 * 105.0));
    }

    @Test
    void 매_라운드_사는_카드는_현금이_총자산의_5퍼센트_아래면_쉰다() {
        // 황금 적립: 매 라운드 현금의 5%. 0.95^59 < 0.05 → 59번 사고 나머지는 현금 부족
        Map<String, Object> game = validate(Map.of(1, 2));

        assertThat(roundsWhere(game, r -> triggered(r).contains(2))).hasSize(59);
        assertThat(roundsWhere(game, r -> !skipped(r).isEmpty())).hasSize(41);
        assertThat(skipped(rounds(game).get(99)).get(0)).containsEntry("reason", "CASH_LOW");
    }

    @Test
    void 다섯_라운드마다_사는_카드는_고른_뒤부터_5의_배수_라운드에_산다() {
        Map<String, Object> game = validate(Map.of(25, 11));

        List<Integer> expected = new ArrayList<>();
        for (int r = 25; r <= 100; r += 5) expected.add(r);
        assertThat(roundsWhere(game, r -> triggered(r).contains(11))).isEqualTo(expected);
    }

    @Test
    void 보유_자산_비중과_현금_비중의_합은_100() {
        setPrices("^SPX", Map.of(10, -4.0, 30, 6.0));
        Map<String, Object> game = validate(Map.of(1, 1, 25, 2, 50, 3, 75, 10));

        for (Map<String, Object> r : rounds(game)) {
            @SuppressWarnings("unchecked")
            List<Map<String, Object>> holdings = (List<Map<String, Object>>) r.get("holdings");
            double sum = holdings.stream().mapToDouble(h -> ((Number) h.get("weight")).doubleValue()).sum()
                    + ((Number) r.get("cashWeight")).doubleValue();
            assertThat(sum).isCloseTo(100.0, org.assertj.core.data.Offset.offset(0.011));
        }
    }

    // =============================================
    // 위기 대응
    // =============================================

    @Test
    void 절반_판다는_보유_종목을_절반씩_그날_종가에_판다() {
        setPrices("^SPX", Map.of(10, -20.0));            // 10라운드에 80으로 하락
        Map<String, Object> game = service.validateGame(GAME_START.toString(), Map.of(1, 1),
                new TreeMap<>(Map.of(10, "SELL_HALF")), "^SPX");

        Map<String, Object> last = rounds(game).get(99);
        assertThat(((Number) last.get("cash")).longValue()).isEqualTo(7_000_000L + 15_000L * 80);
    }

    @Test
    void 더_산다는_현금의_30퍼센트로_기준_지수를_산다() {
        setPrices("^NDX", Map.of(10, -50.0, 60, 100.0)); // 10라운드에 50, 60라운드에 다시 100
        Map<String, Object> game = service.validateGame(GAME_START.toString(), Map.of(),
                new TreeMap<>(Map.of(10, "BUY_MORE")), "^NDX");

        // 300만원어치를 50에 사서 100이 되면 600만원 → 700만 + 600만
        assertThat(game.get("final_asset")).isEqualTo(13_000_000L);
    }

    @Test
    void 버틴다는_아무것도_바꾸지_않는다() {
        setPrices("^SPX", Map.of(10, -8.0, 40, 5.0));
        Map<String, Object> base = validate(Map.of(1, 1, 25, 3));
        Map<String, Object> held = service.validateGame(GAME_START.toString(), Map.of(1, 1, 25, 3),
                new TreeMap<>(Map.of(10, "HOLD", 60, "HOLD")), "^SPX");

        assertThat(rounds(held).stream().map(this::asset).toList())
                .isEqualTo(rounds(base).stream().map(this::asset).toList());
    }

    @Test
    void 잘못된_위기_대응은_거절한다() {
        assertThatThrownBy(() -> service.validateGame(GAME_START.toString(), Map.of(1, 1),
                new TreeMap<>(Map.of(25, "HOLD")), "^SPX"))
                .isInstanceOf(IllegalArgumentException.class).hasMessageContaining("카드 선택 라운드가 아닌");
        assertThatThrownBy(() -> service.validateGame(GAME_START.toString(), Map.of(1, 1),
                new TreeMap<>(Map.of(10, "PANIC")), "^SPX"))
                .isInstanceOf(IllegalArgumentException.class).hasMessageContaining("알 수 없는 위기 대응");
    }

    // =============================================
    // 게임 진행 (시작 → 카드·위기 대응 → 종료)
    // =============================================

    @Test
    void 시작_응답에_위기_대응_라운드와_시작_전_브리핑이_있다() {
        addNews(1, 10, "danger", true);
        addNews(2, 25, "danger", true);      // 카드 선택 라운드에 걸린 속보 → 위기 대응 없이 일반 뉴스
        addNews(3, 40, "caution", false);
        addNews(4, 60, "positive", true);
        setPreStartPrice("USO", 125.0);      // 시작 전 20거래일 동안 125 → 100 (-20%)

        Map<String, Object> start = service.startGame(1);

        assertThat(start.get("decisionRounds")).isEqualTo(List.of(10, 60));
        assertThat(start.get("buyMoreTarget")).isEqualTo("S&P500");
        assertThat((List<?>) start.get("firstCardOptions")).hasSize(3);

        @SuppressWarnings("unchecked")
        Map<String, Object> briefing = (Map<String, Object>) start.get("briefing");
        assertThat(briefing.get("intro")).isEqualTo("테스트 배경");
        assertThat(briefing.get("days")).isEqualTo(20);
        assertThat((List<?>) briefing.get("spxSeries")).hasSize(21);
        @SuppressWarnings("unchecked")
        List<Map<String, Object>> assets = (List<Map<String, Object>>) briefing.get("assets");
        assertThat(assets).hasSize(6);
        assertThat(assets.get(0)).containsEntry("name", "S&P500").containsEntry("changeRate", 0.0);
    }

    @Test
    void 라운드마다_보유하지_않은_종목의_가격도_보내고_상장_전_종목은_뺀다() {
        // 원유(USO)는 30라운드 날짜부터 상장된 것으로 둔다
        LocalDate listed = dateOfRound(30);
        prices.put("USO", list("USO").stream().filter(p -> !p.getTradeDate().isBefore(listed)).toList());

        Map<String, Object> start = service.startGame(1);
        String sid = (String) start.get("sessionId");
        // 1라운드: 아직 아무것도 갖고 있지 않아도 상장된 모든 종목의 가격이 온다
        assertThat(tickers(rounds(start).get(0))).containsExactly("^SPX", "^NDX", "XAUUSD", "AAPL", "TLT");

        // 무엇을 골라도 갖고 있지 않은 종목까지 모두 온다 (기존: S&P500 + 보유 종목만)
        @SuppressWarnings("unchecked")
        List<Integer> options = (List<Integer>) start.get("firstCardOptions");
        Map<String, Object> r1 = service.selectCard(sid, 1, options.get(0));
        @SuppressWarnings("unchecked")
        Map<String, Object> r25 = service.selectCard(sid, 25, ((List<Integer>) r1.get("nextCardOptions")).get(0));
        List<Map<String, Object>> played = new ArrayList<>(rounds(r1));
        played.addAll(rounds(r25));
        assertThat(played).hasSize(49);                 // 1~49라운드 (30라운드 전후 모두 포함)
        for (Map<String, Object> round : played) {
            int n = (Integer) round.get("round");
            if (n < 30) {
                assertThat(tickers(round)).as(n + "라운드").containsExactly("^SPX", "^NDX", "XAUUSD", "AAPL", "TLT");
            } else {
                assertThat(tickers(round)).as(n + "라운드").containsExactlyElementsOf(TICKERS);
            }
        }
    }

    @SuppressWarnings("unchecked")
    private List<String> tickers(Map<String, Object> round) {
        return ((List<Map<String, Object>>) round.get("priceData")).stream()
                .map(p -> (String) p.get("ticker")).toList();
    }

    @Test
    void 카드_선택과_위기_대응_라운드에서만_멈추고_100라운드까지_진행된다() {
        addNews(1, 10, "danger", true);
        addNews(2, 60, "positive", true);
        setPrices("^SPX", Map.of(10, -5.0, 30, 4.0));

        Map<String, Object> start = service.startGame(1);
        String sid = (String) start.get("sessionId");
        @SuppressWarnings("unchecked")
        List<Integer> options = (List<Integer>) start.get("firstCardOptions");

        // 1라운드 카드 → 다음은 10라운드 위기 대응
        Map<String, Object> r1 = service.selectCard(sid, 1, options.get(0));
        assertThat(r1.get("nextEventRound")).isEqualTo(10);
        assertThat(r1.get("nextEventType")).isEqualTo("DECISION");
        assertThat(r1.get("nextCardOptions")).isNull();
        assertThat(roundsWhere(r1, r -> true)).first().isEqualTo(1);
        assertThat(roundsWhere(r1, r -> true)).last().isEqualTo(9);
        @SuppressWarnings("unchecked")
        Map<String, Object> prompt = (Map<String, Object>) r1.get("nextDecision");
        assertThat(prompt.get("round")).isEqualTo(10);
        assertThat(((Map<?, ?>) prompt.get("news")).get("headline")).isEqualTo("테스트 뉴스 10라운드");

        // 위기 대응 라운드에는 카드를 고를 수 없고, 카드 라운드가 아니면 위기 대응도 할 수 없다
        assertThatThrownBy(() -> service.selectCard(sid, 10, 2))
                .isInstanceOf(IllegalArgumentException.class).hasMessageContaining("카드 선택 라운드가 아닙니다");
        assertThatThrownBy(() -> service.decide(sid, 10, "PANIC"))
                .isInstanceOf(IllegalArgumentException.class).hasMessageContaining("알 수 없는 위기 대응");
        assertThatThrownBy(() -> service.decide(sid, 11, "HOLD"))
                .isInstanceOf(IllegalArgumentException.class).hasMessageContaining("10라운드 차례");

        // 10라운드 위기 대응 → 다음은 25라운드 카드
        Map<String, Object> r10 = service.decide(sid, 10, "SELL_HALF");
        assertThat(r10.get("decision")).isEqualTo("SELL_HALF");
        assertThat(r10.get("nextEventRound")).isEqualTo(25);
        assertThat(r10.get("nextEventType")).isEqualTo("CARD");
        @SuppressWarnings("unchecked")
        List<Integer> options25 = (List<Integer>) r10.get("nextCardOptions");
        assertThat(options25).hasSize(3).doesNotContain(options.get(0));
        assertThatThrownBy(() -> service.decide(sid, 25, "HOLD"))
                .isInstanceOf(IllegalArgumentException.class).hasMessageContaining("위기 대응 라운드가 아닙니다");

        // 제시되지 않은 카드·이미 고른 카드는 거절
        int notOffered = cards().stream().map(Card::getId)
                .filter(id -> !options25.contains(id) && !id.equals(options.get(0))).findFirst().orElseThrow();
        assertThatThrownBy(() -> service.selectCard(sid, 25, notOffered))
                .isInstanceOf(IllegalArgumentException.class).hasMessageContaining("제시된 카드가 아닙니다");

        Map<String, Object> r25 = service.selectCard(sid, 25, options25.get(0));
        assertThat(r25.get("nextEventRound")).isEqualTo(50);
        @SuppressWarnings("unchecked")
        Map<String, Object> r50 = service.selectCard(sid, 50, ((List<Integer>) r25.get("nextCardOptions")).get(0));
        assertThat(r50.get("nextEventRound")).isEqualTo(60);
        assertThat(r50.get("nextEventType")).isEqualTo("DECISION");

        Map<String, Object> r60 = service.decide(sid, 60, "HOLD");
        assertThat(r60.get("nextEventRound")).isEqualTo(75);
        @SuppressWarnings("unchecked")
        Map<String, Object> r75 = service.selectCard(sid, 75, ((List<Integer>) r60.get("nextCardOptions")).get(0));
        assertThat(r75.get("nextEventRound")).isNull();
        assertThat(roundsWhere(r75, r -> true)).last().isEqualTo(100);

        GameSession session = sessions.get(sid);
        assertThat(session.getStatus()).isEqualTo("FINISHED");
        assertThat(session.getDecisions()).isEqualTo("10:SELL_HALF|60:HOLD");
        assertThatThrownBy(() -> service.selectCard(sid, 100, 1))
                .isInstanceOf(IllegalArgumentException.class).hasMessageContaining("이미 종료된 게임");

        // 이어 붙인 100라운드 = 같은 선택으로 한 번에 계산한 결과
        List<Long> played = new ArrayList<>();
        for (Map<String, Object> part : List.of(r1, r10, r25, r50, r60, r75)) {
            rounds(part).forEach(r -> played.add(asset(r)));
        }
        Map<Integer, Integer> picked = new TreeMap<>();
        String[] applied = session.getAppliedCards().split(",");
        int[] cardRounds = {1, 25, 50, 75};
        for (int i = 0; i < 4; i++) picked.put(cardRounds[i], Integer.parseInt(applied[i]));
        Map<String, Object> oneShot = service.validateGame(GAME_START.toString(), picked,
                new TreeMap<>(Map.of(10, "SELL_HALF", 60, "HOLD")), "^SPX");
        assertThat(played).hasSize(100).isEqualTo(rounds(oneShot).stream().map(this::asset).toList());
    }

    @Test
    void 없는_세션과_빈_값은_400으로_응답할_예외() {
        assertThatThrownBy(() -> service.startGame(null))
                .isInstanceOf(IllegalArgumentException.class).hasMessageContaining("scenarioId");
        assertThatThrownBy(() -> service.startGame(99))
                .isInstanceOf(IllegalArgumentException.class).hasMessageContaining("존재하지 않는 시나리오");
        assertThatThrownBy(() -> service.selectCard("none", 1, 1))
                .isInstanceOf(IllegalArgumentException.class).hasMessageContaining("존재하지 않는 세션");
        assertThatThrownBy(() -> service.analyzeResult(null))
                .isInstanceOf(IllegalArgumentException.class).hasMessageContaining("sessionId");
    }

    // =============================================
    // AI 서버 연동
    // =============================================

    private String playUntilRound25() {
        addNews(1, 10, "danger", true);
        Map<String, Object> start = service.startGame(1);
        String sid = (String) start.get("sessionId");
        @SuppressWarnings("unchecked")
        List<Integer> options = (List<Integer>) start.get("firstCardOptions");
        service.selectCard(sid, 1, options.get(0));
        service.decide(sid, 10, "BUY_MORE");
        return sid;
    }

    @Test
    void AI_예측은_25와_50라운드만_가능하고_서버에_기록된_카드를_쓴다() {
        String sid = playUntilRound25();
        aiResponse = path -> switch (path) {
            case "/ai/v2/recommend" -> Map.of(
                    "recommendedCardId", 3,
                    "rankings", List.of(Map.of("rank", 1, "cardId", 3, "contribution", 1.4)),
                    "modelVersion", "v2_B");
            case "/ai/v2/feedback" -> Map.of("feedback", "지금 시장: 테스트");
            default -> Map.of();
        };

        assertThatThrownBy(() -> service.recommendV2(sid, 75, List.of(), List.of(1, 2, 3)))
                .isInstanceOf(IllegalArgumentException.class).hasMessageContaining("25·50라운드에서만");
        assertThatThrownBy(() -> service.recommendV2(sid, 50, List.of(), List.of(1, 2, 3)))
                .isInstanceOf(IllegalArgumentException.class).hasMessageContaining("지금은 25라운드");

        // 앱이 엉뚱한 목록을 보내도 서버에 기록된 보유 카드·후보 카드로 요청한다
        Map<String, Object> result = service.recommendV2(sid, 25, List.of(99), List.of(97, 98, 99));
        assertThat(result.get("recommendedCardName")).isEqualTo("공포탐욕");
        assertThat(result.get("feedback")).isEqualTo("지금 시장: 테스트");

        Map<String, Object> request = aiRequests.get(aiPaths.indexOf("/ai/v2/recommend"));
        GameSession session = sessions.get(sid);
        assertThat(request.get("alreadyCards").toString()).isEqualTo("[" + session.getAppliedCards() + "]");
        assertThat(session.getOfferedCards()).contains("25:" + request.get("candidateCards").toString()
                .replace("[", "").replace("]", "").replace(" ", ""));
        assertThat(request.get("startDate")).isEqualTo(GAME_START.toString());
    }

    @Test
    void AI_서버가_꺼져_있으면_예측은_503용_예외_분석은_null() {
        String sid = playUntilRound25();
        when(restTemplate.exchange(contains("/ai/"), eq(HttpMethod.POST), any(HttpEntity.class), eq(Map.class)))
                .thenThrow(new ResourceAccessException("Connection refused"));

        assertThatThrownBy(() -> service.recommendV2(sid, 25, null, null))
                .isInstanceOf(AiServerException.class).hasMessageContaining("AI 서버에 연결할 수 없습니다");

        GameSession session = sessions.get(sid);
        ReflectionTestUtils.setField(session, "status", "FINISHED");
        ReflectionTestUtils.setField(session, "appliedCards", "1,2,3,4");
        assertThat(service.analyzeResult(sid)).isNull();
        assertThat(service.coachResult(sid)).isNull();
    }

    @Test
    void 사후_분석_요청에_위기_대응과_기준_지수를_함께_보낸다() {
        String sid = playUntilRound25();
        GameSession session = sessions.get(sid);
        ReflectionTestUtils.setField(session, "status", "FINISHED");
        ReflectionTestUtils.setField(session, "appliedCards", "1,2,3,4");
        ReflectionTestUtils.setField(session, "offeredCards", "1:1,5,6|25:2,7,8|50:3,9,10|75:4,11,5");

        Map<String, Object> combo = Map.of(
                "rank", 1, "tiedCount", 1, "finalAsset", 11_000_000, "finalReturnRate", 10.0, "topPercent", 0.1,
                "cardSelections", Map.of("1", 1, "25", 2, "50", 3, "75", 4));
        aiResponse = path -> switch (path) {
            case "/ai/analysis/backtest" -> Map.of(
                    "totalCombinations", 7920, "cardPoolSize", 11,
                    "topCombos", List.of(combo), "playerResult", combo,
                    "grade", "S",
                    "risk", Map.of("playerMdd", -3.0, "marketMdd", -9.0),
                    "cardReport", List.of(Map.of("round", 1, "cardId", 1, "effectReturnRate", 2.5)),
                    "decisionReview", Map.of(
                            "effectReturnRate", 1.2,
                            "rounds", List.of(Map.of("round", 10, "choice", "BUY_MORE", "alternatives", List.of()))));
            case "/ai/analysis/coach" -> Map.of("comment", "요약: 테스트\n다음엔: 테스트", "status", "fallback");
            default -> Map.of();
        };

        Map<String, Object> analysis = service.analyzeResult(sid);
        Map<String, Object> request = aiRequests.get(aiPaths.indexOf("/ai/analysis/backtest"));
        assertThat(request.get("decisions")).isEqualTo(Map.of("10", "BUY_MORE"));
        assertThat(request.get("baseTicker")).isEqualTo("^SPX");
        assertThat(request.get("playerCardSelections")).isEqualTo(Map.of("1", 1, "25", 2, "50", 3, "75", 4));
        assertThat(request.get("offeredCards")).isNotNull();

        assertThat(analysis.get("grade")).isEqualTo("S");
        assertThat(analysis.get("cardReport")).isNotNull();
        @SuppressWarnings("unchecked")
        List<Map<String, Object>> reviewed =
                (List<Map<String, Object>>) ((Map<String, Object>) analysis.get("decisionReview")).get("rounds");
        assertThat(reviewed.get(0)).containsEntry("headline", "테스트 뉴스 10라운드").containsEntry("level", "danger");
        @SuppressWarnings("unchecked")
        List<Map<String, Object>> comboCards =
                (List<Map<String, Object>>) ((Map<String, Object>) analysis.get("playerResult")).get("cards");
        assertThat(comboCards.get(1)).containsEntry("cardName", "황금 적립");

        Map<String, Object> coach = service.coachResult(sid);
        assertThat(coach.get("status")).isEqualTo("fallback");
        assertThat((String) coach.get("comment")).startsWith("요약:");
    }

    @Test
    void 끝나지_않은_게임은_분석할_수_없다() {
        String sid = playUntilRound25();
        assertThatThrownBy(() -> service.analyzeResult(sid))
                .isInstanceOf(IllegalArgumentException.class).hasMessageContaining("아직 종료되지 않은 게임");
    }

    @Test
    void 마지막_위기_대응이_끝나면_전체_조합_미리_계산을_요청한다() {
        playUntilRound25();      // 위기 대응은 10라운드 하나 → 그 대응 직후 요청
        int index = aiPaths.indexOf("/ai/analysis/prewarm");
        assertThat(index).isGreaterThanOrEqualTo(0);
        assertThat(aiRequests.get(index).get("decisions")).isEqualTo(Map.of("10", "BUY_MORE"));
        assertThat(aiRequests.get(index).get("startDate")).isEqualTo(GAME_START.toString());
    }

    @Test
    void 미리_계산_요청은_위기_대응_응답을_기다리게_하지_않는다() {
        List<Runnable> queued = new ArrayList<>();
        ReflectionTestUtils.setField(service, "prewarmExecutor", (Executor) queued::add);

        playUntilRound25();                                         // 위기 대응 응답은 이미 돌아왔지만
        assertThat(aiPaths).doesNotContain("/ai/analysis/prewarm");  // 미리 계산 요청은 아직 보내지 않았고
        assertThat(queued).hasSize(1);                              // 실행기에 따로 넘겨져 있다
        queued.forEach(Runnable::run);
        assertThat(aiPaths).contains("/ai/analysis/prewarm");
    }
}
