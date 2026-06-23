import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/db_helper.dart';
import '../services/assessment_engine.dart';

class MathQuizScreen extends StatefulWidget {
  final VoidCallback? onQuit;
  const MathQuizScreen({super.key, this.onQuit});
  final String studentLevel;
  const MathQuizScreen({super.key, this.onQuit, required this.studentLevel});

  @override
  State<MathQuizScreen> createState() => _MathQuizScreenState();
}

class _MathQuizScreenState extends State<MathQuizScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _answerController = TextEditingController();
  int _currentIndex = 0;
  int _correctCount = 0;
  final List<int> _wrongIndexes = [];
  String? _errorText;

  // Adaptive Learning State
  int _currentLevel = 1;
  bool _isLoadingQuestions = true;
  List<Map<String, dynamic>> _questions = [];

  // Classroom Homework Revision State
  List<Map<String, dynamic>> _homeworkQuestions = [];
  bool _isLoadingHomework = true;
  bool _showSelectionScreen = true;
  bool _isHomeworkMode = false;

  // Per-question overlay
  bool _showingFeedback = false;
  bool _lastCorrect = false;

  late AnimationController _progressController;
  Animation<double>? _progressAnim;

  // ── Expanded Question Bank (Levels 1-5) ──────────────────────────
  final Map<int, List<Map<String, dynamic>>> _questionBank = {
    1: [
      {'q': '125 + 375', 'a': '500', 'type': 'text', 'topic': 'Addition'},
      {'q': '7 × 8', 'a': '56', 'type': 'text', 'topic': 'Multiplication'},
      {'q': '1/2 + 1/2', 'a': '1', 'type': 'text', 'topic': 'Fractions'},
      {'q': 'Which is the area of a rectangle?', 'a': 'L × W', 'type': 'mcq', 'topic': 'Geometry', 'options': ['L + W', 'L × W', '2 × (L+W)']}
    ],
    2: [
      {'q': '15% of 200', 'a': '30', 'type': 'text', 'topic': 'Percentages'},
      {'q': 'Solve for x: 2x + 5 = 15', 'a': '5', 'type': 'text', 'topic': 'Algebra'},
      {'q': 'Square root of 144', 'a': '12', 'type': 'text', 'topic': 'Roots'},
      {'q': 'Simplify 12/16', 'a': '3/4', 'type': 'mcq', 'topic': 'Fractions', 'options': ['1/2', '2/3', '3/4']}
    ],
    3: [
      {'q': 'Calculate: (25 × 4) ÷ 2', 'a': '50', 'type': 'text', 'topic': 'Order of Ops'},
      {'q': 'Area of circle (r=7, π=22/7)', 'a': '154', 'type': 'text', 'topic': 'Geometry'},
      {'q': '1.25 + 0.75', 'a': '2', 'type': 'text', 'topic': 'Decimals'},
      {'q': 'Sum of angles in a triangle?', 'a': '180', 'type': 'mcq', 'topic': 'Geometry', 'options': ['90', '180', '360']}
    ],
    4: [
      {'q': 'Solve for y: 3y - 7 = 20', 'a': '9', 'type': 'text', 'topic': 'Algebra'},
      {'q': 'What is 2/5 as a percentage?', 'a': '40', 'type': 'text', 'topic': 'Percentages'},
      {'q': '3³ (3 cubed)', 'a': '27', 'type': 'text', 'topic': 'Exponents'},
      {'q': 'A triangle with all sides equal is called?', 'a': 'Equilateral', 'type': 'mcq', 'topic': 'Geometry', 'options': ['Isosceles', 'Scalene', 'Equilateral']}
    ],
    5: [
      {'q': 'Solve: (12 + 8) × (5 - 2)', 'a': '60', 'type': 'text', 'topic': 'Arithmetic'},
      {'q': 'Find the average of 10, 20, 30, 40', 'a': '25', 'type': 'text', 'topic': 'Statistics'},
      {'q': '0.5 × 0.5', 'a': '0.25', 'type': 'text', 'topic': 'Decimals'},
      {'q': 'How many faces does a cube have?', 'a': '6', 'type': 'mcq', 'topic': 'Geometry', 'options': ['4', '6', '8']}
    ],
  };

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _fetchHomeworkQuestions();
  }

  Future<void> _fetchHomeworkQuestions() async {
    try {
      final supabase = Supabase.instance.client;
      final response = await supabase
          .from('homework')
          .select('questions, title')
          .eq('level', widget.studentLevel);
      
      final List<Map<String, dynamic>> fetched = [];
      if (response != null) {
        for (var hw in response) {
          final qList = hw['questions'];
          final String title = hw['title'] ?? 'Revision';
          if (qList is List) {
            for (var q in qList) {
              if (q is Map) {
                final String text = q['text']?.toString() ?? '';
                final String answer = q['correct_answer']?.toString() ?? '';
                final String type = q['type']?.toString() ?? 'text';
                final List<dynamic>? options = q['options'] is List ? q['options'] : null;
                
                if (text.isNotEmpty && answer.isNotEmpty) {
                  fetched.add({
                    'q': text,
                    'a': answer,
                    'type': type,
                    'topic': title,
                    'options': options?.map((o) => o.toString()).toList(),
                  });
                }
              }
            }
          }
        }
      }
      
      if (mounted) {
        setState(() {
          _homeworkQuestions = fetched;
          _isLoadingHomework = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching homework questions for quiz: $e");
      if (mounted) {
        setState(() {
          _isLoadingHomework = false;
        });
      }
    }
  }

  void _startHomeworkRevision() {
    if (_homeworkQuestions.isEmpty) return;
    setState(() {
      _isHomeworkMode = true;
      _showSelectionScreen = false;
      _isLoadingQuestions = false;
      _questions = List.from(_homeworkQuestions)..shuffle();
      // Cap homework revision at 10 random questions at a time to prevent overload
      if (_questions.length > 10) {
        _questions = _questions.sublist(0, 10);
      }
      _currentIndex = 0;
      _correctCount = 0;
      _wrongIndexes.clear();
      
      _answerController.clear();
      _selectedOption = null;
      _errorText = null;
      
      final double target = (_currentIndex + 1) / _questions.length;
      _progressAnim = Tween<double>(begin: 0, end: target).animate(
          CurvedAnimation(parent: _progressController, curve: Curves.easeInOut));
      _progressController..reset()..forward();
    });
  }

  void _startChallengeLevels() {
    setState(() {
      _isHomeworkMode = false;
      _showSelectionScreen = false;
    });
    _loadLevel(1);
  }

  void _loadLevel(int level) {
    setState(() {
      _currentLevel = level;
      _questions = List.from(_questionBank[level] ?? _questionBank[1]!)..shuffle();
      _currentIndex = 0;
      _correctCount = 0;
      _wrongIndexes.clear();
      _isLoadingQuestions = false;
      
      _answerController.clear();
      _selectedOption = null;
      _errorText = null;
      
      final double target = (_currentIndex + 1) / _questions.length;
      _progressAnim = Tween<double>(begin: 0, end: target).animate(
          CurvedAnimation(parent: _progressController, curve: Curves.easeInOut));
      _progressController..reset()..forward();
    });
  }

  @override
  void dispose() {
    _progressController.dispose();
    _answerController.dispose();
    super.dispose();
  }

  void _updateProgressBar() {
    if (_questions.isEmpty || _progressAnim == null) return;
    final double begin = _progressAnim!.value;
    final double target = (_currentIndex + 1) / _questions.length;
    _progressAnim = Tween<double>(begin: begin, end: target).animate(
        CurvedAnimation(parent: _progressController, curve: Curves.easeInOut));
    _progressController..reset()..forward();
  }

  void _checkAnswer() {
    final q = _questions[_currentIndex];
    final String type = q['type'] as String;
    final String studentAnswer = type == 'mcq' ? (_selectedOption ?? '') : _answerController.text.trim();

    if (studentAnswer.isEmpty) {
      setState(() => _errorText = 'Please enter an answer!');
      return;
    }

    final bool correct = studentAnswer.trim().toLowerCase() == (q['a'] as String).trim().toLowerCase();

    if (correct) {
      _correctCount++;
    } else {
      _wrongIndexes.add(_currentIndex);
    }
    if (correct) _correctCount++;
    else _wrongIndexes.add(_currentIndex);

    setState(() {
      _showingFeedback = true;
      _lastCorrect = correct;
      _errorText = null;
    });

    Future.delayed(const Duration(milliseconds: 2000), () {
      if (!mounted) return;
      setState(() => _showingFeedback = false);

      if (_currentIndex < _questions.length - 1) {
        setState(() {
          _currentIndex++;
          _selectedOption = null;
          _answerController.clear();
        });
        _updateProgressBar();
      } else {
        _finishQuiz();
      }
    });
  }

  Future<void> _finishQuiz() async {
    final AssessmentResult result = AssessmentEngine.evaluate(
      correctCount: _correctCount,
      totalQuestions: _questions.length,
      topic: 'Mixed Practice Level $_currentLevel',
      topic: _isHomeworkMode ? 'Homework Revision' : 'Mixed Practice Level $_currentLevel',
      wrongIndexes: _wrongIndexes,
    );

    bool isMastered = result.grade == 'A' || result.grade == 'B';
    // Max level is now 5
    bool levelUnlocked = isMastered && _currentLevel < 5;

    await DBHelper().savePerformance({
      'topic': 'Quiz Level $_currentLevel',
    bool levelUnlocked = !_isHomeworkMode && isMastered && _currentLevel < 5;

    await DBHelper().savePerformance({
      'topic': _isHomeworkMode ? 'Homework Revision' : 'Quiz Level $_currentLevel',
      'score': _correctCount.toDouble(),
      'total_questions': _questions.length,
      'date_taken': DateTime.now().toString(),
      'grade': result.grade,
      'recommendation': levelUnlocked ? 'Congrats! Level ${_currentLevel + 1} Unlocked.' : result.recommendation,
      'recommendation': _isHomeworkMode
          ? (isMastered ? 'Excellent homework revision work!' : 'Keep practicing to master your homework questions.')
          : (levelUnlocked ? 'Congrats! Level ${_currentLevel + 1} Unlocked.' : result.recommendation),
      'is_synced': 0,
    });

    if (mounted) _showResultDialog(result, levelUnlocked, isMastered);
  }

  void _showResultDialog(AssessmentResult result, bool levelUnlocked, bool isMastered) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 70, height: 70,
                decoration: BoxDecoration(color: result.gradeColor, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Text(result.grade, style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 12),
              Text(
                levelUnlocked 
                    ? "LEVEL UNLOCKED! 🏆" 
                    : (isMastered ? "MASTERY ACHIEVED! ⭐" : "Quiz Finished"), 
                _isHomeworkMode
                    ? "REVISION COMPLETE! 📝"
                    : (levelUnlocked 
                        ? "LEVEL UNLOCKED! 🏆" 
                        : (isMastered ? "MASTERY ACHIEVED! ⭐" : "Quiz Finished")), 
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: result.gradeColor),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(result.feedback, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14)),
              const Divider(height: 30),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        if (widget.onQuit != null) widget.onQuit!();
                      },
                      child: const Text('Dashboard'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        if (levelUnlocked) {
                          _loadLevel(_currentLevel + 1);
                        } else {
                          _loadLevel(_currentLevel);
                        if (_isHomeworkMode) {
                          _startHomeworkRevision();
                        } else {
                          if (levelUnlocked) _loadLevel(_currentLevel + 1);
                          else _loadLevel(_currentLevel);
                        }
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: result.gradeColor),
                      child: Text(
                        levelUnlocked 
                            ? 'Next Level' 
                            : (isMastered ? 'Play Again' : 'Retry'), 
                        _isHomeworkMode
                            ? 'Practice Again'
                            : (levelUnlocked 
                                ? 'Next Level' 
                                : (isMastered ? 'Play Again' : 'Retry')), 
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _selectedOption;

  @override
  Widget build(BuildContext context) {
    const primaryBlue = Color(0xFF0D47A1);

    if (_showSelectionScreen) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          if (widget.onQuit != null) widget.onQuit!();
        },
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Math Practice Hub', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            backgroundColor: primaryBlue,
            foregroundColor: Colors.white,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: widget.onQuit,
            ),
          ),
          body: _buildSelectionScreen(),
        ),
      );
    }

    if (_isLoadingQuestions) return const Center(child: CircularProgressIndicator());

    final q = _questions[_currentIndex];
    final bool isMcq = q['type'] == 'mcq';
    const primaryBlue = Color(0xFF0D47A1);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      // EXPERT FIX: Prevent overflow when keyboard appears
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Text('Practice Level $_currentLevel'),
        backgroundColor: primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onQuit,
        ),
      ),
      body: Stack(
        children: [
          // EXPERT FIX: Wrap in ScrollView to avoid "Bottom Overflow"
          SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Question ${_currentIndex + 1}/${_questions.length}',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: primaryBlue),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.orange.withOpacity(0.5)),
                      ),
                      child: Text(
                        'Level $_currentLevel',
                        style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (_progressAnim != null)
                  AnimatedBuilder(
                    animation: _progressAnim!,
                    builder: (_, _) => ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: LinearProgressIndicator(
                        value: _progressAnim!.value,
                        backgroundColor: Colors.grey[200],
                        color: Colors.orange,
                        minHeight: 8,
                      ),
                    ),
                  ),
                const SizedBox(height: 25),
                
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 5))],
                  ),
                  child: Column(
                    children: [
                      Align(
                        alignment: Alignment.topRight,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: const BoxDecoration(
                            color: primaryBlue,
                            borderRadius: BorderRadius.only(
                              topRight: Radius.circular(24),
                              bottomLeft: Radius.circular(24),
                            ),
                          ),
                          child: Text(
                            q['topic'] ?? 'Math',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(30, 10, 30, 40),
                        child: Text(
                          q['q'] as String,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, height: 1.4),

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        setState(() => _showSelectionScreen = true);
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F9FA),
        // EXPERT FIX: Prevent overflow when keyboard appears
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          title: Text(_isHomeworkMode ? 'Homework Revision' : 'Practice Level $_currentLevel'),
          backgroundColor: primaryBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => setState(() => _showSelectionScreen = true),
          ),
        ),
        body: Stack(
          children: [
            // EXPERT FIX: Wrap in ScrollView to avoid "Bottom Overflow"
            SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Question ${_currentIndex + 1}/${_questions.length}',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: primaryBlue),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.orange.withOpacity(0.5)),
                        ),
                        child: Text(
                          _isHomeworkMode ? 'Revision' : 'Level $_currentLevel',
                          style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),
                
                if (isMcq)
                  ... (q['options'] as List).map((opt) {
                    bool selected = _selectedOption == opt;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedOption = opt),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 15),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        decoration: BoxDecoration(
                          color: selected ? Colors.orange.withOpacity(0.1) : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: selected ? Colors.orange : Colors.grey.shade200,
                            width: selected ? 2 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              selected ? Icons.radio_button_checked : Icons.radio_button_off,
                              color: selected ? Colors.orange : Colors.grey,
                            ),
                            const SizedBox(width: 15),
                            Text(opt, style: TextStyle(fontSize: 16, fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
                          ],
                        ),
                      ),
                    );
                  })
                else
                  TextField(
                    controller: _answerController,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      labelText: 'Type your answer here',
                      errorText: _errorText,
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: Colors.orange, width: 2),
                      ),
                    ),
                    keyboardType: TextInputType.text,
                  ),
                const SizedBox(height: 40), // Spacing before button
                SizedBox(
                  width: double.infinity,
                  height: 58,
                  child: ElevatedButton(
                    onPressed: _showingFeedback ? null : _checkAnswer,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 4,
                    ),
                    child: const Text('SUBMIT ANSWER', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
          
          if (_showingFeedback)
            Positioned.fill(
              child: Container(
                color: Colors.black26,
                child: Center(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 60),
                    padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
                    decoration: BoxDecoration(
                      color: _lastCorrect ? const Color(0xFF1B5E20) : const Color(0xFFC62828),
                      borderRadius: BorderRadius.circular(25),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 8))
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _lastCorrect ? Icons.check_circle : Icons.cancel,
                          color: Colors.white,
                          size: 55,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _lastCorrect ? "Correct! ✅" : "Incorrect ❌",
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        if (!_lastCorrect) ...[
                          const SizedBox(height: 8),
                          Text(
                            "Answer: ${q['a']}",
                            style: const TextStyle(
                              fontSize: 18,
                  const SizedBox(height: 10),
                  if (_progressAnim != null)
                    AnimatedBuilder(
                      animation: _progressAnim!,
                      builder: (_, __) => ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: LinearProgressIndicator(
                          value: _progressAnim!.value,
                          backgroundColor: Colors.grey[200],
                          color: Colors.orange,
                          minHeight: 8,
                        ),
                      ),
                    ),
                  const SizedBox(height: 25),
                  
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 5))],
                    ),
                    child: Column(
                      children: [
                        Align(
                          alignment: Alignment.topRight,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: const BoxDecoration(
                              color: primaryBlue,
                              borderRadius: BorderRadius.only(
                                topRight: Radius.circular(24),
                                bottomLeft: Radius.circular(24),
                              ),
                            ),
                            child: Text(
                              q['topic'] ?? 'Math',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(30, 10, 30, 40),
                          child: Text(
                            q['q'] as String,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),
                  
                  if (isMcq)
                    ... (q['options'] as List).map((opt) {
                      bool selected = _selectedOption == opt;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedOption = opt),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 15),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                          decoration: BoxDecoration(
                            color: selected ? Colors.orange.withOpacity(0.1) : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: selected ? Colors.orange : Colors.grey.shade200,
                              width: selected ? 2 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                                color: selected ? Colors.orange : Colors.grey,
                              ),
                              const SizedBox(width: 15),
                              Text(opt, style: TextStyle(fontSize: 16, fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
                            ],
                          ),
                        ),
                      );
                    }).toList()
                  else
                    TextField(
                      controller: _answerController,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        labelText: 'Type your answer here',
                        errorText: _errorText,
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(color: Colors.orange, width: 2),
                        ),
                      ),
                      keyboardType: TextInputType.text,
                    ),
                  const SizedBox(height: 40), // Spacing before button
                  SizedBox(
                    width: double.infinity,
                    height: 58,
                    child: ElevatedButton(
                      onPressed: _showingFeedback ? null : _checkAnswer,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 4,
                      ),
                      child: const Text('SUBMIT ANSWER', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
            
            if (_showingFeedback)
              Positioned.fill(
                child: Container(
                  color: Colors.black26,
                  child: Center(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 60),
                      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
                      decoration: BoxDecoration(
                        color: _lastCorrect ? const Color(0xFF1B5E20) : const Color(0xFFC62828),
                        borderRadius: BorderRadius.circular(25),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 8))
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _lastCorrect ? Icons.check_circle : Icons.cancel,
                            color: Colors.white,
                            size: 55,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _lastCorrect ? "Correct! ✅" : "Incorrect ❌",
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ],
                          if (!_lastCorrect) ...[
                            const SizedBox(height: 8),
                            Text(
                              "Answer: ${q['a']}",
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectionScreen() {
    const Color primaryBlue = Color(0xFF0D47A1);
    const Color accentOrange = Color(0xFFE65100);

    return SingleChildScrollView(
      child: Column(
        children: [
          // Header Section
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 30, 20, 40),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [primaryBlue, Color(0xFF1565C0)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(36),
                bottomRight: Radius.circular(36),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.studentLevel,
                  style: const TextStyle(
                    color: Color(0xFFBBDEFB),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  "Choose Practice Mode",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  "Practice posted homework questions to prepare for exams, or challenge yourself through classic levels.",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 30),
          
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                // MODE 1: Homework Revision Practice
                _buildModeCard(
                  title: "Classroom Revision",
                  subtitle: _isLoadingHomework
                      ? "Checking classroom assignments..."
                      : (_homeworkQuestions.isEmpty
                          ? "No homework uploaded yet for your class"
                          : "Practice ${_homeworkQuestions.length} homework questions"),
                  icon: Icons.auto_stories,
                  gradientColors: [const Color(0xFF2E7D32), const Color(0xFF4CAF50)],
                  isEnabled: !_isLoadingHomework && _homeworkQuestions.isNotEmpty,
                  onTap: _startHomeworkRevision,
                  showProgress: _isLoadingHomework,
                ),
                
                const SizedBox(height: 20),
                
                // MODE 2: Challenge Levels
                _buildModeCard(
                  title: "Classic Challenge",
                  subtitle: "Test your speed and mastery from Level 1 to 5",
                  icon: Icons.workspace_premium,
                  gradientColors: [accentOrange, const Color(0xFFFF8F00)],
                  isEnabled: true,
                  onTap: _startChallengeLevels,
                  showProgress: false,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required List<Color> gradientColors,
    required bool isEnabled,
    required VoidCallback onTap,
    required bool showProgress,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: isEnabled ? onTap : null,
          child: Opacity(
            opacity: isEnabled ? 1.0 : 0.6,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: gradientColors,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(icon, color: Colors.white, size: 30),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 6),
                        if (showProgress)
                          const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey),
                          )
                        else
                          Text(
                            subtitle,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                              height: 1.3,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Icon(
                    Icons.arrow_forward_ios,
                    color: isEnabled ? Colors.grey[400] : Colors.grey[300],
                    size: 16,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
