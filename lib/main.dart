// lib/main.dart
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:convert';
// WebSocket server hostname
const String hostname = "ws://172.26.123.7:8000"; // Change as needed

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

  // Send a JSON object to the WebSocket if it exists
  void sendJsonToWebSocket(Map<String, dynamic> jsonObject) {
    if (_webSocketChannel != null) {
      try {
        _webSocketChannel!.sink.add(jsonEncode(jsonObject));
        print('Sent to WebSocket: ${jsonEncode(jsonObject)}');
      } catch (e) {
        print('Error sending to WebSocket: $e');
      }
    } else {
      print('WebSocket is not connected.');
    }
  }
  WebSocketChannel? _webSocketChannel;
  String username = "User";
  double focusPercentage = 100.0;
  int remainingSeconds = 300;
  bool isTimerRunning = false;
  Timer? _uiTimer;
  DateTime? targetEndTime;
  DateTime? _backgroundTime;
  int _consecutiveActiveSeconds = 0;
  late AnimationController _shimmerController;
  // Mock opponent (later will be updated via WebSockets)
  String opponentName = "Opponent1";
  double opponentScore = 87.0;

  // Session code generated once on app load but can be changed
  late String sessionCode;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    sessionCode = _generateRandomString();
    
    // Auto-connect to WebSocket with the session code on app startup
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _connectToWebSocket(sessionCode);
    });
  }
  
  // Connect to WebSocket using the provided code
  void _connectToWebSocket(String code) {
    try {
      final channel = WebSocketChannel.connect(
        Uri.parse('$hostname/ws/$code'),
      );
      setState(() {
        _webSocketChannel?.sink.close();
        _webSocketChannel = channel;
      });
      print('WebSocketChannel connected to: $hostname/ws/$code');
      
      // Send username immediately after connection is established
      Future.delayed(const Duration(milliseconds: 500), () {
        sendJsonToWebSocket({
          'type': 'set_username',
          'value': username
        });
        print('Initial username sent: $username');
      });
    } catch (e) {
      print('WebSocketChannel connection failed: $e');
    }
  }

  @override
  void dispose() {
  WidgetsBinding.instance.removeObserver(this);
  _uiTimer?.cancel();
  _shimmerController.dispose();
  _webSocketChannel?.sink.close();
  super.dispose();
  }

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
          final awaySeconds =
              DateTime.now().difference(_backgroundTime!).inSeconds;
          if (awaySeconds > 0) {
            setState(() {
              focusPercentage =
                  (focusPercentage - awaySeconds * 0.2).clamp(0.0, 100.0);
              if (targetEndTime != null) {
                remainingSeconds =
                    max(0, targetEndTime!.difference(DateTime.now()).inSeconds);
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
      final newRemaining =
          max(0, targetEndTime!.difference(DateTime.now()).inSeconds);

      setState(() {
        remainingSeconds = newRemaining;
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
      remainingSeconds =
          max(0, targetEndTime!.difference(DateTime.now()).inSeconds);
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

  Future<void> _showSetTimeDialog() async {
    if (isTimerRunning) return;

    final minutesController =
        TextEditingController(text: (remainingSeconds ~/ 60).toString());
    final secondsController =
        TextEditingController(text: (remainingSeconds % 60).toString());

    await showDialog<bool>(
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
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
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
          TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () {
                // Just return the trimmed text
                Navigator.pop(context, controller.text.trim());
              },
              child: const Text('Save')),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      // First update the username locally
      setState(() {
        username = result;
      });
      
      // Then send the update via WebSocket
      sendJsonToWebSocket({
        'type': 'set_username',
        'value': username
      });
      
      print('Username updated to: $username');
    }
  }

  void _showCodeDialog() {
    final codeController = TextEditingController(text: sessionCode);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Session Code'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Current Session Code: $sessionCode',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: codeController,
              decoration: const InputDecoration(
                labelText: 'Edit code or enter new code',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final enteredCode = codeController.text.trim();
              if (enteredCode.isNotEmpty) {
                setState(() {
                  sessionCode = enteredCode;
                });
                // Connect to WebSocket with the entered code
                _connectToWebSocket(enteredCode);
              }
              Navigator.pop(context);
            },
            child: const Text('Connect'),
          ),
        ],
      ),
    );
  }

  String _generateRandomString() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rand = Random();
    return List.generate(6, (_) => chars[rand.nextInt(chars.length)]).join();
  }

  String _formatTime(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Widget _focusBar() {
    final targetColor =
        Color.lerp(Colors.red, Colors.green, focusPercentage / 100)!;

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
                        begin:
                            Alignment(-1.0 + _shimmerController.value * 2, 0),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: _editUsername,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      )
                    ],
                  ),
                  child: Text(
                    username,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Focus: ${focusPercentage.toStringAsFixed(2)}%',
                style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87),
              ),
              const SizedBox(height: 12),
              _focusBar(),
              const SizedBox(height: 6),

              // ✅ Opponent display
              Text(
                'Opponent: $opponentName | Score: ${opponentScore.toStringAsFixed(2)}%',
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.black54,
                  fontWeight: FontWeight.w500,
                ),
              ),

              const SizedBox(height: 30),
              GestureDetector(
                onTap: _showSetTimeDialog,
                child: Text(
                  _formatTime(remainingSeconds),
                  style: const TextStyle(
                      fontSize: 56,
                      fontWeight: FontWeight.bold,
                      color: Colors.black),
                ),
              ),
              const SizedBox(height: 24),
              _playPauseButton(),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCodeDialog,
        backgroundColor: Colors.yellow.shade700,
        child: const Icon(Icons.flash_on, color: Colors.white, size: 32),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}
