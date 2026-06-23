import 'package:homework_support_system/services/web_safe_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homework_support_system/screens/crop_image_screen.dart';

void main() {
  group('CropImageScreen UI Tests', () {
    testWidgets('Should render CropImageScreen and show interactive crop layout instantly', (WidgetTester tester) async {
      CropImageScreen.isTesting = true;
      // Create a dummy image file
      final tempDir = Directory.systemTemp;
      final file = File('${tempDir.path}/test_image.png');
      await file.writeAsBytes([1, 2, 3]); // dummy bytes

      await tester.pumpWidget(
        MaterialApp(
          home: CropImageScreen(imageFile: file),
        ),
      );

      // Pump to process async microtask state change and rebuild the tree
      await tester.pump();
      await tester.pump();

      // Verify that the title of the screen is rendered
      expect(find.text("Crop Homework Sheet"), findsOneWidget);

      // Verify the crop instructions banner is rendered
      expect(find.text("Drag corners to crop your homework questions"), findsOneWidget);

      // Verify the "DONE" button is rendered
      expect(find.text("DONE"), findsOneWidget);

      // Clean up test file
      if (await file.exists()) {
        await file.delete();
      }
    });
  });
}
