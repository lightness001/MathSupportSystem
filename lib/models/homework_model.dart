class Question {
  final String questionText;
  final String type; // 'MCQ' or 'text'
  final List<String>? options;
  final String correctAnswer;

  Question({
    required this.questionText,
    required this.type,
    this.options,
    required this.correctAnswer,
  });
}

class Homework {
  final String id;
  final String title;
  final List<Question> questions;
  final String dueDate;
  final String? description;
  final String? fileUrl;

  Homework({
    required this.id,
    required this.title,
    required this.questions,
    required this.dueDate,
    this.description,
    this.fileUrl,
  });
}
