import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:video_player/video_player.dart';
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
  final String id;
  final String title;
  final String password; // Exact lowercase check (or custom checker)
  final int rewardLevels;
  final String hint;
  final int order;

  QuestInfo({
    this.id = '',
    required this.title,
    required this.password,
    required this.rewardLevels,
    required this.hint,
    this.order = 0,
  });

  factory QuestInfo.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return QuestInfo(
      id: doc.id,
      title: data['title'] as String? ?? '',
      password: data['password'] as String? ?? '',
      rewardLevels: (data['rewardLevels'] ?? data['reward_levels'] as num?)?.toInt() ?? 10,
      hint: data['hint'] as String? ?? '',
      order: (data['order'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'password': password,
      'rewardLevels': rewardLevels,
      'hint': hint,
      'order': order,
    };
  }

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
  StreamSubscription? _questsSubscription;

  // Countdown target: August 15, 2026, 09:00 AM
  final DateTime _targetDate = DateTime(2026, 8, 15, 9, 0);
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

  // Default fallback quests
  static final List<QuestInfo> _defaultQuests = [
    QuestInfo(
      id: "quest_1",
      title: "Get dressed!",
      password: "svensexa!",
      rewardLevels: 10,
      hint: "Quest Code: Svensexa!",
      order: 1,
    ),
    QuestInfo(
      id: "quest_2",
      title: "Drink a Viking Mead!",
      password: "skål!",
      rewardLevels: 100,
      hint: "What do Vikings say when raising a cup? (skål! / skal!)",
      order: 2,
    ),
    QuestInfo(
      id: "quest_3",
      title: "Defeat the Celtic dragon!",
      password: "excalibur",
      rewardLevels: 100,
      hint: "The legendary sword of King Arthur",
      order: 3,
    ),
    QuestInfo(
      id: "quest_4",
      title: "Gather the Groomsmen!",
      password: "fellowship",
      rewardLevels: 100,
      hint: "The first book in the Lord of the Rings trilogy: 'The ... of the Ring'",
      order: 4,
    ),
    QuestInfo(
      id: "quest_5",
      title: "Patrol the Midgard Border",
      password: "odin",
      rewardLevels: 100,
      hint: "The Allfather of Norse mythology (Repeatable Quest!)",
      order: 5,
    ),
  ];

  // Active quest list dynamically populated from Firestore
  late List<QuestInfo> _quests = List.from(_defaultQuests);

  final TextEditingController _questPasswordController = TextEditingController();
  final TextEditingController _potionPasswordController = TextEditingController();
  String _questError = "";

  @override
  void initState() {
    super.initState();
    _loadState();
    _initCountdown();
    _listenToQuests();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _stateSubscription?.cancel();
    _questsSubscription?.cancel();
    _usernameController.dispose();
    _classController.dispose();
    _raceController.dispose();
    _questPasswordController.dispose();
    _potionPasswordController.dispose();
    _inputFocusNode.dispose();
    _levelInputController.dispose();
    super.dispose();
  }

  // Listen to quests from Firestore database
  void _listenToQuests() {
    final questsRef = FirebaseFirestore.instance.collection('quests');
    
    _questsSubscription = questsRef.orderBy('order').snapshots().listen((snapshot) async {
      if (snapshot.docs.isEmpty) {
        // Seed default quests into Firestore if empty
        debugPrint("Firestore 'quests' collection is empty. Seeding default quests...");
        final batch = FirebaseFirestore.instance.batch();
        for (final q in _defaultQuests) {
          final docRef = questsRef.doc(q.id);
          batch.set(docRef, q.toMap());
        }
        await batch.commit().catchError((e) {
          debugPrint("Failed to seed default quests: $e");
        });
        return;
      }
      
      final loadedQuests = snapshot.docs
          .map((doc) => QuestInfo.fromFirestore(doc))
          .toList();
          
      if (mounted && loadedQuests.isNotEmpty) {
        setState(() {
          _quests = loadedQuests;
        });
      }
    }, onError: (error) {
      debugPrint("Error listening to Firestore quests, using defaults: $error");
    });
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

  // Load state locally from SharedPreferences
  Future<void> _loadState() async {
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
  }

  void _startMusic() {
    // Attempt play
    if (!AudioController.instance.isMuted) {
      AudioController.instance.playThemeMusic();
    }
  }

  Future<void> _saveAdventureState(AdventureState state) async {
    // Save state locally per device
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('adventure_state', state.index);
  }

  Future<void> _saveLevel(int level) async {
    // Save level locally per device
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('aragnoz_level', level);
  }

  Future<void> _saveCompletedQuests(int count) async {
    // Save completed quests count locally per device
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('completed_quests_count', count);
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
    final inputPassword = _questPasswordController.text.trim();
    if (inputPassword.isEmpty) return;

    // Special master bypass password to reach victory instantly
    if (inputPassword == "32167") {
      final oldLevel = _level;
      setState(() {
        _questError = "";
        _questPasswordController.clear();
      });
      
      // Log bypass usage to Firestore
      try {
        FirebaseFirestore.instance.collection('quest_logs').add({
          'timestamp': FieldValue.serverTimestamp(),
          'quest_title': 'Master Bypass Code Used',
          'old_level': oldLevel,
          'new_level': _targetLevel,
          'password_used': '32167',
        });
      } catch (e) {
        debugPrint("Failed to write bypass log to Firestore: $e");
      }

      _cheatToVictory();
      return;
    }

    final currentQuestIndex = _completedQuestsCount.clamp(0, _quests.length - 1);
    final currentQuest = _quests[currentQuestIndex];

    if (currentQuest.checkPassword(inputPassword)) {
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

      // Log successful quest completion to Firestore
      try {
        FirebaseFirestore.instance.collection('quest_logs').add({
          'timestamp': FieldValue.serverTimestamp(),
          'quest_title': currentQuest.title,
          'old_level': oldLevel,
          'new_level': newLevel,
          'password_used': _questPasswordController.text.trim(),
        });
      } catch (e) {
        debugPrint("Failed to write quest log to Firestore: $e");
      }

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

  void _showDrinkPotionDialog() {
    String dialogError = "";

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E2125),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Color(0xFFD4AF37), width: 1.8),
              ),
              title: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFFFFD700), width: 1.8),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: Image.asset(
                        'assets/images/potion.jpg',
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            const Icon(Icons.science, color: Color(0xFFFFD700), size: 22),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      "Drink Potion (10 levels)",
                      style: TextStyle(
                        color: Color(0xFFE5C158),
                        fontFamily: 'MedievalSharp',
                        fontSize: 16,
                      ),
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Ange 'Potion secret message' för att dricka potionen och få +10 levlar:",
                    style: TextStyle(color: Colors.white70, fontSize: 13, fontFamily: 'MedievalSharp'),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black,
                      border: Border.all(color: const Color(0xFF8B7355), width: 1.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: TextField(
                      controller: _potionPasswordController,
                      style: const TextStyle(
                        color: Color(0xFFE5C158),
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        fontFamily: 'MedievalSharp',
                      ),
                      decoration: const InputDecoration(
                        hintText: "Potion secret message...",
                        hintStyle: TextStyle(color: Colors.grey, fontSize: 12, fontFamily: 'MedievalSharp'),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                  ),
                  if (dialogError.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      dialogError,
                      style: const TextStyle(
                        color: Color(0xFFFF8A80),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'MedievalSharp',
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    _potionPasswordController.clear();
                    Navigator.pop(context);
                  },
                  child: const Text("Avbryt", style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE5C158),
                    foregroundColor: Colors.black,
                  ),
                  onPressed: () {
                    final rawInput = _potionPasswordController.text.trim();
                    final input = rawInput.toLowerCase();
                    
                    bool isValid = false;
                    if (input == 'potion secret message' ||
                        input == 'potion secret message!' ||
                        input == 'potion secret message.' ||
                        input == 'potion of level up !' ||
                        input == 'potion of level up!' ||
                        input == 'potion of level up' ||
                        input == '32167') {
                      isValid = true;
                    }

                    if (isValid) {
                      final oldLevel = _level;
                      final newLevel = _level + 10;
                      setState(() {
                        _level = newLevel;
                      });
                      _saveLevel(newLevel);
                      
                      // Log potion drink to Firestore
                      try {
                        FirebaseFirestore.instance.collection('quest_logs').add({
                          'timestamp': FieldValue.serverTimestamp(),
                          'quest_title': 'Magic Potion Consumed (+10 levels)',
                          'old_level': oldLevel,
                          'new_level': newLevel,
                          'password_used': rawInput,
                        });
                      } catch (e) {
                        debugPrint("Failed to write potion log to Firestore: $e");
                      }

                      _potionPasswordController.clear();
                      Navigator.pop(context);

                      if (oldLevel < _targetLevel && newLevel >= _targetLevel) {
                        AudioController.instance.playVictorySound();
                      } else {
                        AudioController.instance.playLevelUpSound();
                      }

                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          backgroundColor: Color(0xFF2E7D32),
                          content: Text(
                            "Slurp! Du drack potionen och fick +10 levlar!",
                            style: TextStyle(fontFamily: 'MedievalSharp', color: Colors.white),
                          ),
                        ),
                      );
                    } else {
                      setDialogState(() {
                        dialogError = "Fel hemligt meddelande! Potionen har ingen effekt.";
                      });
                    }
                  },
                  child: const Text("DRINK!", style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'MedievalSharp')),
                ),
              ],
            );
          },
        );
      },
    );
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
      backgroundColor: const Color(0xFF07080A),
      body: Stack(
        children: [
          // Background atmospheric stone texture
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                image: DecorationImage(
                  image: AssetImage('assets/images/daoc_background.jpg'),
                  fit: BoxFit.cover,
                  opacity: 0.25,
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 440),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F1115).withOpacity(0.95),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFD4AF37), width: 1.8),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFFD700).withOpacity(0.15),
                      blurRadius: 24,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Official DAoC Logo 2 spanning full width with seamless bottom gradient mask
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
                      child: ShaderMask(
                        shaderCallback: (rect) {
                          return const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.black, Colors.black, Colors.transparent],
                            stops: [0.0, 0.72, 1.0],
                          ).createShader(rect);
                        },
                        blendMode: BlendMode.dstIn,
                        child: Image.asset(
                          'assets/images/daoc_logo2.jpg',
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              padding: const EdgeInsets.all(24),
                              alignment: Alignment.center,
                              child: const Text(
                                "DARK AGE OF CAMELOT",
                                style: TextStyle(
                                  fontFamily: 'Cinzel Decorative',
                                  fontSize: 22,
                                  color: Color(0xFFE5C158),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),

                    // Form Content padded below the logo
                    Padding(
                      padding: const EdgeInsets.fromLTRB(28.0, 4.0, 28.0, 28.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            "CHARACTER CREDENTIALS",
                            style: TextStyle(
                              fontFamily: 'MedievalSharp',
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFD4AF37),
                              letterSpacing: 1.5,
                            ),
                          ),
                          const SizedBox(height: 18),

                          // Inputs with icons and leather/gold borders
                          _loginTextField(_usernameController, "Character Name", Icons.person_outline),
                          const SizedBox(height: 14),
                          _loginTextField(_classController, "Class", Icons.shield_outlined),
                          const SizedBox(height: 14),
                          _loginTextField(_raceController, "Race", Icons.fort_outlined),
                          const SizedBox(height: 22),

                          // Error display
                          if (_loginError.isNotEmpty) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFB71C1C).withOpacity(0.2),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFFB71C1C), width: 1.2),
                              ),
                              child: Text(
                                _loginError,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Color(0xFFFF8A80),
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'MedievalSharp',
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                          ],

                          // Golden sword-hilt styled action button
                          ElevatedButton(
                            onPressed: () {
                              _verifyLogin();
                              // Ensure music attempts playing on button click
                              _audioInitialized = true;
                            },
                            style: ElevatedButton.styleFrom(
                              padding: EdgeInsets.zero,
                              elevation: 8,
                              shadowColor: const Color(0xFFFFD700).withOpacity(0.4),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: const BorderSide(color: Color(0xFFFFF0A0), width: 1.5),
                              ),
                            ),
                            child: Ink(
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFFF3D075), Color(0xFFC59227), Color(0xFF946B00)],
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Container(
                                height: 52,
                                alignment: Alignment.center,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: const [
                                    Icon(Icons.auto_awesome, color: Colors.black87, size: 20),
                                    SizedBox(width: 8),
                                    Text(
                                      "BEGIN ADVENTURE",
                                      style: TextStyle(
                                        color: Colors.black,
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1.5,
                                        fontFamily: 'MedievalSharp',
                                      ),
                                    ),
                                    SizedBox(width: 8),
                                    Icon(Icons.auto_awesome, color: Colors.black87, size: 20),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _loginTextField(TextEditingController controller, String hint, IconData icon) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0B0D10),
        border: Border.all(color: const Color(0xFF8B7355), width: 1.2),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white, fontSize: 14, fontFamily: 'MedievalSharp'),
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: const Color(0xFFD4AF37), size: 20),
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey.withOpacity(0.7), fontSize: 13, fontFamily: 'MedievalSharp'),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
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
                      // Retro character intro video
                      Container(
                        height: 220,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFF8B7355), width: 2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: const IntroVideoWidget(),
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
                      const SizedBox(height: 16),

                      // POTION DRINK CONTAINER
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF2C2214), Color(0xFF16110A)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE5C158), width: 1.5),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFFFD700).withValues(alpha: 0.15),
                              blurRadius: 10,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: const Color(0xFFFFD700), width: 2),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.amber.withValues(alpha: 0.3),
                                    blurRadius: 8,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(26),
                                child: Image.asset(
                                  'assets/images/potion.jpg',
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) =>
                                      const Icon(Icons.science, color: Color(0xFFFFD700), size: 26),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "MAGIC POTION",
                                    style: TextStyle(
                                      fontFamily: 'MedievalSharp',
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFE5C158),
                                      letterSpacing: 1.0,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    "+10 levels per potion bottle!",
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.white70,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            ElevatedButton.icon(
                              onPressed: _showDrinkPotionDialog,
                              icon: const Icon(Icons.local_drink, size: 16, color: Colors.black),
                              label: const Text(
                                "Drink potion (10 levels)",
                                style: TextStyle(
                                  fontFamily: 'MedievalSharp',
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFFFD700),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                            ),
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

          // Hidden Reset drawer
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

class IntroVideoWidget extends StatefulWidget {
  const IntroVideoWidget({super.key});

  @override
  State<IntroVideoWidget> createState() => _IntroVideoWidgetState();
}

class _IntroVideoWidgetState extends State<IntroVideoWidget> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.asset('assets/videos/aragnoz_intro.mp4')
      ..initialize().then((_) {
        if (mounted) {
          setState(() {
            _isInitialized = true;
          });
          _controller.setLooping(true);
          _controller.setVolume(0.0); // Mute for seamless background playback
          _controller.play();
        }
      }).catchError((error) {
        debugPrint("Video initialization failed: $error");
        if (mounted) {
          setState(() {
            _hasError = true;
          });
        }
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Image.asset(
        'assets/images/aragnoz_retro.jpg',
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return const Center(child: Icon(Icons.broken_image, size: 48));
        },
      );
    }

    if (!_isInitialized) {
      return Stack(
        alignment: Alignment.center,
        children: [
          Image.asset(
            'assets/images/aragnoz_retro.jpg',
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
          ),
          const CircularProgressIndicator(color: Color(0xFFD4AF37)),
        ],
      );
    }

    return ClipRect(
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: _controller.value.size.width,
            height: _controller.value.size.height,
            child: VideoPlayer(_controller),
          ),
        ),
      ),
    );
  }
}

