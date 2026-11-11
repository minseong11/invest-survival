import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import '../models/scenario.dart';
import '../models/game_session.dart';
import '../services/game_service.dart';
import '../services/mock_data.dart';
import '../widgets/scenario_card.dart';
import '../widgets/toss/toss_widgets.dart';
import '../theme/toss_theme.dart';
import 'game_screen.dart';

class ScenarioScreen extends StatefulWidget {
  const ScenarioScreen({super.key});

  @override
  State<ScenarioScreen> createState() => _ScenarioScreenState();
}

class _ScenarioScreenState extends State<ScenarioScreen> {
  final GameService _gameService = GameService();

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
      setState(() {
        _scenarios = data;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  // 임시 데이터로 불러오기 (fromJson 거침)
  void _loadMockScenarios() {
    setState(() => _isLoading = true);
    final List<dynamic> list = MockData.scenarios['data'] as List<dynamic>;
    final scenarios = list.map((json) => Scenario.fromJson(json)).toList();
    setState(() {
      _scenarios = scenarios;
      _isLoading = false;
    });
  }

  Future<void> _onScenarioTap(Scenario scenario) async {
    setState(() => _isStarting = true);
    try {
      final gameSession = await _gameService.startGame(scenario.id);
      if (!mounted) return;
      setState(() => _isStarting = false);
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => GameScreen(session: gameSession)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isStarting = false);
      showTossToast(context, e.toString());
    }
  }

  void _startMockGame(Scenario scenario) {
    final gameSession = GameSession.fromJson(
      MockData.gameSession['data'] as Map<String, dynamic>,
    );
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => GameScreen(session: gameSession)),
    );
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
            // 개발용 버튼: 디버그 실행에서만 표시
            if (kDebugMode)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                child: _buildMockButtons(),
              ),
            const SizedBox(height: 16),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildMockButtons() {
    return Row(
      children: [
        const TossBadge(
            label: '개발용', bg: TossColors.grey100, fg: TossColors.grey600),
        const SizedBox(width: 8),
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _mockButton(label: '수동 요청', onTap: _loadScenarios),
              _mockButton(label: '임시 시나리오', onTap: _loadMockScenarios),
              _mockButton(
                label: '임시 게임',
                onTap: _scenarios.isEmpty
                    ? null
                    : () => _startMockGame(_scenarios[0]),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _mockButton({
    required String label,
    required VoidCallback? onTap,
  }) {
    return TossChipButton(
      label: label,
      onTap: onTap,
      bg: TossColors.grey100,
      fg: onTap == null ? TossColors.grey400 : TossColors.grey700,
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
            if (kDebugMode) ...[
              const SizedBox(height: 8),
              TossButton(
                label: '임시 데이터로 계속하기',
                type: TossButtonType.secondary,
                onTap: _loadMockScenarios,
                height: 52,
              ),
            ],
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
    return const FadeInUp(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('투자 서바이벌',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: TossColors.blue500)),
          SizedBox(height: 8),
          Text('어떤 위기에서\n살아남아 볼까요?', style: TossText.title1),
          SizedBox(height: 8),
          Text('과거 시장으로 돌아가 내 전략을 시험해 보세요', style: TossText.sub),
        ],
      ),
    );
  }
}
