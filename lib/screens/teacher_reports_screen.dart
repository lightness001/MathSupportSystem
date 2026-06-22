import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TeacherReportsScreen extends StatefulWidget {
  const TeacherReportsScreen({super.key});

  @override
  State<TeacherReportsScreen> createState() => _TeacherReportsScreenState();
}

class _TeacherReportsScreenState extends State<TeacherReportsScreen> {
  final supabase = Supabase.instance.client;
  String _selectedSubject = 'All Assignments';
  String _selectedTerm = 'This Term';
  String _activeClass = 'All My Classes';
  List<String> _myClasses = [];
  List<String> _assignmentTitles = ['All Assignments'];
  bool _isLoadingClasses = true;

  @override
  void initState() {
    super.initState();
    _loadTeacherClasses();
  }

  Future<void> _loadTeacherClasses() async {
    try {
      final String teacherId = supabase.auth.currentUser!.id;
      
      // Load teacher classes
      final profile = await supabase.from('profiles').select('level').eq('id', teacherId).single();
      String levelStr = profile['level'] ?? '';
      List<String> joined = [];
      if (levelStr.contains(',')) {
        joined = levelStr.split(',').map((e) => e.trim()).toList();
      } else if (levelStr != 'Teacher' && levelStr.isNotEmpty) {
        joined = [levelStr];
      }

      // Load all homework titles created by this teacher to populate the dropdown dynamically
      final homeworkRes = await supabase
          .from('homework')
          .select('title')
          .eq('teacher_id', teacherId);
      final List hwList = homeworkRes as List;
      final Set<String> titlesSet = hwList.map((h) => h['title']?.toString() ?? '').where((t) => t.isNotEmpty).toSet();

      setState(() {
        _myClasses = joined;
        _assignmentTitles = ['All Assignments', ...titlesSet];
        _isLoadingClasses = false;
      });
    } catch (e) {
      debugPrint("Error loading classes: $e");
      setState(() => _isLoadingClasses = false);
    }
  }

