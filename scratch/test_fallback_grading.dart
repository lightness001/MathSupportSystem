import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:homework_support_system/services/auto_grading_service.dart';
import 'package:homework_support_system/main.dart';

void main() async {
  print("Testing AutoGradingService with fallback mechanism...");
  
  // Set the Gemini API key to something invalid to force failure
  AppSettings.geminiApiKey.value = "INVALID_KEY";

  final result = await AutoGradingService.gradeSubmission(
    homeworkTitle: "Simple Math Assignment",
    homeworkDescription: "Solve the following math questions:\n1. 10 + 20 =\n2. 5 * 6 =\n3. 100 / 4 =",
    studentTextAnswer: "1. 30\n2. 30\n3. 25",
  );

  print("\n--- GRADING RESULT ---");
  print("Grading Source: ${result.gradingSource}");
  print("Score: ${result.score}");
  print("Correct Count: ${result.correctCount}");
  print("Total Questions: ${result.totalQuestions}");
  print("Feedback: ${result.feedback}");
  print("Recommendation: ${result.recommendation}");
}
