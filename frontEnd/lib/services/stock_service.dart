import 'package:dio/dio.dart';

// 데이터 모델 클래스
class StockPrice {
  final int? id;
  final String ticker;
  final double price;

  StockPrice({this.id, required this.ticker, required this.price});

  factory StockPrice.fromJson(Map<String, dynamic> json) {
    return StockPrice(
      id: json['id'],
      ticker: json['ticker'] ?? 'Unknown',
      price: (json['price'] ?? 0.0).toDouble(),
    );
  }
}

// API 통신 서비스 클래스
class StockService {
  final Dio _dio = Dio(BaseOptions(
    baseUrl: 'http://10.38.67.231:8080/',
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 3),
  ));

  Future<List<StockPrice>> getAllPrices() async {
    try {
      final response =
          await _dio.get('/api/price'); // http://10.38.67.231:8080/api/price
      if (response.statusCode == 200) {
        List<dynamic> data = response.data;
        return data.map((json) => StockPrice.fromJson(json)).toList();
      } else {
        throw Exception("서버 응답 오류");
      }
    } catch (e) {
      print("통신 에러: $e");
      rethrow;
    }
  }
}
