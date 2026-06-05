import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'login_screen.dart';
import 'teacher_homework_screen.dart';
import 'teacher_submissions_screen.dart';
import 'teacher_reports_screen.dart';
import 'teacher_upload_homework_sheet.dart';
import 'teacher_settings_screen.dart';
import 'teacher_chat_screen.dart';
import '../main.dart';

class TeacherDashboard extends StatefulWidget {
  final String userName;
  const TeacherDashboard({super.key, this.userName = "Mwalimu"});

  @override
  State<TeacherDashboard> createState() => _TeacherDashboardState();
}

class _TeacherDashboardState extends State<TeacherDashboard> {
  final supabase = Supabase.instance.client;
  int _currentIndex = 0;
  Future<Map<String, num>>? _statsFuture;
  List<String> _myClasses = [];

  @override
  void initState() {
    super.initState();
    _loadTeacherSettings();
  }

  Future<void> _loadTeacherSettings() async {
    try {
      final String teacherId = supabase.auth.currentUser!.id;
      final profile = await supabase.from('profiles').select('username, level').eq('id', teacherId).single();
      String levelStr = profile['level'] ?? '';
      final String uName = profile['username'] ?? '';
      if (levelStr.contains(',')) {
        _myClasses = levelStr.split(',').map((e) => e.trim()).toList();
      } else if (levelStr != 'Teacher' && levelStr.isNotEmpty) {
        _myClasses = [levelStr];
      }

      // Fallback: If _myClasses is empty or only 'Teacher', resolve from teacher_records using teacher's username
      if ((_myClasses.isEmpty || levelStr == 'Teacher') && uName.isNotEmpty) {
        try {
          final rec = await supabase
              .from('teacher_records')
              .select('classes')
              .eq('employee_number', uName.toUpperCase())
              .maybeSingle();
          if (rec != null && rec['classes'] != null) {
            final List<dynamic> cls = rec['classes'] as List<dynamic>;
            _myClasses = cls.map((e) => e.toString()).toList();
            // Update profiles table level field in the DB to persist classes
            if (_myClasses.isNotEmpty) {
              await supabase.from('profiles').update({'level': _myClasses.join(',')}).eq('id', teacherId);
            }
          }
        } catch (err) {
          debugPrint("Failed to fetch classes from teacher_records: $err");
        }
      }
      _refreshStats();
    } catch (e) {
      debugPrint("Error loading settings: $e");
    }
  }

  void _refreshStats() {
    setState(() { _statsFuture = _fetchTeacherStats(); });
  }

  Future<Map<String, num>> _fetchTeacherStats() async {
    try {
      final String teacherId = supabase.auth.currentUser!.id;
      final homeworkRes = await supabase.from('homework').select('id, level').eq('teacher_id', teacherId);
      final homeworkList = homeworkRes as List;
      final int homeworkCreated = homeworkList.length;

      int totalStudents = 0;
      if (_myClasses.isNotEmpty) {
        final studentsRes = await supabase.from('profiles').select('id, level').ilike('role', 'student').eq('status', 'active');
        final List studentList = studentsRes as List;
        totalStudents = studentList.where((s) => _myClasses.contains(s['level'].toString())).length;
      }

      int totalPending = 0;
      if (homeworkList.isNotEmpty && _myClasses.isNotEmpty) {
        final allSubRes = await supabase.from('submissions').select('homework_id');
        final allSubList = allSubRes as List;
        final allStudentsRes = await supabase.from('profiles').select('level').ilike('role', 'student').eq('status', 'active');
        final allStudentsList = allStudentsRes as List;

        for (var hw in homeworkList) {
          final int studentsInLevel = allStudentsList.where((s) => s['level'].toString() == hw['level'].toString()).length;
          final int actualSubmissions = allSubList.where((s) => s['homework_id'].toString() == hw['id'].toString()).length;
          int missing = studentsInLevel - actualSubmissions;
          if (missing > 0) totalPending += missing;
        }
      }

      int totalSubmissions = 0;
      if (homeworkList.isNotEmpty) {
        final List homeworkIds = homeworkList.map((h) => h['id'].toString()).toList();
        final allSubRes = await supabase.from('submissions').select('homework_id');
        final allSubList = allSubRes as List;
        totalSubmissions = allSubList.where((s) => homeworkIds.contains(s['homework_id'].toString())).length;
      }

      final resultsRes = await supabase.from('results').select('''
        score, submissions!inner(homework!inner(teacher_id))
      ''').eq('submissions.homework.teacher_id', teacherId);

      double averageScore = 0;
      final resultsList = resultsRes as List;
      if (resultsList.isNotEmpty) {
        double totalScore = 0;
        for (var r in resultsList) { totalScore += (r['score'] as num).toDouble(); }
        averageScore = totalScore / resultsList.length;
      }

      return {
        'totalStudents': totalStudents,
        'homeworkCreated': homeworkCreated,
        'pendingSubmissions': totalPending,
        'averageClassScore': averageScore.round(),
        'totalSubmissions': totalSubmissions,
      };
    } catch (e) {
      return {'totalStudents': 0, 'homeworkCreated': 0, 'pendingSubmissions': 0, 'averageClassScore': 0, 'totalSubmissions': 0};
    }
  }

