package com.capstone.survival;

import com.capstone.survival.service.CsvImportService;
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

    @Override
    public void run(ApplicationArguments args) {
        log.info("===== CSV 데이터 적재 시작 =====");
        csvImportService.importAll();
        log.info("===== CSV 데이터 적재 완료 =====");
    }
}