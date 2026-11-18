"""
기존 스크립트형 테스트를 pytest에서도 실행 (#125)

test_card_facts.py / test_verify_feedback.py / test_feedback_pipeline.py는
`python3 파일이름.py`로 실행해 눈으로 결과를 읽는 방식이었다.
그 스크립트를 그대로 불러 실패가 0건인지 확인해서, `pytest` 한 번과 CI에서 함께 검사되게 한다.
"""
import fastapi_server as fs


def test_card_facts_match_game_logic(capsys):
    import test_card_facts
    assert test_card_facts.main() == 0, capsys.readouterr().out


def test_verifier_self_test(capsys):
    import test_verify_feedback
    assert test_verify_feedback.run() == [], capsys.readouterr().out


def test_feedback_pipeline(capsys):
    import test_feedback_pipeline
    original = fs.client.messages.create
    try:
        assert test_feedback_pipeline.main() == 0, capsys.readouterr().out
    finally:
        fs.client.messages.create = original
