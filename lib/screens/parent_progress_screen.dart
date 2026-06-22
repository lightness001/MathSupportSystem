import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auto_grading_service.dart';
import '../services/assessment_engine.dart';
import '../main.dart';

class ParentProgressScreen extends StatelessWidget {
  final String childName;
  final String fullName;
  final String level;

  const ParentProgressScreen({
    super.key,
    required this.childName,
    required this.fullName,
    required this.level,
  });

  Future<List<Map<String, dynamic>>> _fetchLiveProgress() async {
    final supabase = Supabase.instance.client;
    final response = await supabase.from('results').select('''
          id,
          score,
          feedback,
          submissions!inner(homework!inner(title), profiles!inner(username))
        ''').eq('submissions.profiles.username', childName);
    return List<Map<String, dynamic>>.from(response);
  }

  String _t(String en, String sw) {
    return AppSettings.language.value == 'Kiswahili' ? sw : en;
  }

  @override
  Widget build(BuildContext context) {
    const Color primaryBlue = Color(0xFF0D47A1);

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _fetchLiveProgress(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        final results = snapshot.data ?? [];

        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("$childName's Progress", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              Text(
                "${(fullName.isNotEmpty && fullName != childName) ? '$fullName ($childName)' : childName}'s Progress",
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              Text("Detailed analysis for $level", style: const TextStyle(color: Colors.grey, fontSize: 14)),
              const SizedBox(height: 25),

              // PERFORMANCE CHART
              if (results.isNotEmpty) ...[
                const Text("Score Trend", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                SizedBox(
                  height: 200,
                  child: BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround, maxY: 100,
                      titlesData: FlTitlesData(
                        show: true,
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 40,
                            getTitlesWidget: (double value, TitleMeta meta) {
                              int index = value.toInt();
                              if (index >= 0 && index < results.length) {
                                String fullTitle = results[index]['submissions']?['homework']?['title'] ?? 'Task';
                                String displayTitle = fullTitle.length > 12 
                                    ? '${fullTitle.substring(0, 10)}..' 
                                    : fullTitle;
                                return Padding(
                                  padding: const EdgeInsets.only(top: 6.0),
                                  child: Tooltip(
                                    message: fullTitle,
                                    child: Text(
                                      displayTitle,
                                      style: const TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black87,
                                      ),
                                    ),
                                  ),
                                );
                              }
                              return const SizedBox.shrink();
                            },
                          ),
                        ),
                        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 35)),
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      ),
                      gridData: const FlGridData(show: false),
                      borderData: FlBorderData(
                        show: true,
                        border: Border(
                          left: BorderSide(color: Colors.grey.shade400, width: 1.5),
                          bottom: BorderSide(color: Colors.grey.shade400, width: 1.5),
                        ),
                      ),
                      barGroups: results.asMap().entries.map((e) {
                        return BarChartGroupData(x: e.key, barRods: [BarChartRodData(toY: (e.value['score'] as num).toDouble(), color: primaryBlue, width: 18, borderRadius: BorderRadius.circular(4))]);
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(height: 40),
              ],

              // TOPIC BREAKDOWN
              const Text("Topic Performance", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 15),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.grey.shade200), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10)]),
                child: results.isEmpty 
                  ? const Center(child: Text("No data available yet.", style: TextStyle(color: Colors.grey)))
                  : Column(
                      children: results.map((data) {
                        final String topic = data['submissions']?['homework']?['title'] ?? "Task";
                        final double score = (data['score'] as num?)?.toDouble() ?? 0;
                        return InkWell(
                          onTap: () => _showResultDetailsSheet(context, data),
                          borderRadius: BorderRadius.circular(10),
                          child: _buildProgressBar(topic, score / 100, primaryBlue),
                        );
                      }).toList(),
                    ),
              ),
              const SizedBox(height: 50),
            ],
          ),
        );
      },
    );
  }

  Widget _buildProgressBar(String topic, double value, Color themeColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(topic, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              Text("${(value * 100).toInt()}%", style: TextStyle(color: themeColor, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(value: value, minHeight: 8, backgroundColor: Colors.grey.shade100, valueColor: AlwaysStoppedAnimation<Color>(themeColor)),
          ),
        ],
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
