// 카드 정보 정의
// 서버에서 cardId를 받으면 클라에서 이 정보로 UI를 그림

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

  // 전체 카드 목록
  static const List<CardInfo> all = [
    CardInfo(
      id: 1,
      name: '거인의 어깨',
      description: '현재 자산의 30%로\nS&P500 즉시 매수',
      emoji: '🏛️',
      ticker: '^SPX',
    ),
    CardInfo(
      id: 2,
      name: '황금 적립',
      description: '매 라운드\n자산의 5%씩 금 매수',
      emoji: '🪙',
      ticker: 'GLD',
    ),
    CardInfo(
      id: 3,
      name: '공포탐욕',
      description: 'SPX -3% 이하 시\n자산의 20% SPX 매수',
      emoji: '😱',
      ticker: '^SPX',
    ),
    CardInfo(
      id: 4,
      name: '금 피난처',
      description: 'SPX -5% 이하 시\n자산의 15% 금 매수',
      emoji: '🛡️',
      ticker: 'GLD',
    ),
    CardInfo(
      id: 5,
      name: '기술의 파도',
      description: 'NDX +2% 이상 시\n자산의 10% 나스닥 매수',
      emoji: '🌊',
      ticker: '^NDX',
    ),
    CardInfo(
      id: 6,
      name: '낙폭과대 사냥',
      description: 'NDX -4% 이하 시\n자산의 25% 나스닥 매수 (최대 3회)',
      emoji: '🎯',
      ticker: '^NDX',
    ),
  ];
}