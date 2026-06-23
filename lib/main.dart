import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/login_screen.dart';
import 'services/web_safe_file.dart';

class AppSettings {
  static final ValueNotifier<ThemeMode> themeMode = ValueNotifier<ThemeMode>(ThemeMode.light);
  static final ValueNotifier<String> language = ValueNotifier<String>('English');
  static final ValueNotifier<String> geminiApiKey = ValueNotifier<String>('');

  /// Supabase Service Role Key — required for admin operations like
  /// resetting another user's password via the Supabase Admin REST API.
  /// Get it from: Supabase Dashboard → Project Settings → API → service_role key.
  static final ValueNotifier<String> supabaseServiceRoleKey = ValueNotifier<String>('');

  static Future<Directory> getSafeDirectory() async {
    try {
      final ioDir = await getApplicationDocumentsDirectory();
      return Directory(ioDir.path);
    } catch (e) {
      debugPrint("SafeDirectory: path_provider failed ($e), falling back to systemTemp");
      return Directory.systemTemp;
    }
  }

  static Future<void> loadSettings() async {
    try {
      final directory = await getSafeDirectory();
      final file = File('${directory.path}/teacher_settings_config.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        final Map<String, dynamic> data = jsonDecode(content);
        final bool darkMode = data['darkMode'] ?? false;
        themeMode.value = darkMode ? ThemeMode.dark : ThemeMode.light;
        language.value = data['selectedLanguage'] ?? 'English';
        geminiApiKey.value = data['geminiApiKey'] ?? '';
        supabaseServiceRoleKey.value = data['supabaseServiceRoleKey'] ?? '';
      }
    } catch (e) {
      debugPrint("Error loading app settings: $e");
    }
  }

  static Future<void> updateDarkMode(bool darkMode) async {
    themeMode.value = darkMode ? ThemeMode.dark : ThemeMode.light;
    await _save();
  }

  static Future<void> updateLanguage(String lang) async {
    language.value = lang;
    await _save();
  }

  static Future<void> updateGeminiApiKey(String key) async {
    geminiApiKey.value = key;
    await _save();
  }

  static Future<void> updateSupabaseServiceRoleKey(String key) async {
    supabaseServiceRoleKey.value = key;
    await _save();
  }

  static Future<void> _save() async {
    try {
      final directory = await getSafeDirectory();
      final file = File('${directory.path}/teacher_settings_config.json');
      Map<String, dynamic> existing = {};
      if (await file.exists()) {
        existing = jsonDecode(await file.readAsString());
      }
      existing['darkMode'] = themeMode.value == ThemeMode.dark;
      existing['selectedLanguage'] = language.value;
      existing['geminiApiKey'] = geminiApiKey.value;
      existing['supabaseServiceRoleKey'] = supabaseServiceRoleKey.value;
      await file.writeAsString(jsonEncode(existing));
    } catch (e) {
      debugPrint("Error saving settings: $e");
    }
  }
}

void main() async {
  // 1. Ensure Flutter is fully initialized
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Initialize Supabase with your URL and Anon Key
  await Supabase.initialize(
    url: 'https://wnxeohqejdiytqkxdcwe.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndueGVvaHFlamRpeXRxa3hkY3dlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY0MjExMTksImV4cCI6MjA5MTk5NzExOX0.-c4Y4rhmc3TSlVpoSwazqCdLp51d5ri1FAHEqlJr8H0',
  );

  // 3. Load App Settings
  await AppSettings.loadSettings();

  runApp(const MathSupportApp());
}

class MathSupportApp extends StatelessWidget {
  const MathSupportApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppSettings.themeMode,
      builder: (context, mode, child) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Homework Support System',
          themeMode: mode,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
            brightness: Brightness.light,
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.blue,
              brightness: Brightness.dark,
            ),
          ),
          home: const LoginScreen(),
        );
      },
    );
  }
}
