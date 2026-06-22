import 'dart:io';
import 'package:path_provider/path_provider.dart';

void main() async {
  print("Reading settings...");
  try {
    final tempDir = Directory.systemTemp;
    final fileTemp = File('${tempDir.path}/teacher_settings_config.json');
    if (await fileTemp.exists()) {
      print("Found in systemTemp: ${await fileTemp.readAsString()}");
    } else {
      print("Not found in systemTemp.");
    }
  } catch (e) {
    print("Error: $e");
  }
}
