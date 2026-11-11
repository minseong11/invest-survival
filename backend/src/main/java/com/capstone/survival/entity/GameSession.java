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

    @Column(name = "created_at")
    private LocalDateTime createdAt;

    // 기존 필드들 아래에 추가
    private Long cash;              // 현재 현금
    private Double spxShares;       // 보유 SPX 수량
    private Double ndxShares;
    private Double xauusdShares;
    private Double usoShares;
    private Double aaplShares;
    private Double tltShares;
    private Integer currentRound;   // 현재 라운드
    private String appliedCards;    // 적용된 카드 목록 "1,2"

    @Column(name = "trigger_count")
    private String triggerCount;
    // ↑ 카드별 발동 횟수 저장 "6:2" → 카드6번이 2회 발동됨

    @Column(name = "offered_cards")
    private String offeredCards;
    // ↑ (11주차) 라운드별로 제시한 카드 후보 "1:3,4,10|25:7,8,2|50:...|75:..."
    //   카드 선택 검증과 사후 분석("받은 후보 안에서의 최선")에 사용

    public GameSession(String sessionId, Integer scenarioId,
                       String scenarioTitle, String ticker,
                       String gameStartDate) {
        this.sessionId = sessionId;
        this.scenarioId = scenarioId;
        this.scenarioTitle = scenarioTitle;
        this.ticker = ticker;
        this.totalRounds = 100;
        this.initialAsset = 10_000_000L;
        this.status = "PLAYING";
        this.gameStartDate = gameStartDate;
        this.createdAt = LocalDateTime.now();
        this.cash = 10_000_000L;
        this.spxShares = 0.0;
        this.ndxShares = 0.0;
        this.xauusdShares = 0.0;
        this.usoShares = 0.0;
        this.aaplShares = 0.0;
        this.tltShares = 0.0;
        this.currentRound = 1;
        this.appliedCards = "";
        this.triggerCount = "";
        this.offeredCards = "";
    }

    // 라운드별 제시 후보 갱신 (직렬화는 GameService에서)
    public void updateOfferedCards(String offeredCards) {
        this.offeredCards = offeredCards;
    }

    // 상태 업데이트 메서드 추가
    public void update(Long cash, Double spxShares, Double ndxShares,
                       Double xauusdShares, Double usoShares,
                       Double aaplShares, Double tltShares,
                       Integer currentRound,
                       String appliedCards, String triggerCount) {
        this.cash = cash;
        this.spxShares = spxShares;
        this.ndxShares = ndxShares;
        this.xauusdShares = xauusdShares;
        this.usoShares = usoShares;
        this.aaplShares = aaplShares;
        this.tltShares = tltShares;
        this.currentRound = currentRound;
        this.appliedCards = appliedCards;
        this.triggerCount = triggerCount;
    }

    // 게임 종료 처리 (75라운드 카드 선택 후 100라운드까지 계산이 끝났을 때)
    public void finish() {
        this.status = "FINISHED";
    }
}