package com.capstone.survival;

import com.capstone.survival.service.CsvImportService;
import com.capstone.survival.service.ScenarioDataChecker;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.stereotype.Component;

@Slf4j
@Component
@RequiredArgsConstructor
public class CsvImportRunner implements ApplicationRunner {

    private final CsvImportService csvImportService;
    private final ScenarioDataChecker scenarioDataChecker;

    @Override
    public void run(ApplicationArguments args) {
        log.info("===== CSV 데이터 적재 시작 =====");
        csvImportService.importAll();
        log.info("===== CSV 데이터 적재 완료 =====");

        // (11주차) 시나리오별 실제 게임 기간 가격 검사 — 실패 시 서버 기동 중단
        log.info("===== 시나리오 데이터 검사 시작 =====");
        scenarioDataChecker.checkAll();
        log.info("===== 시나리오 데이터 검사 완료 =====");
    }
}