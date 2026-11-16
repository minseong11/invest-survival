package com.capstone.survival.repository;

import com.capstone.survival.entity.StockPrice;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.LocalDate;
import java.util.List;
import java.util.Optional;

public interface StockPriceRepository extends JpaRepository<StockPrice, Long> {

    // 시나리오 기간 주가 조회 (게임 시작 시 사용)
    List<StockPrice> findByTickerAndTradeDateBetweenOrderByTradeDate(
            String ticker, LocalDate startDate, LocalDate endDate
    );

    // 특정 날짜 이후 주가 조회 (라운드 진행 시 사용)
    List<StockPrice> findByTickerAndTradeDateGreaterThanEqualOrderByTradeDate(
            String ticker, LocalDate startDate
    );

    // (#125) 특정 날짜부터 100거래일 — 게임 100라운드에 필요한 만큼만 읽는다
    //   (기존에는 시작일부터 데이터 끝까지 전부 읽어, 닷컴 시나리오는 요청마다 종목당 6천 행 넘게 읽었음)
    List<StockPrice> findTop100ByTickerAndTradeDateGreaterThanEqualOrderByTradeDate(
            String ticker, LocalDate startDate
    );

    // (#125) 특정 날짜 직전 21거래일 (최근 순) — 시작 전 브리핑의 20거래일 등락 계산용
    List<StockPrice> findTop21ByTickerAndTradeDateLessThanOrderByTradeDateDesc(
            String ticker, LocalDate tradeDate
    );

    // (#125) 종목의 저장된 날짜 전체 — CSV 임포트에서 중복 확인을 한 번에 하기 위해
    @Query("select s.tradeDate from StockPrice s where s.ticker = :ticker")
    List<LocalDate> findTradeDatesByTicker(@Param("ticker") String ticker);

    // 특정 날짜 이전(포함) 가장 최근 주가 — 상장 여부 판단, 직전 거래일 가격 조회용
    Optional<StockPrice> findTopByTickerAndTradeDateLessThanEqualOrderByTradeDateDesc(
            String ticker, LocalDate tradeDate
    );
}
