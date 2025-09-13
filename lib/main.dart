// lib/main.dart
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

void main() {
  runApp(const FocusApp());
}

class FocusApp extends StatelessWidget {
  const FocusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Focus Tracker',
      theme: ThemeData.light().copyWith(
        scaffoldBackgroundColor: Colors.white,
      ),
      home: const FocusHomePage(),
    );
  }
}

class FocusHomePage extends StatefulWidget {
  const FocusHomePage({super.key});

  @override
  State<FocusHomePage> createState() => _FocusHomePageState();
}

class _FocusHomePageState extends State<FocusHomePage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  // --- User & focus state
  String username = "User";
  double focusPercentage = 100.0; // starts at 100%

  // --- Timer state
  int remainingSeconds = 300; // default 5:00
  bool isTimerRunning = false;
  Timer? _uiTimer; // updates the UI every second
  DateTime? targetEndTime;

  // --- App background tracking
  DateTime? _backgroundTime;
  int _consecutiveActiveSeconds = 0;

  // --- Shimmer animation for focus bar
  late AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _uiTimer?.cancel();
    _shimmerController.dispose();
    super.dispose();
  }

  // --- App lifecycle handling
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!isTimerRunning) return;

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _backgroundTime ??= DateTime.now();
        _uiTimer?.cancel();
        _consecutiveActiveSeconds = 0;
        break;
      case AppLifecycleState.resumed:
        if (_backgroundTime != null) {
          final awaySeconds = DateTime.now().difference(_backgroundTime!).inSeconds;
          if (awaySeconds > 0) {
            setState(() {
              focusPercentage = (focusPercentage - awaySeconds * 0.2).clamp(0.0, 100.0);
              // Update remainingSeconds correctly using targetEndTime
              if (targetEndTime != null) {
                remainingSeconds = max(0, targetEndTime!.difference(DateTime.now()).inSeconds);
                if (remainingSeconds == 0) isTimerRunning = false;
              }
            });
          }
        }
        _backgroundTime = null;
        if (isTimerRunning && targetEndTime != null) _startUITimer();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  // --- Timer management using targetEndTime
  void _startTimer() {
    if (isTimerRunning) return;
    setState(() {
      isTimerRunning = true;
      targetEndTime = DateTime.now().add(Duration(seconds: remainingSeconds));
    });
    _startUITimer();
  }

  void _startUITimer() {
    _uiTimer?.cancel();
    _consecutiveActiveSeconds = 0;

    _uiTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (targetEndTime == null) return;

      final newRemaining = max(0, targetEndTime!.difference(DateTime.now()).inSeconds);
      setState(() {
        remainingSeconds = newRemaining;

        // On-app recovery
        _consecutiveActiveSeconds++;
        if (_consecutiveActiveSeconds >= 5) {
          focusPercentage = (focusPercentage + 0.05).clamp(0.0, 100.0);
          _consecutiveActiveSeconds = 0;
        }

        if (remainingSeconds == 0) {
          isTimerRunning = false;
          _uiTimer?.cancel();
        }
      });
    });
  }

  void _pauseTimer() {
    _uiTimer?.cancel();
    if (targetEndTime != null) {
      // recalc remainingSeconds
      remainingSeconds = max(0, targetEndTime!.difference(DateTime.now()).inSeconds);
    }
    setState(() {
      isTimerRunning = false;
    });
  }

  void _togglePlayPause() {
    if (isTimerRunning) {
      _pauseTimer();
    } else {
      _startTimer();
    }
  }

  // --- Set timer dialog
  Future<void> _showSetTimeDialog() async {
    if (isTimerRunning) return;

    final minutesController = TextEditingController(text: (remainingSeconds ~/ 60).toString());
    final secondsController = TextEditingController(text: (remainingSeconds % 60).toString());

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Set Timer (mm:ss)'),
        content: Row(
          children: [
            Expanded(
              child: TextField(
                controller: minutesController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Minutes'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: secondsController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Seconds'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final m = int.tryParse(minutesController.text) ?? 0;
              final s = int.tryParse(secondsController.text) ?? 0;
              setState(() {
                remainingSeconds = m * 60 + s;
              });
              Navigator.pop(context, true);
            },
            child: const Text('Set'),
          ),
        ],
      ),
    );
  }

  // --- Edit username
  Future<void> _editUsername() async {
    final controller = TextEditingController(text: username);
    final result = await showDialog<String?>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change Name'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      setState(() {
        username = result;
      });
    }
  }

  String _formatTime(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  // --- Focus bar
  Widget _focusBar() {
    final targetColor = Color.lerp(Colors.red, Colors.green, focusPercentage / 100)!;

    return Container(
      width: 280,
      height: 22,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black26, width: 1.5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeInOut,
              width: 280 * (focusPercentage / 100),
              decoration: BoxDecoration(color: targetColor),
            ),
            AnimatedBuilder(
              animation: _shimmerController,
              builder: (context, _) {
                return Positioned.fill(
                  child: ShaderMask(
                    shaderCallback: (rect) {
                      return LinearGradient(
                        colors: [
                          Colors.white.withOpacity(0.25),
                          Colors.transparent,
                          Colors.white.withOpacity(0.25),
                        ],
                        stops: const [0.0, 0.5, 1.0],
                        begin: Alignment(-1.0 + _shimmerController.value * 2, 0),
                        end: Alignment(1.0 - _shimmerController.value * 2, 0),
                      ).createShader(rect);
                    },
                    blendMode: BlendMode.srcOver,
                    child: Container(color: Colors.transparent),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _playPauseButton() {
    return GestureDetector(
      onTap: _togglePlayPause,
      child: Container(
        width: 110,
        height: 110,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: [Color(0xFFFF9AA2), Color(0xFFFF6F91)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.pink.withOpacity(0.25),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Center(
          child: Icon(
            isTimerRunning ? Icons.pause : Icons.play_arrow,
            size: 52,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  // --- Lightning button random code
  String _generateRandomString() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rand = Random();
    return List.generate(6, (_) => chars[rand.nextInt(chars.length)]).join();
  }

  void _showRandomString() {
    final code = _generateRandomString();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Your Random Code'),
        content: Text(
          code,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            GestureDetector(
              onTap: _editUsername,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                alignment: Alignment.center,
                child: Text(
                  username,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.black54),
                ),
              ),
            ),
            const Spacer(),
            Text(
              'Focus: ${focusPercentage.toStringAsFixed(2)}%',
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
            const SizedBox(height: 12),
            _focusBar(),
            const SizedBox(height: 30),
            GestureDetector(
              onTap: _showSetTimeDialog,
              child: Text(
                _formatTime(remainingSeconds),
                style: const TextStyle(fontSize: 56, fontWeight: FontWeight.bold, color: Colors.black),
              ),
            ),
            const SizedBox(height: 24),
            _playPauseButton(),
            const Spacer(),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showRandomString,
        backgroundColor: Colors.yellow.shade700,
        child: const Icon(Icons.flash_on, color: Colors.white, size: 32),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}
