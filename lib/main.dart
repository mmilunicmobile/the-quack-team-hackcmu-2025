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
  
  // Timestamp tracking for background penalties
  DateTime? _backgroundStartTime;
  bool _wasTimerRunningBeforeBackground = false;
  int _lastPingTimestamp = 0; // Timestamp of our last score update
  int _opponentLastPingTimestamp = 0; // Timestamp of opponent's last score update
  double _opponentRawScore = 100.0; // Opponent's raw score before time adjustment

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
  String username = "Scotty";
  double focusPercentage = 100.0;
  double remainingSeconds = 20 * 60; // Default 20 minutes
  double visualTimerDisplayTime = 0;
  bool isTimerRunning = false;
  DateTime? targetEndTime;
  Timer? _uiTimer;
  Timer? _backgroundPenaltyTimer;  // For background penalty updates
  // DateTime? _backgroundTime;
  double _consecutiveActiveSeconds = 0;
  late AnimationController _shimmerController;
  // Mock opponent (later will be updated via WebSockets)
  String opponentName = "Pending...";
  double opponentScore = 100.0;

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
      _startUITimer();
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
      
      // Set up listener for incoming messages from the server
      channel.stream.listen(
        (message) {
          try {
            final data = jsonDecode(message.toString());
            print('Received from WebSocket: $data');
            
            // Handle incoming data (scores, usernames, timer info)
            // API now excludes the current user from arrays
            
            // Update opponent name if usernames are available
            if (data['usernames'] != null && data['usernames'].isNotEmpty && data['usernames'][0] != null) {
              setState(() {
                // First entry in the array is now the opponent (current user is excluded)
                opponentName = data['usernames'][0];
              });
            }
            
            // Update opponent score and ping time if available
            if (data['scores'] != null && data['scores'].isNotEmpty) {
              // First entry is now the opponent's score (current user is excluded)
              final rawScore = data['scores'][0].toDouble();
              
              // Check if last_ping_times is provided
              if (data['last_ping_times'] != null && data['last_ping_times'].isNotEmpty) {
                final pingTime = data['last_ping_times'][0];
                if (pingTime is int) {
                  _opponentLastPingTimestamp = pingTime;
                  _opponentRawScore = rawScore;
                  
                  // Calculate adjusted score based on timestamp
                  final adjustedScore = _calculateAdjustedScore(_opponentRawScore, _opponentLastPingTimestamp);
                  
                  setState(() {
                    opponentScore = adjustedScore;
                  });
                  
                  print('Received opponent score: raw=$_opponentRawScore, adjusted=$opponentScore, timestamp=$_opponentLastPingTimestamp');
                } else {
                  setState(() {
                    opponentScore = rawScore;
                    _opponentRawScore = rawScore;
                  });
                  print('Received opponent score without valid timestamp: $rawScore');
                }
              } else {
                setState(() {
                  opponentScore = rawScore;
                  _opponentRawScore = rawScore;
                });
                print('Received opponent score without timestamp: $rawScore');
              }
            }
            
            // Handle timer updates from the server
            if (data['timer_running'] != null) {
              final bool timerShouldBeRunning = data['timer_running'] == true;
              
            setState(() {
              isTimerRunning = timerShouldBeRunning;
            }
            );
            }

            if (data['timer_end_time'] != null) {
                  // Convert Python time.time() (seconds since epoch) to DateTime
                  final double endTimeSeconds = data['timer_end_time'].toDouble();
                  final int endTimeMilliseconds = (endTimeSeconds * 1000).toInt();
                  final DateTime serverEndTime = DateTime.fromMillisecondsSinceEpoch(endTimeMilliseconds);
                  
                  // Calculate remaining time based on server's end time
                  // final remainingMillis = max(0, serverEndTime.difference(DateTime.now()).inMilliseconds);
                  // final newRemainingSeconds = (remainingMillis / 1000).ceil();
                  
                  setState(() {
                    targetEndTime = serverEndTime;
                    // remainingSeconds = newRemainingSeconds;
                  });
                  
                  print('Timer end time updated: ${serverEndTime.toIso8601String()}');
            }

            if (data['time_remaining'] != null) {
                  setState(() {
                    remainingSeconds = data['time_remaining'].toDouble();
                  }
                  );
            }
          } catch (e) {
            print('Error processing WebSocket message: $e');
          }
        },
        onDone: () {
          print('WebSocket connection closed');
        },
        onError: (error) {
          print('WebSocket error: $error');
        },
      );
      
      // Send username immediately after connection is established
      Future.delayed(const Duration(milliseconds: 500), () {
        sendJsonToWebSocket({
          'type': 'set_username',
          'value': username
        });
        print('Initial username sent: $username');
        
        // Also send initial focus score with timestamp
        _lastPingTimestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        sendJsonToWebSocket({
          'type': 'set_score',
          'value': focusPercentage,
          'last_ping_time': _lastPingTimestamp
        });
        print('Initial focus score sent: $focusPercentage, timestamp: $_lastPingTimestamp');
      });
    } catch (e) {
      print('WebSocketChannel connection failed: $e');
    }
  }

  @override
  void dispose() {
  WidgetsBinding.instance.removeObserver(this);
  _uiTimer?.cancel();
  _backgroundPenaltyTimer?.cancel();
  _shimmerController.dispose();
  _webSocketChannel?.sink.close();
  super.dispose();
  }


  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    print('App lifecycle state changed to: $state');
    
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        // Record when the app goes to background
        _backgroundStartTime = DateTime.now();
        _wasTimerRunningBeforeBackground = isTimerRunning;
        
        // Cancel the UI timer
        _uiTimer?.cancel();
        _consecutiveActiveSeconds = 0;
        
        print('App went to background at: ${_backgroundStartTime.toString()}');
        
        // We still use the background penalty timer, but it will use timestamps
        // This is a fallback in case the app gets some background execution time
        _startBackgroundPenaltyTimer();
        break;
        
      case AppLifecycleState.resumed:
        print('App resumed from background');
        
        // Cancel any running background timer
        _backgroundPenaltyTimer?.cancel();
        
        // Apply a one-time penalty for the time spent in background
        _applyBackgroundPenalty();
        
        // Restart the UI timer
        _startUITimer();
        break;
    }
  }
  
  // Apply a one-time penalty for the time spent in background
  void _applyBackgroundPenalty() {
    // Only apply penalty if timer was running when we went to background
    if (_backgroundStartTime != null && _wasTimerRunningBeforeBackground && isTimerRunning) {
      // Calculate seconds spent in background
      final secondsInBackground = DateTime.now().difference(_backgroundStartTime!).inSeconds;
      print('App was in background for $secondsInBackground seconds');
      
      if (secondsInBackground <= 0) {
        print('App was in background for 0 or negative seconds, skipping penalty');
        return;
      }
      
      // Apply penalty at the same rate (1.5 points per second)
      final double penaltyAmount = min(1.5 * secondsInBackground, focusPercentage);
      
      if (penaltyAmount > 0) {
        setState(() {
          double oldFocusPercentage = focusPercentage;
          focusPercentage = (focusPercentage - penaltyAmount).clamp(0.0, 100.0);
          print('Applied background penalty: -$penaltyAmount. Old: $oldFocusPercentage, New: $focusPercentage');
        });
        
        // Send the updated score to server with current timestamp
        _lastPingTimestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        sendJsonToWebSocket({
          'type': 'set_score',
          'value': focusPercentage,
          'last_ping_time': _lastPingTimestamp
        });
        print('Sent updated focus score after background: $focusPercentage, timestamp: $_lastPingTimestamp');
      }
    }
    
    // Reset background tracking
    _backgroundStartTime = null;
    _wasTimerRunningBeforeBackground = false;
  }

  void _startTimer() {
    // if (isTimerRunning) return;
    // setState(() {
    //   isTimerRunning = true;
    //   targetEndTime = DateTime.now().add(Duration(seconds: remainingSeconds));
    // });
    
    // Send start timer message to backend
    sendJsonToWebSocket({
      'type': 'start_timer'
    });
    print('Timer start sent to backend');
    
    // _startUITimer();
  }

  // Start a background timer that periodically decrements focus score and sends updates
  void _startBackgroundPenaltyTimer() {
    _backgroundPenaltyTimer?.cancel();

    // Decrease focus score every 2 seconds when in background
    _backgroundPenaltyTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!isTimerRunning) {
        return;
      }
      
      // Only update if we're really in background
      double oldFocusPercentage = focusPercentage;
        
      focusPercentage = (focusPercentage - 1.5).clamp(0.0, 100.0);
        
      // Send the update to backend without using setState, including timestamp
      if (oldFocusPercentage != focusPercentage) {
          _lastPingTimestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
          sendJsonToWebSocket({
            'type': 'set_score',
            'value': focusPercentage,
            'last_ping_time': _lastPingTimestamp
          });
          print('Background focus score updated: $focusPercentage, timestamp: $_lastPingTimestamp');
      }
    });
  }
  
  // Calculate the adjusted score based on timestamp
  double _calculateAdjustedScore(double rawScore, int lastPingTimestamp) {
    // If timer isn't running, no need to adjust score
    if (!isTimerRunning) {
      return rawScore;
    }
    
    // Calculate seconds elapsed since last ping
    final currentTimestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final secondsElapsed = currentTimestamp - lastPingTimestamp;
    
    // Don't adjust if last ping was very recent (within 1 second)
    if (secondsElapsed <= 1) {
      return rawScore;
    }
    
    // Add a small fudge factor to account for network delay (0.25 seconds)
    final adjustedSecondsElapsed = secondsElapsed - 0.25;
    
    if (adjustedSecondsElapsed <= 0) {
      return rawScore;
    }
    
    // Apply the same penalty rate as the original background timer (1.5 points per second)
    final penalty = 1.5 * adjustedSecondsElapsed;
    final adjustedScore = (rawScore - penalty).clamp(0.0, 100.0);
    
    print('Adjusted opponent score: $rawScore -> $adjustedScore (${adjustedSecondsElapsed.toStringAsFixed(1)}s elapsed)');
    
    return adjustedScore;
  }

  void _startUITimer() {
    _uiTimer?.cancel();
    _consecutiveActiveSeconds = 0;

    _uiTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (targetEndTime == null) return;
      final double newRemaining;
      if (isTimerRunning) {
        newRemaining =
            max(0.0, targetEndTime!.difference(DateTime.now()).inMilliseconds / 1000.0);
            
        // Check if the timer just reached zero
        if (newRemaining <= 0.1 && visualTimerDisplayTime > 0.1) {
          // Timer just ended, show winner popup
          _showWinnerDialog();
        }
      } else {
        newRemaining = remainingSeconds;
      }

      

      setState(() {
        if (isTimerRunning) {
          _consecutiveActiveSeconds += 0.1;
          
          // Periodically adjust opponent's score based on their last ping time
          // Only update the UI, not the stored raw score
          if (_opponentLastPingTimestamp > 0) {
            opponentScore = _calculateAdjustedScore(_opponentRawScore, _opponentLastPingTimestamp);
          }
        }
        
        visualTimerDisplayTime = newRemaining;

        if (_consecutiveActiveSeconds >= 4) {
          double oldFocusPercentage = focusPercentage;
          focusPercentage = (focusPercentage + 0.05).clamp(0.0, 100.0);
          
          // If focus percentage changed, send update to backend with timestamp
          if (oldFocusPercentage != focusPercentage) {
            _lastPingTimestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
            sendJsonToWebSocket({
              'type': 'set_score',
              'value': focusPercentage,
              'last_ping_time': _lastPingTimestamp
            });
            print('Focus score updated to: $focusPercentage, timestamp: $_lastPingTimestamp');
          }
          
          _consecutiveActiveSeconds = 0;
        }
      });
    });
  }
  
  // Show a dialog announcing the winner when the timer hits zero
  void _showWinnerDialog() {
    // Determine the winner based on focus scores
    final bool userWon = focusPercentage > opponentScore;
    final bool tie = (focusPercentage - opponentScore).abs() < 0.01;
    
    final String winnerName = userWon ? username : opponentName;
    final String resultMessage = tie 
        ? "It's a tie!" 
        : "$winnerName wins!";
    final String scoreMessage = "Final scores:\n$username: ${focusPercentage.toStringAsFixed(2)}%\n$opponentName: ${opponentScore.toStringAsFixed(2)}%";
    
    // Show the dialog only if not already showing another dialog
    showDialog(
      context: context,
      barrierDismissible: false, // User must tap a button to close the dialog
      builder: (context) => AlertDialog(
        title: Text(
          resultMessage,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: tie ? Colors.blue : (userWon ? Colors.green : Colors.red),
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Text(
              scoreMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 20),
            Icon(
              tie ? Icons.handshake : (userWon ? Icons.emoji_events : Icons.mood),
              size: 60,
              color: tie ? Colors.blue : (userWon ? Colors.amber : Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              // Reset the timer for a new session if needed
              sendJsonToWebSocket({
                'type': 'set_timer',
                'value': 20 * 60 // Reset to 20 minutes
              });
            },
            child: const Text('New Session'),
          ),
        ],
      ),
    );
  }

  void _pauseTimer() {
    // _uiTimer?.cancel();
    // if (targetEndTime != null) {
    //   remainingSeconds =
    //       max(0, targetEndTime!.difference(DateTime.now()).inSeconds);
    // }
    // setState(() {
    //   isTimerRunning = false;
    // });
    
    // Send stop timer message to backend
    sendJsonToWebSocket({
      'type': 'stop_timer'
    });
    print('Timer stop sent to backend');
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
              final newSeconds = m * 60 + s;
              
              // setState(() {
              //   remainingSeconds = newSeconds;
              // });
              
              // Send timer update to backend
              sendJsonToWebSocket({
                'type': 'set_timer',
                'value': newSeconds
              });
              print('Timer set to $newSeconds seconds, sent to backend');
              
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
    print("Formatting time $seconds");
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
  
  Widget _opponentFocusBar() {
    return Container(
      width: 280,
      height: 16, // Slightly smaller than the user's bar
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black26, width: 1.0),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: Stack(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeInOut,
              width: 280 * (opponentScore / 100),
              decoration: BoxDecoration(
                color: Colors.grey.shade500, // Gray color for opponent bar
              ),
            ),
            AnimatedBuilder(
              animation: _shimmerController,
              builder: (context, _) {
                return Positioned.fill(
                  child: ShaderMask(
                    shaderCallback: (rect) {
                      return LinearGradient(
                        colors: [
                          Colors.white.withOpacity(0.2),
                          Colors.transparent,
                          Colors.white.withOpacity(0.2),
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
              const SizedBox(height: 4),
              _opponentFocusBar(), // Added opponent focus bar

              const SizedBox(height: 26),
              GestureDetector(
                onTap: _showSetTimeDialog,
                child: Text(
                  _formatTime(visualTimerDisplayTime.floor()),
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
