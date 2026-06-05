import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homework_support_system/screens/homework_player_screen.dart';
import 'package:homework_support_system/models/homework_model.dart';

void main() {
  group('HomeworkPlayerScreen UI Tests', () {
    testWidgets('Should build and render document player layout successfully', (WidgetTester tester) async {
      final homework = Homework(
        id: '123',
        title: 'Addition homework',
        dueDate: '2026-12-31',
        description: 'Please complete the addition sheet carefully.',
        questions: [], // empty list triggers document layout
      );

      await tester.pumpWidget(
        MaterialApp(
          home: HomeworkPlayerScreen(homework: homework),
        ),
      );

      // Let state initialization finish (Supabase catch block) and rebuild
      await tester.pump();

      // Verify that the title of the homework is displayed
      expect(find.text('Addition homework'), findsWidgets);

      // Verify description is displayed
      expect(find.text('Please complete the addition sheet carefully.'), findsOneWidget);

      // Verify file picker text is rendered
      expect(find.text('Upload handwritten answers / photos / document (Optional)'), findsOneWidget);

      // Verify submission button is rendered
      expect(find.text('SUBMIT ASSIGNMENT'), findsOneWidget);
    });
  });
}
