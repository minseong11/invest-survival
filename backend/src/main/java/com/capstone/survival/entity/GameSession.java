package com.capstone.survival.entity;

import jakarta.persistence.*;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;

@Entity
@Table(name = "game_session")
@Getter
@NoArgsConstructor
public class GameSession {

    @Id
    private String sessionId;

    private Integer scenarioId;
    private String scenarioTitle;
    private String ticker;
    private Integer totalRounds;
    private Long initialAsset;
    private String status; // PLAYING, FINISHED
    private String gameStartDate;
    // 기존 필드들 아래에 추가
    private Long cash;              // 현재 현금
    private Double spxShares;       // 보유 SPX 수량
    private Integer currentRound;   // 현재 라운드
    private String appliedCards;    // 적용된 카드 목록 "1,2"

    @Column(name = "created_at")
    private LocalDateTime createdAt;

    public GameSession(String sessionId, Integer scenarioId, String scenarioTitle,
                       String ticker, String gameStartDate) {
        this.sessionId = sessionId;
        this.scenarioId = scenarioId;
        this.scenarioTitle = scenarioTitle;
        this.ticker = ticker;
        this.totalRounds = 10;
        this.initialAsset = 10_000_000L;
        this.status = "PLAYING";
        this.gameStartDate = gameStartDate;
        this.createdAt = LocalDateTime.now();
        this.cash = 10_000_000L;  // 초기 현금 = 초기 자산
        this.spxShares = 0.0;
        this.currentRound = 1;
        this.appliedCards = "";
    }

    // 상태 업데이트 메서드 추가
    public void update(Long cash, Double spxShares,
                       Integer currentRound, String appliedCards) {
        this.cash = cash;
        this.spxShares = spxShares;
        this.currentRound = currentRound;
        this.appliedCards = appliedCards;
    }
}