  void _showClassManagementDialog() {
    List<String> tempSelection = List.from(_myClasses);
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text("Manage Your Classes"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: ['Standard 4', 'Standard 7'].map((level) {
              bool isSelected = tempSelection.contains(level);
              return CheckboxListTile(
                title: Text(level), value: isSelected,
                onChanged: (val) {
                  setDialogState(() { if (val!) tempSelection.add(level); else tempSelection.remove(level); });
                },
              );
            }).toList(),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
            ElevatedButton(
              onPressed: () async {
                final String teacherId = supabase.auth.currentUser!.id;
                await supabase.from('profiles').update({'level': tempSelection.join(',')}).eq('id', teacherId);
                if (mounted) { setState(() => _myClasses = tempSelection); _refreshStats(); Navigator.pop(ctx); }
              },
              child: const Text("Save"),
            ),
          ],
        ),
      ),
    );
  }

  void _showStudentsList() {
    if (_myClasses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("You are not managing any classes right now.")));
      return;
    }
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return _StudentsListSheet(myClasses: _myClasses);
      }
    );
  }

  void _showRecentHomework() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return TeacherUploadHomeworkSheet(myClasses: _myClasses);
      }
    );
    _refreshStats();
  }

  String _t(String en, String sw) {
    return AppSettings.language.value == 'Kiswahili' ? sw : en;
  }

  AppBar _buildAppBar(BuildContext context) {
    final titles = [
      _t("Teacher Portal", "Tovuti ya Mwalimu"),
      _t("Homework Management", "Usimamizi wa Kazi za Nyumbani"),
      _t("Academic Reports", "Ripoti za Kitaaluma"),
      _t("App Settings", "Mipangilio ya Programu"),
      _t("Student Submissions", "Kazi Zilizowasilishwa")
    ];
    return AppBar(
      title: Text(titles[_currentIndex], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      backgroundColor: const Color(0xFF0D47A1),
      elevation: 0,
      automaticallyImplyLeading: false,
      actions: (_currentIndex == 3 || _currentIndex == 4)
          ? null
          : [
              if (_currentIndex == 0) ...[
                IconButton(
                  icon: const Icon(Icons.chat_bubble_outline, color: Colors.white),
                  tooltip: _t("Messages", "Mawasiliano"),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => TeacherChatPortal(
                          teacherName: widget.userName,
                          myClasses: _myClasses,
                        ),
                      ),
                    );
                  },
                ),
                IconButton(icon: const Icon(Icons.refresh, color: Colors.white), onPressed: _refreshStats),
              ],
              PopupMenuButton<String>(
                icon: const Icon(Icons.account_circle, color: Colors.white, size: 30),
                onSelected: (value) {
                  if (value == 'logout') _showLogoutDialog(context);
                  if (value == 'classes') _showClassManagementDialog();
                },
                itemBuilder: (BuildContext context) => [
                  PopupMenuItem(value: 'profile', child: Row(children: [const Icon(Icons.person, color: Colors.black54), const SizedBox(width: 10), Text(widget.userName)])),
                  PopupMenuItem(value: 'classes', child: Row(children: [const Icon(Icons.class_outlined, color: Colors.blue), const SizedBox(width: 10), Text(_t("Manage My Classes", "Dhibiti Madarasa Yangu"))])),
                  const PopupMenuDivider(),
                  PopupMenuItem(value: 'logout', child: Row(children: [const Icon(Icons.logout, color: Colors.redAccent), const SizedBox(width: 10), Text(_t("Logout", "Toka"))])),
                ],
              ),
            ],
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text("Logout"),
          content: Text("Log out ${widget.userName}?"),
          actions: [
            TextButton(child: const Text("Cancel"), onPressed: () => Navigator.pop(dialogContext)),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              child: const Text("Logout", style: TextStyle(color: Colors.white)),
              onPressed: () {
                Navigator.pop(dialogContext);
                Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const LoginScreen()), (route) => false);
              },
            ),
          ],
        );
      },
    );
  }

  Future<bool?> _showExitConfirmationDialog(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.exit_to_app, color: Color(0xFF0D47A1)),
            SizedBox(width: 10),
            Text("Exit App?"),
          ],
        ),
        content: const Text("Are you sure you want to close the homework support system?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD32F2F),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text("Exit", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const Color primaryBlue = Color(0xFF0D47A1);
    final List<Widget> _screens = [
      _buildHomeContent(primaryBlue),
      const TeacherHomeworkScreen(),
      const TeacherReportsScreen(),
      const TeacherSettingsScreen(),
      const TeacherSubmissionsScreen(),
    ];

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
              _refreshStats();
            } else {
              final shouldExit = await _showExitConfirmationDialog(context);
              if (shouldExit == true && context.mounted) {
                await SystemNavigator.pop();
              }
            }
          },
          child: Scaffold(
            backgroundColor: const Color(0xFFF8F9FA),
            appBar: _buildAppBar(context),
            body: _screens[_currentIndex],
            bottomNavigationBar: BottomNavigationBar(
              currentIndex: _currentIndex > 3 ? 0 : _currentIndex,
              onTap: (index) {
                setState(() => _currentIndex = index);
                if (index == 0) _refreshStats();
              },
              type: BottomNavigationBarType.fixed,
              selectedItemColor: primaryBlue,
              unselectedItemColor: Colors.grey,
              items: [
                BottomNavigationBarItem(icon: const Icon(Icons.dashboard_outlined), label: _t("Dashboard", "Dashibodi")),
                BottomNavigationBarItem(icon: const Icon(Icons.book_outlined), label: _t("Homework", "Kazi")),
                BottomNavigationBarItem(icon: const Icon(Icons.bar_chart_outlined), label: _t("Reports", "Ripoti")),
                BottomNavigationBarItem(icon: const Icon(Icons.settings_outlined), label: _t("Settings", "Mipangilio")),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHomeContent(Color primaryBlue) {
    return RefreshIndicator(
      onRefresh: () async => _refreshStats(),
      child: FutureBuilder<Map<String, num>>(
        future: _statsFuture,
        builder: (context, snapshot) {
          final stats = snapshot.data ?? {'totalStudents': 0, 'homeworkCreated': 0, 'pendingSubmissions': 0, 'averageClassScore': 0, 'totalSubmissions': 0};
          final bool isLoading = snapshot.connectionState == ConnectionState.waiting;

          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_t("Welcome, ${widget.userName}", "Karibu, ${widget.userName}"), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                  Text(_myClasses.isEmpty ? _t("No active classes selected", "Hakuna madarasa yaliyochaguliwa") : "${_t("Managing", "Kusimamia")}: ${_myClasses.join(', ')}", style: const TextStyle(color: Colors.grey, fontSize: 16)),
                  const SizedBox(height: 25),
                  
                  GridView.count(
                    crossAxisCount: 2,
                    crossAxisSpacing: 15,
                    mainAxisSpacing: 15,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    childAspectRatio: 1.3,
                    children: [
                      GestureDetector(
                        onTap: _showStudentsList,
                        child: _statCard(_t("Your Students", "Wanafunzi Wako"), isLoading ? "..." : "${stats['totalStudents']}", Icons.people, Colors.blue),
                      ),
                      GestureDetector(
                        onTap: _showRecentHomework,
                        child: _statCard(_t("Your Homework", "Kazi za Nyumbani"), isLoading ? "..." : "${stats['homeworkCreated']}", Icons.menu_book, Colors.purple),
                      ),
                      GestureDetector(onTap: () => setState(() => _currentIndex = 2), child: _statCard(_t("Pending", "Zinazosubiri"), isLoading ? "..." : "${stats['pendingSubmissions']}", Icons.pending_actions, Colors.red)),
                      GestureDetector(
                        onTap: () => setState(() => _currentIndex = 4),
                        child: _statCard(_t("Submissions", "Kazi Zilizowasilishwa"), isLoading ? "..." : "${stats['totalSubmissions']}", Icons.assignment_turned_in, Colors.green, actionLabel: _t("View All", "Ona Zote")),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 30),
                  Text(_t("Recent Performance", "Matokeo ya Hivi Karibuni"), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const CircleAvatar(backgroundColor: Color(0xFFE8F5E9), child: Icon(Icons.trending_up, color: Colors.green)),
                            const SizedBox(width: 15),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(_t("Class Progress", "Maendeleo ya Darasa"), style: const TextStyle(fontWeight: FontWeight.bold)),
                                  Text(isLoading ? _t("Calculating...", "Inahesabu...") : _t("Your students are averaging ${stats['averageClassScore']}% across all tasks.", "Wanafunzi wako wanapata wastani wa ${stats['averageClassScore']}% kwenye kazi zote."), style: TextStyle(color: Colors.grey[600], fontSize: 14)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 30),
                        GestureDetector(
                          onTap: () => setState(() => _currentIndex = 2), // Sends to reports
                          child: Row(
                            children: [
                              const CircleAvatar(backgroundColor: Color(0xFFFFF3E0), child: Icon(Icons.notification_important, color: Colors.orange)),
                              const SizedBox(width: 15),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(_t("Missing Work", "Kazi Zisizowasilishwa"), style: const TextStyle(fontWeight: FontWeight.bold)),
                                    Text(isLoading ? _t("Checking...", "Inakagua...") : _t("There are ${stats['pendingSubmissions']} total assignments missing. Click to see WHO.", "Kuna jumla ya kazi ${stats['pendingSubmissions']} ambazo hazijawasilishwa. Bofya kuona NANI."), style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 14)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _statCard(String title, String value, IconData icon, Color color, {String? actionLabel}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 4))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(title, style: TextStyle(color: Colors.grey[600], fontSize: 11, fontWeight: FontWeight.w600)), Icon(icon, color: color.withOpacity(0.7), size: 18)]),
          const Spacer(),
          Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
          if (actionLabel != null) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text("$actionLabel ", style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
                Icon(Icons.arrow_forward_ios, size: 8, color: color),
              ],
            )
          ]
        ],
      ),
    );
  }
}

class _StudentsListSheet extends StatefulWidget {
  final List<String> myClasses;
  const _StudentsListSheet({required this.myClasses});

  @override
  State<_StudentsListSheet> createState() => _StudentsListSheetState();
}

class _StudentsListSheetState extends State<_StudentsListSheet> {
  final supabase = Supabase.instance.client;
  bool _isLoading = true;
  List<Map<String, dynamic>> _students = [];
  String _activeFilter = 'All My Classes';

  @override
  void initState() {
    super.initState();
    _fetchStudents();
  }

  Future<void> _fetchStudents() async {
    try {
       final res = await supabase.from('profiles').select('full_name, username, level').ilike('role', 'student').eq('status', 'active');
       final List<dynamic> data = res as List<dynamic>;
       final filtered = data.where((s) => widget.myClasses.contains(s['level'].toString())).map((e) => e as Map<String, dynamic>).toList();
       
       // Sort by level then name
       filtered.sort((a, b) {
          int levelCmp = a['level'].toString().compareTo(b['level'].toString());
          if (levelCmp != 0) return levelCmp;
          return (a['full_name'] ?? '').toString().compareTo((b['full_name'] ?? '').toString());
       });
       
       if (mounted) {
         setState(() {
           _students = filtered;
           _isLoading = false;
         });
       }
    } catch (e) {
       if (mounted) {
         setState(() => _isLoading = false);
       }
    }
  }

  Widget _buildFilterChip(String label, Color color) {
    bool isActive = _activeFilter == label;
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: ChoiceChip(
        label: Text(label), selected: isActive,
        onSelected: (val) => setState(() => _activeFilter = label),
        selectedColor: color,
        labelStyle: TextStyle(color: isActive ? Colors.white : Colors.black87, fontWeight: isActive ? FontWeight.bold : FontWeight.normal),
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
     const primaryBlue = Color(0xFF0D47A1);
     
     List<Map<String, dynamic>> displayStudents = _students;
     if (_activeFilter != 'All My Classes') {
       displayStudents = displayStudents.where((s) => s['level'] == _activeFilter).toList();
     }

     return Container(
       padding: const EdgeInsets.all(20),
       height: MediaQuery.of(context).size.height * 0.7,
       child: Column(
         crossAxisAlignment: CrossAxisAlignment.start,
         children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Your Students", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                )
              ],
            ),
            if (widget.myClasses.isNotEmpty)
              Container(
                height: 50,
                margin: const EdgeInsets.only(top: 10, bottom: 10),
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _buildFilterChip('All My Classes', primaryBlue),
                    ...widget.myClasses.map((lvl) => _buildFilterChip(lvl, primaryBlue)),
                  ],
                ),
              ),
            if (_isLoading)
               const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (displayStudents.isEmpty)
               const Expanded(child: Center(child: Text("No students found in this category.")))
            else
               Expanded(
                 child: ListView.separated(
                   itemCount: displayStudents.length,
                   separatorBuilder: (context, index) => const Divider(),
                   itemBuilder: (context, index) {
                      final student = displayStudents[index];
                      final isStd7 = student['level'] == 'Standard 7';
                      return ListTile(
                         leading: CircleAvatar(
                           backgroundColor: isStd7 ? Colors.blue[100] : Colors.green[100],
                           child: Icon(Icons.person, color: isStd7 ? Colors.blue : Colors.green),
                         ),
                         title: Text(student['full_name'] ?? student['username'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.bold)),
                         subtitle: Text("Level: ${student['level'] ?? ''}"),
                      );
                   }
                 )
               )
         ]
       )
     );
  }
}
