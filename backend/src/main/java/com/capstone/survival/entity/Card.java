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
}