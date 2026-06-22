import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/assessment_engine.dart';
import '../services/auto_grading_service.dart';

/// Shows a student's full result for a single assignment:
/// - Grade badge + percentage
/// - Teacher / engine feedback and recommendation
/// - List of wrong questions with correct answers revealed
/// - "Retry" button (pops back so student can re-attempt)
class StudentFeedbackScreen extends StatelessWidget {
  final Map<String, dynamic> result; // row from Supabase `results` join

  const StudentFeedbackScreen({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final double score = (result['score'] as num?)?.toDouble() ?? 0;
    
    // SAFE FALLBACK: dynamically derive grade if empty/null
    final String grade = result['grade'] != null && result['grade'].toString().trim().isNotEmpty && result['grade'] != '?'
        ? result['grade'] as String
        : AssessmentEngine.evaluate(
            correctCount: score.toInt(),
            totalQuestions: 100,
            topic: '',
            wrongIndexes: [],
          ).grade;

    final String rawFeedback = result['feedback'] as String? ?? 'No feedback yet.';
    final parsedFeedback = AutoGradingService.parseFeedback(rawFeedback);
    final String feedback = parsedFeedback.feedback;

    String homeworkTitle = '';
    if (result['submissions']?['homework'] != null) {
      homeworkTitle = result['submissions']?['homework']?['title']?.toString() ?? '';
    } else if (result['homework_title'] != null) {
      homeworkTitle = result['homework_title']?.toString() ?? '';
    }

    // SAFE FALLBACK: dynamically derive recommendation if empty/null
    String recommendation = parsedFeedback.recommendation;
    if (recommendation.isEmpty) {
      recommendation = result['recommendation'] != null && result['recommendation'].toString().trim().isNotEmpty
          ? result['recommendation'] as String
          : AssessmentEngine.evaluate(
              correctCount: score.toInt(),
              totalQuestions: 100,
              topic: homeworkTitle,
              wrongIndexes: [],
            ).recommendation;
    }

    final Color gradeColor = AssessmentEngine.colorForPercent(score);

    // Decode wrong question indexes (stored as JSON array e.g. [0, 2])
    List<int> wrongIndexes = [];
    final rawWrong = result['wrong_questions'];
    if (rawWrong != null) {
      try {
        wrongIndexes =
            List<int>.from(jsonDecode(rawWrong.toString()));
      } catch (_) {}
    }

    // Homework questions list (may be attached if called with data)
    final List<dynamic> questions =
        result['homework_questions'] as List<dynamic>? ?? [];

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FA),
      appBar: AppBar(
        title: const Text(
          'My Result',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF0D47A1),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Grade hero card ──────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    gradeColor,
                    gradeColor.withOpacity(0.7),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                      color: gradeColor.withOpacity(0.3),
                      blurRadius: 16,
                      offset: const Offset(0, 8)),
                ],
              ),
              child: Row(
                children: [
                  // Big grade circle
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.25),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: Colors.white.withOpacity(0.6), width: 2),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      grade,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 40,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AssessmentEngine.evaluate(
                            correctCount: score.toInt(),
                            totalQuestions: 100,
                            topic: '',
                            wrongIndexes: [],
                          ).label,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          AssessmentEngine.formatPercent(score),
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.85),
                              fontSize: 28,
                              fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Feedback card ────────────────────────────────────────
            _sectionCard(
              icon: Icons.chat_bubble_outline,
              iconColor: const Color(0xFF0D47A1),
              title: 'Feedback',
              child: Text(
                feedback,
                style:
                    TextStyle(fontSize: 15, color: Colors.grey[800], height: 1.5),
              ),
            ),
            const SizedBox(height: 16),

            // ── Recommendation card ──────────────────────────────────
            if (recommendation.isNotEmpty)
              _sectionCard(
                icon: Icons.lightbulb_outline,
                iconColor: Colors.amber[700]!,
                title: 'What To Do Next',
                child: Text(
                  recommendation,
                  style: TextStyle(
                      fontSize: 15, color: Colors.grey[800], height: 1.5),
                ),
              ),
            // ── AI Revision Exercises card ───────────────────────────
            if (parsedFeedback.revisionQuestions.isNotEmpty) ...[
              _sectionCard(
                icon: Icons.auto_stories,
                iconColor: const Color(0xFF3F51B5),
                title: 'AI Practice Exercises',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: parsedFeedback.revisionQuestions.map((q) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          margin: const EdgeInsets.only(top: 2),
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Color(0xFFE8EAF6),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.arrow_forward,
                            size: 10,
                            color: Color(0xFF3F51B5),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            q,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[800],
                              height: 1.4,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )).toList(),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // ── Wrong questions card ─────────────────────────────────
            if (wrongIndexes.isNotEmpty && questions.isNotEmpty) ...[
              _sectionCard(
                icon: Icons.close_rounded,
                iconColor: Colors.red,
                title:
                    'Questions You Missed (${wrongIndexes.length})',
                child: Column(
                  children: wrongIndexes.map((idx) {
                    if (idx >= questions.length) return const SizedBox();
                    final q = questions[idx] as Map<String, dynamic>;
                    return Container(
                      margin: const EdgeInsets.only(top: 12),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red.shade100),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Q${idx + 1}: ${q['text'] ?? q['questionText'] ?? ''}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.check_circle,
                                  color: Colors.green, size: 16),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Correct answer: '
                                  '${q['correct_answer'] ?? q['correctAnswer'] ?? ''}',
                                  style: const TextStyle(
                                      color: Color(0xFF1B5E20),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // ── Retry button ─────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.replay, color: Colors.white),
                label: const Text(
                  'Go Back & Retry',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0D47A1),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  // ── Helper: section card ───────────────────────────────────────────

  Widget _sectionCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

// ── Convenience: fetch & open from results list ────────────────────────

class StudentFeedbackLoader extends StatelessWidget {
  final String submissionId;

  const StudentFeedbackLoader({super.key, required this.submissionId});

  @override
  Widget build(BuildContext context) {
    final supabase = Supabase.instance.client;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Result Detail',
            style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF0D47A1),
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<Map<String, dynamic>>(
      body: FutureBuilder<Map<String, dynamic>?>(
        future: supabase
            .from('results')
            .select('''
              id, score, feedback, created_at,
              submissions!inner(
                homework!inner(title, questions)
              )
            ''')
            .eq('submission_id', submissionId)
            .single(),
            .maybeSingle(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError || !snap.hasData) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          final data = snap.data!;
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          final data = snap.data;
          if (data == null) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.hourglass_empty_rounded, size: 80, color: Colors.orange),
                    SizedBox(height: 16),
                    Text(
                      "Awaiting Teacher Mark",
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    Text(
                      "Your submission has been received. Your teacher will review and grade your mathematics work shortly.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            );
          }
          final hwQuestions = data['submissions']?['homework']
              ?['questions'] as List<dynamic>? ??
              [];
          return StudentFeedbackScreen(
            result: {...data, 'homework_questions': hwQuestions},
          );
        },
      ),
    );
  }
}
