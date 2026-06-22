import 'dart:io' hide File, Directory;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../services/web_safe_file.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'login_screen.dart';
import 'parent_home_screen.dart';
import 'parent_progress_screen.dart';
import 'parent_notifications_screen.dart';
import 'parent_settings_screen.dart';
import 'parent_chat_screen.dart';
import 'parent_schools_screen.dart';
import '../services/school_service.dart';
import '../main.dart';

class ParentDashboard extends StatefulWidget {
  final String selectedSchool;

  const ParentDashboard({super.key, required this.selectedSchool});

  @override
  State<ParentDashboard> createState() => _ParentDashboardState();
}

class _ParentDashboardState extends State<ParentDashboard> {
  int _currentIndex = 0;
  String _selectedChild = "";

  // Stores both student_username and student_level
  List<Map<String, String>> _linkedChildrenData = [];
  bool _isLoading = true;
  List<School> _availableSchools = [];

  @override
  void initState() {
    super.initState();
    _loadLinkedChildren();
    _loadAvailableSchools();
  }

  Future<void> _loadAvailableSchools() async {
    final list = await SchoolService.getSchools();
    if (mounted) {
      setState(() {
        _availableSchools = list;
      });
    }
  }

  Future<void> _saveSchoolLocally(String username, String school) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/parent_schools_config.json');
      Map<String, dynamic> data = {};
      if (await file.exists()) {
        data = jsonDecode(await file.readAsString());
      }
      data[username] = school.isNotEmpty ? school : "Dar es Salaam Academy";
      await file.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint("Error saving school locally: $e");
    }
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

  Future<void> _loadLinkedChildren() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      // Dynamic select to fetch all existing columns safely
      final response = await Supabase.instance.client
          .from('parent_child_links')
          .select()
          .eq('parent_id', user.id);

      final List<dynamic> responseList = response as List<dynamic>;
      final List<String> usernames = responseList.map((item) => item['student_username'].toString()).toList();
      
      Map<String, String> nameMap = {};
      if (usernames.isNotEmpty) {
        try {
          final profilesRes = await Supabase.instance.client
              .from('profiles')
              .select('username, full_name')
              .inFilter('username', usernames);
          final List<dynamic> profilesList = profilesRes as List<dynamic>;
          nameMap = {
            for (var p in profilesList) p['username'].toString(): p['full_name']?.toString() ?? p['username'].toString()
          };
        } catch (profileErr) {
          debugPrint("Error loading profile names: $profileErr");
        }
      }

      final Map<String, String> localSchools = await _loadSchoolsLocally();

      final List<Map<String, String>> fetchedData =
          List<Map<String, String>>.from(
            responseList.map(
              (item) {
                final String username = item['student_username'].toString();
                // Check if school is in database, otherwise check local storage, otherwise default
                String school = (item['school']?.toString() ?? localSchools[username]) ?? "";
                if (school.isEmpty) {
                  school = username.startsWith('a') ? "Greenwood Academy" : "Hillside International";
                }
                return {
                  'username': username,
                  'fullName': nameMap[username] ?? username,
                  'level': item['student_level']?.toString() ?? 'Standard 7',
                  'school': school,
                };
              },
            ),
          );

      // Filter only children belonging to selected school
      final filteredData = fetchedData.where((child) => child['school'] == widget.selectedSchool).toList();

      // De-duplicate children by username to prevent Dropdown crash and visual duplicates
      final List<Map<String, String>> deDuplicated = [];
      final Set<String> seenUsernames = {};
      for (var child in filteredData) {
        final String uname = (child['username'] ?? '').toLowerCase();
        if (uname.isNotEmpty && !seenUsernames.contains(uname)) {
          seenUsernames.add(uname);
          deDuplicated.add(child);
        }
      }

      setState(() {
        _linkedChildrenData = deDuplicated;
        if (_linkedChildrenData.isNotEmpty) {
          _selectedChild = _linkedChildrenData.first['username']!;
        }
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Fetch error: $e");
      setState(() => _isLoading = false);
    }
  }

  // Helper to find the level of the currently selected child
  String _getCurrentLevel() {
    final match = _linkedChildrenData.firstWhere(
      (child) => child['username'] == _selectedChild,
      orElse: () => {'level': 'Standard 7'},
    );
    return match['level']!;
  }

  // Helper to find the school of the currently selected child
  String _getCurrentSchool() {
    final match = _linkedChildrenData.firstWhere(
      (child) => child['username'] == _selectedChild,
      orElse: () => {'school': widget.selectedSchool},
    );
    return match['school']!;
  }

  // Helper to find the full name of the currently selected child
  String _getCurrentFullName() {
    final match = _linkedChildrenData.firstWhere(
      (child) => child['username'] == _selectedChild,
      orElse: () => {'fullName': _selectedChild},
    );
    return match['fullName']!;
  }

  List<Widget> get _screens => [
    ParentHomeScreen(
      childName: _selectedChild,
      level: _getCurrentLevel(),
    ),
    _linkedChildrenData.isEmpty
        ? const Center(child: Text("No children linked yet."))
        : ParentProgressScreen(
            childName: _selectedChild,
            fullName: _getCurrentFullName(),
            level: _getCurrentLevel(),
          ),
    ParentNotificationsScreen(childName: _selectedChild),
    const ParentSettingsScreen(),
  ];

  String _t(String en, String sw) {
    return AppSettings.language.value == 'Kiswahili' ? sw : en;
  }

  Future<bool?> _showExitConfirmationDialog(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.exit_to_app, color: Color(0xFF0D47A1)),
            const SizedBox(width: 10),
            Text(_t("Exit App?", "Toka kwenye Programu?")),
          ],
        ),
        content: Text(_t("Are you sure you want to close the homework support system?", "Je, una uhakika unataka kufunga mfumo wa kusaidia kazi za nyumbani?")),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_t("Cancel", "Ghairi"), style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD32F2F),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(_t("Exit", "Ondoka"), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const Color primaryBlue = Color(0xFF0D47A1);

    return ValueListenableBuilder<String>(
      valueListenable: AppSettings.language,
      builder: (context, lang, child) {
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) async {
            if (didPop) return;
            if (_currentIndex != 0) {
              setState(() {
                _currentIndex = 0;
              });
            } else {
              final shouldExit = await _showExitConfirmationDialog(context);
              if (shouldExit == true && context.mounted) {
                await SystemNavigator.pop();
              }
            }
          },
          child: Scaffold(
            backgroundColor: Colors.white,
            appBar: AppBar(
              title: _currentIndex == 3
                  ? Text(_t("App Settings", "Mipangilio ya Programu"), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
                  : _linkedChildrenData.isEmpty
                      ? Text(_t("Parent Portal", "Tovuti ya Wazazi"), style: const TextStyle(color: Colors.white))
                      : DropdownButtonHideUnderline(
                          child: SizedBox(
                            width: 140,
                            child: DropdownButton<String>(
                              value: _selectedChild,
                              dropdownColor: primaryBlue,
                              isExpanded: true,
                              icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
                              selectedItemBuilder: (BuildContext context) {
                                return _linkedChildrenData.map<Widget>((child) {
                                  final String uname = child['username'] ?? '';
                                  final String fn = child['fullName'] ?? '';
                                  final String disp = (fn.isNotEmpty && fn != uname) ? "$fn ($uname)" : uname;
                                  return Container(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      disp,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  );
                                }).toList();
                              },
                              items: _linkedChildrenData.map((child) {
                                final String uname = child['username'] ?? '';
                                final String fn = child['fullName'] ?? '';
                                final String disp = (fn.isNotEmpty && fn != uname) ? "$fn ($uname)" : uname;
                                return DropdownMenuItem<String>(
                                  value: child['username'],
                                  child: Text(
                                    "$disp (${child['school'] ?? ''})",
                                    style: const TextStyle(color: Colors.white, fontSize: 13),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                );
                              }).toList(),
                              onChanged: (String? newValue) {
                                setState(() => _selectedChild = newValue!);
                              },
                            ),
                          ),
                        ),
              backgroundColor: primaryBlue,
              elevation: 0,
              actions: _currentIndex == 3
                  ? null
                  : [
                      IconButton(
                        icon: const Icon(Icons.swap_horiz, color: Colors.white),
                        tooltip: _t("Switch School", "Badili Shule"),
                        onPressed: () {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const ParentSchoolsScreen(),
                            ),
                          );
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.chat_bubble_outline, color: Colors.white),
                        tooltip: _t("Teacher Chat", "Mawasiliano na Mwalimu"),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ParentChatScreen(
                                selectedChild: _selectedChild,
                                currentLevel: _getCurrentLevel(),
                                selectedSchool: _getCurrentSchool(),
                              ),
                            ),
                          );
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.person_add_alt_1, color: Colors.white),
                        onPressed: () => _showAddChildDialog(context),
                      ),
                      IconButton(
                        icon: const Icon(Icons.logout, color: Colors.white),
                        onPressed: () => _showLogoutDialog(context),
                      ),
                    ],
            ),
            body: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _screens[_currentIndex],
            bottomNavigationBar: BottomNavigationBar(
              currentIndex: _currentIndex,
              selectedItemColor: primaryBlue,
              unselectedItemColor: Colors.grey,
              type: BottomNavigationBarType.fixed,
              onTap: (index) => setState(() => _currentIndex = index),
              items: [
                BottomNavigationBarItem(icon: const Icon(Icons.home_outlined), label: _t("Home", "Nyumbani")),
                BottomNavigationBarItem(icon: const Icon(Icons.bar_chart_outlined), label: _t("Progress", "Maendeleo")),
                BottomNavigationBarItem(icon: const Icon(Icons.notifications_outlined), label: _t("Notifications", "Arifa")),
                BottomNavigationBarItem(icon: const Icon(Icons.settings_outlined), label: _t("Settings", "Mipangilio")),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(_t("Logout", "Kuondoka")),
        content: Text(_t("Are you sure you want to log out from the Parent Portal?", "Je, una uhakika unataka kuondoka kwenye Tovuti ya Wazazi?")),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(_t("Cancel", "Ghairi")),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              await Supabase.instance.client.auth.signOut();
              if (!mounted) return;
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => const LoginScreen()),
                (route) => false,
              );
            },
            child: Text(_t("Logout", "Ondoka"), style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showAddChildDialog(BuildContext context) {
    final childUsernameController = TextEditingController();
    String selectedSchool = _availableSchools.isNotEmpty
        ? _availableSchools.first.schoolName
        : "Westfield Academy";

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(_t("Link Another Child", "Unganisha Mtoto Mwingine")),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: childUsernameController,
                  decoration: InputDecoration(
                    labelText: _t("Student Username", "Jina la Mwanafunzi"),
                    prefixIcon: const Icon(Icons.person_outline),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 15),
                DropdownButtonFormField<String>(
                  initialValue: selectedSchool,
                  value: selectedSchool,
                  decoration: InputDecoration(
                    labelText: _t("School Name", "Jina la Shule"),
                    prefixIcon: const Icon(Icons.school_outlined),
                    border: const OutlineInputBorder(),
                  ),
                  items: (_availableSchools.isEmpty
                          ? [
                              'Westfield Academy',
                              'Riverside International',
                              'Greenwood Academy',
                              'Hillside International',
                              'Dar es Salaam Academy'
                            ]
                          : _availableSchools.map((s) => s.schoolName).toList())
                      .map((school) {
                    return DropdownMenuItem(value: school, child: Text(school));
                  }).toList(),
                  onChanged: (val) {
                    setDialogState(() {
                      selectedSchool = val!;
                    });
                  },
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
                final newChild = childUsernameController.text.trim().toLowerCase();
                final schoolName = selectedSchool;
              if (newChild.isNotEmpty) {
                try {
                  setState(() => _isLoading = true);

                  // 1. Verify if the student exists first
                  final studentData = await Supabase.instance.client
                      .from('profiles')
                      .select()
                      .eq('username', newChild)
                      .maybeSingle();

                  if (studentData == null) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(_t("Student '$newChild' does not exist.", "Mwanafunzi '$newChild' hayupo.")),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                    setState(() => _isLoading = false);
                    return;
                  }

                  final userId = Supabase.instance.client.auth.currentUser!.id;

                  // Check if student is already linked to this parent
                  final existingLink = await Supabase.instance.client
                      .from('parent_child_links')
                      .select()
                      .eq('parent_id', userId)
                      .eq('student_username', newChild)
                      .maybeSingle();

                  if (existingLink != null) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(_t("Student '$newChild' is already linked to your account.", "Mwanafunzi '$newChild' tayari ameunganishwa kwenye akaunti yako.")),
                          backgroundColor: Colors.orange,
                        ),
                      );
                    }
                    setState(() => _isLoading = false);
                    return;
                  }

                  // 2. Try inserting child using actual level + school
                  try {
                    await Supabase.instance.client
                        .from('parent_child_links')
                        .insert({
                          'parent_id': userId,
                          'student_username': newChild,
                          'student_level': studentData['level'] ?? 'Standard 7',
                          'school': schoolName.isNotEmpty ? schoolName : "Dar es Salaam Academy",
                        });
                  } catch (dbErr) {
                    // Fallback if 'school' column doesn't exist in parent_child_links yet
                    await Supabase.instance.client
                        .from('parent_child_links')
                        .insert({
                          'parent_id': userId,
                          'student_username': newChild,
                          'student_level': studentData['level'] ?? 'Standard 7',
                        });
                    await _saveSchoolLocally(newChild, schoolName);
                  }

                  // Refresh the whole list
                  await _loadLinkedChildren();
                  if (context.mounted) Navigator.pop(context);
                } catch (e) {
                  debugPrint("Link error: $e");
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(_t("Error linking child: $e", "Makosa ya kuunganisha mtoto: $e"))),
                    );
                  }
                } finally {
                  if (mounted) setState(() => _isLoading = false);
                }
              }
            },
            child: Text(_t("Link Child", "Unganisha"), style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    ),
  );
}
}
