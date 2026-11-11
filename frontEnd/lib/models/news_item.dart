// =============================================
// 시나리오 뉴스 (11주차, 서버 rounds[].news / nextRoundNews)
// { "date": "2008-09-15", "headline": "...", "level": "danger",
//   "source": "CNN Money", "sourceUrl": "https://..." }
// level: danger(위험) / caution(주의) / positive(긍정)
// 같은 뉴스가 nextRoundNews와 다음 응답 rounds[].news로 두 번 올 수 있어
// key(날짜+헤드라인)로 중복을 거른다.
// =============================================
class NewsItem {
  final String date;
  final String headline;
  final String level;
  final String source;
  final String sourceUrl;

  const NewsItem({
    required this.date,
    required this.headline,
    required this.level,
    this.source = '',
    this.sourceUrl = '',
  });

  String get key => '$date|$headline';

  factory NewsItem.fromJson(Map<String, dynamic> json) => NewsItem(
        date:      (json['date'] ?? '') as String,
        headline:  (json['headline'] ?? '') as String,
        level:     (json['level'] ?? 'caution') as String,
        source:    (json['source'] ?? '') as String,
        sourceUrl: (json['sourceUrl'] ?? '') as String,
      );

  static List<NewsItem> listFromJson(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => NewsItem.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }
}
