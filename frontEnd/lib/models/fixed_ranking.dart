// 자동 생성 파일 — 직접 수정하지 말 것
// 생성: backend/python_simulation/export_fixed_ranking.py (2026-10-28)
// 출처: training_data_v2.csv 1,592,160행 (게임 시작일 최대 2018-08-08)
//
// 고정 순위(평소 순위) = 학습 기간에 이 라운드에서 각 카드가 낸 평균 기여도(%p).
// 지금 시장은 보지 않는다. 중간보고서 4장 평가의 '고정 순위' 기준선과 같은 값.

class FixedRanking {
  // 라운드 → {카드 ID: 평균 기여도(%p)}
  static const Map<int, Map<int, double>> means = {
    25: {1: 0.1099, 2: 0.4392, 3: -0.2523, 4: -0.2086, 5: -0.0007, 6: -0.2677, 7: -0.6119, 8: -0.2502, 9: -0.1798, 10: 0.1379, 11: 1.0863},
    50: {1: 0.0813, 2: 0.2263, 3: -0.1012, 4: -0.0993, 5: -0.0239, 6: -0.1186, 7: -0.2722, 8: -0.0929, 9: -0.0994, 10: 0.0742, 11: 0.4267},
  };

  // 후보 카드를 평소 순위(평균 기여도 높은 순)로 정렬. 값이 없으면 빈 목록 → 화면에 표시 안 함
  static List<int> order(int round, List<int> cards) {
    final m = means[round];
    if (m == null || cards.isEmpty || !cards.every(m.containsKey)) return const [];
    final sorted = List<int>.from(cards)..sort((a, b) => m[b]!.compareTo(m[a]!));
    return sorted;
  }
}
