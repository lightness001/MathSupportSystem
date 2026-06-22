// ============================================================
// assessment_engine.dart  –  Rule-Based Auto-Marking Engine
// Grades every submission A-E and generates personalised
// recommendations based on score band, topic, and attempt count.
// ============================================================

import 'package:flutter/material.dart';

class AssessmentResult {
  final double percent;
  final String grade; // A / B / C / D / E
  final String label; // e.g. "Excellent"
  final String feedback; // short motivational sentence
  final String recommendation; // what the student should do next
  final Color gradeColor; // colour to render the badge
  final List<int> wrongQuestionIndexes; // 0-based indexes of missed Qs
  final int? correctCount;
  final int? totalQuestions;
  final List<String>? revisionQuestions;

  const AssessmentResult({
    required this.percent,
    required this.grade,
    required this.label,
    required this.feedback,
    required this.recommendation,
    required this.gradeColor,
    required this.wrongQuestionIndexes,
    this.correctCount,
    this.totalQuestions,
    this.revisionQuestions,
  });
}

class AssessmentEngine {
  // -----------------------------------------------------------
  // PRIMARY ENTRY POINT
  // -----------------------------------------------------------
  /// Evaluates a student attempt and returns a rich [AssessmentResult].
  ///
  /// [correctCount]   – number of questions answered correctly
  /// [totalQuestions] – total number of questions in the assignment
  /// [topic]          – homework topic/title (used for specific advice)
  /// [wrongIndexes]   – 0-based list of question indexes the student got wrong
  /// [attemptNumber]  – how many times the student has attempted this topic
  static AssessmentResult evaluate({
    required int correctCount,
    required int totalQuestions,
    required String topic,
    required List<int> wrongIndexes,
    List<dynamic>? questions,
    int attemptNumber = 1,
  }) {
    if (totalQuestions == 0) {
      return const AssessmentResult(
        percent: 0,
        grade: 'N/A',
        label: 'No Questions',
        feedback: 'This assignment had no questions.',
        recommendation: 'Ask your teacher to add questions.',
        gradeColor: Colors.grey,
        wrongQuestionIndexes: [],
      );
    }

    final double percent = (correctCount / totalQuestions) * 100;
    return _applyRules(percent, topic, wrongIndexes, attemptNumber);
    return _applyRules(percent, topic, wrongIndexes, questions, attemptNumber);
  }

  // -----------------------------------------------------------
  // RULE TABLE
  // -----------------------------------------------------------
  static AssessmentResult _applyRules(
    double percent,
    String topic,
    List<int> wrongIndexes,
    List<dynamic>? questions,
    int attempt,
  ) {
    final String topicAdvice = _topicAdvice(topic);
    final String repeatNote =
        attempt > 1 ? ' This is attempt #$attempt – you are improving!' : '';

    String? getCorrectAnswer(dynamic q) {
      if (q == null) return null;
      if (q is Map) {
        return q['correct_answer']?.toString();
      }
      try {
        return q.correctAnswer;
      } catch (_) {
        return null;
      }
    }

    String missedFeedback = "";
    if (questions != null && wrongIndexes.isNotEmpty) {
      final List<String> missedDetails = [];
      for (var idx in wrongIndexes) {
        if (idx >= 0 && idx < questions.length) {
          final q = questions[idx];
          final String? ans = getCorrectAnswer(q);
          if (ans != null) {
            missedDetails.add("qn${idx + 1} = $ans");
          }
        }
      }
      if (missedDetails.isNotEmpty) {
        missedFeedback = " Review answers for missed question(s): ${missedDetails.join(', ')}.";
      }
    }

    if (percent >= 90) {
      return AssessmentResult(
        percent: percent,
        grade: 'A',
        label: 'Distinction',
        feedback: 'Outstanding work! 🌟$repeatNote',
        feedback: 'Outstanding work! 🌟$repeatNote$missedFeedback',
        recommendation:
            'Excellent performance on $topic. Challenge yourself with '
            'the advanced homework set or help a classmate.',
        gradeColor: const Color(0xFF1B5E20),
        wrongQuestionIndexes: wrongIndexes,
      );
    } else if (percent >= 75) {
      return AssessmentResult(
        percent: percent,
        grade: 'B',
        label: 'Merit',
        feedback: 'Great job! Almost there.$repeatNote',
        feedback: 'Great job! Almost there.$repeatNote$missedFeedback',
        recommendation:
            'Good work on $topic. Review the ${wrongIndexes.length} '
            'question(s) you missed and you will be ready for an A.',
        gradeColor: const Color(0xFF2E7D32),
        wrongQuestionIndexes: wrongIndexes,
      );
    } else if (percent >= 50) {
      return AssessmentResult(
        percent: percent,
        grade: 'C',
        label: 'Pass',
        feedback: 'You passed! Keep building on this.$repeatNote',
        feedback: 'You passed! Keep building on this.$repeatNote$missedFeedback',
        recommendation:
            'You passed $topic. Redo the missed questions once more '
            'and review: $topicAdvice',
        gradeColor: const Color(0xFFF57F17),
        wrongQuestionIndexes: wrongIndexes,
      );
    } else if (percent >= 30) {
      return AssessmentResult(
        percent: percent,
        grade: 'D',
        label: 'Needs Improvement',
        feedback: 'Keep trying! You can do better.$repeatNote',
        feedback: 'Keep trying! You can do better.$repeatNote$missedFeedback',
        recommendation:
            'Focus on $topic before retrying. Specifically: $topicAdvice. '
            'Ask your teacher for the revision notes.',
        gradeColor: const Color(0xFFE65100),
        wrongQuestionIndexes: wrongIndexes,
      );
    } else {
      return AssessmentResult(
        percent: percent,
        grade: 'E',
        label: 'Unsatisfactory',
        feedback: "Don't give up! Let's start from the basics.$repeatNote",
        feedback: "Don't give up! Let's start from the basics.$repeatNote$missedFeedback",
        recommendation:
            'Please see your teacher about $topic. '
            'Begin with: $topicAdvice before attempting again.',
        gradeColor: const Color(0xFFC62828),
        wrongQuestionIndexes: wrongIndexes,
      );
    }
  }

