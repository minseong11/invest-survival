package com.capstone.survival.repository;

import com.capstone.survival.entity.Scenario;
import org.springframework.data.jpa.repository.JpaRepository;

public interface ScenarioRepository extends JpaRepository<Scenario, Integer> {
}