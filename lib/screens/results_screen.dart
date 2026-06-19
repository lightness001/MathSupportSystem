import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../services/assessment_engine.dart';
import 'student_feedback_screen.dart';

class ResultsScreen extends StatelessWidget {
  const ResultsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final supabase = Supabase.instance.client;
    final String? userId = supabase.auth.currentUser?.id;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FA),
      appBar: AppBar(
        title: const Text(
          'My Results',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF0D47A1),
        elevation: 0,
      ),
      body: userId == null
          ? const Center(child: Text('Not logged in'))
          : FutureBuilder<List<dynamic>>(
              future: supabase
                  .from('submissions')
                  .select('''
                    id,
                    submitted_at,
                    homework:homework_id(title),
                    results(
                      id,
                      score,
                      feedback,
                      created_at,
                      submission_id
                    )
                  ''')
                  .eq('student_id', userId)
                  .order('submitted_at', ascending: false),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        'Error loading results:\n${snapshot.error}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  );
                }

                final List<dynamic> submissions = snapshot.data ?? [];
                final List<Map<String, dynamic>> results = [];

                for (var sub in submissions) {
                  // EXPERT FIX: Handle both Map and List for results
                  final dynamic rawResults = sub['results'];
                  List<dynamic> resultsList = [];
                  
                  if (rawResults is List) {
                    resultsList = rawResults;
                  } else if (rawResults is Map) {
                    resultsList = [rawResults];
                  }

                  if (resultsList.isNotEmpty) {
                    final result = Map<String, dynamic>.from(resultsList.first);
                    
                    // EXPERT FIX: Handle both Map and List for homework title
                    final dynamic rawHw = sub['homework'];
                    String hwTitle = 'Assignment';
                    
                    if (rawHw is Map) {
                      hwTitle = rawHw['title'] ?? 'Assignment';
                    } else if (rawHw is List && rawHw.isNotEmpty) {
                      hwTitle = rawHw[0]['title'] ?? 'Assignment';
                    }
                    
                    result['homework_title'] = hwTitle;
                    results.add(result);
                  } else {
                    // Submission exists but no result row yet — pending review!
                    final Map<String, dynamic> result = {
                      'id': 'pending_${sub['id']}',
                      'score': -1.0, // Special flag for pending
                      'feedback': 'Your homework has been submitted successfully and is awaiting teacher review.',
                      'created_at': sub['submitted_at'],
                      'submission_id': sub['id'].toString(),
                    };
                    
                    final dynamic rawHw = sub['homework'];
                    String hwTitle = 'Assignment';
                    if (rawHw is Map) {
                      hwTitle = rawHw['title'] ?? 'Assignment';
                    } else if (rawHw is List && rawHw.isNotEmpty) {
                      hwTitle = rawHw[0]['title'] ?? 'Assignment';
                    }
                    result['homework_title'] = hwTitle;
                    results.add(result);
                  }
                }

                if (results.isEmpty) {
                  return _buildEmptyState();
                }

                // Calculate overall average of graded items only
                double total = 0;
                int gradedCount = 0;
                for (var r in results) {
                  final double s = (r['score'] as num).toDouble();
                  if (s >= 0) {
                    total += s;
                    gradedCount++;
                  }
                }
                final double avg = gradedCount > 0 ? total / gradedCount : 0.0;

                return Column(
                  children: [
                    _buildSummaryHeader(results.length, avg),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Recent Results',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: results.length,
                        itemBuilder: (context, index) {
                          final item = results[index];
                          final double score = (item['score'] as num).toDouble();
                          final bool isPending = score < 0;
                          final String title = item['homework_title'] ?? 'Assignment';
                          final String grade = isPending ? 'P' : AssessmentEngine.evaluate(
                            correctCount: score.toInt(),
                            totalQuestions: 100,
                            topic: title,
                            wrongIndexes: [],
                          ).grade;
                          final String submissionId = item['submission_id']?.toString() ?? '';

                          String dateStr = '';
                          try {
                            dateStr = DateFormat('dd MMM yyyy – hh:mm a')
                                .format(DateTime.parse(item['created_at'].toString()));
                          } catch (_) {}

                          return GestureDetector(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => StudentFeedbackLoader(
                                  submissionId: submissionId,
                                ),
                              ),
                            ),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.04),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 50,
                                    height: 50,
                                    decoration: BoxDecoration(
                                      color: isPending ? Colors.orange : AssessmentEngine.colorForPercent(score),
                                      shape: BoxShape.circle,
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      grade,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 20),
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          title,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold, fontSize: 15),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          dateStr,
                                          style: TextStyle(color: Colors.grey[500], fontSize: 12),
                                        ),
                                        const SizedBox(height: 4),
                                        if (isPending)
                                          const Text(
                                            "Pending Teacher Marking",
                                            style: TextStyle(
                                                color: Colors.orange,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12),
                                          )
                                        else
                                          LinearProgressIndicator(
                                            value: score / 100,
                                            backgroundColor: Colors.grey[200],
                                            color: AssessmentEngine.colorForPercent(score),
                                            minHeight: 5,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      if (isPending)
                                        const Text(
                                          'PENDING',
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                              color: Colors.orange),
                                        )
                                      else
                                        Text(
                                          '${score.toInt()}%',
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 18,
                                              color: AssessmentEngine.colorForPercent(score)),
                                        ),
                                      const SizedBox(height: 4),
                                      const Icon(Icons.chevron_right, color: Colors.grey, size: 18),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }

  Widget _buildSummaryHeader(int count, double avg) {
    final Color avgColor = AssessmentEngine.colorForPercent(avg);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: const BoxDecoration(
        color: Color(0xFF0D47A1),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _headerStat('Assignments', count.toString(), Icons.assignment),
          Container(width: 1, height: 40, color: Colors.white24),
          _headerStat('Avg. Score', AssessmentEngine.formatPercent(avg), Icons.insights),
          Container(width: 1, height: 40, color: Colors.white24),
          _headerStat(
            'Overall Grade',
            AssessmentEngine.evaluate(
                    correctCount: avg.toInt(),
                    totalQuestions: 100,
                    topic: '',
                    wrongIndexes: [])
                .grade,
            Icons.military_tech,
            valueColor: avgColor == const Color(0xFF1B5E20)
                ? Colors.greenAccent
                : avgColor == const Color(0xFFC62828)
                    ? Colors.redAccent
                    : Colors.amberAccent,
          ),
        ],
      ),
    );
  }

  Widget _headerStat(String label, String value, IconData icon, {Color valueColor = Colors.white}) {
    return Column(
      children: [
        Icon(icon, color: Colors.white54, size: 18),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(color: valueColor, fontSize: 20, fontWeight: FontWeight.bold),
        ),
        Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11)),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history_edu, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          const Text(
            'No results yet.',
            style: TextStyle(color: Colors.grey, fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            'Complete a homework assignment to see your grade here.',
            style: TextStyle(color: Colors.grey, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
