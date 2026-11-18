import 'package:flutter/material.dart';
import '../models/scenario.dart';
import '../services/game_service.dart';
import '../widgets/scenario_card.dart';
import '../widgets/toss/toss_widgets.dart';
import '../theme/toss_theme.dart';
import 'game_screen.dart';

class ScenarioScreen extends StatefulWidget {
  // 테스트에서 가짜 서버를 넣을 수 있게 (없으면 실제 서버)
  final GameService? service;
  const ScenarioScreen({super.key, this.service});

  @override
  State<ScenarioScreen> createState() => _ScenarioScreenState();
}

class _ScenarioScreenState extends State<ScenarioScreen> {
  late final GameService _gameService = widget.service ?? GameService();

  bool _isLoading = false;
  bool _isStarting = false;
  String? _errorMessage;
  List<Scenario> _scenarios = [];

  @override
  void initState() {
    super.initState();
    _loadScenarios(); // 진입하자마자 자동 호출
  }

  // 실제 API 호출
  Future<void> _loadScenarios() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final data = await _gameService.getScenarios();
      if (!mounted) return;
      setState(() {
        _scenarios = data;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _onScenarioTap(Scenario scenario) async {
    setState(() => _isStarting = true);
    try {
      final gameSession = await _gameService.startGame(scenario.id);
      if (!mounted) return;
      setState(() => _isStarting = false);
      Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) =>
                GameScreen(session: gameSession, service: widget.service)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isStarting = false);
      showTossToast(context, e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TossColors.white,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 36, 24, 8),
              child: _buildHeader(),
            ),
            const SizedBox(height: 16),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
      );
    }
    if (_errorMessage != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const EmojiTile(emoji: '📡', size: 64),
            const SizedBox(height: 20),
            const Text('서버에 연결하지 못했어요', style: TossText.title3),
            const SizedBox(height: 6),
            Text(
              _errorMessage!,
              style: TossText.caption,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 28),
            TossButton(
              label: '다시 시도하기',
              onTap: _loadScenarios,
              height: 52,
            ),
          ],
        ),
      );
    }
    if (_scenarios.isEmpty) {
      return const Center(
        child: Text('아직 고를 수 있는 시나리오가 없어요', style: TossText.sub),
      );
    }
    if (_isStarting) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            SizedBox(height: 20),
            Text('그때의 시장을 불러오고 있어요', style: TossText.sub),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      itemCount: _scenarios.length,
      itemBuilder: (context, index) {
        return FadeInUp(
          delay: Duration(milliseconds: 60 * index),
          child: ScenarioCard(
            scenario: _scenarios[index],
            onTap: () => _onScenarioTap(_scenarios[index]),
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
    return FadeInUp(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('투자 서바이벌',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: TossColors.blue500)),
              ),
              // (#125) 처음 하는 사람을 위한 게임 방법
              TossChipButton(
                label: '게임 방법',
                onTap: _showHowTo,
                bg: TossColors.grey100,
                fg: TossColors.grey700,
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text('어떤 위기에서\n살아남아 볼까요?', style: TossText.title1),
          const SizedBox(height: 8),
          const Text('과거 시장으로 돌아가 내 전략을 시험해 보세요', style: TossText.sub),
        ],
      ),
    );
  }

  // (#125) 게임 방법 안내
  void _showHowTo() {
    Widget step(String emoji, String title, String body) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            EmojiTile(emoji: emoji, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TossText.body2),
                  const SizedBox(height: 2),
                  Text(body, style: TossText.caption),
                ],
              ),
            ),
          ],
        ),
      );
    }

    showTossSheet(
      context,
      title: '이렇게 진행돼요',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          step('💰', '1,000만원으로 100라운드',
              '실제 금융위기 때의 하루가 한 라운드예요. 약 5개월의 시장을 지나가요.'),
          step('🃏', '전략 카드 4장',
              '1·25·50·75라운드에 후보 3장 중 1장을 골라요. 카드는 정해진 규칙대로 알아서 사고팔아요.'),
          step('🚨', '속보가 나오면 위기 대응',
              '큰 뉴스가 나온 날에는 게임이 멈춰요. 버틸지, 절반을 팔지, 더 살지 직접 정해요.'),
          step('✨', '25·50라운드에는 AI 예측',
              '과거 시장으로 학습한 AI가 후보 카드를 비교해 줘요. 참고만 하고 결정은 내가 해요.'),
          step('🔍', '끝나면 돌아보기',
              '가능한 모든 카드 조합과 비교한 등급, 카드별 성적표, 그때 다르게 대응했다면 어땠을지를 보여줘요.'),
        ],
      ),
    );
  }
}
