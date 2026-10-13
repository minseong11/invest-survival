package com.capstone.survival.repository;

import com.capstone.survival.entity.StockPrice;
import org.springframework.data.jpa.repository.JpaRepository;

import java.time.LocalDate;
import java.util.List;
import java.util.Optional;

public interface StockPriceRepository extends JpaRepository<StockPrice, Long> {

    // 중복 체크용 (기존)
    boolean existsByTickerAndTradeDate(String ticker, LocalDate tradeDate);

    // 시나리오 기간 주가 조회 (게임 시작 시 사용)
    List<StockPrice> findByTickerAndTradeDateBetweenOrderByTradeDate(
            String ticker, LocalDate startDate, LocalDate endDate
    );

    // 특정 날짜 이후 주가 조회 (라운드 진행 시 사용)
    List<StockPrice> findByTickerAndTradeDateGreaterThanEqualOrderByTradeDate(
            String ticker, LocalDate startDate
    );

    // 특정 날짜 이전(포함) 가장 최근 주가 — 상장 여부 판단, 직전 거래일 가격 조회용
    Optional<StockPrice> findTopByTickerAndTradeDateLessThanEqualOrderByTradeDateDesc(
            String ticker, LocalDate tradeDate
    );
}
