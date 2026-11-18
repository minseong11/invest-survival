package com.capstone.survival.service;

import com.capstone.survival.entity.Card;
import com.capstone.survival.entity.Scenario;
import com.capstone.survival.entity.StockPrice;
import com.capstone.survival.repository.CardRepository;
import com.capstone.survival.repository.NewsEventRepository;
import com.capstone.survival.repository.ScenarioRepository;
import com.capstone.survival.repository.StockPriceRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.junit.jupiter.api.io.TempDir;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;
import org.springframework.data.domain.Sort;
import org.springframework.test.util.ReflectionTestUtils;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.DayOfWeek;
import java.time.LocalDate;
import java.util.*;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.when;

/**
 * (12주차) 교수님 피드백 3번 — 기동 실패와 복구를 자동으로 재현한다.
 *
 *  1) 빈 DB에서 필수 종목 CSV 하나를 빼면 서버가 원인·해결 방법과 함께 기동을 멈추고,
 *     CSV를 되돌리면 정상 기동한다 (CsvImportService).
 *  2) 종목 데이터가 "있는지"만으로는 부족하다: CSV가 있어도 시나리오 기간 중 실제 라운드 날짜의
 *     가격이 비어 있으면 기동을 멈춘다 (ScenarioDataChecker).
 *
 *  실제 DB 대신 메모리 속 가격 표(prices)를 쓰고, 저장소 메서드는 그 표를 읽고 쓰도록 연결한다.
 */
@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
class StartupDataCheckTest {

    private static final LocalDate DATA_START = LocalDate.of(2008, 6, 2);
    private static final LocalDate DATA_END   = LocalDate.of(2009, 5, 29);
    private static final LocalDate GAME_START = LocalDate.of(2008, 9, 1);

    // ticker → CSV 파일 이름 (CsvImportService와 같은 값)
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

    @Mock StockPriceRepository stockPriceRepository;
    @Mock ScenarioRepository scenarioRepository;
    @Mock CardRepository cardRepository;
    @Mock NewsEventRepository newsEventRepository;

    @TempDir Path csvDir;

    /** 메모리 속 DB: ticker → 날짜순 가격 */
    private final Map<String, TreeMap<LocalDate, StockPrice>> db = new HashMap<>();

    private CsvImportService importer;
    private ScenarioDataChecker checker;

    @BeforeEach
    void setUp() {
        importer = new CsvImportService(stockPriceRepository);
        ReflectionTestUtils.setField(importer, "csvDir", csvDir.toString());
        checker = new ScenarioDataChecker(scenarioRepository, cardRepository,
                stockPriceRepository, newsEventRepository);

        when(stockPriceRepository.findTradeDatesByTicker(anyString()))
                .thenAnswer(inv -> new ArrayList<>(table(inv.getArgument(0)).keySet()));
        when(stockPriceRepository.saveAll(anyList())).thenAnswer(inv -> {
            List<StockPrice> batch = inv.getArgument(0);
            for (StockPrice p : batch) {
                db.computeIfAbsent(p.getTicker(), t -> new TreeMap<>()).put(p.getTradeDate(), p);
            }
            return batch;
        });
        when(stockPriceRepository.findTopByTickerAndTradeDateLessThanEqualOrderByTradeDateDesc(anyString(), any()))
                .thenAnswer(inv -> Optional.ofNullable(table(inv.getArgument(0))
                        .floorEntry(inv.<LocalDate>getArgument(1))).map(Map.Entry::getValue));
        when(stockPriceRepository.findByTickerAndTradeDateBetweenOrderByTradeDate(anyString(), any(), any()))
                .thenAnswer(inv -> new ArrayList<>(table(inv.getArgument(0))
                        .subMap(inv.getArgument(1), true, inv.getArgument(2), true).values()));

        when(scenarioRepository.findAll(any(Sort.class))).thenReturn(List.of(scenario()));
        when(cardRepository.findAll(any(Sort.class))).thenReturn(cards());
        when(newsEventRepository.findByScenarioIdOrderByEventDate(anyInt())).thenReturn(List.of());
    }

    private TreeMap<LocalDate, StockPrice> table(String ticker) {
        return db.getOrDefault(ticker, new TreeMap<>());
    }

    // ── 1) 빈 DB + CSV 하나 빼기 → 기동 중단 → 복원 → 정상 ─────────────────

    @Test
    void 빈_DB에서_필수_종목_CSV가_하나_없으면_원인과_해결_방법을_알리고_기동을_멈춘다() throws IOException {
        writeAllCsv();
        Files.delete(csvDir.resolve("uso_d.csv"));          // 원유(USO) CSV 하나를 뺀다

        assertThatThrownBy(() -> importer.importAll())
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("필수 주가 데이터 준비 실패로 서버를 시작하지 않습니다")
                .hasMessageContaining("USO: CSV 파일 없음")
                .hasMessageContaining(csvDir.resolve("uso_d.csv").toString())   // 찾아본 경로
                .hasMessageContaining("해결:");
    }

    @Test
    void 뺀_CSV를_되돌리면_다시_정상_기동한다() throws IOException {
        writeAllCsv();
        Files.delete(csvDir.resolve("uso_d.csv"));
        assertThatThrownBy(() -> importer.importAll()).isInstanceOf(IllegalStateException.class);

        writeCsv("USO", weekdays(DATA_START, DATA_END));    // 복원
        assertThatCode(() -> importer.importAll()).doesNotThrowAnyException();
        assertThatCode(() -> checker.checkAll()).doesNotThrowAnyException();
        assertThat(table("USO")).isNotEmpty();
    }

