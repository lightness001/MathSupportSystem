import 'dart:io' as io;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'crop_image_screen.dart';
import 'confirm_questions_screen.dart';
import '../services/web_safe_file.dart';

class TeacherUploadHomeworkSheet extends StatefulWidget {
  final List<String> myClasses;
  const TeacherUploadHomeworkSheet({super.key, required this.myClasses});

  @override
  State<TeacherUploadHomeworkSheet> createState() => _TeacherUploadHomeworkSheetState();
}

class _TeacherUploadHomeworkSheetState extends State<TeacherUploadHomeworkSheet> {
  final supabase = Supabase.instance.client;
  bool _isLoading = true;
  final bool _isUploading = false;
  bool _isUploading = false;
  Map<String, dynamic>? _lastHomework;

  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  String? _selectedLevel;

  @override
  void initState() {
    super.initState();
    if (widget.myClasses.isNotEmpty) {
      _selectedLevel = widget.myClasses.first;
    }
    _fetchLastHomework();
  }

  Future<void> _fetchLastHomework() async {
    try {
      final teacherId = supabase.auth.currentUser!.id;
      final res = await supabase
          .from('homework')
          .select()
          .eq('teacher_id', teacherId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (mounted) {
        setState(() {
          _lastHomework = res;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteHomework(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
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
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Delete", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      setState(() => _isLoading = true);
      await supabase.from('homework').delete().eq('id', id);
      await _fetchLastHomework();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Homework deleted successfully."),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error deleting: $e")));
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _pickAndUploadImage(ImageSource source) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: source, imageQuality: 80);
    if (pickedFile != null) {
      if (mounted) {
        final croppedFile = await Navigator.push<File?>(
          context,
          MaterialPageRoute(
            builder: (context) => CropImageScreen(imageFile: File(pickedFile.path)),
          ),
        );
        if (croppedFile != null) {
          _showPostDialog(croppedFile, isImage: true);
        }
      }
    }
  }

  Future<void> _pickDocument() async {
    FilePickerResult? result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx'],
    );

    if (result != null && result.files.single.path != null) {
      _showPostDialog(File(result.files.single.path!), isImage: false);
    }
  }

  void _showPostDialog(File file, {required bool isImage}) {
    DateTime selectedDueDate = DateTime.now().add(const Duration(days: 7));
    DateTime selectedDueDate = DateTime.now();
    bool isUploadingLocal = false;
    String? errorMessage;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text("Post Homework"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isImage)
                  (kIsWeb
                      ? Image.network(file.path, height: 150, fit: BoxFit.cover)
                      : Image.file(io.File(file.path), height: 150, fit: BoxFit.cover))
                else
                  const Icon(Icons.picture_as_pdf, size: 80, color: Colors.red),
                const SizedBox(height: 15),
                if (errorMessage != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 15),
                    padding: const EdgeInsets.all(10),
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
                DropdownButtonFormField<String>(
                  initialValue: _selectedLevel,
                  value: _selectedLevel,
                  items: widget.myClasses.map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
                  onChanged: (val) => setDialogState(() => _selectedLevel = val),
                  decoration: const InputDecoration(labelText: "Target Level"),
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: _titleController,
                  decoration: const InputDecoration(labelText: "Title (e.g. Chapter 4 Math)"),
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: _descController,
                  decoration: const InputDecoration(labelText: "Description (Optional)"),
                ),
                const SizedBox(height: 15),
                InkWell(
                  onTap: () async {
                    final DateTime? picked = await showDatePicker(
                      context: ctx,
                      initialDate: selectedDueDate,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    final DateTime now = DateTime.now();
                    final DateTime? picked = await showDatePicker(
                      context: ctx,
                      initialDate: selectedDueDate,
                      firstDate: now.subtract(const Duration(days: 1)),
                      lastDate: now.add(const Duration(days: 365)),
                      currentDate: now,
                    );
                    if (picked != null) {
                      setDialogState(() {
                        selectedDueDate = picked;
                      });
                    }
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: "Due Date / Deadline",
                      prefixIcon: Icon(Icons.calendar_today, color: Color(0xFF0D47A1)),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(10)),
                      ),
                    ),
                    child: Text(
                      "${selectedDueDate.year}-${selectedDueDate.month.toString().padLeft(2, '0')}-${selectedDueDate.day.toString().padLeft(2, '0')}",
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                ),
                if (isUploadingLocal)
                  const Padding(
                    padding: EdgeInsets.only(top: 20),
                    child: CircularProgressIndicator(),
                  )
              ],
            ),
          ),
          actions: [
            if (!isUploadingLocal)
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
            if (!isUploadingLocal)
              ElevatedButton(
                onPressed: () async {
                  if (_titleController.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please enter a title.")));
                    return;
                  }
                  setDialogState(() {
                    isUploadingLocal = true;
                    errorMessage = null; // Clear previous errors
                  });
                  try {
                    final rawFileName = file.path.split(RegExp(r"[/\\]")).last;
                    final timestamp = DateTime.now().millisecondsSinceEpoch;
                    
                    // Generate list of standard candidate paths to satisfy different RLS policy options
                    final candidates = [
                      '$_selectedLevel/${timestamp}_$rawFileName', // 1. Class-scoped (e.g. Standard 4/123_file.pdf)
                      '${supabase.auth.currentUser!.id}/$_selectedLevel/${timestamp}_$rawFileName', // 2. Combined (e.g. teacher_id/Standard 4/123_file.pdf)
                      'homework/${timestamp}_$rawFileName', // 3. Generic (e.g. homework/123_file.pdf)
                      '${supabase.auth.currentUser!.id}/${timestamp}_$rawFileName', // 4. Teacher-scoped (e.g. teacher_id/123_file.pdf)
                      '${timestamp}_$rawFileName', // 5. Root level
                    ];

                    String? workingFileName;
                    dynamic lastUploadError;

                    for (final path in candidates) {
                      try {
                        debugPrint("Attempting upload to path: $path");
                        if (kIsWeb) {
                          final bytes = await file.readAsBytes();
                          await supabase.storage.from('homework_files').uploadBinary(
                                path,
                                bytes,
                                fileOptions: const FileOptions(upsert: false),
                              );
                        } else {
                          await supabase.storage.from('homework_files').upload(
                                path,
                                io.File(file.path),
                                fileOptions: const FileOptions(upsert: false),
                              );
                        }
                        workingFileName = path;
                        debugPrint("Upload succeeded at path: $path");
                        break;
                      } catch (e) {
                        debugPrint("Upload failed for path: $path. Error: $e");
                        lastUploadError = e;
                      }
                    }

                    if (workingFileName == null) {
                      throw lastUploadError ?? Exception("Upload failed for all candidate folder formats.");
                    }
                    
                    final String fileUrl = supabase.storage.from('homework_files').getPublicUrl(workingFileName);

                    await supabase.from('homework').insert({
                      'title': _titleController.text.trim(),
                      'description': _descController.text.trim(),
                      'level': _selectedLevel,
                      'teacher_id': supabase.auth.currentUser!.id,
                      'due_date': selectedDueDate.toIso8601String(),
                      'questions': [],
                      'file_url': fileUrl,
                    });

                    _titleController.clear();
                    _descController.clear();
                    
                    if (!ctx.mounted) return;
                    Navigator.pop(ctx);
                    _fetchLastHomework();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Homework posted!")));
                    if (!ctx.mounted) return;
                    Navigator.pop(ctx); // Close the upload dialog

                    final success = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ConfirmQuestionsScreen(
                          file: file,
                          isImage: isImage,
                          fileUrl: fileUrl,
                          title: _titleController.text.trim(),
                          description: _descController.text.trim(),
                          level: _selectedLevel!,
                          dueDate: selectedDueDate,
                        ),
                      ),
                    );

                    _titleController.clear();
                    _descController.clear();

                    if (success == true) {
                      _fetchLastHomework();
                    }
                  } catch (e) {
                    debugPrint("Upload error details: $e");
                    if (ctx.mounted) {
                      setDialogState(() {
                        errorMessage = e.toString();
                        isUploadingLocal = false;
                      });
                    }
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0D47A1)),
                child: const Text("Upload & Post", style: TextStyle(color: Colors.white)),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const primaryBlue = Color(0xFF0D47A1);

    return Container(
      padding: const EdgeInsets.all(20),
      height: MediaQuery.of(context).size.height * 0.8,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Manage Homework", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context))
            ],
          ),
          const Divider(),
          const SizedBox(height: 10),
          const Text("Last Posted Homework", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 10),
          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else if (_lastHomework == null)
            const Center(child: Text("No homework posted yet."))
          else
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              child: Padding(
                padding: const EdgeInsets.all(15.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(backgroundColor: primaryBlue.withOpacity(0.1), child: const Icon(Icons.book, color: primaryBlue)),
                        const SizedBox(width: 15),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_lastHomework!['title'] ?? 'No Title', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              Text("Level: ${_lastHomework!['level']}", style: TextStyle(color: Colors.grey[600])),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _deleteHomework(_lastHomework!['id'].toString()),
                        )
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (_lastHomework!['file_url'] != null)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_lastHomework!['file_url'].toString().toLowerCase().contains('.jpg') || _lastHomework!['file_url'].toString().toLowerCase().contains('.png') || _lastHomework!['file_url'].toString().toLowerCase().contains('.jpeg'))
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.network(_lastHomework!['file_url'], height: 150, width: double.infinity, fit: BoxFit.cover),
                            )
                          else
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                              child: const Row(
                                children: [
                                  Icon(Icons.picture_as_pdf, color: Colors.green),
                                  SizedBox(width: 8),
                                  Text("Document Attached", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          const SizedBox(height: 10),
                          ElevatedButton.icon(
                            onPressed: () => _openUrl(_lastHomework!['file_url']),
                            icon: const Icon(Icons.open_in_new),
                            label: const Text("Open Attachment"),
                          )
                        ]
                      ),
                  ],
                ),
              ),
            ),
          const Spacer(),
          const Text("Post New Homework", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 15),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _actionButton(Icons.camera_alt, "Camera", Colors.blue, () => _pickAndUploadImage(ImageSource.camera)),
              _actionButton(Icons.photo_library, "Gallery", Colors.purple, () => _pickAndUploadImage(ImageSource.gallery)),
              _actionButton(Icons.picture_as_pdf, "Document", Colors.orange, _pickDocument),
            ],
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _actionButton(IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          CircleAvatar(radius: 30, backgroundColor: color.withOpacity(0.1), child: Icon(icon, color: color, size: 30)),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
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
