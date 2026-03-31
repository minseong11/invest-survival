class MockData {

  static Map<String, dynamic> scenarios = {
    "success": true,
    "message": "OK",
    "data": [
      {
        "id": 1,
        "title": "리먼브라더스 사태",
        "year": 2008,
        "difficulty": 5,
        "description": "2008년 금융위기. 역사상 최악의 시장 붕괴.",
        "colorHex": "FAECE7",
      },
      {
        "id": 2,
        "title": "닷컴버블 붕괴",
        "year": 2000,
        "difficulty": 4,
        "description": "인터넷 버블이 터지며 나스닥 80% 폭락.",
        "colorHex": "FAEEDA",
      },
      {
        "id": 3,
        "title": "코로나 쇼크",
        "year": 2020,
        "difficulty": 3,
        "description": "팬데믹으로 인한 급격한 시장 변동.",
        "colorHex": "E6F1FB",
      },
    ]
  };

  // POST /game/start 응답 (카드 선택 전 — roundAsset, returnRate 없음)
  static Map<String, dynamic> gameSession = {
    "success": true,
    "message": "OK",
    "data": {
      "sessionId": "mock-session-001",
      "scenarioTitle": "리먼브라더스 사태",
      "totalRounds": 10,
      "initialAsset": 10000000,
      "rounds": [
        {"round": 1, "date": "2008-01-02", "priceData": [
          {"ticker": "^SPX", "open": 1447.16, "close": 1411.63, "high": 1450.23, "low": 1403.97, "changeRate": -2.46},
          {"ticker": "^NDX", "open": 2069.85, "close": 2017.49, "high": 2072.10, "low": 2011.12, "changeRate": -2.53},
        ]},
        {"round": 2, "date": "2008-01-03", "priceData": [
          {"ticker": "^SPX", "open": 1411.63, "close": 1447.16, "high": 1452.00, "low": 1408.00, "changeRate": 2.52},
          {"ticker": "^NDX", "open": 2017.49, "close": 2050.22, "high": 2058.00, "low": 2013.00, "changeRate": 1.62},
        ]},
        {"round": 3, "date": "2008-01-04", "priceData": [
          {"ticker": "^SPX", "open": 1447.16, "close": 1411.00, "high": 1450.00, "low": 1405.00, "changeRate": -2.50},
          {"ticker": "^NDX", "open": 2050.22, "close": 1990.00, "high": 2055.00, "low": 1985.00, "changeRate": -2.94},
        ]},
        {"round": 4, "date": "2008-01-07", "priceData": [
          {"ticker": "^SPX", "open": 1411.00, "close": 1390.00, "high": 1415.00, "low": 1385.00, "changeRate": -1.49},
          {"ticker": "^NDX", "open": 1990.00, "close": 1965.00, "high": 1995.00, "low": 1960.00, "changeRate": -1.26},
        ]},
        {"round": 5, "date": "2008-01-08", "priceData": [
          {"ticker": "^SPX", "open": 1390.00, "close": 1360.00, "high": 1392.00, "low": 1355.00, "changeRate": -2.16},
          {"ticker": "^NDX", "open": 1965.00, "close": 1920.00, "high": 1968.00, "low": 1915.00, "changeRate": -2.29},
        ]},
        {"round": 6, "date": "2008-01-09", "priceData": [
          {"ticker": "^SPX", "open": 1360.00, "close": 1380.00, "high": 1385.00, "low": 1355.00, "changeRate": 1.47},
          {"ticker": "^NDX", "open": 1920.00, "close": 1945.00, "high": 1950.00, "low": 1915.00, "changeRate": 1.30},
        ]},
        {"round": 7, "date": "2008-01-10", "priceData": [
          {"ticker": "^SPX", "open": 1380.00, "close": 1370.00, "high": 1385.00, "low": 1362.00, "changeRate": -0.72},
          {"ticker": "^NDX", "open": 1945.00, "close": 1930.00, "high": 1950.00, "low": 1925.00, "changeRate": -0.77},
        ]},
        {"round": 8, "date": "2008-01-11", "priceData": [
          {"ticker": "^SPX", "open": 1370.00, "close": 1340.00, "high": 1372.00, "low": 1335.00, "changeRate": -2.19},
          {"ticker": "^NDX", "open": 1930.00, "close": 1890.00, "high": 1932.00, "low": 1885.00, "changeRate": -2.07},
        ]},
        {"round": 9, "date": "2008-01-14", "priceData": [
          {"ticker": "^SPX", "open": 1340.00, "close": 1325.00, "high": 1345.00, "low": 1320.00, "changeRate": -1.12},
          {"ticker": "^NDX", "open": 1890.00, "close": 1860.00, "high": 1895.00, "low": 1855.00, "changeRate": -1.59},
        ]},
        {"round": 10, "date": "2008-01-15", "priceData": [
          {"ticker": "^SPX", "open": 1325.00, "close": 1276.60, "high": 1328.00, "low": 1270.00, "changeRate": -3.65},
          {"ticker": "^NDX", "open": 1860.00, "close": 1790.00, "high": 1862.00, "low": 1785.00, "changeRate": -3.76},
        ]},
      ]
    }
  };

  // POST /game/round/action 응답
  // "거인의 어깨" 카드 선택 후 1~10라운드 결과
  // 초기자산 10,000,000 → 30% = 3,000,000 SPX 매수
  // 매수 시점 SPX 종가: 1411.63 → 수량: 3,000,000 / 1411.63 = 2124.5주
  static Map<String, dynamic> actionResult = {
    "success": true,
    "message": "OK",
    "data": {
      "selectedCard": "거인의 어깨",
      "nextEventRound": null,  // 다음 증강 없음
      "rounds": [
        // 1라운드: 매수 시점
        // 현금: 7,000,000 / 보유SPX: 2124.5주 × 1411.63 = 2,999,977
        // roundAsset = 7,000,000 + 2,999,977 = 9,999,977
        {"round": 1, "date": "2008-01-02", "priceData": [
          {"ticker": "^SPX", "open": 1447.16, "close": 1411.63, "high": 1450.23, "low": 1403.97, "changeRate": -2.46},
        ], "roundAsset": 9999977, "returnRate": -0.0},

        // 2라운드: SPX 1447.16
        // roundAsset = 7,000,000 + 2124.5 × 1447.16 = 7,000,000 + 3,075,408 = 10,075,408
        {"round": 2, "date": "2008-01-03", "priceData": [
          {"ticker": "^SPX", "open": 1411.63, "close": 1447.16, "high": 1452.00, "low": 1408.00, "changeRate": 2.52},
        ], "roundAsset": 10075408, "returnRate": 0.75},

        {"round": 3, "date": "2008-01-04", "priceData": [
          {"ticker": "^SPX", "open": 1447.16, "close": 1411.00, "high": 1450.00, "low": 1405.00, "changeRate": -2.50},
        ], "roundAsset": 9998695, "returnRate": -0.01},

        {"round": 4, "date": "2008-01-07", "priceData": [
          {"ticker": "^SPX", "open": 1411.00, "close": 1390.00, "high": 1415.00, "low": 1385.00, "changeRate": -1.49},
        ], "roundAsset": 9954045, "returnRate": -0.46},

        {"round": 5, "date": "2008-01-08", "priceData": [
          {"ticker": "^SPX", "open": 1390.00, "close": 1360.00, "high": 1392.00, "low": 1355.00, "changeRate": -2.16},
        ], "roundAsset": 9890302, "returnRate": -1.10},

        {"round": 6, "date": "2008-01-09", "priceData": [
          {"ticker": "^SPX", "open": 1360.00, "close": 1380.00, "high": 1385.00, "low": 1355.00, "changeRate": 1.47},
        ], "roundAsset": 9932810, "returnRate": -0.67},

        {"round": 7, "date": "2008-01-10", "priceData": [
          {"ticker": "^SPX", "open": 1380.00, "close": 1370.00, "high": 1385.00, "low": 1362.00, "changeRate": -0.72},
        ], "roundAsset": 9911595, "returnRate": -0.88},

        {"round": 8, "date": "2008-01-11", "priceData": [
          {"ticker": "^SPX", "open": 1370.00, "close": 1340.00, "high": 1372.00, "low": 1335.00, "changeRate": -2.19},
        ], "roundAsset": 9847820, "returnRate": -1.52},

        {"round": 9, "date": "2008-01-14", "priceData": [
          {"ticker": "^SPX", "open": 1340.00, "close": 1325.00, "high": 1345.00, "low": 1320.00, "changeRate": -1.12},
        ], "roundAsset": 9815963, "returnRate": -1.84},

        {"round": 10, "date": "2008-01-15", "priceData": [
          {"ticker": "^SPX", "open": 1325.00, "close": 1276.60, "high": 1328.00, "low": 1270.00, "changeRate": -3.65},
        ], "roundAsset": 9712879, "returnRate": -2.87},
      ]
    }
  };
}