  Future<Map<String, dynamic>> _fetchReportData() async {
    try {
      final String teacherId = supabase.auth.currentUser!.id;

      // 1. Fetch all homework created by this teacher
      final homeworkRes = await supabase
          .from('homework')
          .select('id, title, level')
          .eq('teacher_id', teacherId);
      final List homeworkList = homeworkRes as List;

      // 2. Fetch Performance Data - Scoped to Teacher's homework submissions
      final resultsRes = await supabase.from('results').select('''
        score,
        submissions!inner(
          homework_id,
          homework!inner(title, teacher_id, level)
        )
      ''').eq('submissions.homework.teacher_id', teacherId);
      final List resultsList = resultsRes as List;

      // Filter homework list by active class
      List filteredHomework = homeworkList.where((hw) {
        if (_activeClass != 'All My Classes') {
          return hw['level'] == _activeClass;
        }
        return true;
      }).toList();

      // Compute averages dynamically for each homework
      List<Map<String, dynamic>> assignmentAverages = [];
      for (var hw in filteredHomework) {
        final String hwId = hw['id']?.toString() ?? '';
        final String title = hw['title']?.toString() ?? '';
        
        final hwResults = resultsList.where((r) => r['submissions']?['homework_id']?.toString() == hwId).toList();
        double sum = 0.0;
        for (var r in hwResults) {
          sum += (r['score'] as num).toDouble();
        }
        double avg = hwResults.isNotEmpty ? sum / hwResults.length : 0.0;
        assignmentAverages.add({
          'id': hwId,
          'title': title,
          'average': avg,
        });
      }

      // 3. Missing Work List (Filtered by Class)
      final submissionsRes = await supabase.from('submissions').select('student_id, homework_id');
      final List subList = submissionsRes as List;
      final List<Map<String, String>> missingWork = [];

      for (var hw in homeworkList) {
        if (_activeClass != 'All My Classes' && hw['level'] != _activeClass) continue;

        final String hwLevel = hw['level'] ?? 'Standard 7';
        final levelStudentsRes = await supabase.from('profiles').select('id, username, full_name').ilike('role', 'student').eq('level', hwLevel).eq('status', 'active');
        
        for (var student in (levelStudentsRes as List)) {
          bool submitted = subList.any((s) => s['student_id'].toString() == student['id'].toString() && s['homework_id'].toString() == hw['id'].toString());
          if (!submitted) {
            missingWork.add({'student': student['username'] ?? 'Anonymous', 'homework': hw['title'] ?? 'Assignment', 'level': hwLevel});
            final String stdName = student['full_name'] ?? '';
            final String stdUsername = student['username'] ?? '';
            final String stdLabel = (stdName.isNotEmpty && stdName != stdUsername)
                ? "$stdName ($stdUsername)"
                : stdUsername;
            missingWork.add({'student': stdLabel, 'homework': hw['title'] ?? 'Assignment', 'level': hwLevel});
          }
        }
      }

      return {
        'assignments': assignmentAverages,
        'missingWork': missingWork,
      };
    } catch (e) {
      debugPrint("Error fetching reports: $e");
      return {'assignments': <Map<String, dynamic>>[], 'missingWork': []};
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingClasses) return const Center(child: CircularProgressIndicator());
    const primaryBlue = Color(0xFF0D47A1);

    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          // 1. CLASS SWITCHER (CHIPS)
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
            child: FutureBuilder<Map<String, dynamic>>(
              future: _fetchReportData(),
              builder: (context, snapshot) {
                final data = snapshot.data ?? {'assignments': <Map<String, dynamic>>[], 'missingWork': []};
                final bool isLoading = snapshot.connectionState == ConnectionState.waiting;
                final missingWork = data['missingWork'] as List;

                // Dynamic calculations for assignments
                final List<Map<String, dynamic>> assignments = List<Map<String, dynamic>>.from(data['assignments'] ?? []);

                // Apply Selected dropdown filters
                List<Map<String, dynamic>> displayedAssignments = [];
                if (_selectedSubject == 'All Assignments') {
                  displayedAssignments = assignments;
                } else {
                  displayedAssignments = assignments.where((a) => a['title'] == _selectedSubject).toList();
                }

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 2. DROPDOWN FILTERS
                      Row(
                        children: [
                          Expanded(child: _buildDropdown(_assignmentTitles, _selectedSubject, (val) => setState(() => _selectedSubject = val!))),
                          const SizedBox(width: 10),
                          Expanded(child: _buildDropdown(['This Term', 'Last Term'], _selectedTerm, (val) => setState(() => _selectedTerm = val!))),
                        ],
                      ),
                      const SizedBox(height: 30),

                      const Text("Performance Progress", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 20),
                      SizedBox(
                        height: 200,
                        child: isLoading 
                            ? const Center(child: CircularProgressIndicator()) 
                            : displayedAssignments.isEmpty
                                ? const Center(child: Text("No assignment data found.", style: TextStyle(color: Colors.grey)))
                                : BarChart(
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
                                              if (index >= 0 && index < displayedAssignments.length) {
                                                String fullTitle = displayedAssignments[index]['title'] ?? '';
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
                                        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 30)),
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
                                      barGroups: displayedAssignments.asMap().entries.map((entry) {
                                        int idx = entry.key;
                                        double val = (entry.value['average'] as num).toDouble();
                                        return _makeGroupData(idx, val, primaryBlue);
                                      }).toList(),
                                    ),
                                  ),
                      ),
                      const SizedBox(height: 40),
                      const Text("⚠️ Students Still Lagging", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      Text(_activeClass == 'All My Classes' ? "Showing all missing work." : "Missing work for $_activeClass.", style: const TextStyle(color: Colors.grey, fontSize: 12)),
                      const SizedBox(height: 15),
                      if (missingWork.isEmpty && !isLoading)
                        const Center(child: Text("All students caught up! ✅", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)))
                      else
                        ...missingWork.map((item) => Card(
                          elevation: 0, color: Colors.red.withOpacity(0.05),
                          margin: const EdgeInsets.only(bottom: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.red.withOpacity(0.1))),
                          child: ListTile(
                            leading: const CircleAvatar(backgroundColor: Colors.red, child: Icon(Icons.warning_amber, color: Colors.white, size: 20)),
                            title: Text(item['student']!, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text("Missing: ${item['homework']} (${item['level']})"),
                            trailing: const Text("PENDING", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 10)),
                          ),
                        )).toList(),
                      const SizedBox(height: 50),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, Color color) {
    bool isActive = _activeClass == label;
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: ChoiceChip(
        label: Text(label), selected: isActive,
        onSelected: (val) => setState(() => _activeClass = label),
        selectedColor: color,
        labelStyle: TextStyle(color: isActive ? Colors.white : Colors.black87, fontWeight: isActive ? FontWeight.bold : FontWeight.normal),
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }

  Widget _buildDropdown(List<String> items, String value, Function(String?) onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(8)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value, isExpanded: true,
          items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  BarChartGroupData _makeGroupData(int x, double y, Color barColor) {
    return BarChartGroupData(x: x, barRods: [BarChartRodData(toY: y, color: barColor, width: 22, borderRadius: BorderRadius.circular(4))]);
  }
}
