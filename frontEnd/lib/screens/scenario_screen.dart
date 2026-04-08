import 'package:flutter/material.dart';
import '../models/scenario.dart';
import '../models/game_session.dart';
import '../services/game_service.dart';
import '../services/mock_data.dart';
import '../widgets/scenario_card.dart';
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          backgroundColor: Colors.red[700],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
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
      backgroundColor: const Color(0xFFFAF9F5),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 20),
              _buildMockButtons(),
              const SizedBox(height: 20),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMockButtons() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3CD),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFD700), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '개발용 임시 버튼',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF856404),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              // 수동 API 요청 버튼
              Expanded(
                child: _mockButton(
                  label: '시나리오 수동 요청',
                  onTap: _loadScenarios,
                ),
              ),
              const SizedBox(width: 8),
              // 임시 mock 데이터 버튼
              Expanded(
                child: _mockButton(
                  label: '임시 시나리오 불러오기',
                  onTap: _loadMockScenarios,
                ),
              ),
              const SizedBox(width: 8),
              // 임시 게임 바로 시작
              Expanded(
                child: _mockButton(
                  label: '임시 게임 시작',
                  onTap: _scenarios.isEmpty
                      ? null
                      : () => _startMockGame(_scenarios[0]),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _mockButton({
    required String label,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: onTap == null
              ? const Color(0xFFEEEEEE)
              : const Color(0xFF111111),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: onTap == null
                ? const Color(0xFFAAAAAA)
                : Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 36, color: Color(0xFF6B7684)),
            const SizedBox(height: 12),
            Text(
              _errorMessage!,
              style: const TextStyle(color: Color(0xFF6B7684)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: _loadScenarios,
                  child: const Text('다시 시도'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _loadMockScenarios,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF111111),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('임시 데이터로 계속', style: TextStyle(fontSize: 13)),
                ),
              ],
            ),
          ],
        ),
      );
    }
    if (_scenarios.isEmpty) {
      return const Center(
        child: Text(
          '시나리오를 불러올 수 없어요',
          style: TextStyle(color: Color(0xFF6B7684)),
        ),
      );
    }
    if (_isStarting) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              '게임 데이터 불러오는 중...',
              style: TextStyle(color: Color(0xFF6B7684)),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      itemCount: _scenarios.length,
      itemBuilder: (context, index) {
        return ScenarioCard(
          scenario: _scenarios[index],
          onTap: () => _onScenarioTap(_scenarios[index]),
        );
      },
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFEEEDFE),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Text(
            '투자 서바이벌',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF3C3489),
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          '시나리오를\n선택하세요',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: Color(0xFF111111),
            height: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          '과거의 시장 위기에서 살아남아 보세요',
          style: TextStyle(
            fontSize: 14,
            color: Color(0xFF6B7684),
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }
}