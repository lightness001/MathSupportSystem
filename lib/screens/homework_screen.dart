import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/homework_model.dart';
import 'homework_player_screen.dart';

class HomeworkScreen extends StatefulWidget {
  final String studentLevel;
  const HomeworkScreen({super.key, required this.studentLevel});

  @override
  State<HomeworkScreen> createState() => _HomeworkScreenState();
}

class _HomeworkScreenState extends State<HomeworkScreen> {
  final supabase = Supabase.instance.client;

  @override
  Widget build(BuildContext context) {
    const Color primaryBlue = Color(0xFF0D47A1);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F9FA),
        appBar: AppBar(
          title: const Text(
            "My Assignments",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          backgroundColor: primaryBlue,
          elevation: 0,
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.orangeAccent,
            tabs: [
              Tab(text: "Pending", icon: Icon(Icons.assignment_late)),
              Tab(text: "Completed", icon: Icon(Icons.assignment_turned_in)),
            ],
          ),
        ),
        body: FutureBuilder(
          future: Future.wait([
            supabase
                .from('homework')
                .select()
                .eq('level', widget.studentLevel),
            supabase
                .from('submissions')
                .select('id, homework_id')
                .eq('student_id', supabase.auth.currentUser!.id),
            supabase
                .from('results')
                .select('submission_id'),
          ]),
          builder: (context, AsyncSnapshot<List<dynamic>> snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Center(
                child: Text("Error loading data: ${snapshot.error}"),
              );
            }

            final List<dynamic> allHwData = snapshot.data![0];
            final List<dynamic> submissionData = snapshot.data![1];
            final List<dynamic> resultsData = snapshot.data![2];

            final completedIds = submissionData
                .map((s) => s['homework_id']?.toString())
                .where((id) => id != null)
                .toList();

            final pendingList = allHwData
                .where((hw) => !completedIds.contains(hw['id']?.toString()))
                .toList();
            final completedList = allHwData
                .where((hw) => completedIds.contains(hw['id']?.toString()))
                .toList();

            return TabBarView(
              children: [
                _buildHomeworkList(context, pendingList, isPending: true),
                _buildHomeworkList(context, completedList, isPending: false),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildHomeworkList(
    BuildContext context,
    List<dynamic> homeworkData, {
    required bool isPending,
  }) {
    if (homeworkData.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.done_all, size: 60, color: Colors.grey[300]),
            const SizedBox(height: 10),
            Text(
              isPending ? "All caught up!" : "No completed work yet.",
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: homeworkData.length,
      itemBuilder: (context, index) {
        final hw = homeworkData[index];
        return Card(
          elevation: 2,
          margin: const EdgeInsets.only(bottom: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: const CircleAvatar(
              backgroundColor: Color(0xFFE3F2FD),
              child: Icon(Icons.menu_book, color: Color(0xFF0D47A1)),
            ),
            title: Text(
              hw['title'] ?? 'Untitled',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                Text("Level: ${hw['level'] ?? 'N/A'}"),
                const SizedBox(height: 4),
                Text(
                  isPending
                      ? "Due: ${hw['due_date']?.toString().split('T')[0] ?? 'N/A'}"
                      : "Status: Submitted ✅",
                  style: TextStyle(
                    color: isPending ? Colors.redAccent : Colors.green,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            trailing: isPending
                ? ElevatedButton(
                    onPressed: () {
                      try {
                        final rawQuestions = hw['questions'] as List?;
                        if (rawQuestions == null) {
                          throw "No questions found in this assignment.";
                        }

                        final homeworkModel = Homework(
                          id: hw['id'].toString(),
                          title: hw['title'] ?? 'Untitled',
                          dueDate: hw['due_date']?.toString().split('T')[0] ??
                              'No Date',
                          description: hw['description'],
                          fileUrl: hw['file_url'],
                          questions: rawQuestions
                              .map(
                                (q) => Question(
                                  questionText: q['text'] ?? 'Empty Question',
                                  type: q['type'] ?? 'MCQ',
                                  options: q['options'] != null
                                      ? List<String>.from(q['options'])
                                      : null,
                                  correctAnswer:
                                      q['correct_answer']?.toString() ?? '',
                                ),
                              )
                              .toList(),
                        );

                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                HomeworkPlayerScreen(homework: homeworkModel),
                          ),
                        ).then((_) => setState(() {}));
                      } catch (e) {
                        debugPrint("Start Error: $e");
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text("Could not start assignment: $e"),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orangeAccent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      "START",
                      style: TextStyle(color: Colors.white),
                    ),
                  )
                : const Icon(Icons.check_circle, color: Colors.green),
          ),
        );
      },
    );
  }
}
