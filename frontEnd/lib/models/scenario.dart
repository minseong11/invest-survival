class Scenario {
  final int id;
  final String title;
  final int year;
  final int difficulty; // 1~5
  final String description;
  final String colorHex; // 카드 배경색

  Scenario({
    required this.id,
    required this.title,
    required this.year,
    required this.difficulty,
    required this.description,
    required this.colorHex,
  });

  factory Scenario.fromJson(Map<String, dynamic> json) {
    return Scenario(
      id: json['id'],
      title: json['title'],
      year: json['year'],
      difficulty: json['difficulty'],
      description: json['description'] ?? '',
      colorHex: json['colorHex'] ?? 'EEEDFE',
    );
  }
}
