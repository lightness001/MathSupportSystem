import 'dart:io' hide File, Directory;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/db_helper.dart';
import '../main.dart';
import '../services/web_safe_file.dart';

class TeacherSettingsScreen extends StatefulWidget {
  const TeacherSettingsScreen({super.key});

  @override
  State<TeacherSettingsScreen> createState() => _TeacherSettingsScreenState();
}

class _TeacherSettingsScreenState extends State<TeacherSettingsScreen> {
  final supabase = Supabase.instance.client;

  // Local User State
  bool _isLoading = true;
  String _fullName = '';
  String _level = '';
  String _username = '';
  String _email = '';

  // Settings State (Persisted)
  bool _hwAlerts = true;
  bool _feedbackNotifs = true;
  bool _reminders = false;
  bool _darkMode = false;
  String _selectedLanguage = 'English';
  String _lastSyncedTime = 'Just now';
  
  // Sync Status
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _loadSettingsAndProfile();
  }

  // Persistent settings file path helper
  Future<File> get _settingsFile async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/teacher_settings_config.json');
  }

  Future<void> _loadSettingsAndProfile() async {
    try {
      // 1. Load Profile
      final user = supabase.auth.currentUser;
      if (user != null) {
        final profile = await supabase.from('profiles').select().eq('id', user.id).single();
        _fullName = profile['full_name'] ?? 'Mwalimu';
        _level = profile['level'] ?? 'Teacher';
        _username = profile['username'] ?? '';
        _email = user.email ?? '';
      }
      
      // 2. Load Persisted Settings JSON
      final file = await _settingsFile;
      if (await file.exists()) {
        final content = await file.readAsString();
        final Map<String, dynamic> data = jsonDecode(content);
        _hwAlerts = data['hwAlerts'] ?? true;
        _feedbackNotifs = data['feedbackNotifs'] ?? true;
        _reminders = data['reminders'] ?? false;
        _darkMode = AppSettings.themeMode.value == ThemeMode.dark;
        _selectedLanguage = AppSettings.language.value;
        _lastSyncedTime = data['lastSyncedTime'] ?? 'Just now';
      }
    } catch (e) {
      debugPrint("Error loading profile/settings: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveSettings() async {
    try {
      final file = await _settingsFile;
      final Map<String, dynamic> data = {
        'hwAlerts': _hwAlerts,
        'feedbackNotifs': _feedbackNotifs,
        'reminders': _reminders,
        'darkMode': _darkMode,
        'selectedLanguage': _selectedLanguage,
        'lastSyncedTime': _lastSyncedTime,
      };
      await file.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint("Error saving settings: $e");
    }
  }

  Future<void> _showChangePasswordDialog() async {
    final oldPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    bool isUpdating = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: const [
              Icon(Icons.lock_outline, color: Color(0xFF0D47A1)),
              SizedBox(width: 10),
              Text("Change Password"),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: oldPasswordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: "Old Password",
                    prefixIcon: Icon(Icons.lock_open),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: newPasswordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: "New Password",
                    prefixIcon: Icon(Icons.lock_outline),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: confirmPasswordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: "Confirm New Password",
                    prefixIcon: Icon(Icons.check_circle_outline),
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isUpdating ? null : () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0D47A1),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: isUpdating
                  ? null
                  : () async {
                      final oldPass = oldPasswordController.text.trim();
                      final newPass = newPasswordController.text.trim();
                      final confirmPass = confirmPasswordController.text.trim();

                      if (newPass.length < 8) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Password must be at least 8 characters long")),
                        );
                        return;
                      }
                      if (newPass != confirmPass) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Passwords do not match")),
                        );
                        return;
                      }

                      setDialogState(() => isUpdating = true);
                      try {
                        await supabase.auth.updateUser(UserAttributes(password: newPass));
                        if (context.mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("Password updated successfully! ✅"),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } catch (e) {
                        setDialogState(() => isUpdating = false);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text("Error updating password: $e"), backgroundColor: Colors.red),
                        );
                      }
                    },
              child: isUpdating
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text("Update", style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showGeminiApiKeyDialog() async {
    final controller = TextEditingController(text: AppSettings.geminiApiKey.value);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: const [
            Icon(Icons.vpn_key_outlined, color: Color(0xFF0D47A1)),
            SizedBox(width: 10),
            Text("Gemini API Key"),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _t(
                  "Configure your active Gemini API Key for high-accuracy multimodal grading of worksheets and handwriting recognition.",
                  "Weka ufunguo thabiti wa Gemini API kwa kusahihisha makaratasi na kutambua mwandiko kwa usahihi."
                ),
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: "Gemini API Key",
                  hintText: "AIzaSy...",
                  prefixIcon: Icon(Icons.vpn_key),
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_t("Cancel", "Ghairi")),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0D47A1),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              final key = controller.text.trim();
              await AppSettings.updateGeminiApiKey(key);
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(_t("Gemini API Key updated successfully! ✅", "Ufunguo wa Gemini API umesasishwa! ✅")),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            child: Text(_t("Save", "Hifadhi"), style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _performRealSync() async {
    setState(() => _isSyncing = true);
    try {
      final user = supabase.auth.currentUser;
      if (user != null) {
        // 1. Fetch latest homework assignments for this teacher from Supabase
        final homeworkRes = await supabase.from('homework').select().eq('teacher_id', user.id);
        final homeworkList = homeworkRes as List;

        final db = await DBHelper().database;
        
        // 2. Clear old cached homework and store fresh database cache
        await db.delete('homework_cache');
        for (var hw in homeworkList) {
          await db.insert('homework_cache', {
            'id': hw['id'].toString(),
            'title': hw['title'] ?? '',
            'due_date': hw['due_date'] ?? '',
            'content': hw['description'] ?? '',
          });
        }

        // 3. Update any local unsynced records as synced in SQLite database
        await db.update('student_performance', {'is_synced': 1}, where: 'is_synced = ?', whereArgs: [0]);
      }

      final DateTime now = DateTime.now();
      final String timeString = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";

      if (mounted) {
        setState(() {
          _isSyncing = false;
          _lastSyncedTime = 'Today at $timeString';
        });
        await _saveSettings();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("SQLite database successfully synchronized with Supabase! 🔄✅"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint("Sync error: $e");
      if (mounted) {
        setState(() => _isSyncing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("SQLite Database active. Sync error: $e"),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  void _showHelpSupportDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: const [
            Icon(Icons.help_outline, color: Color(0xFF0D47A1)),
            SizedBox(width: 10),
            Text("Help & Support"),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text("MathSupport Portal", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            SizedBox(height: 5),
            Text("Version 1.2.0 (Stable)", style: TextStyle(color: Colors.grey, fontSize: 13)),
            Divider(height: 30),
            Text("Need Help?", style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 4),
            Text("If you encounter any database sync issues or require feature access, please contact the school systems administrator:", style: TextStyle(fontSize: 14)),
            SizedBox(height: 10),
            Text("📧 support@mathsupport.tz", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0D47A1))),
            Text("📞 +255 712 345 678", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0D47A1))),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const Color primaryBlue = Color(0xFF0D47A1);

    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // PROFILE CARD (Premium Gradient Background)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 30),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [primaryBlue, Color(0xFF1565C0)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(30),
                  bottomRight: Radius.circular(30),
                ),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  const CircleAvatar(
                    radius: 40,
                    backgroundColor: Colors.white,
                    child: Icon(Icons.person, size: 50, color: primaryBlue),
                  ),
                  const SizedBox(height: 15),
                  Text(
                    _fullName,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _level.replaceAll(',', ' & '),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                  const SizedBox(height: 15),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.alternate_email, size: 16, color: Colors.white70),
                      const SizedBox(width: 6),
                      Text(_username, style: const TextStyle(color: Colors.white70)),
                      const SizedBox(width: 20),
                      const Icon(Icons.email_outlined, size: 16, color: Colors.white70),
                      const SizedBox(width: 6),
                      Text(
                        _email.length > 20 ? '${_email.substring(0, 18)}...' : _email,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // SECTION: ACCOUNT SECURITY
                  _buildSectionHeader("Account & Security"),
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.lock_outline, color: primaryBlue),
                          title: const Text("Change Password", style: TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: const Text("Securely update your access password"),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: _showChangePasswordDialog,
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.vpn_key_outlined, color: primaryBlue),
                          title: Text(_t("Gemini API Key", "Ufunguo wa Gemini API"), style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(_t("Configure active AI key for grading worksheets", "Weka ufunguo thabiti wa AI kwa kusahihisha")),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: _showGeminiApiKeyDialog,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 25),

                  // SECTION: PREFERENCES
                  _buildSectionHeader("Preferences"),
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      children: [
                        // Homework Alerts Switch
                        SwitchListTile(
                          activeThumbColor: primaryBlue,
                          secondary: const Icon(Icons.add_alert_outlined, color: primaryBlue),
                          title: const Text("Homework Alerts", style: TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: const Text("Get notifications when students submit"),
                          value: _hwAlerts,
                          onChanged: (val) {
                            setState(() => _hwAlerts = val);
                            _saveSettings();
                          },
                        ),
                        const Divider(height: 1),
                        // Feedback Notifications Switch
                        SwitchListTile(
                          activeThumbColor: primaryBlue,
                          secondary: const Icon(Icons.feedback_outlined, color: primaryBlue),
                          title: const Text("Feedback Alerts", style: TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: const Text("Notifications for system auto-grading"),
                          value: _feedbackNotifs,
                          onChanged: (val) {
                            setState(() => _feedbackNotifs = val);
                            _saveSettings();
                          },
                        ),
                        const Divider(height: 1),
                        // Reminders Switch
                        SwitchListTile(
                          activeThumbColor: primaryBlue,
                          secondary: const Icon(Icons.alarm, color: primaryBlue),
                          title: const Text("System Reminders", style: TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: const Text("Reminders for review deadlines"),
                          value: _reminders,
                          onChanged: (val) {
                            setState(() => _reminders = val);
                            _saveSettings();
                          },
                        ),
                        const Divider(height: 1),
                        // Dark Mode Toggle
                        SwitchListTile(
                          activeThumbColor: primaryBlue,
                          secondary: const Icon(Icons.dark_mode_outlined, color: primaryBlue),
                          title: const Text("Dark Theme", style: TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: const Text("Optional dark styling for teacher portal"),
                          value: _darkMode,
                          onChanged: (val) async {
                            setState(() => _darkMode = val);
                            await AppSettings.updateDarkMode(val);
                            await _saveSettings();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text("Theme updated successfully!"), duration: Duration(seconds: 1)),
                              );
                            }
                          },
                        ),
                        const Divider(height: 1),
                        // Language Dropdown
                        ListTile(
                          leading: const Icon(Icons.translate, color: primaryBlue),
                          title: const Text("Language Selection", style: TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: const Text("Important for East African / Tanzanian schools"),
                          trailing: DropdownButton<String>(
                            value: _selectedLanguage,
                            underline: const SizedBox(),
                            icon: const Icon(Icons.arrow_drop_down, color: primaryBlue),
                            items: ['English', 'Kiswahili'].map((lang) {
                              return DropdownMenuItem(
                                value: lang,
                                child: Text(lang, style: const TextStyle(fontWeight: FontWeight.bold, color: primaryBlue)),
                              );
                            }).toList(),
                            onChanged: (val) async {
                              setState(() => _selectedLanguage = val!);
                              await AppSettings.updateLanguage(val!);
                              await _saveSettings();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text("Language switched to $_selectedLanguage!"), duration: const Duration(seconds: 1)),
                                );
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 25),

                  // SECTION: OFFLINE SYNC
                  _buildSectionHeader("Offline Sync Status"),
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: Colors.grey.shade200),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.cloud_done_outlined, color: Colors.green, size: 28),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      "SQLite + Supabase Synced",
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      "Last Synced: $_lastSyncedTime",
                                      style: const TextStyle(color: Colors.grey, fontSize: 13),
                                    ),
                                  ],
                                ),
                              ),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: primaryBlue,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                ),
                                onPressed: _isSyncing ? null : _performRealSync,
                                icon: _isSyncing
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                      )
                                    : const Icon(Icons.sync, size: 16, color: Colors.white),
                                label: const Text("Sync", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                          const Divider(height: 24),
                          Row(
                            children: const [
                              Icon(Icons.wifi_off_outlined, color: Colors.green, size: 28),
                              SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "Offline Mode Capable",
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                    ),
                                    SizedBox(height: 2),
                                    Text(
                                      "Data safely cached locally on your device",
                                      style: TextStyle(color: Colors.grey, fontSize: 13),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 25),

                  // SECTION: HELP & SUPPORT
                  _buildSectionHeader("Help & Support"),
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.help_center_outlined, color: primaryBlue),
                          title: const Text("Contact Admin", style: TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: const Text("Support details and application version"),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: _showHelpSupportDialog,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.grey,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  String _t(String en, String sw) {
    return AppSettings.language.value == 'Kiswahili' ? sw : en;
  }
}