  // -----------------------------------------------------------
  // TOPIC-SPECIFIC ADVICE LOOKUP
  // -----------------------------------------------------------
  static String _topicAdvice(String topic) {
    final String lower = topic.toLowerCase();

    if (lower.contains('algebra')) {
      return 'practice forming equations, solving for x, and simplifying '
          'expressions step-by-step';
    } else if (lower.contains('geometry') || lower.contains('shape')) {
      return 'revise area and perimeter formulas, angles in triangles, '
          'and properties of quadrilaterals';
    } else if (lower.contains('fraction')) {
      return 'practise finding common denominators, simplifying fractions, '
          'and converting between fractions and decimals';
    } else if (lower.contains('percentag')) {
      return 'revise how to convert fractions to percentages and how to '
          'calculate percentage of a quantity';
    } else if (lower.contains('multipli') || lower.contains('times table')) {
      return 'drill your times tables (especially 6–12) using flashcards '
          'or a times-table chart';
    } else if (lower.contains('division') || lower.contains('divide')) {
      return 'practise long division with remainders and check answers by '
          'multiplying back';
    } else if (lower.contains('addition') || lower.contains('jumla')) {
      return 'practise column addition with carrying, especially for 3-digit '
          'numbers';
    } else if (lower.contains('subtraction') || lower.contains('utoaji')) {
      return 'revise borrowing/regrouping in column subtraction';
    } else if (lower.contains('arithmetic')) {
      return 'review order of operations (BODMAS/PEMDAS) and mixed number '
          'calculations';
    } else if (lower.contains('word problem')) {
      return 'read each word problem twice, underline key numbers, '
          'and write the equation before solving';
    } else {
      return 'review your class notes and textbook for this topic, then '
          'attempt practice exercises';
    }
  }

  // -----------------------------------------------------------
  // HELPERS
  // -----------------------------------------------------------

  /// Returns a human-readable percentage string e.g. "72.5%"
  static String formatPercent(double percent) =>
      '${percent.toStringAsFixed(1)}%';

  /// Returns colour for a score percentage (used by charts / badges)
  static Color colorForPercent(double percent) {
    if (percent >= 90) return const Color(0xFF1B5E20);
    if (percent >= 75) return const Color(0xFF2E7D32);
    if (percent >= 50) return const Color(0xFFF57F17);
    if (percent >= 30) return const Color(0xFFE65100);
    return const Color(0xFFC62828);
  }
}
