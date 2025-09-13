import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const TimerPointsApp());
}

class TimerPointsApp extends StatelessWidget {
  const TimerPointsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Workout Timer + Points',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const WorkoutTimerScreen(),
    );
  }
}

class WorkoutTimerScreen extends StatefulWidget {
  const WorkoutTimerScreen({super.key});

  @override
  State<WorkoutTimerScreen> createState() => _WorkoutTimerScreenState();
}

class _WorkoutTimerScreenState extends State<WorkoutTimerScreen>
    with WidgetsBindingObserver {
  static const screenEventChannel = EventChannel('screen_events');

  int remainingSeconds = 0;
  double points = 0.0;
  bool isTimerRunning = false;
  bool screenUnlocked = true; // track if screen is unlocked

  Timer? _countdownTimer;
  DateTime? _backgroundTime;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Listen to screen lock/unlock events
    screenEventChannel.receiveBroadcastStream().listen((event) {
      if (event == "locked") {
        screenUnlocked = false;
      } else if (event == "unlocked") {
        screenUnlocked = true;
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        // App backgrounded
        _backgroundTime ??= DateTime.now();
        break;

      case AppLifecycleState.resumed:
        if (_backgroundTime != null && screenUnlocked) {
          final awayMilliseconds =
              DateTime.now().difference(_backgroundTime!).inMilliseconds;

          if (awayMilliseconds > 0) {
            final gainedPoints = awayMilliseconds * 0.01;

            setState(() {
              points += gainedPoints;
            });

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("+${gainedPoints.toStringAsFixed(2)} points"),
                duration: const Duration(seconds: 2),
              ),
            );
          }
          _backgroundTime = null;
        }
        break;

      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  void toggleTimer() {
    if (isTimerRunning) {
      _pauseTimer();
    } else {
      _startTimer();
    }
  }

  void _startTimer() {
    if (remainingSeconds <= 0) return;
    setState(() {
      isTimerRunning = true;
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (remainingSeconds > 0) {
        setState(() {
          remainingSeconds--;
        });
      } else {
        _pauseTimer();
      }
    });
  }

  void _pauseTimer() {
    _countdownTimer?.cancel();
    setState(() {
      isTimerRunning = false;
    });
  }

  Future<void> _setTimeDialog() async {
    if (isTimerRunning) return;

    final minutesController =
        TextEditingController(text: (remainingSeconds ~/ 60).toString());
    final secondsController =
        TextEditingController(text: (remainingSeconds % 60).toString());

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Set Timer"),
        content: Row(
          children: [
            Expanded(
              child: TextField(
                controller: minutesController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: "Minutes"),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: secondsController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: "Seconds"),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              final minutes = int.tryParse(minutesController.text) ?? 0;
              final seconds = int.tryParse(secondsController.text) ?? 0;
              setState(() {
                remainingSeconds = minutes * 60 + seconds;
              });
              Navigator.pop(context);
            },
            child: const Text("Set"),
          ),
        ],
      ),
    );
  }

  String _formatTime(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return "${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Center(
            child: GestureDetector(
              onTap: _setTimeDialog,
              child: Text(
                _formatTime(remainingSeconds),
                style:
                    const TextStyle(fontSize: 50, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          Positioned(
            top: 40,
            right: 20,
            child: Text(
              "Points: ${points.toStringAsFixed(2)}",
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: toggleTimer,
        child: Icon(isTimerRunning ? Icons.pause : Icons.play_arrow),
      ),
    );
  }
}