    @Test
    void 게임에_쓰지_않는_코스피_CSV는_없어도_기동한다() throws IOException {
        writeAllCsv();
        Files.delete(csvDir.resolve("^kospi_d.csv"));
        assertThatCode(() -> importer.importAll()).doesNotThrowAnyException();
    }

    // ── 2) 종목 데이터가 "있어도" 실제 라운드 날짜의 가격이 비면 기동 중단 ─────

    @Test
    void 종목_데이터가_있어도_게임_기간_중_가격이_비면_기동을_멈춘다() throws IOException {
        // 채권(TLT) CSV는 있지만 2008-10-06 ~ 2008-10-31 4주가 빠져 있다
        writeAllCsv();
        List<LocalDate> tlt = new ArrayList<>(weekdays(DATA_START, DATA_END));
        tlt.removeIf(d -> !d.isBefore(LocalDate.of(2008, 10, 6)) && !d.isAfter(LocalDate.of(2008, 10, 31)));
        writeCsv("TLT", tlt);

        // 종목별 존재 검사(CSV 임포트)는 통과한다 — TLT 데이터가 "있기는" 하므로
        assertThatCode(() -> importer.importAll()).doesNotThrowAnyException();

        // 실제 사용 날짜 검사에서 걸린다
        assertThatThrownBy(() -> checker.checkAll())
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("시나리오 기간의 주가 데이터가 부족해 서버를 시작하지 않습니다")
                .hasMessageContaining("TLT: 가격이 7일 넘게 빈 라운드")
                .hasMessageContaining("2008-10-03");                     // 마지막으로 가격이 있던 날
    }

    @Test
    void 라운드_기준인_SP500이_100거래일보다_짧으면_기동을_멈춘다() throws IOException {
        writeAllCsv();
        writeCsv("^SPX", weekdays(DATA_START, LocalDate.of(2008, 12, 31)));   // 게임 시작 후 약 85거래일뿐

        assertThatCode(() -> importer.importAll()).doesNotThrowAnyException();
        assertThatThrownBy(() -> checker.checkAll())
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("^SPX")
                .hasMessageContaining("필요 100개");
    }

    @Test
    void 게임_시작_전에_상장되지_않은_종목은_오류가_아니라_그_카드만_제외한다() throws IOException {
        writeAllCsv();
        writeCsv("AAPL", weekdays(LocalDate.of(2008, 11, 3), DATA_END));    // 게임 시작 뒤부터 데이터

        assertThatCode(() -> importer.importAll()).doesNotThrowAnyException();
        assertThatCode(() -> checker.checkAll()).doesNotThrowAnyException();
    }

    // ── 데이터 만들기 ──────────────────────────────────────────

    private void writeAllCsv() throws IOException {
        for (String ticker : CSV_FILES.keySet()) {
            writeCsv(ticker, weekdays(DATA_START, DATA_END));
        }
    }

    private void writeCsv(String ticker, List<LocalDate> dates) throws IOException {
        StringBuilder sb = new StringBuilder("Date,Open,High,Low,Close,Volume\n");
        double price = 100;
        for (LocalDate d : dates) {
            price *= 1.001;
            String v = String.format(Locale.ROOT, "%.4f", price);
            sb.append(d).append(',').append(v).append(',').append(v).append(',')
              .append(v).append(',').append(v).append(",1000\n");
        }
        Files.writeString(csvDir.resolve(CSV_FILES.get(ticker)), sb.toString(), StandardCharsets.UTF_8);
        db.remove(ticker);   // 테스트마다 "빈 DB"에서 시작: 이 종목은 CSV로만 들어온다
    }

    private static List<LocalDate> weekdays(LocalDate from, LocalDate to) {
        List<LocalDate> out = new ArrayList<>();
        for (LocalDate d = from; !d.isAfter(to); d = d.plusDays(1)) {
            if (d.getDayOfWeek() != DayOfWeek.SATURDAY && d.getDayOfWeek() != DayOfWeek.SUNDAY) out.add(d);
        }
        return out;
    }

    private Scenario scenario() {
        Scenario s = new Scenario();
        ReflectionTestUtils.setField(s, "id", 1);
        ReflectionTestUtils.setField(s, "title", "테스트 위기");
        ReflectionTestUtils.setField(s, "ticker", "^SPX");
        ReflectionTestUtils.setField(s, "startDate", GAME_START.toString());
        ReflectionTestUtils.setField(s, "endDate", DATA_END.toString());
        return s;
    }

    private List<Card> cards() {
        List<Card> out = new ArrayList<>();
        String[] tickers = {"^SPX", "XAUUSD", "^SPX", "XAUUSD", "^NDX", "^NDX", "USO", "^SPX", "AAPL", "TLT", "^NDX"};
        for (int i = 0; i < tickers.length; i++) {
            Card c = new Card();
            ReflectionTestUtils.setField(c, "id", i + 1);
            ReflectionTestUtils.setField(c, "name", "카드 " + (i + 1));
            ReflectionTestUtils.setField(c, "ticker", tickers[i]);
            out.add(c);
        }
        return out;
    }
}
