import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/assessment_engine.dart';
import '../services/auto_grading_service.dart';

class TeacherSubmissionsScreen extends StatefulWidget {
  const TeacherSubmissionsScreen({super.key});

  @override
  State<TeacherSubmissionsScreen> createState() => _TeacherSubmissionsScreenState();
}

class _TeacherSubmissionsScreenState extends State<TeacherSubmissionsScreen> {
  final supabase = Supabase.instance.client;
  List<String> _myClasses = [];
  String _activeFilter = 'All My Classes';
  bool _isLoadingClasses = true;

  @override
  void initState() {
    super.initState();
    _loadTeacherClasses();
  }

  Future<void> _loadTeacherClasses() async {
    try {
      final String teacherId = supabase.auth.currentUser!.id;
      final profile = await supabase.from('profiles').select('level').eq('id', teacherId).single();
      String levelStr = profile['level'] ?? '';
      List<String> joined = [];
      if (levelStr.contains(',')) {
        joined = levelStr.split(',').map((e) => e.trim()).toList();
      } else if (levelStr != 'Teacher' && levelStr.isNotEmpty) {
        joined = [levelStr];
      }
      setState(() {
        _myClasses = joined;
        _isLoadingClasses = false;
      });
    } catch (e) {
      debugPrint("Error loading classes: $e");
      setState(() => _isLoadingClasses = false);
    }
  }

  // EXPERT: Fetch submissions for ONLY THIS teacher's assignments
  Future<List<Map<String, dynamic>>> _fetchSubmissions() async {
    final String teacherId = supabase.auth.currentUser!.id;

    // 1. Fetch submissions joined with homework to check teacher_id and level
    final List<dynamic> submissions = await supabase.from('submissions').select('''
          id,
          content,
          submitted_at,
          profiles:student_id(username, level),
          homework:homework_id(title, teacher_id, level)
        ''').eq('homework.teacher_id', teacherId);

    // 2. Filter by Active Class Selection
    List<dynamic> filtered = submissions;
    if (_activeFilter != 'All My Classes') {
      filtered = submissions.where((s) => s['homework']?['level'] == _activeFilter).toList();
    }

    final List<Map<String, dynamic>> enrichedSubmissions = [];
    for (var sub in filtered) {
      final Map<String, dynamic> enriched = Map<String, dynamic>.from(sub);
      try {
        final resultData = await supabase.from('results').select('id, score, feedback').eq('submission_id', sub['id'].toString()).maybeSingle();
        enriched['results'] = resultData != null ? [resultData] : [];
      } catch (e) {
        enriched['results'] = [];
      }
      enrichedSubmissions.add(enriched);
    }
    return enrichedSubmissions;
  }

