import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:homework_support_system/screens/math_quiz_screen.dart';
import 'package:homework_support_system/screens/results_screen.dart';
import 'package:homework_support_system/screens/homework_screen.dart';
import 'package:homework_support_system/screens/login_screen.dart';
import 'package:homework_support_system/screens/student_settings_screen.dart';
import '../services/db_helper.dart';
import '../services/auto_grading_service.dart';
import '../main.dart';

class StudentDashboard extends StatefulWidget {
  final String userName;
  final String studentLevel;

  const StudentDashboard({
    super.key,
    required this.userName,
    required this.studentLevel,
  });

  @override
  State<StudentDashboard> createState() => _StudentDashboardState();
}

class _StudentDashboardState extends State<StudentDashboard> {
  final supabase = Supabase.instance.client;
  int _currentIndex = 0;

  // Real-time stats
  int _pendingCount = 0;
  double _avgScore = 0.0;
  String _latestRemark = "No remarks yet.";
  String _remarkTitle = "Keep Practicing";
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchDashboardStats();
  }

  Future<void> _fetchDashboardStats() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    final String userId = supabase.auth.currentUser!.id;

    try {
      // 1. Fetch total available homework for this student's level
      final homeworkRes = await supabase
          .from('homework')
          .select('id')
          .eq('level', widget.studentLevel);
      final List allHomeworkIds = (homeworkRes as List).map((h) => h['id']?.toString()).whereType<String>().toList();

      // 2. Fetch submissions made by this student
      final submissionsRes = await supabase
          .from('submissions')
          .select('id, homework_id')
          .eq('student_id', userId);
      final List submissionsList = submissionsRes as List;

      // 3. Fetch results for this student
      final resultsRes = await supabase
          .from('results')
          .select('score, feedback, submission_id, submissions!inner(student_id)')
          .eq('submissions.student_id', userId)
          .order('created_at', ascending: false);
      final List resultsList = resultsRes as List;

      // A submission is only fully completed if it has a graded result
      final resultSubmissionIds = resultsList
          .map((r) => r['submission_id']?.toString())
          .where((id) => id != null)
          .toSet();

      final completedHomeworkIds = submissionsList
          .where((s) => resultSubmissionIds.contains(s['id']?.toString()))
          .map((s) => s['homework_id']?.toString())
          .where((id) => id != null)
          .toList();

      // 4. Calculate pending count
      int pending = 0;
      for (var id in allHomeworkIds) {
        if (!completedHomeworkIds.contains(id)) {
          pending++;
        }
      }

      double totalScore = 0;
      String latestRemark = "Welcome! Complete your first homework to see feedback here.";
      String remarkTitle = "Ready to start?";

      if (resultsList.isNotEmpty) {
        for (var r in resultsList) {
          totalScore += (r['score'] as num).toDouble();
        }
        _avgScore = totalScore / resultsList.length;
        final String rawFeedback = resultsList.first['feedback'] ?? "Keep up the good work!";
        latestRemark = AutoGradingService.parseFeedback(rawFeedback).feedback;
        remarkTitle = _avgScore >= 80 ? "Excellent Progress!" : "Good Effort!";
      } else {
        _avgScore = 0.0;
      }

      if (mounted) {
        setState(() {
          _pendingCount = pending;
          _latestRemark = latestRemark;
          _remarkTitle = remarkTitle;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching dashboard stats: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _t(String en, String sw) {
    return AppSettings.language.value == 'Kiswahili' ? sw : en;
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(_t("Logout", "Kuondoka")),
          content: Text(_t("Log out ${widget.userName} to switch accounts?", "Je, unataka kuondoka kwenye akaunti ya ${widget.userName}?")),
          actions: [
            TextButton(
              child: Text(_t("Cancel", "Ghairi")),
              onPressed: () => Navigator.pop(context),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(_t("Logout", "Toka"), style: const TextStyle(color: Colors.white)),
              onPressed: () async {
                await supabase.auth.signOut();
                if (context.mounted) {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (context) => const LoginScreen()),
                    (route) => false,
                  );
                }
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
    const Color accentOrange = Color(0xFFE65100);

    final List<Widget> screens = [
      _buildMainDashboard(primaryBlue, accentOrange),
      HomeworkScreen(studentLevel: widget.studentLevel),
      const ResultsScreen(),
      StudentSettingsScreen(studentLevel: widget.studentLevel),
      MathQuizScreen(onQuit: () => setState(() => _currentIndex = 0)), // Sub-screen Index 4
    ];

    final appBarTitles = [
      _t("MathSupport Student", "Programu ya Hesabu"),
      _t("Homework Portal", "Portal ya Kazi za Nyumbani"),
      _t("My Performance", "Matokeo Yangu"),
      _t("App Settings", "Mipangilio ya Programu"),
      _t("Math Quiz Challenge", "Jaribio la Hesabu"),
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
              _fetchDashboardStats();
            } else {
              final shouldExit = await _showExitConfirmationDialog(context);
              if (shouldExit == true && context.mounted) {
                await SystemNavigator.pop();
              }
            }
          },
          child: Scaffold(
            backgroundColor: const Color(0xFFF8F9FA),
            appBar: AppBar(
              title: Text(
                appBarTitles[_currentIndex],
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              backgroundColor: primaryBlue,
              elevation: 0,
              actions: (_currentIndex == 3 || _currentIndex == 4)
                  ? null
                  : [
                      IconButton(
                        onPressed: _fetchDashboardStats,
                        icon: const Icon(Icons.refresh, color: Colors.white),
                      ),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.account_circle, color: Colors.white, size: 30),
                        onSelected: (value) {
                          if (value == 'logout') _showLogoutDialog(context);
                        },
                        itemBuilder: (BuildContext context) => [
                          PopupMenuItem(
                            value: 'profile',
                            child: Row(
                              children: [
                                const Icon(Icons.person, color: Colors.black54),
                                const SizedBox(width: 10),
                                Text(widget.userName),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'logout',
                            child: Row(
                              children: [
                                const Icon(Icons.logout, color: Colors.redAccent),
                                const SizedBox(width: 10),
                                Text(_t("Logout", "Toka"), style: const TextStyle(color: Colors.redAccent)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
            ),
            body: screens[_currentIndex],
            bottomNavigationBar: Container(
              decoration: const BoxDecoration(
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, spreadRadius: 1)],
              ),
              child: BottomNavigationBar(
                currentIndex: _currentIndex > 3 ? 0 : _currentIndex,
                onTap: (index) {
                  setState(() => _currentIndex = index);
                  if (index == 0) _fetchDashboardStats();
                },
                type: BottomNavigationBarType.fixed,
                selectedItemColor: primaryBlue,
                unselectedItemColor: Colors.grey,
                showUnselectedLabels: true,
                items: [
                  BottomNavigationBarItem(icon: const Icon(Icons.home_outlined), label: _t("Home", "Nyumbani")),
                  BottomNavigationBarItem(icon: const Icon(Icons.menu_book_outlined), label: _t("Homework", "Kazi")),
                  BottomNavigationBarItem(icon: const Icon(Icons.insights_outlined), label: _t("Results", "Matokeo")),
                  BottomNavigationBarItem(icon: const Icon(Icons.settings_outlined), label: _t("Settings", "Mipangilio")),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMainDashboard(Color primaryBlue, Color accentOrange) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _fetchDashboardStats,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(primaryBlue),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Text(
                _t("Hello, ${widget.userName}! Here is your overview:", "Habari, ${widget.userName}! Huu hapa muhtasari wako:"),
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.blueGrey[700],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
              child: Text(
                _t("Overview", "Muhtasari"),
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      _t("Pending\nTasks", "Kazi\nZilizobaki"),
                      _pendingCount.toString(),
                      Icons.assignment_late,
                      _pendingCount > 0 ? Colors.redAccent : Colors.green,
                      onTap: () {
                        setState(() {
                          _currentIndex = 1;
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: _buildStatCard(
                      _t("Average\nScore", "Wastani wa\nAlama"),
                      "${_avgScore.toInt()}%",
                      Icons.insights,
                      accentOrange,
                      onTap: () {
                        setState(() {
                          _currentIndex = 2; // Index of ResultsScreen
                        });
                      },
                    ),
                  ),
                ],
              ),
            ),
            
            // QUICK QUIZ BANNER (KHAN ACADEMY STYLE BANNER)
            const SizedBox(height: 25),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFE65100), Color(0xFFFF8F00)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFE65100).withOpacity(0.25),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    )
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => setState(() => _currentIndex = 4),
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Row(
                        children: [
                          const CircleAvatar(
                            backgroundColor: Colors.white24,
                            radius: 25,
                            child: Icon(Icons.psychology, color: Colors.white, size: 30),
                          ),
                          const SizedBox(width: 15),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _t("Math Quiz", "Jaribio la Hesabu"),
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _t("Test your skills and boost your scores!", "Pima ujuzi wako na uongeze alama zako!"),
                                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 18),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(20, 30, 20, 10),
              child: Text(
                _t("Teacher's Remarks", "Maoni ya Mwalimu"),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10)],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.chat_bubble_outline, size: 20, color: Colors.blue),
                        const SizedBox(width: 10),
                        Text(
                          _remarkTitle,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _latestRemark,
                      style: TextStyle(color: Colors.grey[700], height: 1.5),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color, {VoidCallback? onTap}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 4)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          splashColor: color.withOpacity(0.1),
          highlightColor: color.withOpacity(0.05),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: color.withOpacity(0.1),
                  radius: 20,
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(height: 15),
                Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                const SizedBox(height: 5),
                Text(
                  title,
                  style: TextStyle(color: Colors.grey[500], fontSize: 12, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 15, 20, 20),
      decoration: BoxDecoration(
        color: color,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.studentLevel,
            style: const TextStyle(
              color: Color.fromARGB(255, 181, 213, 255),
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(_t("Math Exam Prep", "Maandalizi ya Mtihani wa Hesabu"), style: TextStyle(color: Colors.blue[100], fontSize: 14)),
        ],
      ),
    );
  }
}
