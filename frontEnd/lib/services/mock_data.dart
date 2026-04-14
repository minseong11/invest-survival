// 실제 API 연결 전 테스트용 임시 데이터
// 서버와 동일한 구조
// /game/start  → rounds 1개
// /game/action → 구간별 rounds (1~24, 25~49, 50~74, 75~100)
class MockData {

  static Map<String, dynamic> scenarios = {
    "success": true,
    "message": "OK",
    "data": [
      {"id": 1, "title": "리먼브라더스 사태", "year": 2008, "difficulty": 5, "description": "2008년 금융위기.", "colorHex": "FAECE7"},
      {"id": 2, "title": "닷컴버블 붕괴", "year": 2000, "difficulty": 4, "description": "인터넷 버블이 터지며 나스닥 80% 폭락.", "colorHex": "FAEEDA"},
      {"id": 3, "title": "코로나 쇼크", "year": 2020, "difficulty": 3, "description": "팬데믹으로 인한 급격한 시장 변동.", "colorHex": "E6F1FB"},
    ]
  };

  // POST /game/start 응답 (서버와 동일: rounds 1개만)
  static Map<String, dynamic> gameSession = {
    "success": true,
    "message": "OK",
    "data": {
      "sessionId": "mock-session-001",
      "scenarioTitle": "리먼브라더스 사태",
      "totalRounds": 100,
      "initialAsset": 10000000,
      "cardSelectRounds": [1, 25, 50, 75],
      "firstCardOptions": [1, 2, 3],
      "rounds": [
        {
          "round": 1,
          "date": "2008-09-02",
          "priceData": [
          {"ticker": "^SPX", "open": 1274.04, "close": 1286.01, "high": 1290.75, "low": 1269.73, "changeRate": 0.66},
          {"ticker": "^NDX", "open": 1726.75, "close": 1654.47, "high": 1727.5, "low": 1650.98, "changeRate": -3.81},
          {"ticker": "GLD", "open": 84.76, "close": 84.35, "high": 84.82, "low": 84.22, "changeRate": -0.76}
          ]
        }
      ]
    }
  };

