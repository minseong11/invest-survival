package com.capstone.survival.entity;

import jakarta.persistence.*;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.time.LocalDate;

/**
 * (11주차) 시나리오별 뉴스 이벤트 — data.sql에서 입력
 * - eventDate: 게임에 표시할 날짜 (주말·장 마감 후 발표는 다음 거래일로 이미 맞춰서 입력)
 *              거래일이 아니면 그 다음 S&P500 거래일 라운드에 표시
 * - level: danger / caution / positive (그날 뉴스 성격 기준, 결과 기준 아님)
 */
@Entity
@Table(name = "news_event")
@Getter
@NoArgsConstructor
public class NewsEvent {

    @Id
    private Integer id;

    @Column(name = "scenario_id", nullable = false)
    private Integer scenarioId;

    @Column(name = "event_date", nullable = false)
    private LocalDate eventDate;

    @Column(nullable = false, length = 200)
    private String headline;

    @Column(nullable = false, length = 20)
    private String level;

    @Column(nullable = false, length = 50)
    private String source;          // 화면 표시용 출처 이름 (예: "연준", "NPR")

    @Column(name = "source_url", nullable = false, length = 500)
    private String sourceUrl;
}