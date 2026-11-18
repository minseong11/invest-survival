"""
글에 넣는 숫자의 반올림이 앱(Dart)과 같은지 (#125)

같은 표가 frontEnd/test/format_test.dart에 있다 ("AI 서버 글과 같은 반올림").
한쪽 표를 바꾸면 다른 쪽도 같이 바꿔야 한다.
"""
import pytest

from display_format import fixed

# (값, 소수 자릿수, 앱이 표시하는 글자)
CASES = [
    (13.25, 1, '13.3'),      # 정확히 절반 → 0에서 먼 쪽 (Python 기본 서식은 '13.2')
    (-13.25, 1, '-13.3'),
    (0.25, 1, '0.3'),
    (13.75, 1, '13.8'),
    (2.5, 0, '3'),
    (0.125, 2, '0.13'),
    (13.35, 1, '13.3'),      # 실제 값이 13.3499… → 양쪽 모두 내림
    (21.65, 1, '21.6'),
    (0.05, 1, '0.1'),        # 실제 값이 0.05000…0277 → 양쪽 모두 올림
    (99.95, 1, '100.0'),
    (-34.9, 1, '-34.9'),
    (10.0, 1, '10.0'),
    (0.0, 1, '0.0'),
    (1.005, 2, '1.00'),
    (8.345, 2, '8.35'),
]


@pytest.mark.parametrize('value, digits, expected', CASES)
def test_fixed_matches_app(value, digits, expected):
    assert fixed(value, digits) == expected


def test_default_is_one_digit_and_accepts_int():
    assert fixed(7) == '7.0'
    assert fixed(-2) == '-2.0'


def test_differs_from_builtin_format_only_at_exact_halves():
    """기본 서식과 다른 곳은 정확히 절반인 값뿐 — 그 밖의 값은 원래 앱과 같았다"""
    different = [(v, d) for v, d, _ in CASES if fixed(v, d) != f'{v:.{d}f}']
    assert different == [(13.25, 1), (-13.25, 1), (0.25, 1), (2.5, 0), (0.125, 2)]


def test_two_digit_values_differ_from_builtin_only_at_x25():
    """
    서버가 보내는 값은 소수 2자리. -99.99~99.99 전체에서 기본 서식과 다른 값은 x.x25뿐이고
    (소수 2자리 중 이진수로 정확히 표현되는 절반 값), 그때는 0에서 먼 쪽으로 반올림한다.
    """
    for i in range(-9999, 10000):
        v = i / 100
        ours, builtin = fixed(v, 1), f'{v:.1f}'
        if abs(i) % 100 == 25:
            assert ours != builtin and abs(float(ours)) > abs(v), (v, ours, builtin)
        else:
            assert ours == builtin, (v, ours, builtin)
