import 'dart:io' hide File, Directory;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart';
import 'parent_dashboard.dart';
import 'login_screen.dart';
import '../services/school_service.dart';
import '../services/web_safe_file.dart';

class ParentSchoolsScreen extends StatefulWidget {
  const ParentSchoolsScreen({super.key});

  @override
  State<ParentSchoolsScreen> createState() => _ParentSchoolsScreenState();
}

class _ParentSchoolsScreenState extends State<ParentSchoolsScreen> {
  final supabase = Supabase.instance.client;
  bool _isLoading = true;
  bool _showDiagnostics = false;
  String _diagnosticLogs = "No diagnostic logs yet. Tap Refresh.";
  
  // Structured map of school name -> List of children in that school
  Map<String, List<Map<String, String>>> _schoolsMap = {};
  List<School> _availableSchools = [];

  @override
  void initState() {
    super.initState();
    _loadLinkedChildrenAndSchools();
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

  Future<Map<String, String>> _loadSchoolsLocally() async {
    try {
      final directory = await AppSettings.getSafeDirectory();
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

  Future<void> _checkAndSyncLocalSignupCache() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final directory = await AppSettings.getSafeDirectory();
      final file = File('${directory.path}/parent_signup_cache.json');
      if (await file.exists()) {
        debugPrint("DEBUG ParentSchoolsScreen: Found local signup cache!");
        final Map<String, dynamic> cache = jsonDecode(await file.readAsString());
        final List children = cache['children'] ?? [];
        
        bool allSuccessful = true;
        for (var child in children) {
          final String username = child['username']?.toString() ?? '';
          final String school = child['school']?.toString() ?? 'Westfield Academy';
          final String level = child['level']?.toString() ?? 'Standard 7';

          if (username.isNotEmpty) {
            debugPrint("DEBUG ParentSchoolsScreen: Syncing cached child '$username' with school '$school'...");
            try {
              await supabase.from('parent_child_links').insert({
                'parent_id': user.id,
                'student_username': username,
                'student_level': level,
                'school': school,
              });
              debugPrint("DEBUG ParentSchoolsScreen: Successfully synced child '$username' to DB!");
            } catch (insertErr) {
              debugPrint("DEBUG ParentSchoolsScreen: Sync insert failed, trying fallback: $insertErr");
              try {
                await supabase.from('parent_child_links').insert({
                  'parent_id': user.id,
                  'student_username': username,
                  'student_level': level,
                });
                // Save locally
                final sFile = File('${directory.path}/parent_schools_config.json');
                Map<String, dynamic> localData = {};
                if (await sFile.exists()) {
                  localData = jsonDecode(await sFile.readAsString());
                }
                localData[username] = school;
                await sFile.writeAsString(jsonEncode(localData));
              } catch (e) {
                debugPrint("DEBUG ParentSchoolsScreen: Fallback sync insert failed: $e");
                allSuccessful = false;
              }
            }
          }
        }
        if (allSuccessful) {
          await file.delete();
          debugPrint("DEBUG ParentSchoolsScreen: Local signup cache synced successfully and deleted.");
        } else {
          debugPrint("DEBUG ParentSchoolsScreen: Sync completed, but some items failed. Kept cache file.");
        }
      }
    } catch (e) {
      debugPrint("DEBUG ParentSchoolsScreen: Error in sync local signup cache: $e");
    }
  }

  Future<void> _loadLinkedChildrenAndSchools() async {
    final StringBuffer diag = StringBuffer();
    diag.writeln("=== Parent Schools Screen Diagnostics ===");
    diag.writeln("Time: ${DateTime.now().toLocal().toString()}");
    
    try {
      setState(() => _isLoading = true);
      
      final user = supabase.auth.currentUser;
      if (user == null) {
        diag.writeln("[ERROR] Current user in auth is NULL!");
        setState(() {
          _diagnosticLogs = diag.toString();
          _isLoading = false;
        });
        return;
      }
      
      diag.writeln("[SUCCESS] Logged in user ID: ${user.id}");
      diag.writeln("[SUCCESS] Logged in email: ${user.email}");
      
      // 1. Check parent profile
      diag.writeln("Checking 'profiles' table...");
      try {
        final profileRes = await supabase.from('profiles').select().eq('id', user.id).maybeSingle();
        if (profileRes == null) {
          diag.writeln("[WARNING] No profile row found in database for ID: ${user.id}!");
        } else {
          diag.writeln("[SUCCESS] Profile found: Role: ${profileRes['role']} | Username: ${profileRes['username']} | Level: ${profileRes['level']}");
        }
      } catch (pErr) {
        diag.writeln("[ERROR] Failed to query profiles table: $pErr");
      }

      // 2. Check sync cache
      diag.writeln("Checking local signup cache file...");
      try {
        final directory = await AppSettings.getSafeDirectory();
        final file = File('${directory.path}/parent_signup_cache.json');
        if (await file.exists()) {
          final content = await file.readAsString();
          diag.writeln("[INFO] Local Cache file exists! Content: $content");
          diag.writeln("Running sync cache...");
          await _checkAndSyncLocalSignupCache();
        } else {
          diag.writeln("[INFO] Local Cache file does not exist.");
        }
      } catch (cErr) {
        diag.writeln("[ERROR] Local cache check failed: $cErr");
      }

      // 3. Fetch parent children links
      diag.writeln("Querying 'parent_child_links' table...");
      final response = await supabase
          .from('parent_child_links')
          .select()
          .eq('parent_id', user.id);

      diag.writeln("[SUCCESS] Query complete! Returned ${response.length} rows.");
      if (response.isNotEmpty) {
        diag.writeln("DB links data: $response");
      } else {
        diag.writeln("[INFO] No rows returned for parent_id: ${user.id} (empty).");
      }

      final Map<String, String> localSchools = await _loadSchoolsLocally();
      diag.writeln("Local schools config: $localSchools");

      // Resolve actual student names from profiles & student_records
      final Map<String, String> usernameToFullName = {};
      final List<String> childUsernames = response
          .map((item) => (item['student_username']?.toString() ?? '').trim().toLowerCase())
          .where((uname) => uname.isNotEmpty)
          .toList();

      if (childUsernames.isNotEmpty) {
        // 1. Fetch pre-registration full name from student_records (admission_number matches username)
        try {
          final List<String> upperUsernames = childUsernames.map((u) => u.toUpperCase()).toList();
          final recordsRes = await supabase
              .from('student_records')
              .select('admission_number, full_name')
              .filter('admission_number', 'in', '(${upperUsernames.join(",")})');
          for (var r in recordsRes) {
            final String u = (r['admission_number']?.toString() ?? '').trim().toLowerCase();
            final String fn = (r['full_name']?.toString() ?? '').trim();
            if (u.isNotEmpty && fn.isNotEmpty) {
              usernameToFullName[u] = fn;
            }
          }
        } catch (recErr) {
          diag.writeln("[ERROR] Failed to fetch full names from student_records: $recErr");
        }

        // 2. Fetch registered profiles full name (profiles override student_records)
        try {
          final profilesRes = await supabase
              .from('profiles')
              .select('username, full_name')
              .filter('username', 'in', '(${childUsernames.join(",")})');
          for (var p in profilesRes) {
            final String u = (p['username']?.toString() ?? '').trim().toLowerCase();
            final String fn = (p['full_name']?.toString() ?? '').trim();
            if (u.isNotEmpty && fn.isNotEmpty) {
              usernameToFullName[u] = fn;
            }
          }
        } catch (profErr) {
          diag.writeln("[ERROR] Failed to fetch full names from profiles: $profErr");
        }
      }

      final Map<String, List<Map<String, String>>> groupedSchools = {};

      for (var item in response) {
        final String username = item['student_username']?.toString() ?? '';
        final String level = item['student_level']?.toString() ?? 'Standard 7';
        
        // Dynamic DB column or local fallback
        String school = (item['school']?.toString() ?? localSchools[username]) ?? "";
        if (school.isEmpty) {
          // Dynamic smart default based on starting letter
          school = username.startsWith('a') ? "Greenwood Academy" : "Hillside International";
        }

        if (!groupedSchools.containsKey(school)) {
          groupedSchools[school] = [];
        }
        
        String gradeText = level;
        if (level.toLowerCase().contains("standard")) {
          gradeText = level.replaceAll(RegExp(r'standard', caseSensitive: false), 'Grade');
        }

        final String resolvedFullName = usernameToFullName[username.trim().toLowerCase()] ?? '';
        final String displayName = resolvedFullName.isNotEmpty
            ? '$resolvedFullName ($username)'
            : (username.isNotEmpty ? username[0].toUpperCase() + username.substring(1) : 'Student');

        groupedSchools[school]!.add({
          'name': displayName,
          'grade': gradeText,
        });
      }

      setState(() {
        _schoolsMap = groupedSchools;
        _diagnosticLogs = diag.toString();
      });
    } catch (e) {
      diag.writeln("[CRITICAL ERROR] Error in load linked children: $e");
      setState(() {
        _diagnosticLogs = diag.toString();
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  String _t(String en, String sw) {
    return AppSettings.language.value == 'sw' ? sw : en;
  }

  @override
  Widget build(BuildContext context) {
    const Color primaryBlue = Color(0xFF0D47A1);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: primaryBlue,
        title: Text(
          _t("My Schools", "Shule Zangu"),
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        centerTitle: true,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_alt_1, color: Colors.white),
            tooltip: _t("Link Another Child", "Unganisha Mtoto"),
            onPressed: () => _showAddChildDialog(context),
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            tooltip: _t("Logout", "Kuondoka"),
            onPressed: () async {
              await supabase.auth.signOut();
              if (mounted) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                );
              }
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _schoolsMap.isEmpty
              ? _buildEmptyState(primaryBlue)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // SUB-HEADER INSTRUCTION
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.02),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _t("Select a school to continue", "Chagua shule ili kuendelea"),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _t(
                              "Only Class 4 and Class 7 students in Mathematics are supported in this app.",
                              "Wanafunzi wa Darasa la 4 na la 7 pekee katika Hisabati ndio wanaoungwa mkono kwenye programu hii.",
                            ),
                            style: TextStyle(
                              fontSize: 13, 
                              color: Colors.grey.shade600,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),

                    // LIST OF REGISTERED SCHOOLS CARDS
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: _schoolsMap.keys.length,
                        itemBuilder: (context, index) {
                          final schoolName = _schoolsMap.keys.elementAt(index);
                          final children = _schoolsMap[schoolName]!;
                          final childCount = children.length;

                          return Container(
                            margin: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.03),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Material(
                              color: Colors.transparent,
                              borderRadius: BorderRadius.circular(16),
                              child: InkWell(
                                onTap: () {
                                  Navigator.pushReplacement(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => ParentDashboard(
                                        selectedSchool: schoolName,
                                      ),
                                    ),
                                  );
                                },
                                borderRadius: BorderRadius.circular(16),
                                child: Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          CircleAvatar(
                                            backgroundColor: const Color(0xFFE3F2FD),
                                            radius: 24,
                                            child: const Icon(
                                              Icons.school_rounded,
                                              color: primaryBlue,
                                              size: 24,
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: Text(
                                              schoolName,
                                              style: const TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.w700,
                                                color: Color(0xFF1E293B),
                                              ),
                                            ),
                                          ),
                                          const Icon(
                                            Icons.chevron_right_rounded,
                                            color: Colors.black38,
                                            size: 22,
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      const Divider(height: 1, color: Color(0xFFF1F5F9)),
                                      const SizedBox(height: 12),
                                      
                                      // Children list details
                                      ...children.map((child) => Padding(
                                            padding: const EdgeInsets.only(left: 8, bottom: 8),
                                            child: Row(
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.all(4),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFFF1F5F9),
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: const Icon(
                                                    Icons.face_retouching_natural_rounded,
                                                    size: 14,
                                                    color: Color(0xFF64748B),
                                                  ),
                                                ),
                                                const SizedBox(width: 10),
                                                Text(
                                                  "${child['name']}",
                                                  style: const TextStyle(
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w600,
                                                    color: Color(0xFF334155),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFFE2E8F0),
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: Text(
                                                    child['grade']!,
                                                    style: const TextStyle(
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.bold,
                                                      color: Color(0xFF64748B),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          )),
                                      const SizedBox(height: 10),
                                      
                                      // Count chip
                                      Padding(
                                        padding: const EdgeInsets.only(left: 8),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFECFDF5),
                                            borderRadius: BorderRadius.circular(100),
                                            border: Border.all(color: const Color(0xFFA7F3D0), width: 1),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(Icons.people_alt_rounded, size: 12, color: Color(0xFF059669)),
                                              const SizedBox(width: 6),
                                              Text(
                                                "$childCount ${_t(childCount == 1 ? "child" : "children", childCount == 1 ? "mtoto" : "watoto")}",
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w800,
                                                  color: Color(0xFF059669),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
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
          title: Text(_t("Link Your Child", "Unganisha Mtoto Wako")),
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
                  final studentData = await supabase
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

                  final userId = supabase.auth.currentUser!.id;

                  // 2. Try inserting child using actual level + school
                  try {
                    await supabase
                        .from('parent_child_links')
                        .insert({
                          'parent_id': userId,
                          'student_username': newChild,
                          'student_level': studentData['level'] ?? 'Standard 7',
                          'school': schoolName.isNotEmpty ? schoolName : "Dar es Salaam Academy",
                        });
                  } catch (dbErr) {
                    // Fallback if 'school' column doesn't exist in parent_child_links yet
                    await supabase
                        .from('parent_child_links')
                        .insert({
                          'parent_id': userId,
                          'student_username': newChild,
                          'student_level': studentData['level'] ?? 'Standard 7',
                        });
                    // Save locally
                    try {
                      final directory = await AppSettings.getSafeDirectory();
                      final file = File('${directory.path}/parent_schools_config.json');
                      Map<String, dynamic> localData = {};
                      if (await file.exists()) {
                        localData = jsonDecode(await file.readAsString());
                      }
                      localData[newChild] = schoolName.isNotEmpty ? schoolName : "Dar es Salaam Academy";
                      await file.writeAsString(jsonEncode(localData));
                    } catch (e) {
                      debugPrint("Error writing local register school mapping: $e");
                    }
                  }

                  // Refresh the whole list
                  await _loadLinkedChildrenAndSchools();
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

  Widget _buildEmptyState(Color primaryBlue) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(32.0),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: const BoxDecoration(
                      color: Color(0xFFE8EAF6),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.school_rounded,
                      size: 64,
                      color: Color(0xFF1A237E),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    _t("No Linked Children Found", "Hakuna Watoto Waliounganishwa"),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20, 
                      fontWeight: FontWeight.w800, 
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _t(
                      "Please link your child to view their schools, assignments, and educational progress.",
                      "Tafadhali unganisha mtoto wako ili kuona shule, kazi za nyumbani na maendeleo yao ya kimasomo.",
                    ),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.grey.shade600, 
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryBlue,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      icon: const Icon(Icons.add_rounded, color: Colors.white),
                      label: Text(
                        _t("Link Your First Child", "Unganisha Mtoto Wako wa Kwanza"),
                        style: const TextStyle(
                          color: Colors.white, 
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      onPressed: () => _showAddChildDialog(context),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            
            // Premium Developer & Synchronization Diagnostic Console
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  key: const PageStorageKey("parent_diagnostic_panel"),
                  initiallyExpanded: _showDiagnostics,
                  onExpansionChanged: (expanded) {
                    setState(() {
                      _showDiagnostics = expanded;
                    });
                  },
                  iconColor: Colors.white,
                  collapsedIconColor: Colors.white60,
                  title: Row(
                    children: [
                      const Icon(Icons.bug_report_rounded, color: Colors.amber, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _t("Database Sync & Connection Diagnostics", "Uchunguzi wa Usawazishaji na Hifadhidata"),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: const BoxDecoration(
                        color: Color(0xFF0F172A),
                        borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                "CONSOLE SYSTEM OUTPUT:",
                                style: TextStyle(
                                  color: Colors.amber,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: "monospace",
                                ),
                              ),
                              IconButton(
                                constraints: const BoxConstraints(),
                                padding: EdgeInsets.zero,
                                icon: const Icon(Icons.refresh_rounded, color: Colors.greenAccent, size: 20),
                                onPressed: _loadLinkedChildrenAndSchools,
                                tooltip: "Force Run Diagnostic",
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF020617),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.white10),
                            ),
                            child: Text(
                              _diagnosticLogs,
                              style: const TextStyle(
                                color: Colors.greenAccent,
                                fontSize: 12,
                                fontFamily: "monospace",
                                height: 1.4,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _t(
                              "💡 Tip: If child list is empty, tap 'Link Child' above or press Refresh icon to run live diagnosis.",
                              "💡 Dokezo: Kama orodha iko wazi, gonga 'Unganisha Mtoto' au alama ya kuonyesha upya.",
                            ),
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 11,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
