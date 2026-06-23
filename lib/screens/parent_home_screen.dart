import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auto_grading_service.dart';
import '../services/assessment_engine.dart';
import '../main.dart';

class ParentHomeScreen extends StatefulWidget {
  final String childName;
  final String level;

  const ParentHomeScreen({super.key, required this.childName, required this.level});

  @override
  State<ParentHomeScreen> createState() => _ParentHomeScreenState();
}

class _ParentHomeScreenState extends State<ParentHomeScreen> {
  Future<Map<String, dynamic>>? _dataFuture;

  @override
  void initState() {
    super.initState();
    _dataFuture = _fetchDynamicData();
  }

  @override
  void didUpdateWidget(covariant ParentHomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.childName != widget.childName || oldWidget.level != widget.level) {
      setState(() {
        _dataFuture = _fetchDynamicData();
      });
    }
  }

  Future<Map<String, dynamic>> _fetchDynamicData() async {
    if (widget.childName.isEmpty) return {"fullName": widget.childName, "average": "0%", "completed": "0", "recent": [], "missing": []};

    final supabase = Supabase.instance.client;
    try {
      // 1. Fetch child ID first
      final studentRes = await supabase.from('profiles').select('id, full_name').eq('username', widget.childName).single();
      final String studentId = studentRes['id'];
      final String fullName = studentRes['full_name'] ?? widget.childName;

      // 2. Fetch all results for stats
      final results = await supabase.from('results').select('id, score, feedback, submissions!inner(homework!inner(title))')
          .eq('submissions.student_id', studentId).order('created_at', ascending: false);

      // 3. Fetch all homework for this child's level to find "Missing" work
      final homeworkRes = await supabase.from('homework').select('id, title').eq('level', widget.level);
      final List hwList = homeworkRes as List;

      // 4. Fetch child's submissions to compare
      final subRes = await supabase.from('submissions').select('homework_id').eq('student_id', studentId);
      final List subList = subRes as List;

      // 5. Calculate Missing Work
      final List<String> missing = [];
      for (var hw in hwList) {
        bool done = subList.any((s) => s['homework_id'].toString() == hw['id'].toString());
        if (!done) missing.add(hw['title']);
      }

      double totalScore = 0;
      final List recent = results.take(3).toList();
      for (var row in results) { totalScore += (row['score'] as num).toDouble(); }

      final avg = results.isEmpty ? 0 : (totalScore / results.length).toInt();
      return {
        "fullName": fullName,
        "average": "$avg%",
        "completed": subList.length.toString(),
        "recent": recent,
        "missing": missing,
      };
    } catch (e) {
      debugPrint("Error: $e");
      return {"fullName": widget.childName, "average": "N/A", "completed": "N/A", "recent": [], "missing": []};
    }
  }

  String _t(String en, String sw) {
    return AppSettings.language.value == 'Kiswahili' ? sw : en;
  }

  @override
  Widget build(BuildContext context) {
    const Color primaryBlue = Color(0xFF0D47A1);

    return FutureBuilder<Map<String, dynamic>>(
      future: _dataFuture,
      builder: (context, snapshot) {
        final data = snapshot.data ?? {"fullName": widget.childName, "average": "...", "completed": "...", "recent": [], "missing": []};
        final String displayName = data['fullName'] ?? widget.childName;
        final bool isLoading = snapshot.connectionState == ConnectionState.waiting;
        final List recent = data['recent'] as List;
        final List missing = data['missing'] as List;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Hello Parent,", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              Text("Overview for $displayName (${widget.level})", style: const TextStyle(fontSize: 14, color: Colors.grey)),
              const SizedBox(height: 25),

              // DYNAMIC STAT CARDS
              Row(
                children: [
                  _statCard("Avg Score", data['average']!, Icons.analytics, Colors.green),
                  const SizedBox(width: 15),
                  _statCard("Tasks Done", data['completed']!, Icons.check_circle, Colors.blue),
                ],
              ),
              const SizedBox(height: 30),

              // MISSING WORK SECTION (Notification Style)
              if (missing.isNotEmpty) ...[
                const Text("⚠️ Needs Attention", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.redAccent)),
                const SizedBox(height: 10),
                ...missing.map((m) => Card(
                  elevation: 0, color: Colors.orange.withOpacity(0.1),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.orange.withOpacity(0.3))),
                  child: ListTile(
                    leading: const Icon(Icons.warning_amber, color: Colors.orange),
                    title: Text("$m is PENDING", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    subtitle: const Text("Your child hasn't finished this yet."),
                  ),
                )),
                const SizedBox(height: 30),
              ],

              // RECENT RESULTS
              const Text("Recent Results", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              if (recent.isEmpty && !isLoading)
                const Center(child: Text("No results yet. Work will appear here."))
              else
                ...recent.map((r) => InkWell(
                  onTap: () => _showResultDetailsSheet(context, r),
                  borderRadius: BorderRadius.circular(15),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.grey.shade200)),
                    child: Row(
                      children: [
                        CircleAvatar(backgroundColor: primaryBlue.withOpacity(0.1), child: const Icon(Icons.description_outlined, color: primaryBlue)),
                        const SizedBox(width: 15),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(r['submissions']?['homework']?['title'] ?? "Task", style: const TextStyle(fontWeight: FontWeight.bold)),
                              Text(AutoGradingService.parseFeedback(r['feedback'] ?? "Excellent work!").feedback, style: const TextStyle(color: Colors.grey, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        ),
                        Text("${(r['score'] as num).toInt()}%", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primaryBlue)),
                      ],
                    ),
                  ),
                )),
              
              const SizedBox(height: 40),
            ],
          ),
        );
      },
    );
  }

  Widget _statCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))]),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 10),
            Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
            Text(title, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
          ],
        ),
      ),
    );
  }

  void _showResultDetailsSheet(BuildContext context, Map<String, dynamic> r) {
    const Color primaryBlue = Color(0xFF0D47A1);
    final String resultId = r['id'].toString();
    final String title = r['submissions']?['homework']?['title'] ?? "Task";
    final double score = (r['score'] as num).toDouble();
    
    final assessment = AssessmentEngine.evaluate(
      correctCount: score.toInt(),
      totalQuestions: 100,
      topic: title,
      wrongIndexes: [],
    );

    final parsed = AutoGradingService.parseFeedback(r['feedback'] ?? "");
    final TextEditingController commentCtrl = TextEditingController(text: parsed.parentFeedback);
    bool isSaving = false;
    String? errorMessage;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setSheetState) => DraggableScrollableSheet(
          initialChildSize: 0.75,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          builder: (_, scrollCtrl) => Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: ListView(
              controller: scrollCtrl,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                
                // HEADER SECTION (Title & Score Badge)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            _t("Homework Evaluation", "Tathmini ya Kazi ya Nyumbani"),
                            style: TextStyle(color: Colors.grey[600], fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: assessment.gradeColor,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          Text(
                            "${score.toInt()}%",
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            "(${assessment.grade})",
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // ERROR MESSAGE IF ANY
                if (errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Text(
                      errorMessage!,
                      style: TextStyle(color: Colors.red.shade800, fontSize: 13),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // TEACHER REMARKS
                Text(
                  _t("Teacher Remarks", "Maoni ya Mwalimu"),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.blue.shade100),
                  ),
                  child: Text(
                    parsed.feedback.isNotEmpty
                        ? parsed.feedback
                        : _t("No teacher remarks written yet.", "Hakuna maoni yaliyoandikwa bado."),
                    style: TextStyle(
                      color: Colors.blue.shade900,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // AI RECOMMENDATIONS & PRACTICE QUESTIONS
                if (parsed.recommendation.isNotEmpty) ...[
                  Text(
                    _t("Recommended Next Steps", "Hatua Zilizopendekezwa"),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    parsed.recommendation,
                    style: const TextStyle(fontSize: 14, height: 1.4, color: Colors.black87),
                  ),
                  const SizedBox(height: 20),
                ],

                if (parsed.revisionQuestions.isNotEmpty) ...[
                  Text(
                    _t("Revision Questions", "Maswali ya Marudio"),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ...parsed.revisionQuestions.map((q) => Padding(
                    padding: const EdgeInsets.only(bottom: 6.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("• ", style: TextStyle(fontWeight: FontWeight.bold)),
                        Expanded(child: Text(q, style: const TextStyle(color: Colors.black54))),
                      ],
                    ),
                  )),
                  const SizedBox(height: 20),
                ],

                const Divider(),
                const SizedBox(height: 12),

                // PARENT FEEDBACK FORM
                Text(
                  _t("Comment / Parent Observation", "Maoni / Uchunguzi wa Mzazi"),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  _t(
                    "Let the teacher know if your child faced any difficulty (e.g., struggles with fractions).",
                    "Mjulishe mwalimu kama mtoto wako alipata shida yoyote (mfano, shida na sehemu).",
                  ),
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: commentCtrl,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: _t(
                      "Write your comment here...",
                      "Andika maoni yako hapa...",
                    ),
                    filled: true,
                    fillColor: Colors.grey[50],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // SAVE BUTTON
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: isSaving
                        ? null
                        : () async {
                            setSheetState(() {
                              isSaving = true;
                              errorMessage = null;
                            });
                            try {
                              final String serialized = AutoGradingService.serializeFeedback(
                                feedback: parsed.feedback,
                                recommendation: parsed.recommendation,
                                revisionQuestions: parsed.revisionQuestions,
                                parentFeedback: commentCtrl.text.trim(),
                              );

                              await Supabase.instance.client
                                  .from('results')
                                  .update({'feedback': serialized})
                                  .eq('id', resultId);

                              if (ctx.mounted) {
                                Navigator.pop(ctx);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      _t("Comment successfully sent to teacher!", "Maoni yametumwa kwa mwalimu kikamilifu!"),
                                    ),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              }
                            } catch (e) {
                              setSheetState(() {
                                isSaving = false;
                                errorMessage = e.toString();
                              });
                            }
                          },
                    icon: isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.send, color: Colors.white),
                    label: Text(
                      isSaving
                          ? _t("Saving...", "Inahifadhi...")
                          : _t("Send to Teacher", "Tuma kwa Mwalimu"),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryBlue,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
