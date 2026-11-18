// 카드 정보 정의
// 서버에서 cardId를 받으면 클라에서 이 정보로 UI를 그림
// (#125) 설명은 종목 코드(SPX·NDX·AAPL) 대신 쉬운 말로 쓴다. 조건·비율·횟수 숫자는 서버 data.sql의 카드 규칙과 같아야 하고,
//        backend/python_simulation/tests/test_card_sources.py가 이 파일과 서버 규칙이 어긋나지 않는지 확인한다.

class CardInfo {
  final int id;
  final String name;
  final String description;
  final String emoji;
  final String ticker;

  const CardInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.emoji,
    required this.ticker,
  });

  // cardId로 카드 정보 찾기
  static CardInfo? fromId(int id) {
    try {
      return all.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }

  // 전체 카드 목록 (v3 기준)
  static const List<CardInfo> all = [
    CardInfo(
      id: 1,
      name: '거인의 어깨',
      description: '고르는 즉시 현금의 30%로 S&P500 매수 (1번)',
      emoji: '🏛️',
      ticker: '^SPX',
    ),
    CardInfo(
      id: 2,
      name: '황금 적립',
      description: '매 라운드 현금의 5%씩 금 매수',
      emoji: '🪙',
      ticker: 'GLD',
    ),
    CardInfo(
      id: 3,
      name: '공포탐욕',
      description: 'S&P500이 하루 3% 이상 떨어진 날마다 현금의 20%로 S&P500 매수',
      emoji: '😱',
      ticker: '^SPX',
    ),
    CardInfo(
      id: 4,
      name: '금 피난처',
      description: 'S&P500이 하루 5% 이상 떨어진 날마다 현금의 15%로 금 매수',
      emoji: '🛡️',
      ticker: 'GLD',
    ),
    CardInfo(
      id: 5,
      name: '기술의 파도',
      description: '나스닥이 하루 2% 이상 오른 날마다 현금의 10%로 나스닥 매수',
      emoji: '🌊',
      ticker: '^NDX',
    ),
    CardInfo(
      id: 6,
      name: '낙폭과대 사냥',
      description: '나스닥이 하루 4% 이상 떨어진 날 현금의 25%로 나스닥 매수 (최대 3번)',
      emoji: '🎯',
      ticker: '^NDX',
    ),
    // ── v3 추가 카드 ──────────────────────────
    CardInfo(
      id: 7,
      name: '원유 베팅',
      description: '고르는 즉시 현금의 20%로 원유 매수 (1번)',
      emoji: '🛢️',
      ticker: 'USO',
    ),
    CardInfo(
      id: 8,
      name: '역발상 투자',
      description: 'S&P500이 하루 3% 이상 오른 날마다 보유 S&P500의 15% 매도',
      emoji: '🔄',
      ticker: '^SPX',
    ),
    CardInfo(
      id: 9,
      name: '애플 줍줍',
      description: '애플이 하루 5% 이상 떨어진 날 현금의 10%로 애플 매수 (최대 5번)',
      emoji: '🍎',
      ticker: 'AAPL',
    ),
    CardInfo(
      id: 10,
      name: '채권 피난처',
      description: '매 라운드 현금의 3%씩 미국 장기채 매수',
      emoji: '📜',
      ticker: 'TLT',
    ),
    CardInfo(
      id: 11,
      name: '분할매수 장인',
      description: '5라운드마다 현금의 10%로 나스닥 매수',
      emoji: '📊',
      ticker: '^NDX',
    ),
  ];
}