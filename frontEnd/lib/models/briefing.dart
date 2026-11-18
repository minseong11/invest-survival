// =============================================
// (#125) 시작 전 브리핑 (서버 /game/start 응답의 briefing)
// 게임 시작일 직전 20거래일의 종목별 등락과 시나리오 배경.
// 게임이 시작되기 전의 정보만 담겨 있다 (게임 중에 알 수 없는 내용 없음).
// 서버가 보내지 않으면(예전 서버) null → 화면에서 해당 칸 생략
// =============================================
class BriefingAsset {
  final String ticker;
  final String name;
  final double changeRate; // 직전 20거래일 등락률(%)

  const BriefingAsset({
    required this.ticker,
    required this.name,
    required this.changeRate,
  });

  factory BriefingAsset.fromJson(Map<String, dynamic> json) => BriefingAsset(
        ticker:     (json['ticker'] ?? '') as String,
        name:       (json['name'] ?? '') as String,
        changeRate: (json['changeRate'] as num?)?.toDouble() ?? 0,
      );
}

class Briefing {
  final String intro;            // 시나리오 배경 (게임 시작일까지 알려진 사실)
  final int days;                // 등락을 계산한 거래일 수 (보통 20). 0이면 시작 전 데이터 없음
  final String fromDate;
  final String toDate;
  final List<BriefingAsset> assets;
  final List<double> spxSeries;  // 시작 전 S&P500 종가 (오래된 날 → 최근)

  const Briefing({
    this.intro = '',
    this.days = 0,
    this.fromDate = '',
    this.toDate = '',
    this.assets = const [],
    this.spxSeries = const [],
  });

  bool get isEmpty => intro.isEmpty && assets.isEmpty;

  static Briefing? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final assets = raw['assets'];
    final series = raw['spxSeries'];
    return Briefing(
      intro:    (raw['intro'] as String?) ?? '',
      days:     (raw['days'] as num?)?.toInt() ?? 0,
      fromDate: (raw['fromDate'] as String?) ?? '',
      toDate:   (raw['toDate'] as String?) ?? '',
      assets: assets is List
          ? assets
              .whereType<Map>()
              .map((e) => BriefingAsset.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
      spxSeries: series is List
          ? series
              .whereType<Map>()
              .map((e) => (e['close'] as num?)?.toDouble() ?? 0)
              .where((v) => v > 0)
              .toList()
          : const [],
    );
  }
}