  // POST /game/round/action — 1라운드 카드 선택 (round 1~24)
  static Map<String, dynamic> actionResult1 = {
    "success": true,
    "message": "OK",
    "data": {
      "selectedCard": "거인의 어깨",
      "nextEventRound": 25,
      "nextCardOptions": [4, 5, 2],
      "rounds": [
        {
          "round": 1,
          "date": "2008-09-02",
          "priceData": [
          {"ticker": "^SPX", "open": 1274.04, "close": 1286.01, "high": 1290.75, "low": 1269.73, "changeRate": 0.66},
          {"ticker": "^NDX", "open": 1726.75, "close": 1654.47, "high": 1727.5, "low": 1650.98, "changeRate": -3.81},
          {"ticker": "GLD", "open": 84.76, "close": 84.35, "high": 84.82, "low": 84.22, "changeRate": -0.76}
          ], "roundAsset": 10000000, "returnRate": 0.0
        },
        {
          "round": 2,
          "date": "2008-09-03",
          "priceData": [
          {"ticker": "^SPX", "open": 1286.59, "close": 1243.19, "high": 1288.01, "low": 1239.53, "changeRate": -3.33},
          {"ticker": "^NDX", "open": 1659.59, "close": 1612.94, "high": 1659.64, "low": 1606.44, "changeRate": -2.51},
          {"ticker": "GLD", "open": 84.45, "close": 85.13, "high": 85.22, "low": 84.41, "changeRate": 0.92}
          ], "roundAsset": 9900110, "returnRate": -1.0
        },
        {
          "round": 3,
          "date": "2008-09-04",
          "priceData": [
          {"ticker": "^SPX", "open": 1238.18, "close": 1277.0, "high": 1282.41, "low": 1234.44, "changeRate": 2.72},
          {"ticker": "^NDX", "open": 1617.89, "close": 1589.07, "high": 1623.79, "low": 1584.81, "changeRate": -1.48},
          {"ticker": "GLD", "open": 85.37, "close": 83.78, "high": 85.47, "low": 83.64, "changeRate": -1.58}
          ], "roundAsset": 9978982, "returnRate": -0.21
        },
        {
          "round": 4,
          "date": "2008-09-05",
          "priceData": [
          {"ticker": "^SPX", "open": 1277.99, "close": 1301.14, "high": 1305.72, "low": 1277.7, "changeRate": 1.89},
          {"ticker": "^NDX", "open": 1584.75, "close": 1599.24, "high": 1601.55, "low": 1584.12, "changeRate": 0.64},
          {"ticker": "GLD", "open": 83.65, "close": 85.36, "high": 85.39, "low": 83.58, "changeRate": 1.88}
          ], "roundAsset": 10035295, "returnRate": 0.35
        },
        {
          "round": 5,
          "date": "2008-09-08",
          "priceData": [
          {"ticker": "^SPX", "open": 1297.36, "close": 1309.34, "high": 1311.09, "low": 1291.28, "changeRate": 0.63},
          {"ticker": "^NDX", "open": 1601.61, "close": 1579.09, "high": 1606.49, "low": 1577.74, "changeRate": -1.26},
          {"ticker": "GLD", "open": 85.48, "close": 85.08, "high": 85.52, "low": 84.98, "changeRate": -0.33}
          ], "roundAsset": 10054424, "returnRate": 0.54
        },
        {
          "round": 6,
          "date": "2008-09-09",
          "priceData": [
          {"ticker": "^SPX", "open": 1311.76, "close": 1347.7, "high": 1353.38, "low": 1306.67, "changeRate": 2.93},
          {"ticker": "^NDX", "open": 1574.81, "close": 1591.72, "high": 1591.98, "low": 1572.33, "changeRate": 0.8},
          {"ticker": "GLD", "open": 84.96, "close": 85.51, "high": 85.56, "low": 84.72, "changeRate": 0.51}
          ], "roundAsset": 10143910, "returnRate": 1.44
        },
        {
          "round": 7,
          "date": "2008-09-10",
          "priceData": [
          {"ticker": "^SPX", "open": 1346.29, "close": 1377.35, "high": 1383.65, "low": 1343.2, "changeRate": 2.2},
          {"ticker": "^NDX", "open": 1587.98, "close": 1565.62, "high": 1589.94, "low": 1561.23, "changeRate": -1.64},
          {"ticker": "GLD", "open": 85.39, "close": 86.32, "high": 86.47, "low": 85.16, "changeRate": 0.95}
          ], "roundAsset": 10213078, "returnRate": 2.13
        },
        {
          "round": 8,
          "date": "2008-09-11",
          "priceData": [
          {"ticker": "^SPX", "open": 1377.48, "close": 1364.95, "high": 1378.11, "low": 1364.63, "changeRate": -0.9},
          {"ticker": "^NDX", "open": 1559.51, "close": 1528.67, "high": 1564.4, "low": 1522.62, "changeRate": -2.36},
          {"ticker": "GLD", "open": 86.28, "close": 88.47, "high": 88.49, "low": 86.18, "changeRate": 2.49}
          ], "roundAsset": 10184151, "returnRate": 1.84
        },
        {
          "round": 9,
          "date": "2008-09-12",
          "priceData": [
          {"ticker": "^SPX", "open": 1369.87, "close": 1405.49, "high": 1405.57, "low": 1364.93, "changeRate": 2.97},
          {"ticker": "^NDX", "open": 1531.45, "close": 1528.21, "high": 1535.56, "low": 1526.17, "changeRate": -0.03},
          {"ticker": "GLD", "open": 88.54, "close": 90.57, "high": 90.6, "low": 88.42, "changeRate": 2.37}
          ], "roundAsset": 10278723, "returnRate": 2.79
        },
        {
          "round": 10,
          "date": "2008-09-15",
          "priceData": [
          {"ticker": "^SPX", "open": 1402.16, "close": 1397.76, "high": 1405.67, "low": 1396.51, "changeRate": -0.55},
          {"ticker": "^NDX", "open": 1534.52, "close": 1576.35, "high": 1583.21, "low": 1532.23, "changeRate": 3.15},
          {"ticker": "GLD", "open": 90.65, "close": 92.33, "high": 92.5, "low": 90.61, "changeRate": 1.94}
          ], "roundAsset": 10260690, "returnRate": 2.61
        },
        {
          "round": 11,
          "date": "2008-09-16",
          "priceData": [
          {"ticker": "^SPX", "open": 1398.18, "close": 1418.17, "high": 1418.17, "low": 1395.91, "changeRate": 1.46},
          {"ticker": "^NDX", "open": 1568.78, "close": 1577.14, "high": 1584.47, "low": 1561.89, "changeRate": 0.05},
          {"ticker": "GLD", "open": 92.51, "close": 93.71, "high": 93.8, "low": 92.49, "changeRate": 1.5}
          ], "roundAsset": 10308302, "returnRate": 3.08
        },
        {
          "round": 12,
          "date": "2008-09-17",
          "priceData": [
          {"ticker": "^SPX", "open": 1417.97, "close": 1449.51, "high": 1450.01, "low": 1412.58, "changeRate": 2.21},
          {"ticker": "^NDX", "open": 1581.33, "close": 1626.03, "high": 1627.07, "low": 1577.57, "changeRate": 3.1},
          {"ticker": "GLD", "open": 93.74, "close": 92.2, "high": 93.81, "low": 91.96, "changeRate": -1.61}
          ], "roundAsset": 10381412, "returnRate": 3.81
        },
        {
          "round": 13,
          "date": "2008-09-18",
          "priceData": [
          {"ticker": "^SPX", "open": 1452.84, "close": 1438.64, "high": 1454.3, "low": 1436.4, "changeRate": -0.75},
          {"ticker": "^NDX", "open": 1634.08, "close": 1586.84, "high": 1639.39, "low": 1583.36, "changeRate": -2.41},
          {"ticker": "GLD", "open": 92.21, "close": 92.6, "high": 92.63, "low": 92.15, "changeRate": 0.43}
          ], "roundAsset": 10356055, "returnRate": 3.56
        },
        {
          "round": 14,
          "date": "2008-09-19",
          "priceData": [
          {"ticker": "^SPX", "open": 1434.61, "close": 1419.94, "high": 1435.12, "low": 1415.46, "changeRate": -1.3},
          {"ticker": "^NDX", "open": 1582.54, "close": 1593.35, "high": 1600.56, "low": 1575.74, "changeRate": 0.41},
          {"ticker": "GLD", "open": 92.36, "close": 91.71, "high": 92.43, "low": 91.53, "changeRate": -0.96}
          ], "roundAsset": 10312431, "returnRate": 3.12
        },
        {
          "round": 15,
          "date": "2008-09-22",
          "priceData": [
          {"ticker": "^SPX", "open": 1420.95, "close": 1389.98, "high": 1424.31, "low": 1384.53, "changeRate": -2.11},
          {"ticker": "^NDX", "open": 1598.25, "close": 1545.39, "high": 1599.77, "low": 1544.64, "changeRate": -3.01},
          {"ticker": "GLD", "open": 91.67, "close": 93.74, "high": 93.86, "low": 91.54, "changeRate": 2.21}
          ], "roundAsset": 10242541, "returnRate": 2.43
        },
        {
          "round": 16,
          "date": "2008-09-23",
          "priceData": [
          {"ticker": "^SPX", "open": 1384.4, "close": 1407.22, "high": 1410.05, "low": 1382.05, "changeRate": 1.24},
          {"ticker": "^NDX", "open": 1550.98, "close": 1561.62, "high": 1563.56, "low": 1549.5, "changeRate": 1.05},
          {"ticker": "GLD", "open": 93.71, "close": 96.02, "high": 96.14, "low": 93.63, "changeRate": 2.43}
          ], "roundAsset": 10282758, "returnRate": 2.83
        },
        {
          "round": 17,
          "date": "2008-09-24",
          "priceData": [
          {"ticker": "^SPX", "open": 1412.3, "close": 1380.76, "high": 1416.19, "low": 1380.41, "changeRate": -1.88},
          {"ticker": "^NDX", "open": 1569.42, "close": 1607.22, "high": 1613.94, "low": 1561.82, "changeRate": 2.92},
          {"ticker": "GLD", "open": 96.27, "close": 96.01, "high": 96.52, "low": 95.96, "changeRate": -0.01}
          ], "roundAsset": 10221032, "returnRate": 2.21
        },
        {
          "round": 18,
          "date": "2008-09-25",
          "priceData": [
          {"ticker": "^SPX", "open": 1374.67, "close": 1376.07, "high": 1378.68, "low": 1367.9, "changeRate": -0.34},
          {"ticker": "^NDX", "open": 1603.45, "close": 1568.65, "high": 1609.74, "low": 1565.08, "changeRate": -2.4},
          {"ticker": "GLD", "open": 95.97, "close": 95.82, "high": 96.25, "low": 95.53, "changeRate": -0.2}
          ], "roundAsset": 10210092, "returnRate": 2.1
        },
        {
          "round": 19,
          "date": "2008-09-26",
          "priceData": [
          {"ticker": "^SPX", "open": 1373.27, "close": 1377.58, "high": 1384.25, "low": 1369.29, "changeRate": 0.11},
          {"ticker": "^NDX", "open": 1569.31, "close": 1590.45, "high": 1596.4, "low": 1568.86, "changeRate": 1.39},
          {"ticker": "GLD", "open": 95.87, "close": 94.57, "high": 96.01, "low": 94.33, "changeRate": -1.3}
          ], "roundAsset": 10213614, "returnRate": 2.14
        },
        {
          "round": 20,
          "date": "2008-09-29",
          "priceData": [
          {"ticker": "^SPX", "open": 1373.25, "close": 1343.42, "high": 1377.34, "low": 1338.88, "changeRate": -2.48},
          {"ticker": "^NDX", "open": 1586.24, "close": 1641.5, "high": 1642.48, "low": 1579.18, "changeRate": 3.21},
          {"ticker": "GLD", "open": 94.43, "close": 93.02, "high": 94.6, "low": 92.85, "changeRate": -1.64}
          ], "roundAsset": 10133926, "returnRate": 1.34
        },
        {
          "round": 21,
          "date": "2008-09-30",
          "priceData": [
          {"ticker": "^SPX", "open": 1349.26, "close": 1332.94, "high": 1350.64, "low": 1328.17, "changeRate": -0.78},
          {"ticker": "^NDX", "open": 1637.21, "close": 1647.74, "high": 1651.0, "low": 1631.71, "changeRate": 0.38},
          {"ticker": "GLD", "open": 92.91, "close": 93.35, "high": 93.44, "low": 92.7, "changeRate": 0.35}
          ], "roundAsset": 10109478, "returnRate": 1.09
        },
        {
          "round": 22,
          "date": "2008-10-01",
          "priceData": [
          {"ticker": "^SPX", "open": 1339.55, "close": 1292.55, "high": 1340.04, "low": 1291.17, "changeRate": -3.03},
          {"ticker": "^NDX", "open": 1643.87, "close": 1638.51, "high": 1651.54, "low": 1631.29, "changeRate": -0.56},
          {"ticker": "GLD", "open": 93.56, "close": 95.67, "high": 95.78, "low": 93.52, "changeRate": 2.49}
          ], "roundAsset": 10015256, "returnRate": 0.15
        },
        {
          "round": 23,
          "date": "2008-10-02",
          "priceData": [
          {"ticker": "^SPX", "open": 1298.85, "close": 1317.37, "high": 1321.68, "low": 1298.8, "changeRate": 1.92},
          {"ticker": "^NDX", "open": 1643.71, "close": 1659.48, "high": 1661.96, "low": 1638.26, "changeRate": 1.28},
          {"ticker": "GLD", "open": 95.92, "close": 96.39, "high": 96.43, "low": 95.89, "changeRate": 0.75}
          ], "roundAsset": 10073157, "returnRate": 0.73
        },
        {
          "round": 24,
          "date": "2008-10-03",
          "priceData": [
          {"ticker": "^SPX", "open": 1318.75, "close": 1280.48, "high": 1323.48, "low": 1279.18, "changeRate": -2.8},
          {"ticker": "^NDX", "open": 1661.71, "close": 1661.97, "high": 1664.16, "low": 1657.65, "changeRate": 0.15},
          {"ticker": "GLD", "open": 96.62, "close": 95.65, "high": 96.87, "low": 95.62, "changeRate": -0.77}
          ], "roundAsset": 9987100, "returnRate": -0.13
        }
      ]
    }
  };

