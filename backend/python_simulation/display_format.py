"""
display_format.py — 글에 넣는 숫자의 반올림을 앱과 맞춘다 (#125)

같은 값이 앱(Dart)과 AI 서버(Python) 양쪽에서 소수 1자리로 표시된다.
  예: 결과 화면의 수익률 막대 "-13.3%"와 AI 코치 문장 "내 자산은 13.3% 줄었어요"

두 언어는 "정확히 절반"인 값을 다르게 반올림한다.
  - Dart   (-13.25).toStringAsFixed(1)  → "-13.3"  (0에서 먼 쪽)
  - Python f'{-13.25:.1f}'              → "-13.2"  (짝수 쪽)
그래서 Python의 기본 서식을 쓰면 같은 화면에 13.3%와 13.2%가 함께 나올 수 있다
(서버 값은 소수 2자리라 x.x25로 끝나는 값에서 생긴다).
→ 화면에 나가는 글의 숫자는 fixed()로 만든다.

둘 다 실수의 실제 값(이진수)을 기준으로 반올림하므로 절반이 아닌 값은 원래 같다.
  예: 13.35는 실제로 13.3499…라서 양쪽 모두 "13.3"

같은 표로 양쪽을 확인한다: tests/test_display_format.py, frontEnd/test/format_test.dart
"""
import math
from decimal import Decimal, ROUND_HALF_UP


def fixed(value: float, digits: int = 1) -> str:
    """소수 digits자리 문자열 — Dart의 toStringAsFixed(digits)와 같은 글자"""
    v = float(value)
    if not math.isfinite(v):
        return f'{v:.{digits}f}'
    step = Decimal(1).scaleb(-digits)   # digits=1 → 0.1
    return str(Decimal(v).quantize(step, rounding=ROUND_HALF_UP))
