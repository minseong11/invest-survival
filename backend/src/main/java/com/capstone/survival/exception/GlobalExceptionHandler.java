package com.capstone.survival.exception;

import com.capstone.survival.dto.ApiResponse;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

/**
 * (11주차) 잘못된 요청을 500 대신 400으로 응답
 * - IllegalArgumentException: 존재하지 않는 세션·카드, 이미 선택한 카드,
 *   제시되지 않은 후보 카드, 차례가 아닌 라운드 등 → 400 + 메시지
 * - 그 외 예외는 기존처럼 Spring 기본 처리(500)
 */
@RestControllerAdvice
public class GlobalExceptionHandler {

    @ExceptionHandler(IllegalArgumentException.class)
    public ResponseEntity<ApiResponse<?>> handleBadRequest(IllegalArgumentException e) {
        return ResponseEntity.status(HttpStatus.BAD_REQUEST).body(ApiResponse.fail(e.getMessage()));
    }
}