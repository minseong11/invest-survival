import 'package:dio/dio.dart';

// 화면에 그대로 보여줄 수 있는 오류 (toString이 메시지만 반환)
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

class ApiClient {
  //static const String _baseUrl = 'http://172.22.165.231:8080';
  //static const String _baseUrl = 'http://172.18.16.192:8080';
  //static const String _baseUrl = 'http://172.18.81.118:8080';정민기
  //static const String _baseUrl = 'http://172.18.107.48:8080';
    static const String _baseUrl = 'http://localhost:8080';

  

  final Dio _dio = Dio(BaseOptions(
    baseUrl: _baseUrl,
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 5),
  ));

  Future<dynamic> get(String path) async {
    try {
      final response = await _dio.get(path);
      return _parseResponse(response);
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  // receiveTimeout: 기본 5초보다 오래 걸리는 요청만 따로 지정
  // (예: 사후 분석 백테스팅은 서버 계산에 약 3.7초 → 여유를 두고 30초)
  Future<dynamic> post(
    String path, {
    Map<String, dynamic>? body,
    Duration? receiveTimeout,
  }) async {
    try {
      final response = await _dio.post(
        path,
        data: body,
        options: receiveTimeout != null
            ? Options(receiveTimeout: receiveTimeout)
            : null,
      );
      return _parseResponse(response);
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  // ② 백엔드 논리 오류
  // success: false 이면 message를 꺼내서 던짐
  // ex) {"success": false, "message": "해당 세션이 없습니다"}
  dynamic _parseResponse(Response response) {
    final body = response.data;

    if (body is Map && body['success'] == true) {
      return body['data'];
    } else {
      final message =
          body is Map ? body['message'] ?? '알 수 없는 오류' : '알 수 없는 오류';
      throw ApiException('$message');
    }
  }

  // ① 네트워크 오류 + ③ HTTP 상태코드 오류
  Exception _handleDioError(DioException e) {
    switch (e.type) {
      // ① 네트워크 오류 — 서버 꺼짐, 와이파이 없음
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
        return ApiException('서버 응답이 늦어요. 잠시 후 다시 시도해 주세요');
      case DioExceptionType.connectionError:
        return ApiException('서버에 연결할 수 없어요');

      // ③ HTTP 상태코드 오류 — 400, 500 등
      //   (11주차) 서버가 잘못된 요청에 400 + {"success":false,"message":...}를 주므로 message를 그대로 표시
      case DioExceptionType.badResponse:
        final statusCode = e.response?.statusCode;
        final data = e.response?.data;
        final serverMessage =
            data is Map && data['message'] is String ? data['message'] as String : null;
        if (serverMessage != null && serverMessage.isNotEmpty) {
          return ApiException(serverMessage, statusCode: statusCode);
        }
        return ApiException(
          statusCode != null && statusCode >= 500
              ? '서버에 문제가 생겼어요 ($statusCode)'
              : '요청을 처리할 수 없어요 ($statusCode)',
          statusCode: statusCode,
        );

      default:
        return ApiException('네트워크 오류: ${e.message}');
    }
  }
}