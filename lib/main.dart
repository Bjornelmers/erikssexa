import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'audio_controller.dart';
import 'custom_particles.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  AudioController.instance.init();
  runApp(const DAoCLevelCounterApp());
}

enum AdventureState { countdown, login, intro, grinding }

class DAoCLevelCounterApp extends StatelessWidget {
  const DAoCLevelCounterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aragnoz - Shaman Level Counter',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        fontFamily: 'Metamorphous',
        textTheme: const TextTheme(
          displayLarge: TextStyle(fontFamily: 'Cinzel Decorative', color: Color(0xFFE5C158)),
          displayMedium: TextStyle(fontFamily: 'Cinzel', color: Color(0xFFE5C158)),
          titleLarge: TextStyle(fontFamily: 'MedievalSharp', color: Color(0xFFD4AF37)),
          bodyLarge: TextStyle(fontFamily: 'Metamorphous', color: Colors.white),
        ),
      ),
      home: const MainAdventureManager(),
    );
  }
}

class QuestInfo {
  final String title;
  final String password; // Exact lowercase check (or custom checker)
  final int rewardLevels;
  final String hint;

  QuestInfo({
    required this.title,
    required this.password,
    required this.rewardLevels,
    required this.hint,
  });

  bool checkPassword(String input) {
    final cleanInput = input.trim().toLowerCase();
    final cleanPassword = password.toLowerCase();
    
    // Special check for "skål!" to support without Swedish letters
    if (cleanPassword.contains('skål')) {
      return cleanInput == 'skål!' || cleanInput == 'skal!' || cleanInput == 'skål' || cleanInput == 'skal';
    }
    
    return cleanInput == cleanPassword;
  }
}

class MainAdventureManager extends StatefulWidget {
  const MainAdventureManager({super.key});

  @override
  State<MainAdventureManager> createState() => _MainAdventureManagerState();
}

class _MainAdventureManagerState extends State<MainAdventureManager> {
  AdventureState _state = AdventureState.countdown;
  int _level = 50; // DAoC character starts at max level 50
  final int _targetLevel = 1337;
  bool _isLoading = true;
  bool _audioInitialized = false;
  StreamSubscription? _stateSubscription;

  // Countdown target: August 15, 2026, 10:30 AM
  final DateTime _targetDate = DateTime(2026, 8, 15, 10, 30);
  Timer? _countdownTimer;
  Duration _timeRemaining = Duration.zero;
  int _bypassClicks = 0;

  // Login form controllers
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _classController = TextEditingController();
  final TextEditingController _raceController = TextEditingController();
  String _loginError = "";

  // Quest grind data
  int _completedQuestsCount = 0;
  final List<QuestInfo> _quests = [
    QuestInfo(
      title: "Get dressed!",
      password: "svensexa!",
      rewardLevels: 10,
      hint: "Quest Code: Svensexa!",
    ),
    QuestInfo(
      title: "Drink a Viking Mead!",
      password: "skål!",
      rewardLevels: 100,
      hint: "What do Vikings say when raising a cup? (skål! / skal!)",
    ),
    QuestInfo(
      title: "Defeat the Celtic dragon!",
      password: "excalibur",
      rewardLevels: 100,
      hint: "The legendary sword of King Arthur",
    ),
    QuestInfo(
      title: "Gather the Groomsmen!",
      password: "fellowship",
      rewardLevels: 100,
      hint: "The first book in the Lord of the Rings trilogy: 'The ... of the Ring'",
    ),
    QuestInfo(
      title: "Patrol the Midgard Border",
      password: "odin",
      rewardLevels: 100,
      hint: "The Allfather of Norse mythology (Repeatable Quest!)",
    ),
  ];

  final TextEditingController _questPasswordController = TextEditingController();
  String _questError = "";

