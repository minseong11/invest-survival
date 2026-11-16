"""
카드 규칙이 적힌 곳들이 서로 어긋나지 않는지 확인 (#125)

카드 규칙은 네 곳에 적혀 있다.
  1) backend/python_simulation/game_logic.py  CARDS            — Python 계산
  2) backend/src/main/resources/data.sql      card 테이블       — Java 계산 (서버가 실제로 쓰는 값)
  3) backend/python_simulation/verify_feedback.py CARD_FACTS    — AI 설명·검증기 (test_card_facts.py가 1과 비교)
  4) frontEnd/lib/models/card_info.dart                        — 앱 화면의 카드 설명
교수님 3주차 피드백(카드 정보가 여러 곳에 흩어져 어긋날 위험)에 따라 1↔3은 이미 검사하고 있었고,
여기서는 1↔2(계산에 쓰는 값)와 1↔2·4의 설명 문구(조건 %·비율·횟수)를 검사한다.
"""
import os
import re

import pytest

from game_logic import CARDS

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
DATA_SQL = os.path.join(REPO, 'backend', 'src', 'main', 'resources', 'data.sql')
CARD_INFO = os.path.join(REPO, 'frontEnd', 'lib', 'models', 'card_info.dart')

# data.sql 종목 이름 → game_logic 종목 이름
TICKER_ALIAS = {'XAUUSD': 'GLD'}

ROW = re.compile(
    r"\(\s*(\d+),\s*'([^']+)',\s*'([^']+)',\s*([\d.]+),\s*'([^']+)',\s*'([A-Z_]+)',\s*"
    r"(null|'[^']+'),\s*(null|\d+),\s*(\d+)\)")


def sql_cards():
    text = open(DATA_SQL, encoding='utf-8').read()
    block = text[text.index('INSERT INTO card'):text.index('ON CONFLICT (id) DO UPDATE SET\n    name')]
    cards = {}
    for m in ROW.finditer(block):
        cid, name, ticker, ratio, desc, ctype, cond, max_trigger, priority = m.groups()
        cards[int(cid)] = {
            'name': name,
            'ticker': TICKER_ALIAS.get(ticker, ticker),
            'ratio': float(ratio),
            'description': desc,
            'type': ctype,
            'condition': None if cond == 'null' else cond.strip("'"),
            'max_trigger': None if max_trigger == 'null' else int(max_trigger),
            'priority': int(priority),
        }
    return cards


def dart_cards():
    text = open(CARD_INFO, encoding='utf-8').read()
    cards = {}
    for m in re.finditer(r"CardInfo\(\s*id:\s*(\d+),\s*name:\s*'([^']+)',\s*description:\s*'([^']+)'", text):
        cards[int(m.group(1))] = {'name': m.group(2), 'description': m.group(3)}
    return cards


def test_all_sources_have_the_same_cards():
    assert set(sql_cards()) == set(CARDS)
    assert set(dart_cards()) == set(CARDS)


@pytest.mark.parametrize('card_id', sorted(CARDS))
def test_server_rules_match_python_rules(card_id):
    sql, py = sql_cards()[card_id], CARDS[card_id]
    for key in ('name', 'ticker', 'ratio', 'type', 'condition', 'max_trigger', 'priority'):
        assert sql[key] == py[key], f'{py["name"]}: {key} — data.sql {sql[key]!r} ≠ game_logic {py[key]!r}'


def numbers_in(text):
    return {float(x) for x in re.findall(r'\d+(?:\.\d+)?', text.replace('S&P500', '').replace('나스닥100', ''))}


@pytest.mark.parametrize('card_id', sorted(CARDS))
@pytest.mark.parametrize('source', ['data.sql', 'card_info.dart'])
def test_descriptions_state_the_real_numbers(card_id, source):
    card = CARDS[card_id]
    desc = (sql_cards() if source == 'data.sql' else dart_cards())[card_id]['description']
    found = numbers_in(desc)

    expected = {round(card['ratio'] * 100, 6)}                              # 매수·매도 비율(%)
    if card['condition']:
        expected.add(abs(float(re.search(r'-?\d+(?:\.\d+)?', card['condition']).group())))   # 조건 %
    if card['max_trigger'] is not None:
        expected.add(float(card['max_trigger']))                           # 최대 횟수
    if card['type'] == 'BUY_EVERY_N':
        expected.add(5.0)                                                  # 5라운드마다
    if card['type'] == 'BUY_ONCE':
        expected.add(1.0)                                                  # (1번)

    assert found == expected, f'{card["name"]} ({source}): 설명 "{desc}"의 숫자 {sorted(found)} ≠ 규칙 {sorted(expected)}'

    # 방향(떨어진/오른)과 매수·매도가 규칙과 같은지
    if card['condition']:
        falling = '<=' in card['condition']
        assert ('떨어진' in desc) == falling and ('오른' in desc) == (not falling), f'{card["name"]} ({source}): {desc}'
    assert ('매도' in desc) == (card['type'] == 'SELL_ON_CONDITION'), f'{card["name"]} ({source}): {desc}'


@pytest.mark.parametrize('card_id', sorted(CARDS))
def test_app_and_server_use_the_same_name(card_id):
    assert dart_cards()[card_id]['name'] == CARDS[card_id]['name'] == sql_cards()[card_id]['name']
