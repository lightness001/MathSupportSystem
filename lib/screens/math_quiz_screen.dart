import 'package:flutter/material.dart';
import '../services/db_helper.dart';
import '../services/assessment_engine.dart';

class MathQuizScreen extends StatefulWidget {
  final VoidCallback? onQuit;
  const MathQuizScreen({super.key, this.onQuit});

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
      wrongIndexes: _wrongIndexes,
    );

    bool isMastered = result.grade == 'A' || result.grade == 'B';
    // Max level is now 5
    bool levelUnlocked = isMastered && _currentLevel < 5;

    await DBHelper().savePerformance({
      'topic': 'Quiz Level $_currentLevel',
      'score': _correctCount.toDouble(),
      'total_questions': _questions.length,
      'date_taken': DateTime.now().toString(),
      'grade': result.grade,
      'recommendation': levelUnlocked ? 'Congrats! Level ${_currentLevel + 1} Unlocked.' : result.recommendation,
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
                        if (levelUnlocked) _loadLevel(_currentLevel + 1);
                        else _loadLevel(_currentLevel);
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: result.gradeColor),
                      child: Text(
                        levelUnlocked 
                            ? 'Next Level' 
                            : (isMastered ? 'Play Again' : 'Retry'), 
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
        ],
      ),
    );
  }
}