  @override
  void initState() {
    super.initState();
    _loadState();
    _initCountdown();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _stateSubscription?.cancel();
    _usernameController.dispose();
    _classController.dispose();
    _raceController.dispose();
    _questPasswordController.dispose();
    _inputFocusNode.dispose();
    _levelInputController.dispose();
    super.dispose();
  }

  // Focus and dummy node to prevent compilation warnings
  final FocusNode _inputFocusNode = FocusNode();
  final TextEditingController _levelInputController = TextEditingController();

  // Initializing the countdown timer
  void _initCountdown() {
    _timeRemaining = _targetDate.difference(DateTime.now());
    if (_timeRemaining.isNegative) {
      _timeRemaining = Duration.zero;
    }

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final now = DateTime.now();
      final diff = _targetDate.difference(now);
      
      if (mounted) {
        setState(() {
          if (diff.isNegative || diff.inSeconds <= 0) {
            _timeRemaining = Duration.zero;
            _countdownTimer?.cancel();
            if (_state == AdventureState.countdown) {
              _state = AdventureState.login;
              _saveAdventureState(AdventureState.login);
              _startMusic();
            }
          } else {
            _timeRemaining = diff;
          }
        });
      }
    });
  }

  // Load state from Firestore with fallback to SharedPreferences
  Future<void> _loadState() async {
    final docRef = FirebaseFirestore.instance.collection('game').doc('state');
    
    _stateSubscription = docRef.snapshots().listen((snapshot) async {
      if (!snapshot.exists) {
        // Initialize Firestore document if it doesn't exist
        await docRef.set({
          'aragnoz_level': 50,
          'adventure_state': AdventureState.countdown.index,
          'completed_quests_count': 0,
        });
        return;
      }
      
      final data = snapshot.data();
      if (data == null) return;
      
      final level = data['aragnoz_level'] as int? ?? 50;
      final savedStateIndex = data['adventure_state'] as int? ?? AdventureState.countdown.index;
      final completedQuests = data['completed_quests_count'] as int? ?? 0;
      
      AdventureState savedState = AdventureState.values[savedStateIndex];

      // Double check time target if saved state was countdown
      if (savedState == AdventureState.countdown) {
        if (DateTime.now().isAfter(_targetDate)) {
          savedState = AdventureState.login;
          await docRef.update({'adventure_state': AdventureState.login.index});
        }
      }

      if (mounted) {
        setState(() {
          _level = level;
          _state = savedState;
          _completedQuestsCount = completedQuests;
          _isLoading = false;
        });
      }

      // Start background music automatically if we are in login or grinding and unmuted
      if (!_audioInitialized && (savedState == AdventureState.login || savedState == AdventureState.grinding)) {
        _audioInitialized = true;
        _startMusic();
      }
    }, onError: (error) async {
      debugPrint("Firestore error, falling back to SharedPreferences: $error");
      
      final prefs = await SharedPreferences.getInstance();
      final level = prefs.getInt('aragnoz_level') ?? 50;
      final savedStateIndex = prefs.getInt('adventure_state') ?? AdventureState.countdown.index;
      final completedQuests = prefs.getInt('completed_quests_count') ?? 0;
      
      AdventureState savedState = AdventureState.values[savedStateIndex];

      if (savedState == AdventureState.countdown) {
        if (DateTime.now().isAfter(_targetDate)) {
          savedState = AdventureState.login;
        }
      }

      if (mounted) {
        setState(() {
          _level = level;
          _state = savedState;
          _completedQuestsCount = completedQuests;
          _isLoading = false;
        });
      }

      if (!_audioInitialized && (savedState == AdventureState.login || savedState == AdventureState.grinding)) {
        _audioInitialized = true;
        _startMusic();
      }
    });
  }

  void _startMusic() {
    // Attempt play
    if (!AudioController.instance.isMuted) {
      AudioController.instance.playThemeMusic();
    }
  }

  Future<void> _saveAdventureState(AdventureState state) async {
    // Local backup
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('adventure_state', state.index);
    
    // Firestore update
    try {
      await FirebaseFirestore.instance.collection('game').doc('state').update({
        'adventure_state': state.index,
      });
    } catch (e) {
      debugPrint("Failed to save state to Firestore: $e");
    }
  }

  Future<void> _saveLevel(int level) async {
    // Local backup
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('aragnoz_level', level);
    
    // Firestore update
    try {
      await FirebaseFirestore.instance.collection('game').doc('state').update({
        'aragnoz_level': level,
      });
    } catch (e) {
      debugPrint("Failed to save level to Firestore: $e");
    }
  }

  Future<void> _saveCompletedQuests(int count) async {
    // Local backup
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('completed_quests_count', count);
    
    // Firestore update
    try {
      await FirebaseFirestore.instance.collection('game').doc('state').update({
        'completed_quests_count': count,
      });
    } catch (e) {
      debugPrint("Failed to save completed quests to Firestore: $e");
    }
  }

  // Secrets & Bypass
  void _handleBypassClick() {
    if (_state != AdventureState.countdown) return;
    setState(() {
      _bypassClicks++;
      if (_bypassClicks >= 5) {
        _state = AdventureState.login;
        _saveAdventureState(AdventureState.login);
        _countdownTimer?.cancel();
        
        // Play music immediately since this click counts as user interaction
        AudioController.instance.playThemeMusic();
        _audioInitialized = true;
      }
    });
  }

  // Login verification
  void _verifyLogin() {
    final user = _usernameController.text.trim().toLowerCase();
    final cls = _classController.text.trim().toLowerCase();
    final rc = _raceController.text.trim().toLowerCase();

    if (user == 'aragnoz' && cls == 'shaman' && rc == 'troll') {
      setState(() {
        _loginError = "";
        _state = AdventureState.intro;
      });
      _saveAdventureState(AdventureState.intro);
      AudioController.instance.playLevelUpSound();
      _startMusic(); // Ensure music plays
    } else {
      setState(() {
        _loginError = "Du vet ju för faen inte vad du snackar om! Försök igen.";
      });
    }
  }

  // Quest Verification
  void _submitQuestPassword() {
    if (_questPasswordController.text.isEmpty) return;

    final currentQuestIndex = _completedQuestsCount.clamp(0, _quests.length - 1);
    final currentQuest = _quests[currentQuestIndex];

    if (currentQuest.checkPassword(_questPasswordController.text)) {
      final oldLevel = _level;
      final newLevel = _level + currentQuest.rewardLevels;

      setState(() {
        _level = newLevel;
        _questError = "";
        _questPasswordController.clear();
        
        // Only increment the completed count if it's not the last repeatable quest
        // Or if it is the repeatable quest, we let them repeat it but don't overflow the index list
        if (_completedQuestsCount < _quests.length - 1) {
          _completedQuestsCount++;
        }
      });

      _saveLevel(newLevel);
      _saveCompletedQuests(_completedQuestsCount);

      if (oldLevel < _targetLevel && newLevel >= _targetLevel) {
        AudioController.instance.playVictorySound();
      } else {
        AudioController.instance.playLevelUpSound();
      }
    } else {
      setState(() {
        _questError = "Fel lösenord, din tröge trollskalle! Försök igen.";
      });
    }
  }

  void _cheatToVictory() {
    setState(() {
      _level = _targetLevel;
    });
    _saveLevel(_targetLevel);
    AudioController.instance.playVictorySound();
  }

  void _resetCharacter() {
    setState(() {
      _level = 50; // Back to starting level 50
      _state = AdventureState.countdown;
      _bypassClicks = 0;
      _completedQuestsCount = 0;
      _usernameController.clear();
      _classController.clear();
      _raceController.clear();
      _questPasswordController.clear();
      _loginError = "";
      _questError = "";
      _initCountdown();
    });
    _saveLevel(50);
    _saveCompletedQuests(0);
    _saveAdventureState(AdventureState.countdown);
    AudioController.instance.toggleMute(); // Reset audio toggle
  }

  // ==========================================
  // VIEW BUILDERS
  // ==========================================

  // 1. COUNTDOWN TIMER VIEW
  Widget _buildCountdownScreen() {
    final days = _timeRemaining.inDays;
    final hours = _timeRemaining.inHours % 24;
    final minutes = _timeRemaining.inMinutes % 60;
    final seconds = _timeRemaining.inSeconds % 60;

    String pad(int n) => n.toString().padLeft(2, '0');

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned(
            top: 0,
            right: 0,
            width: 100,
            height: 100,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _handleBypassClick,
            ),
          ),
          
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.hourglass_empty_rounded,
                  size: 48,
                  color: const Color(0xFFD4AF37).withOpacity(0.4),
                ),
                const SizedBox(height: 32),
                
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _timeUnitCard(days.toString(), "DAYS"),
                    _timeDivider(),
                    _timeUnitCard(pad(hours), "HOURS"),
                    _timeDivider(),
                    _timeUnitCard(pad(minutes), "MINUTES"),
                    _timeDivider(),
                    _timeUnitCard(pad(seconds), "SECONDS"),
                  ],
                ),
                const SizedBox(height: 40),
                Text(
                  "Until the Adventure Begins...",
                  style: TextStyle(
                    fontFamily: 'Cinzel',
                    fontSize: 14,
                    color: const Color(0xFF8B7355).withOpacity(0.8),
                    letterSpacing: 2.0,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _timeUnitCard(String value, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontFamily: 'Cinzel Decorative',
            fontSize: 48,
            fontWeight: FontWeight.bold,
            color: Color(0xFFE5C158),
            shadows: [Shadow(color: Color(0xFFFFD700), blurRadius: 10)],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: Colors.grey, letterSpacing: 1.0),
        ),
      ],
    );
  }

  Widget _timeDivider() {
    return const Padding(
      padding: EdgeInsets.only(left: 16, right: 16, bottom: 20),
      child: Text(
        ":",
        style: TextStyle(fontSize: 36, color: Color(0xFF8B7355), fontWeight: FontWeight.bold),
      ),
    );
  }

  // 2. LOGIN / VALIDATION VIEW
  Widget _buildLoginScreen() {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1115),
      body: Stack(
        children: [
          // Background
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                image: DecorationImage(
                  image: AssetImage('assets/images/daoc_background.jpg'),
                  fit: BoxFit.cover,
                  opacity: 0.12,
                ),
              ),
            ),
          ),

          // Audio control top-right
          Positioned(
            top: 20,
            right: 20,
            child: _buildAudioButton(),
          ),

          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 450),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFD4AF37), width: 2),
                  boxShadow: [
                    BoxShadow(color: const Color(0xFFFFD700).withOpacity(0.08), blurRadius: 16)
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(28.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Official DAoC Logo
                      Image.asset(
                        'assets/images/daoc_logo.jpg',
                        height: 180,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return const Text(
                            "DARK AGE OF CAMELOT",
                            style: TextStyle(
                              fontFamily: 'Cinzel Decorative',
                              fontSize: 22,
                              color: Color(0xFFE5C158),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 24),
                      
                      const Text(
                        "Character Credentials Required",
                        style: TextStyle(
                          fontFamily: 'MedievalSharp',
                          fontSize: 16,
                          color: Color(0xFF8B7355),
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Inputs
                      _loginTextField(_usernameController, "Character Name"),
                      const SizedBox(height: 14),
                      _loginTextField(_classController, "Class"),
                      const SizedBox(height: 14),
                      _loginTextField(_raceController, "Race"),
                      const SizedBox(height: 20),

                      // Error display
                      if (_loginError.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFB71C1C).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFB71C1C), width: 1.2),
                          ),
                          child: Text(
                            _loginError,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Color(0xFFFF8A80),
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'MedievalSharp',
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],

                      // Submit button
                      ElevatedButton(
                        onPressed: () {
                          _verifyLogin();
                          // Ensure music attempts playing on button click
                          _audioInitialized = true;
                        },
                        style: ElevatedButton.styleFrom(
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                            side: const BorderSide(color: Color(0xFFD4AF37), width: 1.5),
                          ),
                        ),
                        child: Ink(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFE5C158), Color(0xFFB8860B)],
                            ),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Container(
                            height: 48,
                            alignment: Alignment.center,
                            child: const Text(
                              "BEGIN ADVENTURE",
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _loginTextField(TextEditingController controller, String hint) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        border: Border.all(color: const Color(0xFF8B7355), width: 1.2),
        borderRadius: BorderRadius.circular(6),
      ),
      child: TextField(
        controller: controller,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey.withOpacity(0.7), fontSize: 13),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  // 3. INTRO / STORY SCROLL VIEW
  Widget _buildIntroScreen() {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1115),
      body: Stack(
        children: [
          Positioned(
            top: 20,
            right: 20,
            child: _buildAudioButton(),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 550),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFD4AF37), width: 2),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Retro character photo
                      Container(
                        height: 220,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFF8B7355), width: 2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Image.asset(
                            'assets/images/aragnoz_retro.jpg',
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return const Center(child: Icon(Icons.broken_image, size: 48));
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Parchment scroll story loader
                      FutureBuilder<String>(
                        future: DefaultAssetBundle.of(context).loadString('assets/texts/intro.txt'),
                        builder: (context, snapshot) {
                          String storyText = "Loading adventure logs...";
                          if (snapshot.hasData) {
                            storyText = snapshot.data!;
                          }
                          
                          return Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF4EAD4), // Parchment beige
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFF8B7355), width: 1.5),
                            ),
                            child: Text(
                              storyText,
                              style: const TextStyle(
                                color: Color(0xFF3E2723), // Dark brown ink
                                fontSize: 13,
                                height: 1.45,
                                fontFamily: 'Metamorphous',
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 24),

                      // Start grinding button
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _state = AdventureState.grinding;
                          });
                          _saveAdventureState(AdventureState.grinding);
                          _startMusic();
                        },
                        style: ElevatedButton.styleFrom(
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                            side: const BorderSide(color: Color(0xFFFFD700), width: 1.5),
                          ),
                        ),
                        child: Ink(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFE5C158), Color(0xFFB8860B)],
                            ),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Container(
                            height: 48,
                            alignment: Alignment.center,
                            child: const Text(
                              "START GRINDING",
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 4. GRINDING DASHBOARD VIEW
  Widget _buildGrindingScreen() {
    final bool reachedVictory = _level >= _targetLevel;
    final double progress = (_level / _targetLevel).clamp(0.0, 1.0);

    final currentQuestIndex = _completedQuestsCount.clamp(0, _quests.length - 1);
    final currentQuest = _quests[currentQuestIndex];
    final bool allMainQuestsFinished = _completedQuestsCount >= _quests.length - 1;

    return Scaffold(
      body: Stack(
        children: [
          // Background
          Positioned.fill(
            child: Image.asset(
              'assets/images/daoc_background.jpg',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  decoration: const BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment.center,
                      radius: 1.2,
                      colors: [Color(0xFF262C34), Color(0xFF0F1115)],
                    ),
                  ),
                );
              },
            ),
          ),
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(0.55),
            ),
          ),

          // Audio control HUD (top-right)
          Positioned(
            top: 20,
            right: 20,
            child: _buildAudioButton(),
          ),

          // Main centered content
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 580),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFD4AF37), width: 2.5),
                  boxShadow: [
                    BoxShadow(color: const Color(0xFFD4AF37).withOpacity(0.12), blurRadius: 20, spreadRadius: 4),
                    const BoxShadow(color: Colors.black54, offset: Offset(0, 8), blurRadius: 16),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        "MIDGARD SHAMAN QUEST",
                        style: TextStyle(
                          fontFamily: 'Cinzel Decorative',
                          fontSize: 20,
                          color: Color(0xFFE5C158),
                          letterSpacing: 2.0,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        width: 140,
                        height: 2,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.transparent, Color(0xFFD4AF37), Colors.transparent],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Character Profile Panel (using retro photo)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E2125).withOpacity(0.7),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF8B7355).withOpacity(0.6), width: 1.2),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 85,
                              height: 85,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: const Color(0xFFD4AF37), width: 2.5),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(42),
                                child: Image.asset(
                                  'assets/images/aragnoz_retro.jpg',
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return const Icon(Icons.person, size: 40, color: Colors.grey);
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "Aragnoz",
                                    style: TextStyle(
                                      fontFamily: 'Eagle Lake',
                                      fontSize: 22,
                                      color: Color(0xFFE5C158),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    "Troll Shaman",
                                    style: TextStyle(
                                      fontFamily: 'MedievalSharp',
                                      fontSize: 16,
                                      color: Color(0xFF1E88E5),
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Icon(Icons.shield, size: 14, color: Color(0xFF8B7355)),
                                      SizedBox(width: 4),
                                      Text(
                                        "Realm: Midgard",
                                        style: TextStyle(fontSize: 12, color: Colors.grey),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            )
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Level Display Panel
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [const Color(0xFF2C3238), const Color(0xFF1E2125).withOpacity(0.9)],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF8B7355), width: 1.5),
                        ),
                        child: Column(
                          children: [
                            const Text(
                              "CURRENT LEVEL",
                              style: TextStyle(color: Color(0xFFFFD700), fontSize: 13, letterSpacing: 1.5),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              "$_level",
                              style: const TextStyle(
                                fontFamily: 'Cinzel Decorative',
                                fontSize: 62,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFFE5C158),
                                shadows: [
                                  Shadow(color: Colors.black, offset: Offset(3.0, 3.0), blurRadius: 5.0),
                                ],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              reachedVictory ? "QUEST COMPLETE: ELITE TIER" : "GOAL LEVEL: $_targetLevel",
                              style: TextStyle(
                                color: reachedVictory ? const Color(0xFF4CAF50) : const Color(0xFF8B7355),
                                fontSize: 12,
                                letterSpacing: 1.0,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Quest Progress Bar
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text("Quest Progress", style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
                              Text(
                                reachedVictory ? "100% (ELITE)" : "${(progress * 100).toStringAsFixed(1)}%",
                                style: TextStyle(
                                  color: reachedVictory ? const Color(0xFF4CAF50) : const Color(0xFFE5C158),
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Stack(
                            children: [
                              Container(
                                height: 22,
                                decoration: BoxDecoration(
                                  color: Colors.black,
                                  borderRadius: BorderRadius.circular(11),
                                  border: Border.all(color: const Color(0xFF8B7355), width: 1.5),
                                ),
                              ),
                              FractionallySizedBox(
                                widthFactor: progress,
                                child: Container(
                                  height: 22,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(11),
                                    gradient: LinearGradient(
                                      colors: reachedVictory
                                          ? [const Color(0xFF4CAF50), const Color(0xFF81C784)]
                                          : [const Color(0xFF1E88E5), const Color(0xFF00E5FF)],
                                    ),
                                  ),
                                ),
                              ),
                              Positioned.fill(
                                child: Center(
                                  child: Text(
                                    "$_level / $_targetLevel",
                                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),

                      // QUEST INSTRUCTIONS & CONTROLS (Replacing manual level entry)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E2125).withOpacity(0.5),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF8B7355), width: 1.2),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  allMainQuestsFinished 
                                      ? "ACTIVE QUEST (Repeatable)"
                                      : "ACTIVE QUEST (${currentQuestIndex + 1}/${_quests.length - 1})",
                                  style: const TextStyle(
                                    color: Color(0xFFE5C158),
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFD4AF37).withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: const Color(0xFFD4AF37), width: 0.8),
                                  ),
                                  child: Text(
                                    "+${currentQuest.rewardLevels} Levels",
                                    style: const TextStyle(
                                      color: Color(0xFFFFD700),
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              currentQuest.title,
                              style: const TextStyle(
                                fontFamily: 'MedievalSharp',
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              currentQuest.hint,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade400,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                            const SizedBox(height: 16),
                            
                            // Password entry
                            Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    height: 42,
                                    decoration: BoxDecoration(
                                      color: Colors.black,
                                      border: Border.all(color: const Color(0xFF8B7355), width: 1.2),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: TextField(
                                      controller: _questPasswordController,
                                      style: const TextStyle(
                                        color: Color(0xFFE5C158),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                      decoration: const InputDecoration(
                                        hintText: "Enter Quest Password",
                                        hintStyle: TextStyle(color: Colors.grey, fontSize: 12),
                                        border: InputBorder.none,
                                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                        isDense: true,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton(
                                  onPressed: _submitQuestPassword,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFE5C158),
                                    foregroundColor: Colors.black,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  ),
                                  child: const Text(
                                    "COMPLETE",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            
                            // Error text
                            if (_questError.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                _questError,
                                style: const TextStyle(
                                  color: Color(0xFFFF8A80),
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'MedievalSharp',
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // COMPLETED QUESTS LOG
                      if (_completedQuestsCount > 0) ...[
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            "COMPLETED QUESTS",
                            style: TextStyle(color: Color(0xFF8B7355), fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          constraints: const BoxConstraints(maxHeight: 110),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFF8B7355).withOpacity(0.4), width: 1.0),
                          ),
                          child: ListView.builder(
                            shrinkWrap: true,
                            padding: const EdgeInsets.all(8),
                            itemCount: _completedQuestsCount,
                            itemBuilder: (context, index) {
                              final q = _quests[index];
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  children: [
                                    const Icon(Icons.check_circle_outline_rounded, color: Color(0xFF4CAF50), size: 16),
                                    const SizedBox(width: 8),
                                    Text(
                                      q.title,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                        decoration: TextDecoration.lineThrough,
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      "+${q.rewardLevels} Levels",
                                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Hidden Reset & Cheat Bypass drawer
          Positioned(
            bottom: 12,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Reset Button
                Opacity(
                  opacity: 0.25,
                  child: TextButton(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) {
                          return AlertDialog(
                            backgroundColor: const Color(0xFF1E2125),
                            title: const Text("Restart Quest?", style: TextStyle(color: Color(0xFFE5C158), fontFamily: 'MedievalSharp')),
                            content: const Text("Reset character? This goes back to countdown screen."),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD32F2F)),
                                onPressed: () {
                                  Navigator.pop(context);
                                  _resetCharacter();
                                },
                                child: const Text("Reset", style: TextStyle(color: Colors.white)),
                              )
                            ],
                          );
                        },
                      );
                    },
                    child: const Text("RESET QUEST", style: TextStyle(color: Colors.white, fontSize: 10)),
                  ),
                ),
                const SizedBox(width: 20),
                // Developer Cheat Button
                Opacity(
                  opacity: 0.15,
                  child: TextButton(
                    onPressed: _cheatToVictory,
                    child: const Text("DEV BOOST (1337)", style: TextStyle(color: Colors.white, fontSize: 10)),
                  ),
                ),
              ],
            ),
          ),

          // Celebration scroll overlay
          if (reachedVictory) ...[
            const CelebrationEffect(),
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.75),
                child: Center(
                  child: SingleChildScrollView(
                    child: Container(
                      margin: const EdgeInsets.all(20),
                      constraints: const BoxConstraints(maxWidth: 500),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF2A2218), Color(0xFF15100B)],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFFFD700), width: 3),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 100,
                              height: 100,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: const Color(0xFFFFD700), width: 3.5),
                              ),
                              child: const Icon(Icons.wine_bar_rounded, color: Color(0xFFFFD700), size: 55),
                            ),
                            const SizedBox(height: 24),
                            const Text(
                              "QUEST COMPLETE!",
                              style: TextStyle(fontFamily: 'Cinzel Decorative', fontSize: 26, color: Color(0xFFFFD700), fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              "ARAGNOZ HAS REACHED ELITE LEVEL",
                              style: TextStyle(fontFamily: 'MedievalSharp', fontSize: 13, color: Colors.grey),
                            ),
                            const SizedBox(height: 24),

                            // Parchment Scroll Message Box
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF4EAD4),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFF8B7355), width: 1.5),
                              ),
                              child: const Column(
                                children: [
                                  Text(
                                    "YOU ARE ELITE!",
                                    style: TextStyle(fontFamily: 'MedievalSharp', fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF3E2723)),
                                  ),
                                  SizedBox(height: 12),
                                  Text(
                                    "You are now ready for the absolute final quest:",
                                    textAlign: TextAlign.center,
                                    style: TextStyle(fontSize: 13, color: Color(0xFF4E342E)),
                                  ),
                                  SizedBox(height: 12),
                                  Text(
                                    "\"To get married!\"",
                                    textAlign: TextAlign.center,
                                    style: TextStyle(fontFamily: 'Eagle Lake', fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFFB71C1C)),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 32),

                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                OutlinedButton(
                                  onPressed: () => AudioController.instance.playVictorySound(),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFFFFD700),
                                    side: const BorderSide(color: Color(0xFFFFD700)),
                                  ),
                                  child: const Row(
                                    children: [Icon(Icons.campaign, size: 18), SizedBox(width: 6), Text("BLOW HORN")],
                                  ),
                                ),
                                const SizedBox(width: 16),
                                ElevatedButton(
                                  onPressed: () {
                                    showDialog(
                                      context: context,
                                      builder: (context) {
                                        return AlertDialog(
                                          backgroundColor: const Color(0xFF1E2125),
                                          title: const Text("Restart Shaman Journey?"),
                                          content: const Text("Return to the countdown screen?"),
                                          actions: [
                                            TextButton(onPressed: () => Navigator.pop(context), child: const Text("No")),
                                            ElevatedButton(
                                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD4AF37)),
                                              onPressed: () {
                                                Navigator.pop(context);
                                                _resetCharacter();
                                              },
                                              child: const Text("Reset", style: TextStyle(color: Colors.black)),
                                            )
                                          ],
                                        );
                                      },
                                    );
                                  },
                                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFD700), foregroundColor: Colors.black),
                                  child: const Text("RESTART QUEST"),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ]
        ],
      ),
    );
  }

  Widget _buildAudioButton() {
    return Material(
      color: Colors.transparent,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withOpacity(0.65),
          border: Border.all(
            color: AudioController.instance.isMuted ? const Color(0xFF8B7355) : const Color(0xFFE5C158),
            width: 2,
          ),
        ),
        child: IconButton(
          icon: Icon(
            AudioController.instance.isMuted ? Icons.volume_off_rounded : Icons.music_note_rounded,
            color: AudioController.instance.isMuted ? const Color(0xFF8B7355) : const Color(0xFFFFD700),
            size: 26,
          ),
          onPressed: () {
            setState(() {
              AudioController.instance.toggleMute();
              _audioInitialized = true;
            });
          },
        ),
      ),
    );
  }

  // ==========================================
  // VIEW MANAGER
  // ==========================================
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Color(0xFFE5C158))),
      );
    }

    switch (_state) {
      case AdventureState.countdown:
        return _buildCountdownScreen();
      case AdventureState.login:
        return _buildLoginScreen();
      case AdventureState.intro:
        return _buildIntroScreen();
      case AdventureState.grinding:
        return _buildGrindingScreen();
    }
  }
}

