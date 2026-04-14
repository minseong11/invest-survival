package com.capstone.survival.service;

import com.capstone.survival.entity.StockPrice;
import com.capstone.survival.repository.StockPriceRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.io.BufferedReader;
import java.io.FileReader;
import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

@Slf4j
@Service
@RequiredArgsConstructor
public class CsvImportService {

    private final StockPriceRepository stockPriceRepository;

    // CSV 파일 경로와 ticker 매핑
    private static final Map<String, String> CSV_FILES = Map.ofEntries(
            Map.entry("^SPX",   "data/^spx_d.csv"),
            Map.entry("^NDX",   "data/^ndx_d.csv"),
            Map.entry("^KOSPI", "data/^kospi_d.csv"),
            Map.entry("XAUUSD", "data/xauusd_d.csv"),
            Map.entry("USO",    "data/uso_d.csv"),
            Map.entry("AAPL",   "data/aapl_d.csv"),
            Map.entry("TLT",    "data/tlt_d.csv")
    );

    /**
     * 전체 CSV 파일 일괄 임포트
     * 앱 첫 실행 시 한 번만 돌리면 됨
     */
    public void importAll() {
        for (Map.Entry<String, String> entry : CSV_FILES.entrySet()) {
            String ticker  = entry.getKey();
            String csvPath = entry.getValue();
            try {
                log.info("[임포트 시작] ticker={}", ticker);
                int count = importCsv(ticker, csvPath);
                log.info("[임포트 완료] ticker={}, 저장건수={}", ticker, count);
            } catch (Exception e) {
                log.error("[임포트 실패] ticker={}, error={}", ticker, e.getMessage());
            }
        }
    }

    /**
     * 단일 CSV 파일 파싱 후 DB 저장
     * STOOQ CSV 형식: Date,Open,High,Low,Close,Volume
     */
    @Transactional
    public int importCsv(String ticker, String csvPath) throws Exception {

        List<StockPrice> batch = new ArrayList<>();
        DateTimeFormatter fmt = DateTimeFormatter.ofPattern("yyyy-MM-dd");

        try (BufferedReader br = new BufferedReader(new FileReader(csvPath))) {
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
                    batch.clear();
                }
            }

            // 남은 데이터 저장
            if (!batch.isEmpty()) {
                stockPriceRepository.saveAll(batch);
            }
        }

        return (int) stockPriceRepository.count();
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