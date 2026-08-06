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

enum AdventureState { countdown, login, intro, grinding, admin }

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

class SubQuestInfo {
  final String id;
  final String title;
  final String password;
  final String description;
  final int rewardLevels;

  SubQuestInfo({
    this.id = '',
    required this.title,
    required this.password,
    this.description = '',
    this.rewardLevels = 0,
  });

  factory SubQuestInfo.fromMap(Map<String, dynamic> map, [int index = 0]) {
    return SubQuestInfo(
      id: map['id'] as String? ?? 'sub_$index',
      title: map['title'] as String? ?? '',
      password: map['password'] as String? ?? '',
      description: map['description'] as String? ?? map['hint'] as String? ?? '',
      rewardLevels: (map['rewardLevels'] ?? map['reward_levels'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'password': password,
      'description': description,
      'rewardLevels': rewardLevels,
    };
  }

  bool checkPassword(String input) {
    final cleanInput = input.trim().toLowerCase();
    final cleanPassword = password.toLowerCase();
    
    if (cleanPassword.contains('skål')) {
      return cleanInput == 'skål!' || cleanInput == 'skal!' || cleanInput == 'skål' || cleanInput == 'skal';
    }
    
    return cleanInput == cleanPassword;
  }
}

class QuestInfo {
  final String id;
  final String title;
  final String password; // Exact lowercase check (or custom checker)
  final int rewardLevels;
  final String description;
  final int order;
  final List<SubQuestInfo> subquests;

  QuestInfo({
    this.id = '',
    required this.title,
    required this.password,
    required this.rewardLevels,
    required this.description,
    this.order = 0,
    this.subquests = const [],
  });

  bool get hasSubquests => subquests.isNotEmpty;

  factory QuestInfo.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};

    List<SubQuestInfo> subList = [];
    if (data['subquests'] != null && data['subquests'] is List) {
      final rawList = data['subquests'] as List;
      for (int i = 0; i < rawList.length; i++) {
        if (rawList[i] is Map) {
          subList.add(SubQuestInfo.fromMap(rawList[i] as Map<String, dynamic>, i));
        }
      }
    }

    return QuestInfo(
      id: doc.id,
      title: data['title'] as String? ?? '',
      password: data['password'] as String? ?? '',
      rewardLevels: (data['rewardLevels'] ?? data['reward_levels'] as num?)?.toInt() ?? 10,
      description: data['description'] as String? ?? '',
      order: (data['order'] as num?)?.toInt() ?? 0,
      subquests: subList,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'password': password,
      'rewardLevels': rewardLevels,
      'description': description,
      'order': order,
      'subquests': subquests.map((s) => s.toMap()).toList(),
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

class PotionSecretInfo {
  final String id;
  final String secret;
  final int rewardLevels;

  PotionSecretInfo({
    this.id = '',
    required this.secret,
    this.rewardLevels = 10,
  });

  factory PotionSecretInfo.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return PotionSecretInfo(
      id: doc.id,
      secret: data['secret'] as String? ?? '',
      rewardLevels: (data['rewardLevels'] ?? data['reward_levels'] as num?)?.toInt() ?? 10,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'secret': secret,
      'rewardLevels': rewardLevels,
    };
  }

  bool matches(String input) {
    final cleanInput = input.trim().toLowerCase();
    final cleanSecret = secret.trim().toLowerCase();
    if (cleanSecret.isEmpty) return false;

    if (cleanInput == cleanSecret) return true;

    // Ignore trailing punctuation ! or .
    final cleanInputNoPunct = cleanInput.replaceAll(RegExp(r'[!.]+$'), '').trim();
    final cleanSecretNoPunct = cleanSecret.replaceAll(RegExp(r'[!.]+$'), '').trim();

    return cleanInputNoPunct == cleanSecretNoPunct;
  }
}

class MainAdventureManager extends StatefulWidget {
  const MainAdventureManager({super.key});

  @override
  State<MainAdventureManager> createState() => _MainAdventureManagerState();
}

class _MainAdventureManagerState extends State<MainAdventureManager> {
  AdventureState _state = AdventureState.countdown;
  bool _isAdmin = false;
  int _level = 50; // DAoC character starts at max level 50
  final int _targetLevel = 1337;
  bool _isLoading = true;
  bool _audioInitialized = false;
  StreamSubscription? _stateSubscription;
  StreamSubscription? _questsSubscription;
  StreamSubscription? _potionSecretsSubscription;

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
  Set<String> _completedSubQuestKeys = {};
  final Map<String, TextEditingController> _subQuestControllers = {};

  TextEditingController _getSubQuestController(String key) {
    return _subQuestControllers.putIfAbsent(key, () => TextEditingController());
  }

  // Default fallback quests
  static final List<QuestInfo> _defaultQuests = [
    QuestInfo(
      id: "quest_1",
      title: "Get dressed!",
      password: "svensexa!",
      rewardLevels: 10,
      description: "Gör dig redo för äventyr genom att klä dig som en shaman! Dina vänner hjälper dig.",
      order: 1,
    ),
    QuestInfo(
      id: "quest_2",
      title: "Drink a Viking Mead!",
      password: "skål!",
      rewardLevels: 100,
      description: "Vad säger vikingar när de höjer sina bägare? Höj glaset och säg det magiska ordet!",
      order: 2,
    ),
    QuestInfo(
      id: "quest_3",
      title: "Defeat the Celtic dragon!",
      password: "",
      rewardLevels: 0,
      description: "Samla din styrka och besegra den keltiska draken i tre utmanande delsteg!",
      order: 3,
      subquests: [
        SubQuestInfo(
          id: "sub_3_1",
          title: "Del 1: Hitta Drakens Gömma",
          password: "excalibur",
          description: "Sök upp hålan i de keltiska bergen. Vad heter det legendariska svärdet?",
          rewardLevels: 30,
        ),
        SubQuestInfo(
          id: "sub_3_2",
          title: "Del 2: Avslöja Drakens Namn",
          password: "draco",
          description: "Draken vaknar! Säg drakens uråldriga namn för att försvaga den.",
          rewardLevels: 35,
        ),
        SubQuestInfo(
          id: "sub_3_3",
          title: "Del 3: Banbrytande Nådestöt",
          password: "valhalla",
          description: "Utdela nådestöten genom att utropa vikingarnas krigsrop!",
          rewardLevels: 35,
        ),
      ],
    ),
    QuestInfo(
      id: "quest_4",
      title: "Gather the Groomsmen!",
      password: "fellowship",
      rewardLevels: 100,
      description: "Första boken i Sagan om Ringen-trilogin: 'The ... of the Ring'. Samla brudföljet!",
      order: 4,
    ),
    QuestInfo(
      id: "quest_5",
      title: "Patrol the Midgard Border",
      password: "odin",
      rewardLevels: 100,
      description: "Allfadern i den nordiska mytologin. (Upprepat quest!)",
      order: 5,
    ),
    QuestInfo(
      id: "quest_6",
      title: "Quest 6: The Trial of Valhalla",
      password: "valhalla",
      rewardLevels: 100,
      description: "Beskrivning för Quest 6. Ändra titel, beskrivning och lösenord i Firebase Console.",
      order: 6,
    ),
    QuestInfo(
      id: "quest_7",
      title: "Quest 7: The Runes of Power",
      password: "rune",
      rewardLevels: 100,
      description: "Beskrivning för Quest 7. Ändra titel, beskrivning och lösenord i Firebase Console.",
      order: 7,
    ),
    QuestInfo(
      id: "quest_8",
      title: "Quest 8: The Final Horn",
      password: "skål",
      rewardLevels: 100,
      description: "Beskrivning för Quest 8. Ändra titel, beskrivning och lösenord i Firebase Console.",
      order: 8,
    ),
  ];

  // Active quest list dynamically populated from Firestore
  late List<QuestInfo> _quests = List.from(_defaultQuests);

  // Default fallback potion secrets
  static final List<PotionSecretInfo> _defaultPotionSecrets = [
    PotionSecretInfo(id: "potion_1", secret: "Potion secret message", rewardLevels: 10),
    PotionSecretInfo(id: "potion_2", secret: "Potion of level up!", rewardLevels: 10),
  ];

  // Active potion secrets list dynamically populated from Firestore
  late List<PotionSecretInfo> _potionSecrets = List.from(_defaultPotionSecrets);

  final TextEditingController _questPasswordController = TextEditingController();
  final TextEditingController _potionPasswordController = TextEditingController();
  String _questError = "";

  @override
  void initState() {
    super.initState();
    _loadState();
    _initCountdown();
    _listenToQuests();
    _listenToPotionSecrets();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _stateSubscription?.cancel();
    _questsSubscription?.cancel();
    _potionSecretsSubscription?.cancel();
    _usernameController.dispose();
    _classController.dispose();
    _raceController.dispose();
    _questPasswordController.dispose();
    _potionPasswordController.dispose();
    _inputFocusNode.dispose();
    _levelInputController.dispose();
    for (final c in _subQuestControllers.values) {
      c.dispose();
    }
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

      // Check if any existing documents in Firestore still use 'hint', missing 'description', or missing subquests for quest_3
      bool needsMigration = false;
      final batch = FirebaseFirestore.instance.batch();

      for (final doc in snapshot.docs) {
        final data = doc.data();
        
        if (doc.id == 'quest_3' && (data['subquests'] == null || (data['subquests'] as List).isEmpty)) {
          needsMigration = true;
          final quest3Default = _defaultQuests.firstWhere((q) => q.id == 'quest_3');
          batch.update(doc.reference, quest3Default.toMap());
        } else if (data.containsKey('hint') || !data.containsKey('description')) {
          needsMigration = true;
          
          String defaultDesc = "";
          for (final dq in _defaultQuests) {
            if (dq.id == doc.id) {
              defaultDesc = dq.description;
              break;
            }
          }
          if (defaultDesc.isEmpty) {
            defaultDesc = data['hint'] as String? ?? '';
          }

          batch.update(doc.reference, {
            'description': data['description'] as String? ?? defaultDesc,
            'hint': FieldValue.delete(),
          });
        }
      }

      // Check for missing default quests (e.g. quest_6, quest_7, quest_8) and create them automatically
      final existingIds = snapshot.docs.map((doc) => doc.id).toSet();

      for (final dq in _defaultQuests) {
        if (!existingIds.contains(dq.id)) {
          needsMigration = true;
          final docRef = questsRef.doc(dq.id);
          batch.set(docRef, dq.toMap());
        }
      }

      if (needsMigration) {
        debugPrint("Updating/Seeding Firestore quest documents...");
        await batch.commit().catchError((e) {
          debugPrint("Failed to update quest documents: $e");
        });
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

  // Listen to potion secrets from Firestore database
  void _listenToPotionSecrets() {
    final secretsRef = FirebaseFirestore.instance.collection('potion_secrets');

    _potionSecretsSubscription = secretsRef.snapshots().listen((snapshot) async {
      if (snapshot.docs.isEmpty) {
        debugPrint("Firestore 'potion_secrets' collection is empty. Seeding defaults...");
        final batch = FirebaseFirestore.instance.batch();
        for (final s in _defaultPotionSecrets) {
          final docRef = secretsRef.doc(s.id);
          batch.set(docRef, s.toMap());
        }
        await batch.commit().catchError((e) {
          debugPrint("Failed to seed default potion secrets: $e");
        });
        return;
      }

      final loadedSecrets = snapshot.docs
          .map((doc) => PotionSecretInfo.fromFirestore(doc))
          .where((s) => s.secret.isNotEmpty)
          .toList();

      if (mounted && loadedSecrets.isNotEmpty) {
        setState(() {
          _potionSecrets = loadedSecrets;
        });
      }
    }, onError: (error) {
      debugPrint("Error listening to Firestore potion secrets, using defaults: $error");
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
    final isAdmin = prefs.getBool('is_admin') ?? false;
    final completedQuests = prefs.getInt('completed_quests_count') ?? 0;
    final completedSubQuestsList = prefs.getStringList('completed_subquests') ?? [];
    
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
        _isAdmin = isAdmin;
        _completedQuestsCount = completedQuests;
        _completedSubQuestKeys = completedSubQuestsList.toSet();
        _isLoading = false;
      });
    }

    if (!_audioInitialized && (savedState == AdventureState.login || savedState == AdventureState.grinding || savedState == AdventureState.admin)) {
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

  Future<void> _saveAdminState(bool isAdmin) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_admin', isAdmin);
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

  Future<void> _saveCompletedSubQuests() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('completed_subquests', _completedSubQuestKeys.toList());
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

    final isAdminUser = (user == 'hetelmers hot' || user == 'spellhound');
    final isAragnozUser = (user == 'aragnoz' && cls == 'shaman' && rc == 'troll');

    if (isAdminUser || isAragnozUser) {
      setState(() {
        _loginError = "";
        _isAdmin = isAdminUser;
        _state = AdventureState.intro;
      });
      _saveAdminState(isAdminUser);
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
    if (_isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFC62828),
          content: Text(
            "Åskådarläge: Administatörer kan inte klara uppdrag.",
            style: TextStyle(fontFamily: 'MedievalSharp', color: Colors.white),
          ),
        ),
      );
      return;
    }

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

  void _submitSubQuestPassword(QuestInfo quest, SubQuestInfo sub) {
    if (_isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFC62828),
          content: Text(
            "Åskådarläge: Administatörer kan inte klara delmål.",
            style: TextStyle(fontFamily: 'MedievalSharp', color: Colors.white),
          ),
        ),
      );
      return;
    }

    final subKey = "${quest.id}_${sub.id}";
    final controller = _getSubQuestController(subKey);
    final inputPassword = controller.text.trim();
    if (inputPassword.isEmpty) return;

    if (sub.checkPassword(inputPassword) || inputPassword == "32167") {
      final oldLevel = _level;
      final newLevel = _level + sub.rewardLevels;

      setState(() {
        _completedSubQuestKeys.add(subKey);
        _level = newLevel;
        _questError = "";
        controller.clear();

        // Check if all subquests of this quest are completed
        bool allSubquestsDone = true;
        for (final sq in quest.subquests) {
          if (!_completedSubQuestKeys.contains("${quest.id}_${sq.id}")) {
            allSubquestsDone = false;
            break;
          }
        }

        if (allSubquestsDone) {
          if (quest.rewardLevels > 0) {
            _level += quest.rewardLevels;
          }
          if (_completedQuestsCount < _quests.length - 1) {
            _completedQuestsCount++;
          }
        }
      });

      _saveLevel(_level);
      _saveCompletedQuests(_completedQuestsCount);
      _saveCompletedSubQuests();

      // Log subquest completion to Firestore
      try {
        FirebaseFirestore.instance.collection('quest_logs').add({
          'timestamp': FieldValue.serverTimestamp(),
          'quest_title': "${quest.title} - ${sub.title}",
          'old_level': oldLevel,
          'new_level': _level,
          'password_used': inputPassword,
        });
      } catch (e) {
        debugPrint("Failed to write subquest log to Firestore: $e");
      }

      if (oldLevel < _targetLevel && _level >= _targetLevel) {
        AudioController.instance.playVictorySound();
      } else {
        AudioController.instance.playLevelUpSound();
      }
    } else {
      setState(() {
        _questError = "Fel lösenord för delmålet! Försök igen.";
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
                  const SizedBox(height: 8),
                  // Autofill secret message button for testers
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () {
                        setDialogState(() {
                          _potionPasswordController.text = _potionSecrets.isNotEmpty
                              ? _potionSecrets.first.secret
                              : "Potion secret message";
                        });
                      },
                      icon: const Icon(Icons.auto_fix_high, size: 14, color: Color(0xFFE5C158)),
                      label: const Text(
                        "Autofill secret message (tillfällig knapp för testare)",
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFFE5C158),
                          decoration: TextDecoration.underline,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
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
                    if (_isAdmin) {
                      setDialogState(() {
                        dialogError = "Åskådarläge: Administatörer kan inte dricka potions.";
                      });
                      return;
                    }

                    final rawInput = _potionPasswordController.text.trim();
                    
                    PotionSecretInfo? matchedSecret;
                    for (final s in _potionSecrets) {
                      if (s.matches(rawInput)) {
                        matchedSecret = s;
                        break;
                      }
                    }

                    // Master code fallback
                    if (matchedSecret == null && rawInput == '32167') {
                      matchedSecret = PotionSecretInfo(secret: '32167', rewardLevels: 10);
                    }

                    if (matchedSecret != null) {
                      final reward = matchedSecret.rewardLevels;
                      final oldLevel = _level;
                      final newLevel = _level + reward;
                      setState(() {
                        _level = newLevel;
                      });
                      _saveLevel(newLevel);
                      
                      // Log potion drink to Firestore
                      try {
                        FirebaseFirestore.instance.collection('quest_logs').add({
                          'timestamp': FieldValue.serverTimestamp(),
                          'quest_title': 'Magic Potion Consumed (+$reward levels)',
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
                        SnackBar(
                          backgroundColor: const Color(0xFF2E7D32),
                          content: Text(
                            "Slurp! Du drack potionen och fick +$reward levlar!",
                            style: const TextStyle(fontFamily: 'MedievalSharp', color: Colors.white),
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
      _isAdmin = false;
      _bypassClicks = 0;
      _completedQuestsCount = 0;
      _completedSubQuestKeys.clear();
      _usernameController.clear();
      _classController.clear();
      _raceController.clear();
      _questPasswordController.clear();
      _loginError = "";
      _questError = "";
      for (final c in _subQuestControllers.values) {
        c.clear();
      }
      _initCountdown();
    });
    _saveLevel(50);
    _saveCompletedQuests(0);
    _saveCompletedSubQuests();
    _saveAdminState(false);
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

  Widget _buildSubquestsList(QuestInfo quest) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        const Text(
          "SUB-QUESTS / DELMÅL",
          style: TextStyle(
            fontFamily: 'MedievalSharp',
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Color(0xFFD4AF37),
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: quest.subquests.length,
          separatorBuilder: (context, index) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final sub = quest.subquests[index];
            final subKey = "${quest.id}_${sub.id}";
            final isDone = _completedSubQuestKeys.contains(subKey);

            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDone
                    ? const Color(0xFF1B2E1D).withValues(alpha: 0.6)
                    : const Color(0xFF0F1115).withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isDone ? const Color(0xFF4CAF50) : const Color(0xFF8B7355),
                  width: 1.2,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          "${index + 1}. ${sub.title}",
                          style: TextStyle(
                            fontFamily: 'MedievalSharp',
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: isDone ? const Color(0xFF81C784) : Colors.white,
                            decoration: isDone ? TextDecoration.lineThrough : null,
                          ),
                        ),
                      ),
                      if (sub.rewardLevels > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFD4AF37).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: const Color(0xFFD4AF37), width: 0.8),
                          ),
                          child: Text(
                            "+${sub.rewardLevels} Lvl",
                            style: const TextStyle(
                              color: Color(0xFFFFD700),
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (sub.description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      sub.description,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDone ? Colors.grey.shade500 : Colors.grey.shade300,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  if (isDone)
                    Row(
                      children: const [
                        Icon(Icons.check_circle, color: Color(0xFF4CAF50), size: 16),
                        SizedBox(width: 6),
                        Text(
                          "Delmål avklarat!",
                          style: TextStyle(
                            color: Color(0xFF81C784),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'MedievalSharp',
                          ),
                        ),
                      ],
                    )
                  else ...[
                    // Autofill button for subquest
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () {
                          setState(() {
                            _getSubQuestController(subKey).text = sub.password;
                          });
                        },
                        icon: const Icon(Icons.auto_fix_high, size: 14, color: Color(0xFFE5C158)),
                        label: const Text(
                          "Autofill password (tillfällig knapp för testare)",
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFFE5C158),
                            decoration: TextDecoration.underline,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 38,
                            decoration: BoxDecoration(
                              color: Colors.black,
                              border: Border.all(color: const Color(0xFF8B7355), width: 1.0),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: TextField(
                              controller: _getSubQuestController(subKey),
                              style: const TextStyle(
                                color: Color(0xFFE5C158),
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                              decoration: const InputDecoration(
                                hintText: "Enter Sub-Quest Password",
                                hintStyle: TextStyle(color: Colors.grey, fontSize: 11),
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                isDense: true,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () => _submitSubQuestPassword(quest, sub),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE5C158),
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          child: const Text(
                            "COMPLETE",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ],
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
                      if (_isAdmin) ...[
                        Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF4A148C).withOpacity(0.4),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFBA68C8), width: 1.5),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.admin_panel_settings, color: Color(0xFFE1BEE7), size: 22),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  "ÅSKÅDAR- / ADMINLÄGE\n(Kan se status, men ej klara uppdrag/potions)",
                                  style: TextStyle(
                                    fontFamily: 'MedievalSharp',
                                    fontSize: 11,
                                    color: Color(0xFFE1BEE7),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              ElevatedButton.icon(
                                onPressed: () {
                                  setState(() {
                                    _state = AdventureState.admin;
                                  });
                                },
                                icon: const Icon(Icons.settings, size: 14, color: Colors.black),
                                label: const Text(
                                  "ADMIN-MENY",
                                  style: TextStyle(
                                    fontFamily: 'MedievalSharp',
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFFFD700),
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
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
                            const SizedBox(height: 6),
                            Text(
                              currentQuest.description,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade300,
                                height: 1.35,
                                fontFamily: 'Metamorphous',
                              ),
                            ),
                            const SizedBox(height: 10),
                            
                            // Display subquests UI if quest has subquests, otherwise normal single quest UI
                            if (currentQuest.hasSubquests)
                              _buildSubquestsList(currentQuest)
                            else ...[
                              // Autofill password button for testers
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  onPressed: () {
                                    setState(() {
                                      _questPasswordController.text = currentQuest.password;
                                    });
                                  },
                                  icon: const Icon(Icons.auto_fix_high, size: 14, color: Color(0xFFE5C158)),
                                  label: const Text(
                                    "Autofill password (tillfällig knapp för testare)",
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFFE5C158),
                                      decoration: TextDecoration.underline,
                                    ),
                                  ),
                                  style: TextButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              
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
                            ],
                            
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
  // ADMIN VIEW & QUEST MANAGEMENT
  // ==========================================
  Future<void> _reorderQuests(int currentIndex, int targetIndex) async {
    if (targetIndex < 0 || targetIndex >= _quests.length) return;

    List<QuestInfo> reordered = List.from(_quests);
    final item = reordered.removeAt(currentIndex);
    reordered.insert(targetIndex, item);

    final batch = FirebaseFirestore.instance.batch();
    for (int i = 0; i < reordered.length; i++) {
      final q = reordered[i];
      final newOrder = i + 1;
      final docRef = FirebaseFirestore.instance.collection('quests').doc(q.id);
      batch.update(docRef, {'order': newOrder});
    }

    try {
      await batch.commit();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xFF2E7D32),
            content: Text("Uppdragsordning uppdaterad!"),
          ),
        );
      }
    } catch (e) {
      debugPrint("Failed to reorder quests in Firestore: $e");
    }
  }

  void _showQuestDialog({QuestInfo? existingQuest}) {
    final isEditing = existingQuest != null;
    final titleController = TextEditingController(text: existingQuest?.title ?? '');
    final descController = TextEditingController(text: existingQuest?.description ?? '');
    final passwordController = TextEditingController(text: existingQuest?.password ?? '');
    final rewardController = TextEditingController(text: (existingQuest?.rewardLevels ?? 10).toString());
    final orderController = TextEditingController(text: (existingQuest?.order ?? (_quests.length + 1)).toString());

    List<SubQuestInfo> tempSubquests = existingQuest != null ? List.from(existingQuest.subquests) : [];

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
              title: Text(
                isEditing ? "Redigera uppdrag" : "Lägg till nytt uppdrag",
                style: const TextStyle(color: Color(0xFFE5C158), fontFamily: 'MedievalSharp'),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _adminTextField("Titel", titleController),
                    const SizedBox(height: 10),
                    _adminTextField("Beskrivning", descController, maxLines: 3),
                    const SizedBox(height: 10),
                    _adminTextField("Lösenord", passwordController),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: _adminTextField("Belöning (levlar)", rewardController, isNumber: true)),
                        const SizedBox(width: 10),
                        Expanded(child: _adminTextField("Ordning (1, 2, ...)", orderController, isNumber: true)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "DELMÅL / SUBQUESTS",
                          style: TextStyle(fontFamily: 'MedievalSharp', fontSize: 13, color: Color(0xFFD4AF37), fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add_circle, color: Color(0xFF4CAF50)),
                          onPressed: () {
                            _showSubquestDialog(
                              onSave: (newSub) {
                                setDialogState(() {
                                  tempSubquests.add(newSub);
                                });
                              },
                            );
                          },
                        ),
                      ],
                    ),
                    if (tempSubquests.isEmpty)
                      const Text("Inga delmål tillagda.", style: TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic))
                    else
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: tempSubquests.length,
                        itemBuilder: (context, index) {
                          final sq = tempSubquests[index];
                          return Card(
                            color: const Color(0xFF0F1115),
                            child: ListTile(
                              dense: true,
                              title: Text(sq.title, style: const TextStyle(color: Colors.white, fontSize: 13)),
                              subtitle: Text("Kod: ${sq.password} | +${sq.rewardLevels} Lvl", style: const TextStyle(color: Colors.grey, fontSize: 11)),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit, size: 18, color: Color(0xFFE5C158)),
                                    onPressed: () {
                                      _showSubquestDialog(
                                        existingSub: sq,
                                        onSave: (updatedSub) {
                                          setDialogState(() {
                                            tempSubquests[index] = updatedSub;
                                          });
                                        },
                                      );
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete, size: 18, color: Color(0xFFFF5252)),
                                    onPressed: () {
                                      setDialogState(() {
                                        tempSubquests.removeAt(index);
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Avbryt", style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE5C158),
                    foregroundColor: Colors.black,
                  ),
                  onPressed: () async {
                    final title = titleController.text.trim();
                    if (title.isEmpty) return;

                    final password = passwordController.text.trim();
                    final desc = descController.text.trim();
                    final reward = int.tryParse(rewardController.text.trim()) ?? 10;
                    final order = int.tryParse(orderController.text.trim()) ?? (_quests.length + 1);

                    final docId = isEditing ? existingQuest.id : "quest_${DateTime.now().millisecondsSinceEpoch}";
                    final docRef = FirebaseFirestore.instance.collection('quests').doc(docId);

                    final questData = {
                      'title': title,
                      'password': password,
                      'description': desc,
                      'rewardLevels': reward,
                      'order': order,
                      'subquests': tempSubquests.map((s) => s.toMap()).toList(),
                    };

                    await docRef.set(questData, SetOptions(merge: true));
                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: const Color(0xFF2E7D32),
                          content: Text(isEditing ? "Uppdrag uppdaterat!" : "Nytt uppdrag skapat!"),
                        ),
                      );
                    }
                  },
                  child: Text(isEditing ? "Spara" : "Skapa", style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showSubquestDialog({SubQuestInfo? existingSub, required Function(SubQuestInfo) onSave}) {
    final titleController = TextEditingController(text: existingSub?.title ?? '');
    final descController = TextEditingController(text: existingSub?.description ?? '');
    final passwordController = TextEditingController(text: existingSub?.password ?? '');
    final rewardController = TextEditingController(text: (existingSub?.rewardLevels ?? 10).toString());

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF262C34),
          title: Text(
            existingSub != null ? "Redigera delmål" : "Lägg till delmål",
            style: const TextStyle(color: Color(0xFFE5C158), fontFamily: 'MedievalSharp', fontSize: 16),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _adminTextField("Delmål Titel", titleController),
                const SizedBox(height: 8),
                _adminTextField("Beskrivning", descController, maxLines: 2),
                const SizedBox(height: 8),
                _adminTextField("Lösenord", passwordController),
                const SizedBox(height: 8),
                _adminTextField("Belöning (levlar)", rewardController, isNumber: true),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Avbryt", style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE5C158), foregroundColor: Colors.black),
              onPressed: () {
                final title = titleController.text.trim();
                if (title.isEmpty) return;
                final sub = SubQuestInfo(
                  id: existingSub?.id ?? "sub_${DateTime.now().millisecondsSinceEpoch}",
                  title: title,
                  password: passwordController.text.trim(),
                  description: descController.text.trim(),
                  rewardLevels: int.tryParse(rewardController.text.trim()) ?? 10,
                );
                onSave(sub);
                Navigator.pop(context);
              },
              child: const Text("Spara delmål"),
            ),
          ],
        );
      },
    );
  }

  Widget _adminTextField(String label, TextEditingController controller, {bool isNumber = false, int maxLines = 1}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11, fontFamily: 'MedievalSharp')),
        const SizedBox(height: 4),
        Container(
          decoration: BoxDecoration(
            color: Colors.black,
            border: Border.all(color: const Color(0xFF8B7355), width: 1.0),
            borderRadius: BorderRadius.circular(6),
          ),
          child: TextField(
            controller: controller,
            keyboardType: isNumber ? TextInputType.number : TextInputType.text,
            maxLines: maxLines,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              isDense: true,
            ),
          ),
        ),
      ],
    );
  }

  void _confirmDeleteQuest(QuestInfo quest) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E2125),
          title: const Text("Ta bort uppdrag?", style: TextStyle(color: Color(0xFFFF5252), fontFamily: 'MedievalSharp')),
          content: Text("Är du säker på att du vill ta bort uppdraget '${quest.title}'? Detta går inte att ångra."),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Avbryt")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD32F2F)),
              onPressed: () async {
                Navigator.pop(context);
                await FirebaseFirestore.instance.collection('quests').doc(quest.id).delete();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: const Color(0xFFD32F2F),
                      content: Text("Uppdraget '${quest.title}' har tagits bort."),
                    ),
                  );
                }
              },
              child: const Text("Ta bort", style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  void _showPotionDialog({PotionSecretInfo? existingPotion}) {
    final isEditing = existingPotion != null;
    final secretController = TextEditingController(text: existingPotion?.secret ?? '');
    final rewardController = TextEditingController(text: (existingPotion?.rewardLevels ?? 10).toString());

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E2125),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFFD4AF37), width: 1.8),
          ),
          title: Text(
            isEditing ? "Redigera Potion" : "Lägg till ny Potion-kod",
            style: const TextStyle(color: Color(0xFFE5C158), fontFamily: 'MedievalSharp'),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _adminTextField("Hemligt meddelande / Kod", secretController),
              const SizedBox(height: 10),
              _adminTextField("Belöning i levlar", rewardController, isNumber: true),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Avbryt", style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE5C158),
                foregroundColor: Colors.black,
              ),
              onPressed: () async {
                final secret = secretController.text.trim();
                if (secret.isEmpty) return;

                final reward = int.tryParse(rewardController.text.trim()) ?? 10;
                final docId = isEditing ? existingPotion.id : "potion_${DateTime.now().millisecondsSinceEpoch}";
                final docRef = FirebaseFirestore.instance.collection('potion_secrets').doc(docId);

                await docRef.set({
                  'secret': secret,
                  'rewardLevels': reward,
                }, SetOptions(merge: true));

                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: const Color(0xFF2E7D32),
                      content: Text(isEditing ? "Potion-kod uppdaterad!" : "Ny potion-kod skapad!"),
                    ),
                  );
                }
              },
              child: Text(isEditing ? "Spara" : "Skapa", style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  void _confirmDeletePotion(PotionSecretInfo potion) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E2125),
          title: const Text("Ta bort Potion?", style: TextStyle(color: Color(0xFFFF5252), fontFamily: 'MedievalSharp')),
          content: Text("Är du säker på att du vill ta bort potion-koden '${potion.secret}'?"),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Avbryt")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD32F2F)),
              onPressed: () async {
                Navigator.pop(context);
                await FirebaseFirestore.instance.collection('potion_secrets').doc(potion.id).delete();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: const Color(0xFFD32F2F),
                      content: Text("Potion-koden '${potion.secret}' har tagits bort."),
                    ),
                  );
                }
              },
              child: const Text("Ta bort", style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAdminScreen() {
    int totalQuestLevels = 0;
    for (final q in _quests) {
      totalQuestLevels += q.rewardLevels;
      for (final sq in q.subquests) {
        totalQuestLevels += sq.rewardLevels;
      }
    }

    int potionCount = 10;
    int potionRewardPerBottle = _potionSecrets.isNotEmpty ? _potionSecrets.first.rewardLevels : 10;
    int totalPotionLevels = potionCount * potionRewardPerBottle;

    final int maxAchievableLevel = 50 + totalQuestLevels + totalPotionLevels;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFF0F1115),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1E2125),
          iconTheme: const IconThemeData(color: Color(0xFFE5C158)),
          title: const Text(
            "⚙️ ADMINPANEL",
            style: TextStyle(
              fontFamily: 'Cinzel Decorative',
              fontSize: 16,
              color: Color(0xFFE5C158),
              fontWeight: FontWeight.bold,
            ),
          ),
          bottom: const TabBar(
            indicatorColor: Color(0xFFFFD700),
            labelColor: Color(0xFFFFD700),
            unselectedLabelColor: Colors.grey,
            tabs: [
              Tab(icon: Icon(Icons.assignment), text: "Uppdrag"),
              Tab(icon: Icon(Icons.science), text: "Potions"),
            ],
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _state = AdventureState.grinding;
                  });
                },
                icon: const Icon(Icons.visibility, size: 16, color: Colors.black),
                label: const Text(
                  "TILLBAKA TILL ARAGNOZ",
                  style: TextStyle(fontFamily: 'MedievalSharp', fontSize: 11, color: Colors.black, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE5C158),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              // Max Level Summary Card at top of Admin View
              Container(
                margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2C2214), Color(0xFF16110A)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFFD700), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFFD700).withValues(alpha: 0.15),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFD700).withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.star_rounded, color: Color(0xFFFFD700), size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "MAX LEVEL (UPPDRAG + 10 ST POTIONS):",
                            style: TextStyle(
                              fontFamily: 'MedievalSharp',
                              fontSize: 11,
                              color: Colors.grey,
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Text(
                                "Level $maxAchievableLevel",
                                style: const TextStyle(
                                  fontFamily: 'Cinzel Decorative',
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFFFD700),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  "(Start 50 + $totalQuestLevels Lvl uppdrag + $totalPotionLevels Lvl från 10 st potions)",
                                  style: const TextStyle(
                                    fontFamily: 'MedievalSharp',
                                    fontSize: 11,
                                    color: Color(0xFF81C784),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (maxAchievableLevel >= 1337)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF4CAF50).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0xFF4CAF50), width: 1),
                        ),
                        child: const Text(
                          "GOAL REACHED! (≥1337)",
                          style: TextStyle(color: Color(0xFF81C784), fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],
                ),
              ),

              Expanded(
                child: TabBarView(
                  children: [
                    // Tab 1: Quests Manager
                    Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          color: Colors.black45,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                "Totalt ${_quests.length} uppdrag i databasen",
                                style: const TextStyle(color: Colors.white70, fontSize: 13, fontFamily: 'MedievalSharp'),
                              ),
                              ElevatedButton.icon(
                                onPressed: () => _showQuestDialog(),
                                icon: const Icon(Icons.add, size: 18, color: Colors.black),
                                label: const Text("Nytt Uppdrag", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontFamily: 'MedievalSharp')),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF4CAF50),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ReorderableListView.builder(
                            padding: const EdgeInsets.all(12),
                            itemCount: _quests.length,
                            onReorder: (oldIndex, newIndex) {
                              if (newIndex > oldIndex) {
                                newIndex -= 1;
                              }
                              _reorderQuests(oldIndex, newIndex);
                            },
                            itemBuilder: (context, index) {
                              final quest = _quests[index];
                              return Card(
                                key: ValueKey(quest.id),
                                color: const Color(0xFF1E2125),
                                margin: const EdgeInsets.only(bottom: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  side: const BorderSide(color: Color(0xFF8B7355), width: 1.2),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFD4AF37).withValues(alpha: 0.2),
                                              borderRadius: BorderRadius.circular(4),
                                              border: Border.all(color: const Color(0xFFD4AF37), width: 1),
                                            ),
                                            child: Text(
                                              "#${quest.order}",
                                              style: const TextStyle(color: Color(0xFFFFD700), fontWeight: FontWeight.bold, fontSize: 12),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              quest.title,
                                              style: const TextStyle(
                                                fontFamily: 'MedievalSharp',
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF2E7D32).withValues(alpha: 0.3),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              "+${quest.rewardLevels} Lvl",
                                              style: const TextStyle(color: Color(0xFF81C784), fontSize: 11, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (quest.description.isNotEmpty) ...[
                                        const SizedBox(height: 6),
                                        Text(
                                          quest.description,
                                          style: const TextStyle(color: Colors.grey, fontSize: 12, fontStyle: FontStyle.italic),
                                        ),
                                      ],
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          const Icon(Icons.key, size: 14, color: Color(0xFFD4AF37)),
                                          const SizedBox(width: 4),
                                          Text(
                                            "Lösenord: ${quest.password.isEmpty ? '(inga, har delmål)' : quest.password}",
                                            style: const TextStyle(color: Color(0xFFE5C158), fontSize: 12, fontFamily: 'MedievalSharp'),
                                          ),
                                          if (quest.hasSubquests) ...[
                                            const SizedBox(width: 12),
                                            Text(
                                              "(${quest.subquests.length} delmål)",
                                              style: const TextStyle(color: Colors.cyanAccent, fontSize: 11),
                                            ),
                                          ],
                                        ],
                                      ),
                                      const Divider(color: Color(0xFF3E474F), height: 16),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.end,
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.arrow_upward, size: 20, color: Colors.grey),
                                            onPressed: index > 0 ? () => _reorderQuests(index, index - 1) : null,
                                            tooltip: "Flytta upp",
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.arrow_downward, size: 20, color: Colors.grey),
                                            onPressed: index < _quests.length - 1 ? () => _reorderQuests(index, index + 1) : null,
                                            tooltip: "Flytta ner",
                                          ),
                                          const SizedBox(width: 8),
                                          ElevatedButton.icon(
                                            onPressed: () => _showQuestDialog(existingQuest: quest),
                                            icon: const Icon(Icons.edit, size: 16, color: Colors.black),
                                            label: const Text("Redigera", style: TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.bold)),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: const Color(0xFFE5C158),
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          ElevatedButton.icon(
                                            onPressed: () => _confirmDeleteQuest(quest),
                                            icon: const Icon(Icons.delete, size: 16, color: Colors.white),
                                            label: const Text("Ta bort", style: TextStyle(color: Colors.white, fontSize: 11)),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: const Color(0xFFD32F2F),
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),

                    // Tab 2: Potions Manager
                    Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          color: Colors.black45,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                "Totalt ${_potionSecrets.length} potion-koder i databasen",
                                style: const TextStyle(color: Colors.white70, fontSize: 13, fontFamily: 'MedievalSharp'),
                              ),
                              ElevatedButton.icon(
                                onPressed: () => _showPotionDialog(),
                                icon: const Icon(Icons.add, size: 18, color: Colors.black),
                                label: const Text("Ny Potion", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontFamily: 'MedievalSharp')),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF4CAF50),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            padding: const EdgeInsets.all(12),
                            itemCount: _potionSecrets.length,
                            itemBuilder: (context, index) {
                              final potion = _potionSecrets[index];
                              return Card(
                                key: ValueKey(potion.id),
                                color: const Color(0xFF1E2125),
                                margin: const EdgeInsets.only(bottom: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  side: const BorderSide(color: Color(0xFF8B7355), width: 1.2),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 40,
                                        height: 40,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(color: const Color(0xFFFFD700), width: 1.5),
                                        ),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(20),
                                          child: Image.asset(
                                            'assets/images/potion.jpg',
                                            fit: BoxFit.cover,
                                            errorBuilder: (context, error, stackTrace) =>
                                                const Icon(Icons.science, color: Color(0xFFFFD700), size: 20),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              potion.secret,
                                              style: const TextStyle(
                                                fontFamily: 'MedievalSharp',
                                                fontSize: 15,
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFFE5C158),
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              "Belöning: +${potion.rewardLevels} levlar",
                                              style: const TextStyle(color: Colors.grey, fontSize: 12),
                                            ),
                                          ],
                                        ),
                                      ),
                                      ElevatedButton.icon(
                                        onPressed: () => _showPotionDialog(existingPotion: potion),
                                        icon: const Icon(Icons.edit, size: 16, color: Colors.black),
                                        label: const Text("Redigera", style: TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.bold)),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFFE5C158),
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      ElevatedButton.icon(
                                        onPressed: () => _confirmDeletePotion(potion),
                                        icon: const Icon(Icons.delete, size: 16, color: Colors.white),
                                        label: const Text("Ta bort", style: TextStyle(color: Colors.white, fontSize: 11)),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFFD32F2F),
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
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
      case AdventureState.admin:
        return _buildAdminScreen();
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