  // POST /game/round/action — 25라운드 카드 선택 (round 25~49)
  static Map<String, dynamic> actionResult2 = {
    "success": true,
    "message": "OK",
    "data": {
      "selectedCard": "황금 적립",
      "nextEventRound": 50,
      "nextCardOptions": [3, 6, 5],
      "rounds": [
        {
          "round": 25,
          "date": "2008-10-06",
          "priceData": [
          {"ticker": "^SPX", "open": 1283.95, "close": 1270.88, "high": 1288.04, "low": 1269.22, "changeRate": -0.75},
          {"ticker": "^NDX", "open": 1665.98, "close": 1630.06, "high": 1670.58, "low": 1626.57, "changeRate": -1.92},
          {"ticker": "GLD", "open": 95.37, "close": 93.76, "high": 95.39, "low": 93.51, "changeRate": -1.98}
          ], "roundAsset": 9987100, "returnRate": 0.0
        },
        {
          "round": 26,
          "date": "2008-10-07",
          "priceData": [
          {"ticker": "^SPX", "open": 1271.93, "close": 1301.13, "high": 1302.09, "low": 1271.12, "changeRate": 2.38},
          {"ticker": "^NDX", "open": 1626.93, "close": 1631.53, "high": 1638.86, "low": 1620.45, "changeRate": 0.09},
          {"ticker": "GLD", "open": 93.96, "close": 95.41, "high": 95.67, "low": 93.9, "changeRate": 1.76}
          ], "roundAsset": 10058415, "returnRate": 0.71
        },
        {
          "round": 27,
          "date": "2008-10-08",
          "priceData": [
          {"ticker": "^SPX", "open": 1306.13, "close": 1276.67, "high": 1308.78, "low": 1272.71, "changeRate": -1.88},
          {"ticker": "^NDX", "open": 1625.89, "close": 1578.83, "high": 1633.45, "low": 1572.0, "changeRate": -3.23},
          {"ticker": "GLD", "open": 95.68, "close": 96.85, "high": 97.09, "low": 95.43, "changeRate": 1.51}
          ], "roundAsset": 10000750, "returnRate": 0.14
        },
        {
          "round": 28,
          "date": "2008-10-09",
          "priceData": [
          {"ticker": "^SPX", "open": 1282.17, "close": 1234.03, "high": 1287.31, "low": 1228.7, "changeRate": -3.34},
          {"ticker": "^NDX", "open": 1583.74, "close": 1602.83, "high": 1604.97, "low": 1577.51, "changeRate": 1.52},
          {"ticker": "GLD", "open": 96.62, "close": 96.36, "high": 96.87, "low": 96.11, "changeRate": -0.51}
          ], "roundAsset": 9900225, "returnRate": -0.87
        },
        {
          "round": 29,
          "date": "2008-10-10",
          "priceData": [
          {"ticker": "^SPX", "open": 1231.63, "close": 1208.73, "high": 1236.53, "low": 1207.35, "changeRate": -2.05},
          {"ticker": "^NDX", "open": 1595.2, "close": 1636.81, "high": 1638.39, "low": 1592.58, "changeRate": 2.12},
          {"ticker": "GLD", "open": 96.57, "close": 96.43, "high": 96.85, "low": 96.35, "changeRate": 0.07}
          ], "roundAsset": 9840580, "returnRate": -1.47
        },
        {
          "round": 30,
          "date": "2008-10-13",
          "priceData": [
          {"ticker": "^SPX", "open": 1209.17, "close": 1216.83, "high": 1222.54, "low": 1208.47, "changeRate": 0.67},
          {"ticker": "^NDX", "open": 1644.51, "close": 1620.44, "high": 1645.98, "low": 1612.64, "changeRate": -1.0},
          {"ticker": "GLD", "open": 96.29, "close": 98.76, "high": 98.79, "low": 96.16, "changeRate": 2.42}
          ], "roundAsset": 9859676, "returnRate": -1.28
        },
        {
          "round": 31,
          "date": "2008-10-14",
          "priceData": [
          {"ticker": "^SPX", "open": 1216.97, "close": 1231.92, "high": 1234.29, "low": 1213.46, "changeRate": 1.24},
          {"ticker": "^NDX", "open": 1616.47, "close": 1593.7, "high": 1622.2, "low": 1593.69, "changeRate": -1.65},
          {"ticker": "GLD", "open": 99.01, "close": 99.48, "high": 99.64, "low": 98.8, "changeRate": 0.73}
          ], "roundAsset": 9895251, "returnRate": -0.92
        },
        {
          "round": 32,
          "date": "2008-10-15",
          "priceData": [
          {"ticker": "^SPX", "open": 1226.62, "close": 1248.18, "high": 1252.33, "low": 1224.59, "changeRate": 1.32},
          {"ticker": "^NDX", "open": 1590.73, "close": 1610.12, "high": 1616.95, "low": 1585.01, "changeRate": 1.03},
          {"ticker": "GLD", "open": 99.36, "close": 99.12, "high": 99.45, "low": 99.0, "changeRate": -0.36}
          ], "roundAsset": 9933584, "returnRate": -0.54
        },
        {
          "round": 33,
          "date": "2008-10-16",
          "priceData": [
          {"ticker": "^SPX", "open": 1247.19, "close": 1237.2, "high": 1253.05, "low": 1233.01, "changeRate": -0.88},
          {"ticker": "^NDX", "open": 1616.61, "close": 1581.46, "high": 1621.59, "low": 1579.08, "changeRate": -1.78},
          {"ticker": "GLD", "open": 99.15, "close": 97.7, "high": 99.15, "low": 97.62, "changeRate": -1.43}
          ], "roundAsset": 9907699, "returnRate": -0.8
        },
        {
          "round": 34,
          "date": "2008-10-17",
          "priceData": [
          {"ticker": "^SPX", "open": 1236.77, "close": 1228.42, "high": 1239.5, "low": 1227.11, "changeRate": -0.71},
          {"ticker": "^NDX", "open": 1581.04, "close": 1587.0, "high": 1594.15, "low": 1574.75, "changeRate": 0.35},
          {"ticker": "GLD", "open": 97.51, "close": 98.63, "high": 98.66, "low": 97.36, "changeRate": 0.95}
          ], "roundAsset": 9887000, "returnRate": -1.0
        },
        {
          "round": 35,
          "date": "2008-10-20",
          "priceData": [
          {"ticker": "^SPX", "open": 1231.51, "close": 1235.91, "high": 1240.07, "low": 1230.13, "changeRate": 0.61},
          {"ticker": "^NDX", "open": 1582.23, "close": 1563.35, "high": 1582.42, "low": 1561.44, "changeRate": -1.49},
          {"ticker": "GLD", "open": 98.62, "close": 100.29, "high": 100.55, "low": 98.6, "changeRate": 1.68}
          ], "roundAsset": 9904657, "returnRate": -0.83
        },
        {
          "round": 36,
          "date": "2008-10-21",
          "priceData": [
          {"ticker": "^SPX", "open": 1238.34, "close": 1225.9, "high": 1241.4, "low": 1224.4, "changeRate": -0.81},
          {"ticker": "^NDX", "open": 1565.79, "close": 1574.61, "high": 1574.65, "low": 1559.91, "changeRate": 0.72},
          {"ticker": "GLD", "open": 100.45, "close": 99.16, "high": 100.48, "low": 99.03, "changeRate": -1.13}
          ], "roundAsset": 9881059, "returnRate": -1.06
        },
        {
          "round": 37,
          "date": "2008-10-22",
          "priceData": [
          {"ticker": "^SPX", "open": 1220.39, "close": 1196.97, "high": 1221.91, "low": 1191.89, "changeRate": -2.36},
          {"ticker": "^NDX", "open": 1573.92, "close": 1624.68, "high": 1631.19, "low": 1568.67, "changeRate": 3.18},
          {"ticker": "GLD", "open": 99.45, "close": 99.49, "high": 99.67, "low": 99.17, "changeRate": 0.33}
          ], "roundAsset": 9812855, "returnRate": -1.74
        },
        {
          "round": 38,
          "date": "2008-10-23",
          "priceData": [
          {"ticker": "^SPX", "open": 1197.03, "close": 1224.38, "high": 1229.46, "low": 1193.75, "changeRate": 2.29},
          {"ticker": "^NDX", "open": 1631.13, "close": 1634.27, "high": 1640.35, "low": 1627.26, "changeRate": 0.59},
          {"ticker": "GLD", "open": 99.35, "close": 100.72, "high": 100.79, "low": 99.16, "changeRate": 1.24}
          ], "roundAsset": 9877475, "returnRate": -1.1
        },
        {
          "round": 39,
          "date": "2008-10-24",
          "priceData": [
          {"ticker": "^SPX", "open": 1221.62, "close": 1242.5, "high": 1242.98, "low": 1219.87, "changeRate": 1.48},
          {"ticker": "^NDX", "open": 1630.54, "close": 1632.8, "high": 1635.41, "low": 1626.14, "changeRate": -0.09},
          {"ticker": "GLD", "open": 100.5, "close": 101.55, "high": 101.62, "low": 100.29, "changeRate": 0.82}
          ], "roundAsset": 9920193, "returnRate": -0.67
        },
        {
          "round": 40,
          "date": "2008-10-27",
          "priceData": [
          {"ticker": "^SPX", "open": 1243.03, "close": 1256.04, "high": 1258.65, "low": 1241.74, "changeRate": 1.09},
          {"ticker": "^NDX", "open": 1631.5, "close": 1575.33, "high": 1638.88, "low": 1570.73, "changeRate": -3.52},
          {"ticker": "GLD", "open": 101.67, "close": 101.38, "high": 101.93, "low": 101.15, "changeRate": -0.17}
          ], "roundAsset": 9952114, "returnRate": -0.35
        },
        {
          "round": 41,
          "date": "2008-10-28",
          "priceData": [
          {"ticker": "^SPX", "open": 1259.22, "close": 1243.1, "high": 1264.59, "low": 1237.17, "changeRate": -1.03},
          {"ticker": "^NDX", "open": 1574.05, "close": 1512.95, "high": 1579.93, "low": 1508.82, "changeRate": -3.96},
          {"ticker": "GLD", "open": 101.44, "close": 100.95, "high": 101.51, "low": 100.88, "changeRate": -0.42}
          ], "roundAsset": 9921608, "returnRate": -0.66
        },
        {
          "round": 42,
          "date": "2008-10-29",
          "priceData": [
          {"ticker": "^SPX", "open": 1245.33, "close": 1234.77, "high": 1247.85, "low": 1233.75, "changeRate": -0.67},
          {"ticker": "^NDX", "open": 1512.46, "close": 1455.76, "high": 1513.43, "low": 1451.23, "changeRate": -3.78},
          {"ticker": "GLD", "open": 100.66, "close": 100.46, "high": 100.78, "low": 100.29, "changeRate": -0.49}
          ], "roundAsset": 9901970, "returnRate": -0.85
        },
        {
          "round": 43,
          "date": "2008-10-30",
          "priceData": [
          {"ticker": "^SPX", "open": 1234.3, "close": 1193.78, "high": 1234.61, "low": 1191.52, "changeRate": -3.32},
          {"ticker": "^NDX", "open": 1451.56, "close": 1467.7, "high": 1470.1, "low": 1446.04, "changeRate": 0.82},
          {"ticker": "GLD", "open": 100.39, "close": 99.06, "high": 100.62, "low": 98.81, "changeRate": -1.39}
          ], "roundAsset": 9805335, "returnRate": -1.82
        },
        {
          "round": 44,
          "date": "2008-10-31",
          "priceData": [
          {"ticker": "^SPX", "open": 1194.25, "close": 1171.58, "high": 1200.22, "low": 1169.53, "changeRate": -1.86},
          {"ticker": "^NDX", "open": 1469.9, "close": 1417.94, "high": 1475.64, "low": 1413.32, "changeRate": -3.39},
          {"ticker": "GLD", "open": 99.21, "close": 97.17, "high": 99.49, "low": 97.11, "changeRate": -1.91}
          ], "roundAsset": 9752998, "returnRate": -2.34
        },
        {
          "round": 45,
          "date": "2008-11-03",
          "priceData": [
          {"ticker": "^SPX", "open": 1173.57, "close": 1132.1, "high": 1176.88, "low": 1130.87, "changeRate": -3.37},
          {"ticker": "^NDX", "open": 1420.77, "close": 1377.39, "high": 1426.22, "low": 1376.23, "changeRate": -2.86},
          {"ticker": "GLD", "open": 97.23, "close": 95.78, "high": 97.45, "low": 95.75, "changeRate": -1.43}
          ], "roundAsset": 9659923, "returnRate": -3.28
        },
        {
          "round": 46,
          "date": "2008-11-04",
          "priceData": [
          {"ticker": "^SPX", "open": 1126.73, "close": 1152.82, "high": 1154.62, "low": 1122.91, "changeRate": 1.83},
          {"ticker": "^NDX", "open": 1383.7, "close": 1422.02, "high": 1424.84, "low": 1378.75, "changeRate": 3.24},
          {"ticker": "GLD", "open": 95.54, "close": 94.33, "high": 95.74, "low": 94.15, "changeRate": -1.51}
          ], "roundAsset": 9708771, "returnRate": -2.79
        },
        {
          "round": 47,
          "date": "2008-11-05",
          "priceData": [
          {"ticker": "^SPX", "open": 1153.98, "close": 1120.08, "high": 1154.68, "low": 1114.57, "changeRate": -2.84},
          {"ticker": "^NDX", "open": 1426.04, "close": 1447.47, "high": 1449.98, "low": 1422.99, "changeRate": 1.79},
          {"ticker": "GLD", "open": 94.26, "close": 96.06, "high": 96.21, "low": 94.16, "changeRate": 1.83}
          ], "roundAsset": 9631585, "returnRate": -3.56
        },
        {
          "round": 48,
          "date": "2008-11-06",
          "priceData": [
          {"ticker": "^SPX", "open": 1125.24, "close": 1142.71, "high": 1146.34, "low": 1120.58, "changeRate": 2.02},
          {"ticker": "^NDX", "open": 1450.47, "close": 1478.88, "high": 1482.1, "low": 1445.15, "changeRate": 2.17},
          {"ticker": "GLD", "open": 96.33, "close": 94.59, "high": 96.41, "low": 94.36, "changeRate": -1.53}
          ], "roundAsset": 9684936, "returnRate": -3.03
        },
        {
          "round": 49,
          "date": "2008-11-07",
          "priceData": [
          {"ticker": "^SPX", "open": 1145.35, "close": 1142.71, "high": 1146.89, "low": 1137.84, "changeRate": -0.0},
          {"ticker": "^NDX", "open": 1483.77, "close": 1473.41, "high": 1484.41, "low": 1466.91, "changeRate": -0.37},
          {"ticker": "GLD", "open": 94.44, "close": 94.55, "high": 94.68, "low": 94.27, "changeRate": -0.04}
          ], "roundAsset": 9684936, "returnRate": -3.03
        }
      ]
    }
  };

