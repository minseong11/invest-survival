import 'package:dio/dio.dart';

class ApiClient {
  //static const String _baseUrl = 'http://172.22.165.231:8080';
  //static const String _baseUrl = 'http://172.18.16.192:8080';
  static const String _baseUrl = 'http://172.18.81.118:8080';
  

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
      throw Exception('백엔드 오류: $message');
    }
  }

  // ① 네트워크 오류 + ③ HTTP 상태코드 오류
  Exception _handleDioError(DioException e) {
    switch (e.type) {
      // ① 네트워크 오류 — 서버 꺼짐, 와이파이 없음
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
        return Exception('네트워크 오류: 연결 시간 초과');
      case DioExceptionType.connectionError:
        return Exception('네트워크 오류: 서버에 연결할 수 없어요');

      // ③ HTTP 상태코드 오류 — 400, 500 등
      case DioExceptionType.badResponse:
        final statusCode = e.response?.statusCode;
        return Exception('HTTP 오류: $statusCode');

      default:
        return Exception('네트워크 오류: ${e.message}');
    }
  }
}