import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class TeacherHomeworkScreen extends StatefulWidget {
  const TeacherHomeworkScreen({super.key});

  @override
  State<TeacherHomeworkScreen> createState() => _TeacherHomeworkScreenState();
}

class _TeacherHomeworkScreenState extends State<TeacherHomeworkScreen> {
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
      } else if (levelStr != 'Teacher' && levelStr.isNotEmpty) joined = [levelStr];
      setState(() { _myClasses = joined; _isLoadingClasses = false; });
    } catch (e) {
      setState(() => _isLoadingClasses = false);
    }
  }



  @override
  Widget build(BuildContext context) {
    if (_isLoadingClasses) return const Center(child: CircularProgressIndicator());
    const primaryBlue = Color(0xFF0D47A1);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: Column(
        children: [
          if (_myClasses.isNotEmpty)
            Container(
              height: 60, padding: const EdgeInsets.symmetric(vertical: 10),
              child: ListView(
                scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 15),
                children: [
                  _buildFilterChip('All My Classes', primaryBlue),
                  ..._myClasses.map((lvl) => _buildFilterChip(lvl, primaryBlue)),
                ],
              ),
            ),

          Expanded(
            child: StreamBuilder(
              stream: supabase.from('homework').stream(primaryKey: ['id']).eq('teacher_id', supabase.auth.currentUser!.id),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                var homeworkList = snapshot.data!;
                if (_activeFilter != 'All My Classes') { homeworkList = homeworkList.where((h) => h['level'] == _activeFilter).toList(); }

                if (homeworkList.isEmpty) return const Center(child: Text("No homework yet. Click + to post."));

                return ListView.builder(
                  itemCount: homeworkList.length,
                  itemBuilder: (context, index) {
                    final item = homeworkList[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 8), elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: Colors.grey.shade200)),
                      child: ListTile(
                        onTap: () => _showHomeworkDetails(item),
                        leading: CircleAvatar(
                          backgroundColor: primaryBlue.withOpacity(0.1),
                          child: Icon(item['file_url'] != null ? Icons.attachment : Icons.book, color: primaryBlue)
                        ),
                        title: Text(item['title'] ?? 'No Title', style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text("${item['level']} • Due: ${item['due_date']?.toString().split('T')[0]}"),
                        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
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
        label: Text(label), selected: isActive,
        onSelected: (val) => setState(() => _activeFilter = label),
        selectedColor: color,
        labelStyle: TextStyle(color: isActive ? Colors.white : Colors.black87, fontWeight: isActive ? FontWeight.bold : FontWeight.normal),
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }

  void _showHomeworkDetails(Map<String, dynamic> item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Homework Preview"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item['title'] ?? 'No Title', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              if (item['description'] != null && item['description'].toString().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 15.0),
                  child: Text(item['description'], style: const TextStyle(fontSize: 16)),
                ),
              if (item['file_url'] != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (item['file_url'].toString().toLowerCase().contains('.jpg') || item['file_url'].toString().toLowerCase().contains('.png') || item['file_url'].toString().toLowerCase().contains('.jpeg'))
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(item['file_url'], height: 200, width: double.infinity, fit: BoxFit.cover),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(10)),
                        child: Row(
                          children: [
                            const Icon(Icons.picture_as_pdf, color: Colors.green),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                "Document Attached",
                                style: TextStyle(color: Colors.green.shade800, fontWeight: FontWeight.bold)
                              )
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 10),
                    ElevatedButton.icon(
                      onPressed: () => _openUrl(item['file_url']),
                      icon: const Icon(Icons.open_in_new),
                      label: const Text("Open Attachment"),
                    )
                  ]
                )
              else if (item['questions'] != null && (item['questions'] as List).isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Questions:", style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 5),
                    ...((item['questions'] as List).map((q) => Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Text("• ${q['text']}"),
                    )).toList())
                  ]
                )
              else
                const Text("No content.", style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
               final confirm = await showDialog<bool>(
                 context: context,
                 builder: (confirmCtx) => AlertDialog(
                   shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                   title: const Row(
                     children: [
                       Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 28),
                       SizedBox(width: 10),
                       Text("Confirm Delete"),
                     ],
                   ),
                   content: const Text(
                     "Are you sure you want to delete this homework? This action cannot be undone.",
                     style: TextStyle(fontSize: 16),
                   ),
                   actions: [
                     TextButton(
                       onPressed: () => Navigator.pop(confirmCtx, false),
                       child: const Text("Cancel", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                     ),
                     ElevatedButton(
                       style: ElevatedButton.styleFrom(
                         backgroundColor: Colors.redAccent,
                         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                       ),
                       onPressed: () => Navigator.pop(confirmCtx, true),
                       child: const Text("Delete", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                     ),
                   ],
                 ),
               );

               if (confirm == true) {
                 if (mounted) Navigator.pop(ctx);
                 await supabase.from('homework').delete().eq('id', item['id']);
                 if (mounted) {
                   ScaffoldMessenger.of(context).showSnackBar(
                     const SnackBar(
                       content: Text("Homework deleted successfully."),
                       backgroundColor: Colors.redAccent,
                     ),
                   );
                 }
               }
            },
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Close Preview"),
          ),
        ],
      )
    );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Could not open the file.")));
      }
    }
  }

}
