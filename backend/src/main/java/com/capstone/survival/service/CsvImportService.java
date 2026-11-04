package com.capstone.survival.service;

import com.capstone.survival.entity.StockPrice;
import com.capstone.survival.repository.StockPriceRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.io.BufferedReader;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

@Slf4j
@Service
@RequiredArgsConstructor
public class CsvImportService {

    private final StockPriceRepository stockPriceRepository;

    /**
     * CSV 폴더 경로 (application.yaml의 data.csv-dir)
     * - 상대 경로면 서버를 실행한 폴더 기준 → backend/에서 실행할 때 backend/data
     * - 다른 폴더에서 실행해야 하면 절대 경로로 지정
     */
    @Value("${data.csv-dir:data}")
    private String csvDir;

    // ticker → CSV 파일 이름 (순서 유지)
    private static final Map<String, String> CSV_FILES = new LinkedHashMap<>();
    static {
        CSV_FILES.put("^SPX",   "^spx_d.csv");
        CSV_FILES.put("^NDX",   "^ndx_d.csv");
        CSV_FILES.put("XAUUSD", "xauusd_d.csv");
        CSV_FILES.put("USO",    "uso_d.csv");
        CSV_FILES.put("AAPL",   "aapl_d.csv");
        CSV_FILES.put("TLT",    "tlt_d.csv");
        CSV_FILES.put("^KOSPI", "^kospi_d.csv");
    }

    // 게임(카드·시나리오)에 쓰는 종목 — 하나라도 준비되지 않으면 서버 기동 중단
    // ^KOSPI는 어느 카드도 쓰지 않으므로 실패해도 경고만 남김
    private static final Set<String> REQUIRED_TICKERS =
            Set.of("^SPX", "^NDX", "XAUUSD", "USO", "AAPL", "TLT");

    /**
     * 전체 CSV 파일 일괄 임포트 (서버 시작 시 CsvImportRunner가 호출)
     * - 이미 DB에 있는 날짜는 건너뜀 (재실행해도 중복 없음)
     * - CSV가 없어도 DB에 해당 종목 데이터가 이미 있으면 경고만 하고 계속
     * - 필수 종목의 CSV도 없고 DB에도 데이터가 없으면 IllegalStateException → 서버 기동 중단
     */
    public void importAll() {
        Path dir = Paths.get(csvDir).toAbsolutePath().normalize();
        log.info("[CSV 폴더] {} (설정값 data.csv-dir={})", dir, csvDir);

        List<String> failures = new ArrayList<>();

        for (Map.Entry<String, String> entry : CSV_FILES.entrySet()) {
            String ticker = entry.getKey();
            Path csvPath = dir.resolve(entry.getValue());
            boolean required = REQUIRED_TICKERS.contains(ticker);

            if (!Files.exists(csvPath)) {
                if (hasDataInDb(ticker)) {
                    log.warn("[임포트 건너뜀] ticker={}, CSV 없음({}) — DB에 기존 데이터가 있어 그대로 사용", ticker, csvPath);
                } else if (required) {
                    failures.add(String.format("%s: CSV 파일 없음 (%s), DB에도 데이터 없음", ticker, csvPath));
                } else {
                    log.warn("[임포트 건너뜀] ticker={}, CSV 없음({}) — 게임에 쓰지 않는 종목이라 계속 진행", ticker, csvPath);
                }
                continue;
            }

            try {
                log.info("[임포트 시작] ticker={}, file={}", ticker, csvPath);
                int saved = importCsv(ticker, csvPath);
                log.info("[임포트 완료] ticker={}, 새로 저장={}건", ticker, saved);
            } catch (Exception e) {
                if (required) {
                    failures.add(String.format("%s: 임포트 실패 (%s) — %s", ticker, csvPath, e.getMessage()));
                } else {
                    log.warn("[임포트 실패] ticker={}, error={} — 게임에 쓰지 않는 종목이라 계속 진행", ticker, e.getMessage());
                }
            }
        }

        if (!failures.isEmpty()) {
            String message = "필수 주가 데이터 준비 실패로 서버를 시작하지 않습니다.\n  - "
                    + String.join("\n  - ", failures)
                    + "\n해결: backend/ 폴더에서 서버를 실행하거나, application.yaml의 data.csv-dir에 CSV 폴더의 절대 경로를 지정하세요."
                    + "\n(CSV 파일은 git에 없으므로 README의 'git에 없는 파일'을 참고해 backend/data/에 넣어야 합니다.)";
            log.error(message);
            throw new IllegalStateException(message);
        }
    }

    /**
     * 단일 CSV 파일 파싱 후 DB 저장
     * STOOQ CSV 형식: Date,Open,High,Low,Close,Volume
     * @return 새로 저장한 건수 (이미 있던 날짜는 제외)
     */
    @Transactional
    public int importCsv(String ticker, Path csvPath) throws Exception {

        List<StockPrice> batch = new ArrayList<>();
        DateTimeFormatter fmt = DateTimeFormatter.ofPattern("yyyy-MM-dd");
        int saved = 0;

        try (BufferedReader br = Files.newBufferedReader(csvPath, StandardCharsets.UTF_8)) {
            String line;
            boolean isHeader = true;

            while ((line = br.readLine()) != null) {
                // 첫 줄 헤더 스킵
                if (isHeader) { isHeader = false; continue; }
                // 빈 줄 스킵
                if (line.isBlank()) continue;

                String[] cols = line.split(",");
                if (cols.length < 5) continue;

                LocalDate date = LocalDate.parse(cols[0].trim(), fmt);

                // 중복 데이터 스킵
                if (stockPriceRepository.existsByTickerAndTradeDate(ticker, date)) continue;

                Double open   = parseDouble(cols[1]);
                Double high   = parseDouble(cols[2]);
                Double low    = parseDouble(cols[3]);
                Double close  = parseDouble(cols[4]);
                // STOOQ는 Adj Close 없고 Volume이 5번째
                Double adjClose = null;
                Long   volume = cols.length > 5 ? parseLong(cols[5]) : null;

                if (close == null) continue; // close 없으면 스킵

                batch.add(new StockPrice(ticker, date, open, high, low, close, adjClose, volume));

                // 1000건마다 배치 저장 (메모리 관리)
                if (batch.size() >= 1000) {
                    stockPriceRepository.saveAll(batch);
                    saved += batch.size();
                    batch.clear();
                }
            }

            // 남은 데이터 저장
            if (!batch.isEmpty()) {
                stockPriceRepository.saveAll(batch);
                saved += batch.size();
            }
        }

        return saved;
    }

    // DB에 해당 종목 데이터가 하나라도 있는지 (오늘 이전 가장 최근 가격 존재 여부)
    private boolean hasDataInDb(String ticker) {
        return stockPriceRepository
                .findTopByTickerAndTradeDateLessThanEqualOrderByTradeDateDesc(ticker, LocalDate.now())
                .isPresent();
    }

    private Double parseDouble(String val) {
        try { return Double.parseDouble(val.trim()); }
        catch (Exception e) { return null; }
    }

    private Long parseLong(String val) {
        try { return Long.parseLong(val.trim()); }
        catch (Exception e) { return null; }
    }
}