  // POST /game/round/action — 50라운드 카드 선택 (round 50~74)
  static Map<String, dynamic> actionResult3 = {
    "success": true,
    "message": "OK",
    "data": {
      "selectedCard": "공포탐욕",
      "nextEventRound": 75,
      "nextCardOptions": [4, 6, 2],
      "rounds": [
        {
          "round": 50,
          "date": "2008-11-10",
          "priceData": [
          {"ticker": "^SPX", "open": 1139.07, "close": 1130.83, "high": 1140.28, "low": 1126.32, "changeRate": -1.04},
          {"ticker": "^NDX", "open": 1471.06, "close": 1417.72, "high": 1477.54, "low": 1412.75, "changeRate": -3.78},
          {"ticker": "GLD", "open": 94.42, "close": 96.28, "high": 96.28, "low": 94.15, "changeRate": 1.83}
          ], "roundAsset": 9684936, "returnRate": 0.0
        },
        {
          "round": 51,
          "date": "2008-11-11",
          "priceData": [
          {"ticker": "^SPX", "open": 1133.75, "close": 1097.58, "high": 1137.66, "low": 1094.04, "changeRate": -2.94},
          {"ticker": "^NDX", "open": 1417.59, "close": 1437.57, "high": 1443.27, "low": 1416.93, "changeRate": 1.4},
          {"ticker": "GLD", "open": 96.12, "close": 96.47, "high": 96.67, "low": 96.03, "changeRate": 0.2}
          ], "roundAsset": 9599506, "returnRate": -0.88
        },
        {
          "round": 52,
          "date": "2008-11-12",
          "priceData": [
          {"ticker": "^SPX", "open": 1096.76, "close": 1100.65, "high": 1104.76, "low": 1094.95, "changeRate": 0.28},
          {"ticker": "^NDX", "open": 1440.49, "close": 1431.1, "high": 1442.44, "low": 1429.3, "changeRate": -0.45},
          {"ticker": "GLD", "open": 96.25, "close": 96.85, "high": 96.91, "low": 96.22, "changeRate": 0.39}
          ], "roundAsset": 9607393, "returnRate": -0.8
        },
        {
          "round": 53,
          "date": "2008-11-13",
          "priceData": [
          {"ticker": "^SPX", "open": 1097.53, "close": 1100.43, "high": 1103.09, "low": 1093.55, "changeRate": -0.02},
          {"ticker": "^NDX", "open": 1437.92, "close": 1455.71, "high": 1459.53, "low": 1435.89, "changeRate": 1.72},
          {"ticker": "GLD", "open": 96.62, "close": 95.72, "high": 96.68, "low": 95.65, "changeRate": -1.17}
          ], "roundAsset": 9606828, "returnRate": -0.81
        },
        {
          "round": 54,
          "date": "2008-11-14",
          "priceData": [
          {"ticker": "^SPX", "open": 1097.95, "close": 1074.79, "high": 1103.3, "low": 1071.82, "changeRate": -2.33},
          {"ticker": "^NDX", "open": 1458.58, "close": 1399.08, "high": 1459.5, "low": 1393.0, "changeRate": -3.89},
          {"ticker": "GLD", "open": 95.71, "close": 96.1, "high": 96.35, "low": 95.55, "changeRate": 0.4}
          ], "roundAsset": 9540950, "returnRate": -1.49
        },
        {
          "round": 55,
          "date": "2008-11-17",
          "priceData": [
          {"ticker": "^SPX", "open": 1069.97, "close": 1069.95, "high": 1075.0, "low": 1067.39, "changeRate": -0.45},
          {"ticker": "^NDX", "open": 1403.59, "close": 1389.29, "high": 1406.4, "low": 1388.78, "changeRate": -0.7},
          {"ticker": "GLD", "open": 96.17, "close": 94.98, "high": 96.19, "low": 94.94, "changeRate": -1.17}
          ], "roundAsset": 9528515, "returnRate": -1.62
        },
        {
          "round": 56,
          "date": "2008-11-18",
          "priceData": [
          {"ticker": "^SPX", "open": 1065.87, "close": 1071.66, "high": 1075.76, "low": 1062.64, "changeRate": 0.16},
          {"ticker": "^NDX", "open": 1393.33, "close": 1365.39, "high": 1394.9, "low": 1361.82, "changeRate": -1.72},
          {"ticker": "GLD", "open": 94.95, "close": 97.33, "high": 97.46, "low": 94.7, "changeRate": 2.47}
          ], "roundAsset": 9532908, "returnRate": -1.57
        },
        {
          "round": 57,
          "date": "2008-11-19",
          "priceData": [
          {"ticker": "^SPX", "open": 1072.83, "close": 1103.17, "high": 1107.25, "low": 1067.75, "changeRate": 2.94},
          {"ticker": "^NDX", "open": 1361.4, "close": 1342.04, "high": 1362.84, "low": 1337.61, "changeRate": -1.71},
          {"ticker": "GLD", "open": 97.13, "close": 98.1, "high": 98.15, "low": 97.11, "changeRate": 0.79}
          ], "roundAsset": 9613868, "returnRate": -0.73
        },
        {
          "round": 58,
          "date": "2008-11-20",
          "priceData": [
          {"ticker": "^SPX", "open": 1100.87, "close": 1064.78, "high": 1102.14, "low": 1061.02, "changeRate": -3.48},
          {"ticker": "^NDX", "open": 1344.76, "close": 1333.72, "high": 1347.81, "low": 1329.14, "changeRate": -0.62},
          {"ticker": "GLD", "open": 98.35, "close": 98.76, "high": 98.99, "low": 98.17, "changeRate": 0.67}
          ], "roundAsset": 9515231, "returnRate": -1.75
        },
        {
          "round": 59,
          "date": "2008-11-21",
          "priceData": [
          {"ticker": "^SPX", "open": 1065.25, "close": 1073.3, "high": 1076.78, "low": 1060.41, "changeRate": 0.8},
          {"ticker": "^NDX", "open": 1338.08, "close": 1373.73, "high": 1374.22, "low": 1336.97, "changeRate": 3.0},
          {"ticker": "GLD", "open": 98.65, "close": 98.67, "high": 98.89, "low": 98.48, "changeRate": -0.09}
          ], "roundAsset": 9537122, "returnRate": -1.53
        },
        {
          "round": 60,
          "date": "2008-11-24",
          "priceData": [
          {"ticker": "^SPX", "open": 1075.44, "close": 1055.91, "high": 1080.51, "low": 1053.27, "changeRate": -1.62},
          {"ticker": "^NDX", "open": 1373.64, "close": 1331.56, "high": 1374.19, "low": 1331.29, "changeRate": -3.07},
          {"ticker": "GLD", "open": 98.63, "close": 99.76, "high": 99.86, "low": 98.56, "changeRate": 1.1}
          ], "roundAsset": 9492441, "returnRate": -1.99
        },
        {
          "round": 61,
          "date": "2008-11-25",
          "priceData": [
          {"ticker": "^SPX", "open": 1056.7, "close": 1025.18, "high": 1061.72, "low": 1020.06, "changeRate": -2.91},
          {"ticker": "^NDX", "open": 1333.85, "close": 1374.3, "high": 1376.15, "low": 1333.58, "changeRate": 3.21},
          {"ticker": "GLD", "open": 99.91, "close": 101.52, "high": 101.66, "low": 99.71, "changeRate": 1.76}
          ], "roundAsset": 9413486, "returnRate": -2.8
        },
        {
          "round": 62,
          "date": "2008-11-26",
          "priceData": [
          {"ticker": "^SPX", "open": 1026.56, "close": 1050.3, "high": 1052.88, "low": 1026.09, "changeRate": 2.45},
          {"ticker": "^NDX", "open": 1372.21, "close": 1338.02, "high": 1374.5, "low": 1333.54, "changeRate": -2.64},
          {"ticker": "GLD", "open": 101.74, "close": 102.16, "high": 102.26, "low": 101.53, "changeRate": 0.63}
          ], "roundAsset": 9478027, "returnRate": -2.14
        },
        {
          "round": 63,
          "date": "2008-11-27",
          "priceData": [
          {"ticker": "^SPX", "open": 1050.83, "close": 1033.18, "high": 1053.22, "low": 1031.56, "changeRate": -1.63},
          {"ticker": "^NDX", "open": 1335.66, "close": 1379.36, "high": 1386.05, "low": 1332.96, "changeRate": 3.09},
          {"ticker": "GLD", "open": 102.17, "close": 103.86, "high": 104.17, "low": 101.97, "changeRate": 1.66}
          ], "roundAsset": 9434040, "returnRate": -2.59
        },
        {
          "round": 64,
          "date": "2008-11-28",
          "priceData": [
          {"ticker": "^SPX", "open": 1031.75, "close": 1033.49, "high": 1037.4, "low": 1028.52, "changeRate": 0.03},
          {"ticker": "^NDX", "open": 1382.95, "close": 1366.95, "high": 1384.36, "low": 1363.2, "changeRate": -0.9},
          {"ticker": "GLD", "open": 104.13, "close": 102.66, "high": 104.27, "low": 102.44, "changeRate": -1.16}
          ], "roundAsset": 9434837, "returnRate": -2.58
        },
        {
          "round": 65,
          "date": "2008-12-01",
          "priceData": [
          {"ticker": "^SPX", "open": 1030.8, "close": 1005.48, "high": 1031.62, "low": 1002.71, "changeRate": -2.71},
          {"ticker": "^NDX", "open": 1367.66, "close": 1412.06, "high": 1412.72, "low": 1360.87, "changeRate": 3.3},
          {"ticker": "GLD", "open": 102.91, "close": 103.42, "high": 103.56, "low": 102.87, "changeRate": 0.74}
          ], "roundAsset": 9362870, "returnRate": -3.33
        },
        {
          "round": 66,
          "date": "2008-12-02",
          "priceData": [
          {"ticker": "^SPX", "open": 1005.57, "close": 1024.68, "high": 1026.08, "low": 1001.37, "changeRate": 1.91},
          {"ticker": "^NDX", "open": 1418.84, "close": 1408.39, "high": 1420.57, "low": 1404.51, "changeRate": -0.26},
          {"ticker": "GLD", "open": 103.35, "close": 104.68, "high": 104.97, "low": 103.19, "changeRate": 1.22}
          ], "roundAsset": 9412201, "returnRate": -2.82
        },
        {
          "round": 67,
          "date": "2008-12-03",
          "priceData": [
          {"ticker": "^SPX", "open": 1027.65, "close": 1047.43, "high": 1049.6, "low": 1022.85, "changeRate": 2.22},
          {"ticker": "^NDX", "open": 1408.5, "close": 1443.32, "high": 1449.24, "low": 1406.51, "changeRate": 2.48},
          {"ticker": "GLD", "open": 104.55, "close": 103.88, "high": 104.73, "low": 103.57, "changeRate": -0.76}
          ], "roundAsset": 9470653, "returnRate": -2.21
        },
        {
          "round": 68,
          "date": "2008-12-04",
          "priceData": [
          {"ticker": "^SPX", "open": 1045.81, "close": 1044.08, "high": 1048.7, "low": 1041.24, "changeRate": -0.32},
          {"ticker": "^NDX", "open": 1442.68, "close": 1401.61, "high": 1445.0, "low": 1400.29, "changeRate": -2.89},
          {"ticker": "GLD", "open": 104.0, "close": 104.32, "high": 104.5, "low": 103.93, "changeRate": 0.42}
          ], "roundAsset": 9462046, "returnRate": -2.3
        },
        {
          "round": 69,
          "date": "2008-12-05",
          "priceData": [
          {"ticker": "^SPX", "open": 1046.22, "close": 1060.16, "high": 1064.46, "low": 1044.2, "changeRate": 1.54},
          {"ticker": "^NDX", "open": 1403.9, "close": 1350.17, "high": 1409.66, "low": 1343.55, "changeRate": -3.67},
          {"ticker": "GLD", "open": 104.32, "close": 105.73, "high": 105.74, "low": 104.16, "changeRate": 1.35}
          ], "roundAsset": 9503361, "returnRate": -1.87
        },
        {
          "round": 70,
          "date": "2008-12-08",
          "priceData": [
          {"ticker": "^SPX", "open": 1059.53, "close": 1063.76, "high": 1066.56, "low": 1057.11, "changeRate": 0.34},
          {"ticker": "^NDX", "open": 1353.17, "close": 1384.19, "high": 1387.03, "low": 1348.74, "changeRate": 2.52},
          {"ticker": "GLD", "open": 105.51, "close": 107.77, "high": 107.92, "low": 105.2, "changeRate": 1.93}
          ], "roundAsset": 9512611, "returnRate": -1.78
        },
        {
          "round": 71,
          "date": "2008-12-09",
          "priceData": [
          {"ticker": "^SPX", "open": 1067.5, "close": 1049.93, "high": 1072.05, "low": 1045.42, "changeRate": -1.3},
          {"ticker": "^NDX", "open": 1382.53, "close": 1400.8, "high": 1403.02, "low": 1377.56, "changeRate": 1.2},
          {"ticker": "GLD", "open": 107.94, "close": 108.76, "high": 109.04, "low": 107.93, "changeRate": 0.92}
          ], "roundAsset": 9477077, "returnRate": -2.15
        },
        {
          "round": 72,
          "date": "2008-12-10",
          "priceData": [
          {"ticker": "^SPX", "open": 1055.15, "close": 1017.8, "high": 1059.09, "low": 1015.59, "changeRate": -3.06},
          {"ticker": "^NDX", "open": 1395.17, "close": 1411.03, "high": 1415.5, "low": 1389.08, "changeRate": 0.73},
          {"ticker": "GLD", "open": 108.72, "close": 111.09, "high": 111.32, "low": 108.43, "changeRate": 2.14}
          ], "roundAsset": 9394524, "returnRate": -3.0
        },
        {
          "round": 73,
          "date": "2008-12-11",
          "priceData": [
          {"ticker": "^SPX", "open": 1016.53, "close": 985.23, "high": 1017.27, "low": 982.61, "changeRate": -3.2},
          {"ticker": "^NDX", "open": 1411.96, "close": 1438.83, "high": 1444.53, "low": 1410.76, "changeRate": 1.97},
          {"ticker": "GLD", "open": 110.81, "close": 110.33, "high": 111.1, "low": 110.12, "changeRate": -0.68}
          ], "roundAsset": 9310841, "returnRate": -3.86
        },
        {
          "round": 74,
          "date": "2008-12-12",
          "priceData": [
          {"ticker": "^SPX", "open": 984.85, "close": 966.22, "high": 986.1, "low": 964.99, "changeRate": -1.93},
          {"ticker": "^NDX", "open": 1431.77, "close": 1479.84, "high": 1485.79, "low": 1425.32, "changeRate": 2.85},
          {"ticker": "GLD", "open": 110.45, "close": 108.83, "high": 110.5, "low": 108.69, "changeRate": -1.36}
          ], "roundAsset": 9261998, "returnRate": -4.37
        }
      ]
    }
  };

