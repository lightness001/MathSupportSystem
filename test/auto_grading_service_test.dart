import 'package:flutter_test/flutter_test.dart';
import 'package:homework_support_system/services/auto_grading_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AutoGradingService Precision & Noise Filtering Tests', () {
    test('Should parse student answers correctly and ignore status bar time (13:03)', () {
      const String homeworkDescription = """
Addition
1. Add: 345 + 678
2. Add: 1,245 + 3,678
3. Add: 456 + 789 + 123
4. Add: 9,876 + 5,432
5. Add: 675 + 908
6. Add: 2,345 + 1,234
""";

      // Simulated noisy OCR extraction from a gallery app screenshot containing status bar time "13:03"
      const String simulatedOcrSubmission = """
13:03
Answers
1. 345 + 678 = 1,023
Answer 1023
2. 1245 + 2678 = 4,923
Answer 4923
3. 456 + 789 + 123 = 1,368
Answer 1368
4. 9876 + 5432 = 15,308
Answer 15308
5. 675 + 908 = 1,583
Answer 1583
6. 2345 + 1234 = 3,579
Answer 3579
""";

      // Trigger the gradeSubmission's fallback rule engine under the hood
      final result = AutoGradingService.gradeSubmission(
        homeworkTitle: "Addition Homework",
        homeworkDescription: homeworkDescription,
        studentTextAnswer: simulatedOcrSubmission,
      );

      // Verify the synchronous/asynchronous output
      result.then((res) {
        expect(res.totalQuestions, equals(6));
        expect(res.correctCount, equals(6));
        expect(res.score, equals(100.0));
        expect(res.gradingSource, contains("Math Parser Engine"));
        expect(res.feedback, contains("Excellent! You got all 6 questions 100% correct."));
      });
    });

    test('Should successfully merge question numbers and answers on separate lines', () {
      const String homeworkDescription = "1. Add: 10 + 20\n2. Add: 30 + 40";
      
      // Simulated OCR where the question number is on its own line due to bounding box separation
      const String separatedLinesOcr = """
1.
10 + 20 = 30
2.
30 + 40 = 70
""";

      final resultFuture = AutoGradingService.gradeSubmission(
        homeworkTitle: "Simple Homework",
        homeworkDescription: homeworkDescription,
        studentTextAnswer: separatedLinesOcr,
      );

      resultFuture.then((res) {
        expect(res.totalQuestions, equals(2));
        expect(res.correctCount, equals(2));
        expect(res.score, equals(100.0));
      });
    });

    test('Should successfully parse and grade Mathematics word-problem worksheet', () {
      const String homeworkDescription = """
Mathematics
1. Solve: 456 × 23
2. Divide 1,248 by 12.
3. Find the area of a rectangle with length 15 cm and width 8 cm.
4. Convert 3/4 into a percentage.
5. A farmer sold 45 bags of maize at Tsh 35,000 each. How much money did he receive?
""";

      const String studentOcrSubmission = """
1. 456 x 23
456 x 23 = 10,488
Answer: 10,488
2. 1,248 / 12
1,248 / 12 = 104
Answer: 104
3. Area of rectangle = Length x Width
15 x 8 = 120 cm^2
Answer: 120 cm^2
4. Convert 3/4 into percentage
3/4 x 100 = 75%
Answer: 75%
""";

      final resultFuture = AutoGradingService.gradeSubmission(
        homeworkTitle: "mixed questions",
        homeworkDescription: homeworkDescription,
        studentTextAnswer: studentOcrSubmission,
      );

      resultFuture.then((res) {
        expect(res.totalQuestions, equals(5));
        expect(res.correctCount, equals(4)); // 1 to 4 are correct, 5 is unanswered/missing
        expect(res.score, equals(80.0));
        expect(res.feedback, contains("Good effort! You answered 4 out of 5 questions correctly."));
        expect(res.recommendation, contains("Review corrections: Q5 = 1575000."));
      });
    });
  });
}
