// =============================================
// (#125) 사후 분석 AI 코치 한마디 — POST /game/result/coach
// 서버가 줄 머리말로 나눈 글을 보낸다.
//   요약: …   잘한 점: …   아쉬운 점: …   위기 대응: …   다음엔: …
// 숫자가 들어가는 앞의 줄들은 프로그램이 사후 분석 결과로 쓰고, "다음엔" 한 줄만 AI(LLM)가 쓴다.
// status: llm(검사를 통과한 AI 문장) / fallback(검사 실패 → 규칙 기반 문장) / failed(AI 호출 실패 → 규칙 기반 문장)
// =============================================
class CoachLine {
  final String head;
  final String body;
  const CoachLine(this.head, this.body);
}

class CoachComment {
  final String comment;
  final String status;

  const CoachComment({required this.comment, this.status = ''});

  // "다음엔" 줄을 AI가 썼는지 (아니면 미리 정해 둔 규칙 문장)
  bool get byAi => status == 'llm';

  // 머리말 기준으로 나눈 줄. 머리말이 없는 줄은 head가 빈 문자열
  List<CoachLine> get lines {
    final out = <CoachLine>[];
    for (final raw in comment.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final i = line.indexOf(': ');
      if (i > 0 && i <= 6) {
        out.add(CoachLine(line.substring(0, i), line.substring(i + 2)));
      } else {
        out.add(CoachLine('', line));
      }
    }
    return out;
  }

  static CoachComment? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final comment = raw['comment'];
    if (comment is! String || comment.trim().isEmpty) return null;
    return CoachComment(
      comment: comment,
      status: (raw['status'] as String?) ?? '',
    );
  }
}
