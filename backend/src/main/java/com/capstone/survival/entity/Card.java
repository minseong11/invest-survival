package com.capstone.survival.entity;

import jakarta.persistence.*;
import lombok.Getter;
import lombok.NoArgsConstructor;

@Entity
@Table(name = "card")
@Getter
@NoArgsConstructor
public class Card {

    @Id
    private Integer id;

    private String name;       // "거인의 어깨"
    private String ticker;     // "^SPX"
    private Double ratio;      // 0.3 (자산의 30%)
    private String description; // "현재 자산의 30%로 S&P500 즉시 매수"

    // ↓ 새로 추가
    private String type;
    // BUY_ONCE         → 즉시 1회 매수
    // BUY_SPLIT        → 매 라운드 분할 매수
    // BUY_ON_CONDITION → 조건 충족 시 매수

    private String condition;
    // null             → 조건 없음
    // "SPX_CHANGE <= -3" → SPX 등락률 -3% 이하
    // "SPX_CHANGE <= -5" → SPX 등락률 -5% 이하
    // "NDX_CHANGE >= 2"  → NDX 등락률 +2% 이상
    // "NDX_CHANGE <= -4" → NDX 등락률 -4% 이하

    private Integer maxTrigger;
    // null → 무제한
    // 3    → 최대 3회
}