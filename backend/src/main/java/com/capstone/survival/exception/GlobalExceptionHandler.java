package com.capstone.survival.exception;

import com.capstone.survival.dto.ApiResponse;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

/**
 * 오류 응답을 {"success": false, "message": "..."} 형식으로 통일 — 앱은 message를 그대로 보여준다
 *
 * (11주차) 잘못된 요청을 500 대신 400으로 응답
 * - IllegalArgumentException: 존재하지 않는 세션·카드, 이미 선택한 카드,
 *   제시되지 않은 후보 카드, 차례가 아닌 라운드 등 → 400 + 메시지
 * (#125)
 * - 요청 본문이 비었거나 JSON이 아님 → 400 (값의 형식이 틀린 경우는 컨트롤러가 IllegalArgumentException으로 알림)
 * - AiServerException: AI 서버 연결 실패 → 503 + 메시지
 * - IllegalStateException: 주가 데이터 부족 등 서버 쪽 준비 문제 → 500 + 메시지
 * - 그 외 예외 → 500 + 일반 안내 문구 (내부 오류 문구를 그대로 내보내지 않음)
 */
@Slf4j
@RestControllerAdvice
public class GlobalExceptionHandler {

    @ExceptionHandler(IllegalArgumentException.class)
    public ResponseEntity<ApiResponse<?>> handleBadRequest(IllegalArgumentException e) {
        return ResponseEntity.status(HttpStatus.BAD_REQUEST).body(ApiResponse.fail(e.getMessage()));
    }

    @ExceptionHandler(HttpMessageNotReadableException.class)
    public ResponseEntity<ApiResponse<?>> handleMalformedRequest(HttpMessageNotReadableException e) {
        return ResponseEntity.status(HttpStatus.BAD_REQUEST)
                .body(ApiResponse.fail("요청 형식이 올바르지 않습니다"));
    }

    @ExceptionHandler(AiServerException.class)
    public ResponseEntity<ApiResponse<?>> handleAiServer(AiServerException e) {
        log.warn("[AI 서버 오류] {}", e.getMessage());
        return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE)
                .body(ApiResponse.fail("AI 서버에 연결할 수 없습니다. 잠시 후 다시 시도해 주세요"));
    }

    @ExceptionHandler(IllegalStateException.class)
    public ResponseEntity<ApiResponse<?>> handleServerState(IllegalStateException e) {
        log.error("[서버 상태 오류] {}", e.getMessage());
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(ApiResponse.fail(e.getMessage()));
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<ApiResponse<?>> handleUnexpected(Exception e) {
        log.error("[처리되지 않은 오류]", e);
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(ApiResponse.fail("서버에 문제가 생겼습니다. 잠시 후 다시 시도해 주세요"));
    }
}
