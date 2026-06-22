// ============================================================
// performance_model.dart  –  Richer model to support grading
// ============================================================

class Performance {
  final int? id;
  final String topic;
  final double score;
  final int totalQuestions;
  final String dateTaken;
  final String grade; // A / B / C / D / E
  final String recommendation;
  final String wrongQuestionsJson; // JSON array of missed question indexes
  final bool isTeacherReviewed;
  final String teacherComment;

  const Performance({
    this.id,
    required this.topic,
    required this.score,
    required this.totalQuestions,
    required this.dateTaken,
    this.grade = '',
    this.recommendation = '',
    this.wrongQuestionsJson = '[]',
    this.isTeacherReviewed = false,
    this.teacherComment = '',
  });

  /// Derive the percentage (0-100)
  double get percent =>
      totalQuestions > 0 ? (score / totalQuestions) * 100 : 0;

  // ----- SQLite serialisation -----

  /// Create from a SQLite row map
  factory Performance.fromMap(Map<String, dynamic> map) {
    return Performance(
      id: map['id'] as int?,
      topic: map['topic'] as String? ?? '',
      score: (map['score'] as num?)?.toDouble() ?? 0,
      totalQuestions: map['total_questions'] as int? ?? 0,
      dateTaken: map['date_taken'] as String? ?? '',
      grade: map['grade'] as String? ?? '',
      recommendation: map['recommendation'] as String? ?? '',
      wrongQuestionsJson: map['wrong_questions'] as String? ?? '[]',
      isTeacherReviewed:
          (map['is_teacher_reviewed'] as int? ?? 0) == 1,
      teacherComment: map['teacher_comment'] as String? ?? '',
    );
  }

  /// Convert to a map suitable for SQLite insert/update
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'topic': topic,
      'score': score,
      'total_questions': totalQuestions,
      'date_taken': dateTaken,
      'grade': grade,
      'recommendation': recommendation,
      'wrong_questions': wrongQuestionsJson,
      'is_teacher_reviewed': isTeacherReviewed ? 1 : 0,
      'teacher_comment': teacherComment,
      'is_synced': 0,
    };
  }
}
