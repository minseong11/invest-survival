package com.capstone.survival.controller;

import com.capstone.survival.dto.ApiResponse;
import com.capstone.survival.entity.StockPrice;
import com.capstone.survival.repository.StockPriceRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDate;
import java.util.List;

@RestController
@CrossOrigin(origins = "*")
@RequestMapping("/api/stock")
@RequiredArgsConstructor
public class StockPriceController {

    private final StockPriceRepository repository;

    // GET http://localhost:8080/api/stock/price?ticker=%5ESPX&startDate=2008-01-01&endDate=2008-12-31
    @GetMapping("/price")
    public ApiResponse<List<StockPrice>> getPrice(
            @RequestParam String ticker,
            @RequestParam String startDate,
            @RequestParam String endDate
    ) {
        List<StockPrice> result = repository
                .findByTickerAndTradeDateBetweenOrderByTradeDate(
                        ticker,
                        LocalDate.parse(startDate),
                        LocalDate.parse(endDate)
                );
        return ApiResponse.ok(result);
    }

    // GET /api/stock/tickers
    @GetMapping("/tickers")
    public ApiResponse<List<String>> getTickers() {
        List<String> tickers = List.of("^SPX", "^NDX", "^KOSPI", "XAUUSD");
        return ApiResponse.ok(tickers);
    }
}