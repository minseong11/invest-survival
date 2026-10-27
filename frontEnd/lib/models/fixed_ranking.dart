// 자동 생성 파일 — 직접 수정하지 말 것
// 생성: backend/python_simulation/export_fixed_ranking.py
//
// 아직 생성 전: means가 비어 있으면 게임 화면에 '평소 순위'가 표시되지 않는다.
// training_data_v2.csv가 있는 PC에서 아래를 실행하면 이 파일이 값으로 채워진다.
//   cd backend/python_simulation && python3 export_fixed_ranking.py

class FixedRanking {
  // 라운드 → {카드 ID: 평균 기여도(%p)}
  static const Map<int, Map<int, double>> means = {};

  // 후보 카드를 평소 순위(평균 기여도 높은 순)로 정렬. 값이 없으면 빈 목록 → 화면에 표시 안 함
  static List<int> order(int round, List<int> cards) {
    final m = means[round];
    if (m == null || cards.isEmpty || !cards.every(m.containsKey)) return const [];
    final sorted = List<int>.from(cards)..sort((a, b) => m[b]!.compareTo(m[a]!));
    return sorted;
  }
}
