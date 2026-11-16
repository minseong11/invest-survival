package com.capstone.survival.exception;

/**
 * (#125) AI 서버(FastAPI) 호출 실패 — 연결 불가, 시간 초과, 오류 응답
 * GlobalExceptionHandler가 503 + 메시지로 응답한다 (기존에는 500 + 메시지 없음)
 */
public class AiServerException extends RuntimeException {
    public AiServerException(String message) {
        super(message);
    }
}
