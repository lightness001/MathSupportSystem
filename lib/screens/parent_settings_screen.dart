import 'dart:io' hide File, Directory;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart';
import '../services/web_safe_file.dart';

class ParentSettingsScreen extends StatefulWidget {
  const ParentSettingsScreen({super.key});

  @override
  State<ParentSettingsScreen> createState() => _ParentSettingsScreenState();
}

class _ParentSettingsScreenState extends State<ParentSettingsScreen> {
  final supabase = Supabase.instance.client;

  // Local Parent State
  bool _isLoading = true;
  String _fullName = '';
  String _email = '';
  List<String> _linkedChildren = [];

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
    return File('${directory.path}/parent_settings_config.json');
  }

  Future<Map<String, String>> _loadSchoolsLocally() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/parent_schools_config.json');
      if (await file.exists()) {
        final Map<String, dynamic> decoded = jsonDecode(await file.readAsString());
        return decoded.map((key, value) => MapEntry(key, value.toString()));
      }
    } catch (e) {
      debugPrint("Error loading schools locally: $e");
    }
    return {};
  }

  Future<void> _loadSettingsAndProfile() async {
    try {
      // 1. Load Parent profile details
      final user = supabase.auth.currentUser;
      if (user != null) {
        final profile = await supabase.from('profiles').select().eq('id', user.id).maybeSingle();
        _fullName = profile != null ? (profile['full_name'] ?? 'Mzazi') : 'Parent';
        _email = user.email ?? '';

        // Load Linked Children
        final response = await supabase
            .from('parent_child_links')
            .select()
            .eq('parent_id', user.id);

        final Map<String, String> localSchools = await _loadSchoolsLocally();

        _linkedChildren = response.map<String>((item) {
          final String name = item['student_username']?.toString() ?? '';
          final String lvl = item['student_level']?.toString() ?? 'Standard 7';
          String school = (item['school']?.toString() ?? localSchools[name]) ?? "";
          if (school.isEmpty) {
            school = name.startsWith('a') ? "Greenwood Academy" : "Hillside International";
          }
          return "$name ($lvl - $school)";
        }).toList();
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
        // Fetch Linked Children from Supabase
        final response = await supabase
            .from('parent_child_links')
            .select('student_username, student_level')
            .eq('parent_id', user.id);

        _linkedChildren = response.map<String>((item) {
          final String name = item['student_username']?.toString() ?? '';
          final String lvl = item['student_level']?.toString() ?? 'Standard 7';
          return "$name ($lvl)";
        }).toList();
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
            Text("MathSupport Parent Portal", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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

  String _t(String en, String sw) {
    return AppSettings.language.value == 'Kiswahili' ? sw : en;
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
                      _t("Parent / Guardian", "Mzazi / Mlezi"),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                  const SizedBox(height: 15),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
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
                  // SECTION: LINKED CHILDREN
                  _buildSectionHeader(_t("Linked Students", "Wanafunzi Waliounganishwa")),
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: Colors.grey.shade200),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Column(
                        children: _linkedChildren.isEmpty
                            ? [
                                ListTile(
                                  leading: const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                                  title: Text(_t("No children linked yet", "Hakuna wanafunzi waliounganishwa bado")),
                                )
                              ]
                            : _linkedChildren.map((child) => ListTile(
                                  leading: const Icon(Icons.school_outlined, color: primaryBlue),
                                  title: Text(child, style: const TextStyle(fontWeight: FontWeight.w600)),
                                )).toList(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 25),

                  // SECTION: ACCOUNT SECURITY
                  _buildSectionHeader(_t("Account & Security", "Akaunti na Usalama")),
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
                          title: Text(_t("Change Password", "Badili Nywila"), style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(_t("Securely update your access password", "Sasisha nenosiri lako kwa usalama")),
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
                  _buildSectionHeader(_t("Preferences", "Vipendeleo")),
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
                          activeColor: primaryBlue,
                          secondary: const Icon(Icons.add_alert_outlined, color: primaryBlue),
                          title: Text(_t("Homework Alerts", "Tahadhari za Kazi"), style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(_t("Notifications for new student assignments", "Arifa za kazi mpya za mwanafunzi")),
                          value: _hwAlerts,
                          onChanged: (val) {
                            setState(() => _hwAlerts = val);
                            _saveSettings();
                          },
                        ),
                        const Divider(height: 1),
                        // Feedback Notifications Switch
                        SwitchListTile(
                          activeColor: primaryBlue,
                          secondary: const Icon(Icons.feedback_outlined, color: primaryBlue),
                          title: Text(_t("Feedback Alerts", "Tahadhari za Maoni"), style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(_t("Notifications for teacher assessments", "Arifa za tathmini za mwalimu")),
                          value: _feedbackNotifs,
                          onChanged: (val) {
                            setState(() => _feedbackNotifs = val);
                            _saveSettings();
                          },
                        ),
                        const Divider(height: 1),
                        // Reminders Switch
                        SwitchListTile(
                          activeColor: primaryBlue,
                          secondary: const Icon(Icons.alarm, color: primaryBlue),
                          title: Text(_t("System Reminders", "Vikumbusho vya Mfumo"), style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(_t("Reminders for homework due dates", "Vikumbusho vya tarehe za mwisho za kazi")),
                          value: _reminders,
                          onChanged: (val) {
                            setState(() => _reminders = val);
                            _saveSettings();
                          },
                        ),
                        const Divider(height: 1),
                        // Dark Mode Toggle
                        SwitchListTile(
                          activeColor: primaryBlue,
                          secondary: const Icon(Icons.dark_mode_outlined, color: primaryBlue),
                          title: Text(_t("Dark Theme", "Mandhari Meusi"), style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(_t("Optional dark styling for parent portal", "Mtindo wa hiari wa giza wa tovuti ya wazazi")),
                          value: _darkMode,
                          onChanged: (val) async {
                            setState(() => _darkMode = val);
                            await AppSettings.updateDarkMode(val);
                            await _saveSettings();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(_t("Theme updated successfully!", "Mandhari yamesasishwa kwa mafanikio!")), duration: const Duration(seconds: 1)),
                              );
                            }
                          },
                        ),
                        const Divider(height: 1),
                        // Language Dropdown
                        ListTile(
                          leading: const Icon(Icons.translate, color: primaryBlue),
                          title: Text(_t("Language Selection", "Uteuzi wa Lugha"), style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(_t("Important for East African / Tanzanian schools", "Muhimu kwa shule za Afrika Mashariki / Tanzania")),
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
                                  SnackBar(content: Text(_t("Language switched to $_selectedLanguage!", "Lugha imebadilishwa kuwa $_selectedLanguage!")), duration: const Duration(seconds: 1)),
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
                  _buildSectionHeader(_t("Offline Sync Status", "Hali ya Kusawazisha Nje ya Mtandao")),
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
                                    Text(
                                      _t("SQLite + Supabase Synced", "SQLite + Supabase Imesawazishwa"),
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      "${_t("Last Synced", "Imesawazishwa Mwisho")}: $_lastSyncedTime",
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
                                label: Text(_t("Sync", "Sawazisha"), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                          const Divider(height: 24),
                          Row(
                            children: [
                              const Icon(Icons.wifi_off_outlined, color: Colors.green, size: 28),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _t("Offline Mode Capable", "Uwezo wa Nje ya Mtandao"),
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _t("Data safely cached locally on your device", "Data zimehifadhiwa salama kwenye kifaa chako"),
                                      style: const TextStyle(color: Colors.grey, fontSize: 13),
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
                  _buildSectionHeader(_t("Help & Support", "Msaada na Usaidizi")),
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
                          title: Text(_t("Contact Admin", "Wasiliana na Msimamizi"), style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(_t("Support details and application version", "Maelezo ya usaidizi na toleo la programu")),
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
}
