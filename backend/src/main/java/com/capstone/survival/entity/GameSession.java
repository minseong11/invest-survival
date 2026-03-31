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
    }
}