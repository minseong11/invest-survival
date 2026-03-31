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
    private String description; // "2008년 금융위기..."
    private String colorHex;    // "FAECE7"
    private String ticker;      // "^SPX" (내부 로직용)
    private String startDate;   // "2008-09-01"
    private String endDate;     // "2009-03-09"
}