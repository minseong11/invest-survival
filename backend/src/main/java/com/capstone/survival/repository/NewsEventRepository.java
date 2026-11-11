package com.capstone.survival.repository;

import com.capstone.survival.entity.NewsEvent;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface NewsEventRepository extends JpaRepository<NewsEvent, Integer> {

    // 시나리오별 뉴스 (날짜순)
    List<NewsEvent> findByScenarioIdOrderByEventDate(Integer scenarioId);
}