package com.capstone.survival.entity;

import jakarta.persistence.*;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.time.LocalDate;

@Entity
@Table(
        name = "stock_price",
        uniqueConstraints = @UniqueConstraint(columnNames = {"ticker", "trade_date"})
)
@Getter
@NoArgsConstructor
public class StockPrice {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false)
    private String ticker;       // ex) ^SPX, ^NDX, ^KOSPI

    @Column(name = "trade_date", nullable = false)
    private LocalDate tradeDate;

    private Double open;
    private Double high;
    private Double low;

    @Column(nullable = false)
    private Double close;

    @Column(name = "adj_close")
    private Double adjClose;

    private Long volume;

    public StockPrice(String ticker, LocalDate tradeDate,
                      Double open, Double high, Double low,
                      Double close, Double adjClose, Long volume) {
        this.ticker = ticker;
        this.tradeDate = tradeDate;
        this.open = open;
        this.high = high;
        this.low = low;
        this.close = close;
        this.adjClose = adjClose;
        this.volume = volume;
    }
}