  void _showOverrideSheet(BuildContext context, Map<String, dynamic> submission) {
    final List<dynamic> resultsList = submission['results'] ?? [];
    final bool hasResult = resultsList.isNotEmpty;
    final String resultId = hasResult ? resultsList[0]['id'].toString() : '';
    double currentScore = hasResult ? (resultsList[0]['score'] as num).toDouble() : 50;
    final String rawFeedback = hasResult ? (resultsList[0]['feedback'] as String? ?? '') : '';
    final parsed = AutoGradingService.parseFeedback(rawFeedback);
    final TextEditingController commentCtrl = TextEditingController(text: parsed.feedback);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => DraggableScrollableSheet(
          initialChildSize: 0.70, maxChildSize: 0.90, minChildSize: 0.5,
          builder: (_, scrollCtrl) => Container(
            decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
            padding: EdgeInsets.only(left: 24, right: 24, top: 20, bottom: MediaQuery.of(ctx).viewInsets.bottom + 20),
            child: ListView(
              controller: scrollCtrl,
              children: [
                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 20),
                const Text('Override Mark', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                Text(submission['profiles']?['username'] ?? 'Student', style: TextStyle(color: Colors.grey[600], fontSize: 14)),
                const SizedBox(height: 16),
                
                // Student's Submitted Content
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Student Submission:",
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        submission['content'] ?? 'No submission text provided.',
                        style: const TextStyle(fontSize: 14, color: Colors.black54, height: 1.4),
                      ),
                      if (submission['content']?.toString().contains('http') == true) ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                             onPressed: () async {
                              final RegExp urlRegExp = RegExp(
                                r'(https?:\/\/[^\s]+)',
                                caseSensitive: false,
                              );
                              final match = urlRegExp.firstMatch(submission['content'] ?? '');
                              if (match != null) {
                                final urlString = match.group(0);
                                if (urlString != null) {
                                  try {
                                    final uri = Uri.parse(urlString.trim());
                                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                                  } catch (e) {
                                    try {
                                      final uri = Uri.parse(urlString.trim());
                                      await launchUrl(uri);
                                    } catch (e2) {
                                      if (ctx.mounted) {
                                        ScaffoldMessenger.of(ctx).showSnackBar(
                                          SnackBar(content: Text("Could not open attachment link: $e2")),
                                        );
                                      }
                                    }
                                  }
                                }
                              }
                            },
                            icon: const Icon(Icons.open_in_new, size: 18, color: Colors.white),
                            label: const Text("Open Attachment Link", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2E7D32),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                
                // Parent's Observation if present
                if (parsed.parentFeedback.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.comment_outlined, color: Colors.orange.shade800, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              "Parent Observation / Recommendation:",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: Colors.orange.shade900,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          parsed.parentFeedback,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.orange.shade900,
                            height: 1.4,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                
                const SizedBox(height: 24),
                Text('New Score: ${currentScore.toInt()}%', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                Slider(
                  value: currentScore, min: 0, max: 100, divisions: 100,
                  activeColor: AssessmentEngine.colorForPercent(currentScore),
                  onChanged: (v) => setSheet(() => currentScore = v),
                ),
                TextField(controller: commentCtrl, maxLines: 3, decoration: InputDecoration(labelText: 'Teacher Comment', filled: true, fillColor: Colors.grey[50], border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity, height: 52,
                  child: ElevatedButton(
                    onPressed: () async {
                      final result = AssessmentEngine.evaluate(correctCount: currentScore.toInt(), totalQuestions: 100, topic: submission['homework']?['title'] ?? '', wrongIndexes: []);
                      try {
                        final String teacherComment = commentCtrl.text.trim().isEmpty 
                            ? parsed.feedback 
                            : commentCtrl.text.trim();

                        if (hasResult) {
                          final String serialized = AutoGradingService.serializeFeedback(
                            feedback: teacherComment,
                            recommendation: parsed.recommendation,
                            revisionQuestions: parsed.revisionQuestions,
                            parentFeedback: parsed.parentFeedback,
                          );
                          await supabase.from('results').update({'score': currentScore, 'feedback': serialized}).eq('id', resultId);
                        } else {
                          final String serialized = AutoGradingService.serializeFeedback(
                            feedback: teacherComment,
                            recommendation: result.recommendation,
                            revisionQuestions: result.revisionQuestions ?? [],
                            parentFeedback: '',
                          );
                          await supabase.from('results').insert({'submission_id': submission['id'].toString(), 'score': currentScore, 'feedback': serialized});
                        }
                        if (ctx.mounted) { Navigator.pop(ctx); setState(() {}); }
                      } catch (e) { debugPrint("Error: $e"); }
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0D47A1), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                    child: const Text('Save Override', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingClasses) return const Center(child: CircularProgressIndicator());
    const primaryBlue = Color(0xFF0D47A1);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: Column(
        children: [
          // EXPERT: CLASS SWITCHER FOR SUBMISSIONS
          if (_myClasses.isNotEmpty)
            Container(
              height: 60,
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 15),
                children: [
                  _buildFilterChip('All My Classes', primaryBlue),
                  ..._myClasses.map((lvl) => _buildFilterChip(lvl, primaryBlue)),
                ],
              ),
            ),

          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _fetchSubmissions(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                final submissions = snapshot.data ?? [];
                if (submissions.isEmpty) return Center(child: Text(_activeFilter == 'All My Classes' ? 'No submissions yet.' : 'No submissions for $_activeFilter'));

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  itemCount: submissions.length,
                  itemBuilder: (context, index) {
                    final item = submissions[index];
                    final String studentName = item['profiles']?['username'] ?? 'Unknown';
                    final String homeworkTitle = item['homework']?['title'] ?? 'Unknown';
                    final String homeworkLevel = item['homework']?['level'] ?? '';
                    final List<dynamic> results = item['results'] ?? [];
                    final bool isGraded = results.isNotEmpty;
                    final double score = isGraded ? (results[0]['score'] as num?)?.toDouble() ?? 0 : 0;
                    final String grade = isGraded ? AssessmentEngine.evaluate(correctCount: score.toInt(), totalQuestions: 100, topic: homeworkTitle, wrongIndexes: []).grade : '?';

                    bool hasParentNote = false;
                    if (isGraded) {
                      final rawFeedback = results[0]['feedback'] as String? ?? '';
                      final parsed = AutoGradingService.parseFeedback(rawFeedback);
                      if (parsed.parentFeedback.isNotEmpty) {
                        hasParentNote = true;
                      }
                    }

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: Colors.grey.shade200)),
                      child: ListTile(
                        leading: CircleAvatar(backgroundColor: primaryBlue.withOpacity(0.1), child: const Icon(Icons.person, color: primaryBlue)),
                        title: Text(studentName, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("$homeworkTitle ($homeworkLevel)"),
                            if (hasParentNote) ...[
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.orange.shade50,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.orange.shade200, width: 0.5),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.comment, size: 10, color: Colors.orange.shade800),
                                    const SizedBox(width: 4),
                                    Text(
                                      "Parent Note",
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.orange.shade800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                        trailing: isGraded 
                          ? _gradeBadge(grade, AssessmentEngine.colorForPercent(score))
                          : const Text("PENDING", style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 10)),
                        onTap: () => _showOverrideSheet(context, item),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, Color color) {
    bool isActive = _activeFilter == label;
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: ChoiceChip(
        label: Text(label),
        selected: isActive,
        onSelected: (val) => setState(() => _activeFilter = label),
        selectedColor: color,
        labelStyle: TextStyle(color: isActive ? Colors.white : Colors.black87, fontWeight: isActive ? FontWeight.bold : FontWeight.normal),
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }

  Widget _gradeBadge(String grade, Color color) {
    return Container(
      width: 32, height: 32,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(grade, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
    );
  }
}
