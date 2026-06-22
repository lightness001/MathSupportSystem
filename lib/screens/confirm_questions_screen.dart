import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auto_grading_service.dart' hide debugPrint;
import '../services/web_safe_file.dart';

class ConfirmQuestionsScreen extends StatefulWidget {
  final File file;
  final bool isImage;
  final String fileUrl;
  final String title;
  final String description;
  final String level;
  final DateTime dueDate;

  const ConfirmQuestionsScreen({
    super.key,
    required this.file,
    required this.isImage,
    required this.fileUrl,
    required this.title,
    required this.description,
    required this.level,
    required this.dueDate,
  });

  @override
  State<ConfirmQuestionsScreen> createState() => _ConfirmQuestionsScreenState();
}

class _ConfirmQuestionsScreenState extends State<ConfirmQuestionsScreen> {
  final supabase = Supabase.instance.client;
  bool _isLoading = true;
  bool _isSaving = false;
  String _loadingMessage = "Initializing extraction...";

  // List of question maps: {'text': String, 'correct_answer': String, 'type': 'MCQ'|'text', 'options': List<String>?}
  final List<Map<String, dynamic>> _questionsList = [];

  @override
  void initState() {
    super.initState();
    _extractAndPrepare();
  }

  Future<void> _extractAndPrepare() async {
    try {
      String ocrText = "";
      if (widget.isImage) {
        setState(() => _loadingMessage = "Running local OCR to detect math questions...");
        ocrText = await AutoGradingService.performOcr(widget.file);
        debugPrint("[ConfirmQuestions] OCR Output: $ocrText");
      }

      setState(() => _loadingMessage = "Analyzing and generating suggested answers...");
      Map<int, double?> extractedMath = {};

      // 1. First try parsing OCR text from the image
      if (ocrText.isNotEmpty) {
        extractedMath = AutoGradingService.extractQuestionsFromDescription(ocrText);
      }

      // 2. If OCR is empty or found no math, fall back to parsing description text
      if (extractedMath.isEmpty && widget.description.isNotEmpty) {
        extractedMath = AutoGradingService.extractQuestionsFromDescription(widget.description);
      }

      // Populate our questions list based on extracted questions
      if (extractedMath.isNotEmpty) {
        final sortedKeys = extractedMath.keys.toList()..sort();
        for (final qNum in sortedKeys) {
          final val = extractedMath[qNum];
          final String ansStr = val == null
              ? ''
              : (val % 1 == 0 ? val.toInt().toString() : val.toString());
          // Find the raw text line corresponding to this question if we can
          String qText = "Question $qNum";
          final lines = (ocrText.isNotEmpty ? ocrText : widget.description).split('\n');
          for (var line in lines) {
            if (line.trim().startsWith(RegExp('$qNum[\\.\\)\\-]'))) {
              qText = line.trim();
              break;
            }
          }

          _questionsList.add({
            'text': qText,
            'correct_answer': ansStr,
            'type': 'text',
            'options': null,
          });
        }
      } else {
        // Default with one empty question so it's not completely blank
        _questionsList.add({
          'text': '',
          'correct_answer': '',
          'type': 'text',
          'options': null,
        });
      }
    } catch (e) {
      debugPrint("[ConfirmQuestions] Extraction error: $e");
      // Fallback with one empty question
      if (_questionsList.isEmpty) {
        _questionsList.add({
          'text': '',
          'correct_answer': '',
          'type': 'text',
          'options': null,
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _addQuestion() {
    setState(() {
      _questionsList.add({
        'text': '',
        'correct_answer': '',
        'type': 'text',
        'options': null,
      });
    });
  }

  void _deleteQuestion(int index) {
    setState(() {
      _questionsList.removeAt(index);
    });
  }

  Future<void> _saveAndPost() async {
    // Validation
    for (int i = 0; i < _questionsList.length; i++) {
      final q = _questionsList[i];
      if ((q['text'] as String).trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Question ${i + 1} text cannot be empty."),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }
      if ((q['correct_answer'] as String).trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Please provide a correct answer key for Question ${i + 1}."),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }
    }

    setState(() => _isSaving = true);

    try {
      // Structure the questions array matching standard JSON schema
      final List<Map<String, dynamic>> finalQuestions = _questionsList.map((q) {
        return {
          'text': (q['text'] as String).trim(),
          'type': q['type'],
          'options': q['options'],
          'correct_answer': (q['correct_answer'] as String).trim(),
        };
      }).toList();

      await supabase.from('homework').insert({
        'title': widget.title,
        'description': widget.description,
        'level': widget.level,
        'teacher_id': supabase.auth.currentUser!.id,
        'due_date': widget.dueDate.toIso8601String(),
        'questions': finalQuestions,
        'file_url': widget.fileUrl,
      });

      if (mounted) {
        // Show success animation or dialog
        _showSuccessDialog();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to save homework: $e"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(28.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircleAvatar(
                radius: 36,
                backgroundColor: Color(0xFFE8F5E9),
                child: Icon(Icons.check_circle, color: Color(0xFF2E7D32), size: 48),
              ),
              const SizedBox(height: 20),
              const Text(
                "Homework Posted!",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                "Questions and Answer Key confirmed successfully. Students will now take this homework step-by-step and be marked automatically with 100% accuracy.",
                style: TextStyle(color: Colors.grey, height: 1.4),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0D47A1),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx); // pop dialog
                    Navigator.pop(context, true); // pop ConfirmQuestionsScreen and return success
                  },
                  child: const Text("Done", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const Color primaryBlue = Color(0xFF0D47A1);

    if (_isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8F9FA),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: primaryBlue),
              const SizedBox(height: 24),
              Text(
                _loadingMessage,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: primaryBlue),
              ),
              const SizedBox(height: 8),
              const Text(
                "This runs entirely locally on your device...",
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        title: const Text("Confirm Answer Key"),
        backgroundColor: primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isSaving
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: primaryBlue),
                  SizedBox(height: 16),
                  Text("Posting homework to class...", style: TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            )
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  color: Colors.orange.shade50,
                  child: Row(
                    children: [
                      Icon(Icons.lightbulb_outline, color: Colors.orange.shade800),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          "Verify the questions and suggested answers extracted from your document. You can edit, delete, or add questions to create a perfect answer key.",
                          style: TextStyle(fontSize: 13, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(20),
                    itemCount: _questionsList.length,
                    itemBuilder: (ctx, index) {
                      final q = _questionsList[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 16),
                        elevation: 1,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(color: Colors.grey.shade200),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    "Question ${index + 1}",
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: primaryBlue),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                    onPressed: () => _deleteQuestion(index),
                                  )
                                ],
                              ),
                              const SizedBox(height: 8),
                              TextFormField(
                                initialValue: q['text'],
                                decoration: const InputDecoration(
                                  labelText: "Question (e.g. 456 × 23)",
                                  hintText: "Enter the question text",
                                  border: OutlineInputBorder(),
                                  filled: true,
                                  fillColor: Color(0xFFFAFAFA),
                                ),
                                onChanged: (val) => q['text'] = val,
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                initialValue: q['correct_answer'],
                                decoration: const InputDecoration(
                                  labelText: "Suggested/Correct Answer",
                                  hintText: "Enter the correct mathematical answer",
                                  border: OutlineInputBorder(),
                                  filled: true,
                                  fillColor: Color(0xFFFAFAFA),
                                  prefixIcon: Icon(Icons.vpn_key_outlined, color: Colors.green),
                                ),
                                onChanged: (val) => q['correct_answer'] = val,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, -4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _addQuestion,
                          icon: const Icon(Icons.add, color: primaryBlue),
                          label: const Text("Add Question", style: TextStyle(color: primaryBlue, fontWeight: FontWeight.bold)),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            side: const BorderSide(color: primaryBlue),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _saveAndPost,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.shade700,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text("Confirm & Post", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