  // POST /game/round/action — 75라운드 카드 선택 (round 75~100)
  static Map<String, dynamic> actionResult4 = {
    "success": true,
    "message": "OK",
    "data": {
      "selectedCard": "금 피난처",
      "nextEventRound": null,
      "nextCardOptions": [],
      "rounds": [
        {
          "round": 75,
          "date": "2008-12-15",
          "priceData": [
          {"ticker": "^SPX", "open": 965.49, "close": 954.14, "high": 966.7, "low": 950.11, "changeRate": -1.25},
          {"ticker": "^NDX", "open": 1475.39, "close": 1485.91, "high": 1488.77, "low": 1471.83, "changeRate": 0.41},
          {"ticker": "GLD", "open": 108.66, "close": 109.79, "high": 109.98, "low": 108.47, "changeRate": 0.88}
          ], "roundAsset": 9261998, "returnRate": 0.0
        },
        {
          "round": 76,
          "date": "2008-12-16",
          "priceData": [
          {"ticker": "^SPX", "open": 955.65, "close": 982.29, "high": 983.64, "low": 952.95, "changeRate": 2.95},
          {"ticker": "^NDX", "open": 1488.67, "close": 1459.31, "high": 1494.21, "low": 1458.95, "changeRate": -1.79},
          {"ticker": "GLD", "open": 109.86, "close": 112.42, "high": 112.59, "low": 109.56, "changeRate": 2.4}
          ], "roundAsset": 9343975, "returnRate": 0.89
        },
        {
          "round": 77,
          "date": "2008-12-17",
          "priceData": [
          {"ticker": "^SPX", "open": 980.84, "close": 966.18, "high": 983.96, "low": 963.18, "changeRate": -1.64},
          {"ticker": "^NDX", "open": 1461.9, "close": 1488.35, "high": 1493.71, "low": 1457.08, "changeRate": 1.99},
          {"ticker": "GLD", "open": 112.65, "close": 113.24, "high": 113.45, "low": 112.34, "changeRate": 0.73}
          ], "roundAsset": 9297060, "returnRate": 0.38
        },
        {
          "round": 78,
          "date": "2008-12-18",
          "priceData": [
          {"ticker": "^SPX", "open": 966.95, "close": 972.94, "high": 976.5, "low": 966.51, "changeRate": 0.7},
          {"ticker": "^NDX", "open": 1485.3, "close": 1463.35, "high": 1490.85, "low": 1462.06, "changeRate": -1.68},
          {"ticker": "GLD", "open": 112.99, "close": 113.22, "high": 113.4, "low": 112.66, "changeRate": -0.02}
          ], "roundAsset": 9316746, "returnRate": 0.59
        },
        {
          "round": 79,
          "date": "2008-12-19",
          "priceData": [
          {"ticker": "^SPX", "open": 970.58, "close": 972.45, "high": 976.46, "low": 968.24, "changeRate": -0.05},
          {"ticker": "^NDX", "open": 1467.83, "close": 1505.06, "high": 1510.68, "low": 1465.34, "changeRate": 2.85},
          {"ticker": "GLD", "open": 112.96, "close": 115.19, "high": 115.52, "low": 112.91, "changeRate": 1.74}
          ], "roundAsset": 9315319, "returnRate": 0.58
        },
        {
          "round": 80,
          "date": "2008-12-22",
          "priceData": [
          {"ticker": "^SPX", "open": 977.12, "close": 999.48, "high": 1004.31, "low": 973.19, "changeRate": 2.78},
          {"ticker": "^NDX", "open": 1503.04, "close": 1541.93, "high": 1548.03, "low": 1502.94, "changeRate": 2.45},
          {"ticker": "GLD", "open": 115.22, "close": 116.64, "high": 116.8, "low": 114.99, "changeRate": 1.26}
          ], "roundAsset": 9394035, "returnRate": 1.43
        },
        {
          "round": 81,
          "date": "2008-12-23",
          "priceData": [
          {"ticker": "^SPX", "open": 1003.88, "close": 1008.18, "high": 1008.73, "low": 1002.71, "changeRate": 0.87},
          {"ticker": "^NDX", "open": 1534.61, "close": 1547.79, "high": 1554.63, "low": 1530.3, "changeRate": 0.38},
          {"ticker": "GLD", "open": 116.93, "close": 118.62, "high": 118.7, "low": 116.91, "changeRate": 1.7}
          ], "roundAsset": 9419371, "returnRate": 1.7
        },
        {
          "round": 82,
          "date": "2008-12-24",
          "priceData": [
          {"ticker": "^SPX", "open": 1007.26, "close": 1026.93, "high": 1027.65, "low": 1002.49, "changeRate": 1.86},
          {"ticker": "^NDX", "open": 1544.76, "close": 1591.44, "high": 1595.36, "low": 1544.01, "changeRate": 2.82},
          {"ticker": "GLD", "open": 118.9, "close": 117.86, "high": 118.95, "low": 117.7, "changeRate": -0.64}
          ], "roundAsset": 9473973, "returnRate": 2.29
        },
        {
          "round": 83,
          "date": "2008-12-25",
          "priceData": [
          {"ticker": "^SPX", "open": 1026.1, "close": 1035.76, "high": 1039.6, "low": 1025.31, "changeRate": 0.86},
          {"ticker": "^NDX", "open": 1590.09, "close": 1616.43, "high": 1617.23, "low": 1586.2, "changeRate": 1.57},
          {"ticker": "GLD", "open": 117.8, "close": 120.52, "high": 120.86, "low": 117.79, "changeRate": 2.26}
          ], "roundAsset": 9499688, "returnRate": 2.57
        },
        {
          "round": 84,
          "date": "2008-12-26",
          "priceData": [
          {"ticker": "^SPX", "open": 1039.44, "close": 1024.47, "high": 1039.96, "low": 1020.96, "changeRate": -1.09},
          {"ticker": "^NDX", "open": 1617.15, "close": 1605.6, "high": 1625.06, "low": 1602.72, "changeRate": -0.67},
          {"ticker": "GLD", "open": 120.45, "close": 123.27, "high": 123.34, "low": 120.41, "changeRate": 2.28}
          ], "roundAsset": 9466810, "returnRate": 2.21
        },
        {
          "round": 85,
          "date": "2008-12-29",
          "priceData": [
          {"ticker": "^SPX", "open": 1025.92, "close": 1045.06, "high": 1048.18, "low": 1025.81, "changeRate": 2.01},
          {"ticker": "^NDX", "open": 1610.2, "close": 1596.13, "high": 1612.16, "low": 1595.13, "changeRate": -0.59},
          {"ticker": "GLD", "open": 123.32, "close": 124.48, "high": 124.51, "low": 123.04, "changeRate": 0.98}
          ], "roundAsset": 9526771, "returnRate": 2.86
        },
        {
          "round": 86,
          "date": "2008-12-30",
          "priceData": [
          {"ticker": "^SPX", "open": 1043.27, "close": 1022.59, "high": 1044.04, "low": 1017.99, "changeRate": -2.15},
          {"ticker": "^NDX", "open": 1588.19, "close": 1558.14, "high": 1595.01, "low": 1557.01, "changeRate": -2.38},
          {"ticker": "GLD", "open": 124.2, "close": 126.86, "high": 126.96, "low": 124.13, "changeRate": 1.91}
          ], "roundAsset": 9461335, "returnRate": 2.15
        },
        {
          "round": 87,
          "date": "2008-12-31",
          "priceData": [
          {"ticker": "^SPX", "open": 1025.56, "close": 1030.77, "high": 1032.0, "low": 1023.9, "changeRate": 0.8},
          {"ticker": "^NDX", "open": 1553.06, "close": 1498.77, "high": 1553.47, "low": 1493.21, "changeRate": -3.81},
          {"ticker": "GLD", "open": 126.88, "close": 124.41, "high": 127.16, "low": 124.23, "changeRate": -1.93}
          ], "roundAsset": 9485156, "returnRate": 2.41
        },
        {
          "round": 88,
          "date": "2009-01-01",
          "priceData": [
          {"ticker": "^SPX", "open": 1030.81, "close": 1046.85, "high": 1051.8, "low": 1030.59, "changeRate": 1.56},
          {"ticker": "^NDX", "open": 1503.01, "close": 1496.52, "high": 1509.53, "low": 1492.62, "changeRate": -0.15},
          {"ticker": "GLD", "open": 124.38, "close": 122.53, "high": 124.74, "low": 122.51, "changeRate": -1.51}
          ], "roundAsset": 9531983, "returnRate": 2.91
        },
        {
          "round": 89,
          "date": "2009-01-02",
          "priceData": [
          {"ticker": "^SPX", "open": 1046.75, "close": 1042.77, "high": 1051.51, "low": 1042.39, "changeRate": -0.39},
          {"ticker": "^NDX", "open": 1490.25, "close": 1481.7, "high": 1494.78, "low": 1481.21, "changeRate": -0.99},
          {"ticker": "GLD", "open": 122.36, "close": 123.87, "high": 124.11, "low": 122.16, "changeRate": 1.09}
          ], "roundAsset": 9520102, "returnRate": 2.79
        },
        {
          "round": 90,
          "date": "2009-01-05",
          "priceData": [
          {"ticker": "^SPX", "open": 1042.29, "close": 1028.28, "high": 1045.45, "low": 1027.77, "changeRate": -1.39},
          {"ticker": "^NDX", "open": 1484.69, "close": 1532.97, "high": 1539.51, "low": 1479.86, "changeRate": 3.46},
          {"ticker": "GLD", "open": 124.07, "close": 124.35, "high": 124.62, "low": 123.99, "changeRate": 0.39}
          ], "roundAsset": 9477905, "returnRate": 2.33
        },
        {
          "round": 91,
          "date": "2009-01-06",
          "priceData": [
          {"ticker": "^SPX", "open": 1027.8, "close": 1022.52, "high": 1029.94, "low": 1022.03, "changeRate": -0.56},
          {"ticker": "^NDX", "open": 1531.85, "close": 1497.86, "high": 1536.94, "low": 1495.06, "changeRate": -2.29},
          {"ticker": "GLD", "open": 124.09, "close": 123.77, "high": 124.43, "low": 123.75, "changeRate": -0.47}
          ], "roundAsset": 9461131, "returnRate": 2.15
        },
        {
          "round": 92,
          "date": "2009-01-07",
          "priceData": [
          {"ticker": "^SPX", "open": 1024.96, "close": 1042.05, "high": 1046.28, "low": 1022.11, "changeRate": 1.91},
          {"ticker": "^NDX", "open": 1499.16, "close": 1448.43, "high": 1503.37, "low": 1446.04, "changeRate": -3.3},
          {"ticker": "GLD", "open": 123.49, "close": 121.83, "high": 123.62, "low": 121.59, "changeRate": -1.57}
          ], "roundAsset": 9518005, "returnRate": 2.76
        },
        {
          "round": 93,
          "date": "2009-01-08",
          "priceData": [
          {"ticker": "^SPX", "open": 1046.93, "close": 1056.43, "high": 1059.6, "low": 1045.09, "changeRate": 1.38},
          {"ticker": "^NDX", "open": 1449.56, "close": 1484.79, "high": 1486.37, "low": 1444.8, "changeRate": 2.51},
          {"ticker": "GLD", "open": 121.63, "close": 123.34, "high": 123.38, "low": 121.32, "changeRate": 1.24}
          ], "roundAsset": 9559882, "returnRate": 3.22
        },
        {
          "round": 94,
          "date": "2009-01-09",
          "priceData": [
          {"ticker": "^SPX", "open": 1059.68, "close": 1044.7, "high": 1064.16, "low": 1039.61, "changeRate": -1.11},
          {"ticker": "^NDX", "open": 1489.52, "close": 1510.33, "high": 1514.96, "low": 1484.73, "changeRate": 1.72},
          {"ticker": "GLD", "open": 122.99, "close": 124.06, "high": 124.41, "low": 122.68, "changeRate": 0.58}
          ], "roundAsset": 9525722, "returnRate": 2.85
        },
        {
          "round": 95,
          "date": "2009-01-12",
          "priceData": [
          {"ticker": "^SPX", "open": 1042.7, "close": 1026.31, "high": 1044.47, "low": 1026.28, "changeRate": -1.76},
          {"ticker": "^NDX", "open": 1515.92, "close": 1470.31, "high": 1520.21, "low": 1467.36, "changeRate": -2.65},
          {"ticker": "GLD", "open": 123.79, "close": 125.5, "high": 125.74, "low": 123.78, "changeRate": 1.16}
          ], "roundAsset": 9472168, "returnRate": 2.27
        },
        {
          "round": 96,
          "date": "2009-01-13",
          "priceData": [
          {"ticker": "^SPX", "open": 1024.68, "close": 1040.17, "high": 1042.09, "low": 1020.98, "changeRate": 1.35},
          {"ticker": "^NDX", "open": 1474.38, "close": 1435.17, "high": 1478.56, "low": 1434.56, "changeRate": -2.39},
          {"ticker": "GLD", "open": 125.16, "close": 125.36, "high": 125.42, "low": 124.93, "changeRate": -0.11}
          ], "roundAsset": 9512530, "returnRate": 2.7
        },
        {
          "round": 97,
          "date": "2009-01-14",
          "priceData": [
          {"ticker": "^SPX", "open": 1040.02, "close": 1049.32, "high": 1051.64, "low": 1038.6, "changeRate": 0.88},
          {"ticker": "^NDX", "open": 1438.83, "close": 1407.04, "high": 1439.65, "low": 1404.02, "changeRate": -1.96},
          {"ticker": "GLD", "open": 125.2, "close": 126.59, "high": 126.85, "low": 125.02, "changeRate": 0.98}
          ], "roundAsset": 9539176, "returnRate": 2.99
        },
        {
          "round": 98,
          "date": "2009-01-15",
          "priceData": [
          {"ticker": "^SPX", "open": 1050.36, "close": 1058.13, "high": 1058.17, "low": 1048.78, "changeRate": 0.84},
          {"ticker": "^NDX", "open": 1402.98, "close": 1355.54, "high": 1403.94, "low": 1353.81, "changeRate": -3.66},
          {"ticker": "GLD", "open": 126.46, "close": 126.31, "high": 126.46, "low": 126.03, "changeRate": -0.22}
          ], "roundAsset": 9564833, "returnRate": 3.27
        },
        {
          "round": 99,
          "date": "2009-01-16",
          "priceData": [
          {"ticker": "^SPX", "open": 1058.13, "close": 1033.16, "high": 1062.54, "low": 1029.0, "changeRate": -2.36},
          {"ticker": "^NDX", "open": 1349.74, "close": 1339.95, "high": 1355.56, "low": 1339.67, "changeRate": -1.15},
          {"ticker": "GLD", "open": 125.95, "close": 127.79, "high": 128.14, "low": 125.62, "changeRate": 1.17}
          ], "roundAsset": 9492116, "returnRate": 2.48
        },
        {
          "round": 100,
          "date": "2009-01-19",
          "priceData": [
          {"ticker": "^SPX", "open": 1032.31, "close": 1035.64, "high": 1036.24, "low": 1032.2, "changeRate": 0.24},
          {"ticker": "^NDX", "open": 1337.6, "close": 1343.97, "high": 1349.35, "low": 1333.47, "changeRate": 0.3},
          {"ticker": "GLD", "open": 128.04, "close": 129.31, "high": 129.67, "low": 128.01, "changeRate": 1.19}
          ], "roundAsset": 9499338, "returnRate": 2.56
        }
      ]
    }
  };

  // 현재 라운드 기준으로 맞는 actionResult 반환
  static Map<String, dynamic> getActionResult(int roundIndex) {
    if (roundIndex < 25)  return actionResult1;
    if (roundIndex < 50)  return actionResult2;
    if (roundIndex < 75)  return actionResult3;
    return actionResult4;
  }
}