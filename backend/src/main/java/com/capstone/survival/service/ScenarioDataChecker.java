package com.capstone.survival.service;

import com.capstone.survival.entity.Card;
import com.capstone.survival.entity.NewsEvent;
import com.capstone.survival.entity.Scenario;
import com.capstone.survival.entity.StockPrice;
import com.capstone.survival.repository.CardRepository;
import com.capstone.survival.repository.NewsEventRepository;
import com.capstone.survival.repository.ScenarioRepository;
import com.capstone.survival.repository.StockPriceRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.Sort;
import org.springframework.stereotype.Service;

import java.time.LocalDate;
import java.time.temporal.ChronoUnit;
import java.util.*;

/**
 * (11주차) 서버 기동 시 시나리오별 실제 게임 기간 가격 데이터 검사 — 교수님 피드백 3번
 *
 * CSV 임포트(필수 종목 데이터가 "있는지") 다음 단계로, 시나리오마다 실제 게임 100라운드 날짜의 가격이 있는지 확인한다.
 *   1) 시나리오 기준 종목: 시작일~종료일 100거래일 이상 (GameService.startGame과 같은 기준)
 *   2) S&P500: 게임 시작일부터 100거래일 이상 (라운드 = S&P500 거래일)
 *   3) 카드 종목: 시작일 이전 데이터가 없으면 상장 전 → 카드 제외 (로그만)
 *               상장된 종목은 100라운드 각 날짜마다 직전 가격이 MAX_GAP_DAYS일 이내인지
 *               (게임은 빈 날짜에 직전 가격을 쓰므로, 오래 비어 있으면 가격이 멈춘 것처럼 계산됨)
 *   4) (11주차) 뉴스: 날짜가 1R~100R 안인지, level이 danger/caution/positive인지, 헤드라인·출처가 있는지
 * 하나라도 실패하면 원인을 모아 IllegalStateException → 서버 기동 중단
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class ScenarioDataChecker {

    private static final int GAME_ROUNDS = 100;
    private static final int MAX_GAP_DAYS = 7;              // 주말+연휴를 넘는 공백이면 빈 구간으로 판단
    private static final int WINDOW_CALENDAR_DAYS = 200;    // 100거래일 ≈ 145일 → 여유 있게 200일만 조회
    private static final Set<String> NEWS_LEVELS = Set.of("danger", "caution", "positive");

    private final ScenarioRepository scenarioRepository;
    private final CardRepository cardRepository;
    private final StockPriceRepository stockPriceRepository;
    private final NewsEventRepository newsEventRepository;

    public void checkAll() {
        List<Scenario> scenarios = scenarioRepository.findAll(Sort.by("id"));
        if (scenarios.isEmpty()) {
            throw new IllegalStateException("시나리오가 DB에 없습니다 (data.sql 실행 여부 확인)");
        }
        List<Card> cards = cardRepository.findAll(Sort.by("id"));

        List<String> failures = new ArrayList<>();
        for (Scenario scenario : scenarios) {
            failures.addAll(checkScenario(scenario, cards));
        }

        if (!failures.isEmpty()) {
            String message = "시나리오 기간의 주가 데이터가 부족해 서버를 시작하지 않습니다.\n  - "
                    + String.join("\n  - ", failures)
                    + "\n해결: 해당 종목 CSV가 시나리오 기간을 모두 포함하는지 확인하고 backend/data/의 파일을 교체하세요.";
            log.error(message);
            throw new IllegalStateException(message);
        }
        log.info("[시나리오 검사] 시나리오 {}개 모두 통과", scenarios.size());
    }

    private List<String> checkScenario(Scenario scenario, List<Card> cards) {
        List<String> failures = new ArrayList<>();
        String label = scenario.getId() + "번 " + scenario.getTitle();
        LocalDate start = LocalDate.parse(scenario.getStartDate());
        LocalDate end = LocalDate.parse(scenario.getEndDate());

        // 1) 시나리오 기준 종목 — startGame과 같은 기준 (부족하면 게임 시작 자체가 안 됨)
        List<StockPrice> base = stockPriceRepository
                .findByTickerAndTradeDateBetweenOrderByTradeDate(scenario.getTicker(), start, end);
        if (base.size() < GAME_ROUNDS) {
            failures.add(String.format("%s / %s: %s~%s 거래일 %d개 (필요 %d개)",
                    label, scenario.getTicker(), start, end, base.size(), GAME_ROUNDS));
            return failures;
        }
        LocalDate gameStart = base.get(0).getTradeDate();   // 세션의 gameStartDate와 같은 값

        // 2) S&P500 100거래일 — 라운드 날짜
        List<StockPrice> spx = stockPriceRepository.findByTickerAndTradeDateBetweenOrderByTradeDate(
                "^SPX", gameStart, gameStart.plusDays(WINDOW_CALENDAR_DAYS));
        if (spx.size() < GAME_ROUNDS) {
            failures.add(String.format("%s / ^SPX: 게임 시작일 %s부터 거래일 %d개 (필요 %d개)",
                    label, gameStart, spx.size(), GAME_ROUNDS));
            return failures;
        }
        List<LocalDate> roundDates = spx.subList(0, GAME_ROUNDS).stream()
                .map(StockPrice::getTradeDate)
                .toList();
        LocalDate firstDate = roundDates.get(0);
        LocalDate lastDate = roundDates.get(GAME_ROUNDS - 1);

        // 3) 카드 종목 — 상장 여부 + 라운드 날짜별 빈 구간
        Set<String> tickers = new LinkedHashSet<>();
        for (Card card : cards) {
            if (!"^SPX".equals(card.getTicker())) tickers.add(card.getTicker());
        }

        Set<String> unlisted = new LinkedHashSet<>();
        for (String ticker : tickers) {
            Optional<StockPrice> before = stockPriceRepository
                    .findTopByTickerAndTradeDateLessThanEqualOrderByTradeDateDesc(ticker, firstDate);
            if (before.isEmpty()) {          // 상장 전 → 게임에서 이 종목 카드는 제시하지 않음
                unlisted.add(ticker);
                continue;
            }

            List<StockPrice> raw = stockPriceRepository
                    .findByTickerAndTradeDateBetweenOrderByTradeDate(ticker, firstDate, lastDate);

            // GameService.loadAlignedPriceList와 같은 방식: 라운드 날짜마다 그날 이전(포함) 가장 최근 가격
            LocalDate latest = before.get().getTradeDate();
            int p = 0;
            List<String> gaps = new ArrayList<>();
            for (int i = 0; i < roundDates.size(); i++) {
                LocalDate d = roundDates.get(i);
                while (p < raw.size() && !raw.get(p).getTradeDate().isAfter(d)) {
                    latest = raw.get(p).getTradeDate();
                    p++;
                }
                long gap = ChronoUnit.DAYS.between(latest, d);
                if (gap > MAX_GAP_DAYS) {
                    gaps.add(String.format("%dR %s (마지막 가격 %s)", i + 1, d, latest));
                }
            }
            if (!gaps.isEmpty()) {
                failures.add(String.format("%s / %s: 가격이 %d일 넘게 빈 라운드 %d개 — 예: %s",
                        label, ticker, MAX_GAP_DAYS, gaps.size(),
                        String.join(", ", gaps.subList(0, Math.min(3, gaps.size())))));
            }
        }

        // 4) 뉴스
        failures.addAll(checkNews(scenario, label, roundDates));

        long usableCards = cards.stream().filter(c -> !unlisted.contains(c.getTicker())).count();
        log.info("[시나리오 검사] {}: 1R {} ~ 100R {}, 사용 가능 카드 {}/{}장, 상장 전 제외 종목 {}",
                label, firstDate, lastDate, usableCards, cards.size(),
                unlisted.isEmpty() ? "없음" : unlisted);
        return failures;
    }

    private List<String> checkNews(Scenario scenario, String label, List<LocalDate> roundDates) {
        List<String> failures = new ArrayList<>();
        LocalDate firstDate = roundDates.get(0);
        LocalDate lastDate = roundDates.get(roundDates.size() - 1);

        List<String> placed = new ArrayList<>();
        for (NewsEvent e : newsEventRepository.findByScenarioIdOrderByEventDate(scenario.getId())) {
            String id = "뉴스 " + e.getId() + "(" + e.getEventDate() + ")";
            if (!NEWS_LEVELS.contains(e.getLevel())) {
                failures.add(String.format("%s / %s: level '%s'은 danger·caution·positive 중 하나여야 함", label, id, e.getLevel()));
            }
            if (isBlank(e.getHeadline()) || isBlank(e.getSource()) || isBlank(e.getSourceUrl())) {
                failures.add(String.format("%s / %s: 헤드라인·출처 이름·출처 URL 중 빈 값이 있음", label, id));
            }
            if (e.getEventDate().isBefore(firstDate) || e.getEventDate().isAfter(lastDate)) {
                failures.add(String.format("%s / %s: 게임 기간(1R %s ~ 100R %s) 밖의 날짜", label, id, firstDate, lastDate));
                continue;
            }
            // 그날 또는 다음 거래일 라운드
            int round = 1;
            while (roundDates.get(round - 1).isBefore(e.getEventDate())) round++;
            placed.add(round + "R");
        }
        log.info("[시나리오 검사] {}: 뉴스 {}개 → {}", label, placed.size(), placed.isEmpty() ? "없음" : String.join(", ", placed));
        return failures;
    }

    private boolean isBlank(String s) {
        return s == null || s.isBlank();
    }
}