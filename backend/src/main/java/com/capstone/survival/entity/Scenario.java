package com.capstone.survival.entity;

import jakarta.persistence.*;
import lombok.Getter;
import lombok.NoArgsConstructor;

@Entity
@Table(name = "scenario")
@Getter
@NoArgsConstructor
public class Scenario {

    @Id
    private Integer id;

    private String title;       // "리먼브라더스 사태"
    private Integer year;       // 2008
    private Integer difficulty; // 1~5
    private String description; // 홈 화면 한 줄 설명 (게임이 시작되는 시점 기준, 결과를 미리 알려주지 않음)

    @Column(length = 500)
    private String intro;       // (#125) 시작 전 브리핑에 보여줄 배경 설명 (게임 시작일까지 알려진 사실만)
    private String colorHex;    // "FAECE7"
    private String ticker;      // "^SPX" (내부 로직용)
    private String startDate;   // "2008-09-01"
    private String endDate;     // "2009-03-09"
}