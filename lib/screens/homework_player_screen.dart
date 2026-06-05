import 'dart:convert';
import 'dart:io' as io;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../services/web_safe_file.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/homework_model.dart';
import '../services/assessment_engine.dart';
import '../services/auto_grading_service.dart';

class HomeworkPlayerScreen extends StatefulWidget {
  final Homework homework;
  const HomeworkPlayerScreen({super.key, required this.homework});

  @override
  State<HomeworkPlayerScreen> createState() => _HomeworkPlayerScreenState();
}

class _HomeworkPlayerScreenState extends State<HomeworkPlayerScreen>
    with SingleTickerProviderStateMixin {
  late final supabase = Supabase.instance.client;

  int currentIndex = 0;
  int correctCount = 0;
  final List<bool> _answerResults = []; // true = correct, false = wrong
  final List<int> _wrongIndexes = [];

  final TextEditingController _textController = TextEditingController();
  String? selectedOption;
  String? _errorText;
  bool _isSubmitting = false;

  // Double-submission prevention states
  bool _checkingStatus = true;
  bool _alreadySubmitted = false;

  // State for document homework
  File? _submissionFile;
  final TextEditingController _submissionTextController = TextEditingController();
  bool _isSubmittingDoc = false;
  String _docSubmittingStatus = "Submitting your homework...";

  // Per-question feedback overlay
  bool _showingFeedback = false;
  bool _lastAnswerCorrect = false;

  // Animated progress
  late AnimationController _progressController;
  late Animation<double> _progressAnim;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _progressAnim = Tween<double>(begin: 0, end: 0).animate(_progressController);
    _updateProgressBar();
    _checkSubmissionStatus();
  }

  void _checkSubmissionStatus() async {
    try {
      // Safely handle uninitialized Supabase client in widget test contexts
      try {
        Supabase.instance.client;
      } catch (_) {
        setState(() {
          _checkingStatus = false;
        });
        return;
      }

      final user = supabase.auth.currentUser;
      if (user == null) {
        setState(() {
          _checkingStatus = false;
        });
        return;
      }
      final response = await supabase
          .from('submissions')
          .select('id')
          .eq('homework_id', widget.homework.id)
          .eq('student_id', user.id)
          .maybeSingle();

      if (response != null) {
        setState(() {
          _alreadySubmitted = true;
          _checkingStatus = false;
        });
      } else {
        setState(() {
          _checkingStatus = false;
        });
      }
    } catch (e) {
      debugPrint("Error checking submission status: $e");
      setState(() {
        _checkingStatus = false;
      });
    }
  }

  @override
  void dispose() {
    _progressController.dispose();
    _textController.dispose();
    _submissionTextController.dispose();
    super.dispose();
  }

  void _updateProgressBar() {
    if (widget.homework.questions.isEmpty) return;
    final double target =
        (currentIndex + 1) / widget.homework.questions.length;
    _progressAnim = Tween<double>(
            begin: _progressAnim.value, end: target)
        .animate(CurvedAnimation(
            parent: _progressController, curve: Curves.easeInOut));
    _progressController
      ..reset()
      ..forward();
  }

  Widget _buildDocumentHomeworkLayout() {
    const Color primaryBlue = Color(0xFF0D47A1);
    
    if (_isSubmittingDoc) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 20),
              Text(
                _docSubmittingStatus,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: primaryBlue),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                "This will only take a moment...",
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    final hasFile = widget.homework.fileUrl != null && widget.homework.fileUrl!.isNotEmpty;
    final fileName = _submissionFile != null ? _submissionFile!.path.split(RegExp(r"[/\\]")).last : null;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FA),
      appBar: AppBar(
        title: Text(widget.homework.title),
        backgroundColor: primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Assignment Detail Card
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: Colors.orange.shade50,
                          radius: 24,
                          child: Icon(Icons.assignment, color: Colors.orange.shade800, size: 28),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.homework.title,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "Due Date: ${widget.homework.dueDate}",
                                style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.w600, fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 30),
                    const Text(
                      "Description:",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.homework.description != null && widget.homework.description!.trim().isNotEmpty
                          ? widget.homework.description!
                          : "No additional instructions provided by the teacher.",
                      style: const TextStyle(fontSize: 15, color: Colors.black54, height: 1.4),
                    ),
                    if (hasFile) ...[
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            final url = widget.homework.fileUrl!;
                            try {
                              final uri = Uri.parse(url.trim());
                              await launchUrl(uri, mode: LaunchMode.externalApplication);
                            } catch (e) {
                              // If external launch fails, try basic launch without mode or fallback to copy url
                              try {
                                final uri = Uri.parse(url.trim());
                                await launchUrl(uri);
                              } catch (e2) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text("Could not open document link: $e2")),
                                  );
                                }
                              }
                            }
                          },
                          icon: const Icon(Icons.download, color: Colors.white),
                          label: const Text("VIEW / DOWNLOAD DOCUMENT", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2E7D32),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            
            // Submission Form Section
            const Text(
              "Your Submission",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: primaryBlue),
            ),
            const SizedBox(height: 12),
            
            // Text answers/comments
            TextField(
              controller: _submissionTextController,
              maxLines: 6,
              decoration: InputDecoration(
                hintText: "Type your answers, comments, or notes here...",
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            // File Attachment Picker
            InkWell(
              onTap: () async {
                try {
                  FilePickerResult? result = await FilePicker.pickFiles(
                    type: FileType.custom,
                    allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg', 'doc', 'docx'],
                  );
                  if (result != null && result.files.single.path != null) {
                    setState(() {
                      _submissionFile = File(result.files.single.path!);
                    });
                  }
                } catch (e) {
                  debugPrint("File picker error: $e");
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _submissionFile != null ? Colors.green.shade300 : Colors.grey.shade300),
                ),
                child: Row(
                  children: [
                    Icon(
                      _submissionFile != null ? Icons.check_circle : Icons.cloud_upload_outlined,
                      color: _submissionFile != null ? Colors.green.shade700 : primaryBlue,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        fileName ?? "Upload handwritten answers / photos / document (Optional)",
                        style: TextStyle(
                          fontSize: 14,
                          color: fileName != null ? Colors.black87 : Colors.black54,
                          fontWeight: fileName != null ? FontWeight.bold : FontWeight.normal,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_submissionFile != null)
                      IconButton(
                        icon: const Icon(Icons.cancel, color: Colors.grey),
                        onPressed: () => setState(() => _submissionFile = null),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),
            
            // Submit Button
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: () async {
                  if (_submissionTextController.text.trim().isEmpty && _submissionFile == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Please write text answers or upload a file before submitting.")),
                    );
                    return;
                  }

                  setState(() {
                    _isSubmittingDoc = true;
                    _docSubmittingStatus = "Uploading your submission...";
                  });

                  try {
                    String finalContent = _submissionTextController.text.trim();
                    
                    // Upload file if selected
                    if (_submissionFile != null) {
                      final rawName = _submissionFile!.path.split(RegExp(r"[/\\]")).last;
                      final workingPath = 'submissions/${supabase.auth.currentUser!.id}/${DateTime.now().millisecondsSinceEpoch}_$rawName';
                      
                      if (kIsWeb) {
                        final bytes = await _submissionFile!.readAsBytes();
                        await supabase.storage.from('homework_files').uploadBinary(
                              workingPath,
                              bytes,
                              fileOptions: const FileOptions(upsert: false),
                            );
                      } else {
                        await supabase.storage.from('homework_files').upload(
                              workingPath,
                              io.File(_submissionFile!.path),
                              fileOptions: const FileOptions(upsert: false),
                            );
                      }
                      
                      final fileUrl = supabase.storage.from('homework_files').getPublicUrl(workingPath);
                      if (finalContent.isEmpty) {
                        finalContent = "Attached File: $fileUrl";
                      } else {
                        finalContent = "$finalContent\n\nAttachment URL: $fileUrl";
                      }
                    }

                    // Upsert the student submission to cleanly handle re-submissions without conflicts
                    final submissionData = await supabase.from('submissions').upsert({
                      'homework_id': widget.homework.id,
                      'student_id': supabase.auth.currentUser!.id,
                      'content': finalContent,
                    }, onConflict: 'homework_id,student_id').select().single();

                    // Update loading status for auto-grading
                    setState(() {
                      _docSubmittingStatus = "Analyzing and grading...";
                    });

                    // Call the AI Auto-Marking Engine
                    final gradingResult = await AutoGradingService.gradeSubmission(
                      homeworkTitle: widget.homework.title,
                      homeworkDescription: widget.homework.description ?? '',
                      studentTextAnswer: _submissionTextController.text.trim(),
                      localFile: _submissionFile,
                      teacherFileUrl: widget.homework.fileUrl,
                      templateQuestions: widget.homework.questions,
                    );

                    // Upsert the result into the Supabase results table to overwrite old scores cleanly
                    await supabase.from('results').upsert({
                      'submission_id': submissionData['id'].toString(),
                      'score': gradingResult.score,
                      'feedback': gradingResult.feedback,
                    }, onConflict: 'submission_id');

                    // Evaluate matching assessment details (Grade letter, colors)
                    final int calcCorrect = gradingResult.correctCount ?? gradingResult.score.toInt();
                    final int calcTotal = gradingResult.totalQuestions ?? 100;
                    
                    final evaluated = AssessmentEngine.evaluate(
                      correctCount: calcCorrect,
                      totalQuestions: calcTotal,
                      topic: widget.homework.title,
                      wrongIndexes: [],
                    );

                    final parsed = AutoGradingService.parseFeedback(gradingResult.feedback);

                    final result = AssessmentResult(
                      percent: gradingResult.score,
                      grade: evaluated.grade,
                      label: evaluated.label,
                      feedback: parsed.feedback,
                      recommendation: parsed.recommendation.isNotEmpty 
                          ? parsed.recommendation 
                          : evaluated.recommendation,
                      gradeColor: evaluated.gradeColor,
                      wrongQuestionIndexes: [],
                      correctCount: gradingResult.correctCount,
                      totalQuestions: gradingResult.totalQuestions,
                      revisionQuestions: parsed.revisionQuestions,
                    );

                    if (mounted) {
                      setState(() {
                        _isSubmittingDoc = false;
                        _alreadySubmitted = true;
                      });
                      _showResultDialog(result);
                    }
                  } catch (e) {
                    debugPrint("Doc Submission & Grading Error: $e");
                    if (mounted) {
                      setState(() => _isSubmittingDoc = false);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text("Error submitting or grading assignment: $e"), backgroundColor: Colors.red),
                      );
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryBlue,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text(
                  "SUBMIT ASSIGNMENT",
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Answer submission ───────────────────────────────────────────────

  void _submitAnswer(String studentAnswer) {
    final String correct =
        widget.homework.questions[currentIndex].correctAnswer;
    final bool isCorrect =
        studentAnswer.trim().toLowerCase() == correct.trim().toLowerCase();

    _answerResults.add(isCorrect);
    if (isCorrect) {
      correctCount++;
    } else {
      _wrongIndexes.add(currentIndex);
    }

    // Show per-question feedback overlay for 1.2 s then advance
    setState(() {
      _showingFeedback = true;
      _lastAnswerCorrect = isCorrect;
    });

    Future.delayed(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      setState(() => _showingFeedback = false);

      if (currentIndex < widget.homework.questions.length - 1) {
        setState(() {
          currentIndex++;
          selectedOption = null;
          _textController.clear();
          _errorText = null;
        });
        _updateProgressBar();
      } else {
        _finishHomework();
      }
    });
  }

  // ── Finish & save ───────────────────────────────────────────────────

  Future<void> _finishHomework() async {
    setState(() => _isSubmitting = true);

    final int total = widget.homework.questions.length;
    final String topic = widget.homework.title;
    final String userId = supabase.auth.currentUser!.id;

    // 1. Run the assessment engine
    final AssessmentResult result = AssessmentEngine.evaluate(
      correctCount: correctCount,
      totalQuestions: total,
      topic: topic,
      wrongIndexes: _wrongIndexes,
    );

    try {
      // 2. Save submission to Supabase using upsert
      final submission = await supabase
          .from('submissions')
          .upsert({
            'homework_id': widget.homework.id,
            'student_id': userId,
            'content': 'Auto-graded by System',
          }, onConflict: 'homework_id,student_id')
          .select()
          .single();

      // 3. Save result to Supabase using upsert
      await supabase.from('results').upsert({
        'submission_id': submission['id'].toString(),
        'score': result.percent,
        'feedback': result.feedback,
      }, onConflict: 'submission_id');

      if (mounted) _showResultDialog(result);
    } catch (e) {
      debugPrint('Sync Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving results: $e'),
            backgroundColor: Colors.red,
          ),
        );
        _showResultDialog(result); // still show result even if sync failed
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _alreadySubmitted = true;
        });
      }
    }
  }

  // ── Result dialog ───────────────────────────────────────────────────

  void _showResultDialog(AssessmentResult result) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Grade badge
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: result.gradeColor,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  result.grade,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                result.label,
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: result.gradeColor),
              ),
              const SizedBox(height: 4),
              Text(
                widget.homework.questions.isNotEmpty
                    ? 'Graded Score: $correctCount / ${widget.homework.questions.length} (${AssessmentEngine.formatPercent(result.percent)})'
                    : (result.correctCount != null && result.totalQuestions != null
                        ? 'Graded Score: ${result.correctCount}/${result.totalQuestions} (${AssessmentEngine.formatPercent(result.percent)})'
                        : 'Graded Score: ${AssessmentEngine.formatPercent(result.percent)}'),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black54),
              ),
              const Divider(height: 28),
              // Feedback
              Text(
                result.feedback,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              // Recommendation box
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: result.gradeColor.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: result.gradeColor.withOpacity(0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lightbulb_outline,
                        color: result.gradeColor, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        result.recommendation,
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey[800], height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              if (result.revisionQuestions != null && result.revisionQuestions!.isNotEmpty) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8EAF6),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFC5CAE9)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.auto_stories, color: Color(0xFF3F51B5), size: 18),
                          SizedBox(width: 8),
                          Text(
                            "AI Practice Exercises",
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF3F51B5),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ...result.revisionQuestions!.map((q) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("📝 ", style: TextStyle(fontSize: 12)),
                            Expanded(
                              child: Text(
                                q,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Colors.black87,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )).toList(),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: result.gradeColor,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text(
                    'Back to Dashboard',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Build ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_checkingStatus) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_alreadySubmitted) {
      const Color primaryBlue = Color(0xFF0D47A1);
      return Scaffold(
        backgroundColor: const Color(0xFFF4F7FA),
        appBar: AppBar(
          title: Text(widget.homework.title),
          backgroundColor: primaryBlue,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: Center(
          child: Container(
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
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
                  "Assignment Completed",
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                const Text(
                  "You have already submitted and completed this homework. Re-submissions or modifications are not allowed.",
                  style: TextStyle(fontSize: 15, color: Colors.black54, height: 1.4),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryBlue,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text(
                      "Back to Dashboard",
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (widget.homework.questions.isEmpty) {
      return _buildDocumentHomeworkLayout();
    }
    if (_isSubmitting) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Saving your results…'),
            ],
          ),
        ),
      );
    }

    final question = widget.homework.questions[currentIndex];

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FA),
      appBar: AppBar(
        title: Text(widget.homework.title),
        backgroundColor: const Color(0xFF0D47A1),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                // Animated progress bar
                AnimatedBuilder(
                  animation: _progressAnim,
                  builder: (_, __) => ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: _progressAnim.value,
                      backgroundColor: Colors.grey[200],
                      color: const Color(0xFF0D47A1),
                      minHeight: 8,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Question ${currentIndex + 1} of '
                      '${widget.homework.questions.length}',
                      style: const TextStyle(
                          color: Colors.grey, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '✅ $correctCount correct',
                      style: const TextStyle(
                          color: Color(0xFF2E7D32),
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Question card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Text(
                    question.questionText,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold, height: 1.4),
                  ),
                ),
                const SizedBox(height: 20),

                // Answer area
                if (question.type == 'MCQ')
                  Expanded(
                    child: ListView(
                      children: question.options!.map((opt) {
                        final bool selected = selectedOption == opt;
                        return GestureDetector(
                          onTap: () => setState(() => selectedOption = opt),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 18, vertical: 14),
                            decoration: BoxDecoration(
                              color: selected
                                  ? const Color(0xFF0D47A1)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: selected
                                    ? const Color(0xFF0D47A1)
                                    : Colors.grey.shade300,
                                width: selected ? 2 : 1,
                              ),
                              boxShadow: selected
                                  ? [
                                      BoxShadow(
                                        color: const Color(0xFF0D47A1)
                                            .withOpacity(0.2),
                                        blurRadius: 8,
                                        offset: const Offset(0, 4),
                                      )
                                    ]
                                  : [],
                            ),
                            child: Text(
                              opt,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: selected ? Colors.white : Colors.black87,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  )
                else ...[
                  TextField(
                    controller: _textController,
                    onChanged: (_) {
                      if (_errorText != null)
                        setState(() => _errorText = null);
                    },
                    decoration: InputDecoration(
                      labelText: 'Type your answer here',
                      errorText: _errorText,
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                  const Spacer(),
                ],

                const SizedBox(height: 16),

                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _showingFeedback
                        ? null
                        : () {
                            final ans = question.type == 'MCQ'
                                ? (selectedOption ?? '')
                                : _textController.text;
                            if (ans.isEmpty) {
                              setState(() => _errorText =
                                  question.type == 'MCQ'
                                      ? null
                                      : 'Please fill in your answer!');
                              if (question.type == 'MCQ') {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content:
                                          Text('Please select an option!')),
                                );
                              }
                              return;
                            }
                            _submitAnswer(ans);
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0D47A1),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text(
                      'SUBMIT ANSWER',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),

          // ── Per-question feedback overlay ──────────────────────────
          if (_showingFeedback)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _showingFeedback ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    color: (_lastAnswerCorrect
                            ? Colors.green
                            : Colors.red)
                        .withOpacity(0.15),
                    alignment: Alignment.center,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 32, vertical: 20),
                      decoration: BoxDecoration(
                        color: _lastAnswerCorrect
                            ? const Color(0xFF1B5E20)
                            : const Color(0xFFC62828),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _lastAnswerCorrect
                                ? Icons.check_circle
                                : Icons.cancel,
                            color: Colors.white,
                            size: 52,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _lastAnswerCorrect ? 'Correct! ✅' : 'Incorrect ❌',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.bold),
                          ),
                          if (!_lastAnswerCorrect) ...[
                            const SizedBox(height: 6),
                            Text(
                              'Correct answer: '
                              '${widget.homework.questions[currentIndex].correctAnswer}',
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 14),
                              textAlign: TextAlign.center,
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
    );
  }
}
