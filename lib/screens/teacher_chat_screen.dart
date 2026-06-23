import 'dart:async';
import 'dart:io' hide File, Directory;
import 'dart:io' as io;
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import '../main.dart';
import '../services/web_safe_file.dart';

// -----------------------------------------------------------------------------
// SCREEN 4 — TEACHER INBOX & CONTROLLERS
// -----------------------------------------------------------------------------
class TeacherChatPortal extends StatefulWidget {
  final String teacherName;
  final List<String> myClasses;

  const TeacherChatPortal({
    super.key,
    required this.teacherName,
    required this.myClasses,
  });

  @override
  State<TeacherChatPortal> createState() => _TeacherChatPortalState();
}

class _TeacherChatPortalState extends State<TeacherChatPortal> {
  final supabase = Supabase.instance.client;
  bool _isLoading = true;
  String _activeFilter = "All classes";
  String _searchQuery = "";
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _parentMessages = [];
  List<Map<String, dynamic>> _availableParentContacts = [];

  List<Map<String, dynamic>> _filteredParentMessages = [];

  String _teacherId = "teacher_kamau"; // Default fallback ID mapping Mrs. Kamau
  String _teacherSchool = "";
  List<Map<String, dynamic>> _broadcasts = [];
  
  List<Map<String, dynamic>> _filteredParentMessages = [];
  List<Map<String, dynamic>> _filteredBroadcasts = [];

  String _teacherId = "teacher_kamau"; // Default fallback ID mapping Mrs. Kamau

  @override
  void initState() {
    super.initState();
    _resolveTeacherId();
    _loadData();
  }

  String mapDBLevelToMock(String dbLevel) {
    if (dbLevel.toLowerCase().contains('4')) return 'Std 4';
    if (dbLevel.toLowerCase().contains('7')) return 'Std 7';
    if (dbLevel.toLowerCase().contains('4')) return 'Std 4A';
    if (dbLevel.toLowerCase().contains('7')) return 'Std 7B';
    return dbLevel;
  }

  void _resolveTeacherId() {
    final user = supabase.auth.currentUser;
    if (user != null) {
      _teacherId = user.id;
    } else {
      final name = widget.teacherName.toLowerCase();
      if (name.contains("kamau")) {
        _teacherId = "teacher_kamau";
      } else if (name.contains("mwangi")) {
        _teacherId = "teacher_mwangi";
      } else if (name.contains("oloo")) {
        _teacherId = "teacher_oloo";
      } else if (name.contains("njoroge")) {
        _teacherId = "teacher_njoroge";
      } else {
        _teacherId = "teacher_kamau";
      }
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    await _resolveTeacherSchool();
    await _initializeChatConfigAndLoad();
  }

  Future<void> _resolveTeacherSchool() async {
    try {
      final res = await supabase
          .from('profiles')
          .select('school')
          .eq('id', _teacherId)
          .eq('role', 'teacher')
          .maybeSingle();
      if (res != null && res['school'] != null) {
        _teacherSchool = res['school'].toString().trim();
      }
    } catch (e) {
      debugPrint('Error resolving teacher school: $e');
    }
  }

    await _initializeChatConfigAndLoad();
  }

  Future<File> get _chatHistoryFile async {
    final directory = await AppSettings.getSafeDirectory();
    return File('${directory.path}/parent_chats_config.json');
  }

  void _purgeOldSeededChatsAndNotifications(Map<String, dynamic> data) {
    final seededPatterns = [
      'reading progress',
      'missed school due to illness',
      'Thank you for the feedback',
      'Good morning! I wanted to share that',
      'needs a bit more practice on fractions',
      'That\'s wonderful news',
      'Kindly confirm attendance for the upcoming parent-teacher conference',
      'Your child was absent today',
      'Term 2 schedule has been updated',
    ];

    final keysToRemove = <String>[];
    for (var entry in data.entries) {
      if (entry.key == 'notifications' || entry.key == 'teacher_unread_counts' || entry.key == 'urgents') {
        continue;
      }
      if (entry.value is List) {
        final List chats = entry.value as List;
        if (chats.isNotEmpty && chats.every((item) {
          if (item is Map<String, dynamic> && item.containsKey('text')) {
            final text = item['text']?.toString() ?? '';
            return seededPatterns.any((pattern) => text.contains(pattern));
          }
          return false;
        })) {
          keysToRemove.add(entry.key);
        }
      }
    }

    for (var key in keysToRemove) {
      data.remove(key);
    }

    if (data['notifications'] is List) {
      data['notifications'] = (data['notifications'] as List).where((notif) {
        if (notif is Map<String, dynamic>) {
          final title = notif['title']?.toString() ?? '';
          return !title.contains('Mrs. Kamau sent you a message about Amani') &&
              !title.contains('Ms. Oloo marked a message urgent') &&
              !title.contains('Mr. Mwangi replied to your message about the science project') &&
              !title.contains('School broadcast: End-of-term parent meeting') &&
              !title.contains('Mr. Njoroge updated the Term 2 timetable');
        }
        return true;
      }).toList();
    }
  }

  Future<void> _initializeChatConfigAndLoad() async {
    try {
      final file = await _chatHistoryFile;
      Map<String, dynamic> data = {};

      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.isNotEmpty) {
          data = jsonDecode(content);
        }
      }
      _purgeOldSeededChatsAndNotifications(data);

      // Query real DB parents, students, and parent_child_links
      List<dynamic> studentProfiles = [];
      List<dynamic> parentProfiles = [];
      List<dynamic> dbLinks = [];

      try {
        final studentRes = await supabase
            .from('profiles')
            .select('id, username, full_name, level, school')
            .eq('role', 'student');
        studentProfiles = studentRes as List<dynamic>? ?? [];

        final parentRes = await supabase
            .from('profiles')
            .select('id, username, full_name, level, school')
            .eq('role', 'parent');
        parentProfiles = parentRes as List<dynamic>? ?? [];

        final linksRes = await supabase
            .from('parent_child_links')
            .select('parent_id, student_username');
        dbLinks = linksRes as List<dynamic>? ?? [];
      } catch (dbErr) {
        debugPrint(
          "Error fetching teacher portal profiles/links from DB: $dbErr",
        );
      }

      // Filter students who are in the classes managed by this teacher
      String normalizeLevel(String value) {
        return value
            .toString()
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9]'), '')
            .trim();
      }

      final String normalizedTeacherSchool =
          _teacherSchool.toLowerCase().trim();
      final List<String> normalizedMyClasses = widget.myClasses
          .map((c) => normalizeLevel(c))
          .where((c) => c.isNotEmpty)
          .toList();

      List<Map<String, dynamic>> filteredStudents = studentProfiles
          .where((s) {
            final String sLevel = normalizeLevel(s['level'] ?? '');
            final bool levelMatches = normalizedMyClasses.isNotEmpty &&
                normalizedMyClasses.any(
                  (c) => sLevel.contains(c) || c.contains(sLevel),
                );
            final String studentSchool =
                s['school']?.toString().toLowerCase().trim() ?? '';
            final bool schoolMatches = normalizedTeacherSchool.isEmpty ||
                studentSchool == normalizedTeacherSchool;
            return levelMatches && schoolMatches;
          })
          .cast<Map<String, dynamic>>()
          .toList();

      if (filteredStudents.isEmpty && studentProfiles.isNotEmpty) {
        debugPrint(
          'No students matched teacher classes ${widget.myClasses}. Falling back to all students in school.',
        );
        filteredStudents = studentProfiles
            .cast<Map<String, dynamic>>()
            .where((s) {
              final String studentSchool =
                  s['school']?.toString().toLowerCase().trim() ?? '';
              return normalizedTeacherSchool.isEmpty ||
                  studentSchool == normalizedTeacherSchool;
            })
            .toList();
      }

      final List<String> studentUsernames = filteredStudents
          .map((s) => s['username'].toString().toLowerCase().trim())
          .toList();

      // Filter parent-child links that map to these students
      final List<Map<String, dynamic>> filteredLinks = [];
      for (var link in dbLinks) {
        final String sUsername = (link['student_username'] ?? '')
            .toString()
            .toLowerCase()
            .trim();
        debugPrint("Error fetching teacher portal profiles/links from DB: $dbErr");
      }

      // Filter students who are in the classes managed by this teacher
      final List<String> myClassesLower = widget.myClasses.map((c) => c.toLowerCase().trim()).toList();
      final filteredStudents = studentProfiles.where((s) {
        final String sLevel = (s['level'] ?? '').toString().toLowerCase().trim();
        return myClassesLower.any((c) => sLevel.contains(c) || c.contains(sLevel));
      }).toList();

      final List<String> studentUsernames = filteredStudents.map((s) => s['username'].toString().toLowerCase().trim()).toList();
      
      // Filter parent-child links that map to these students
      final List<Map<String, dynamic>> filteredLinks = [];
      for (var link in dbLinks) {
        final String sUsername = (link['student_username'] ?? '').toString().toLowerCase().trim();
        if (studentUsernames.contains(sUsername)) {
          filteredLinks.add(Map<String, dynamic>.from(link));
        }
      }

      // Fallback: If no links exist, pair up real parents and students in-memory for testing
      if (filteredLinks.isEmpty &&
          parentProfiles.isNotEmpty &&
          filteredStudents.isNotEmpty) {
        for (
          int i = 0;
          i < min(parentProfiles.length, filteredStudents.length);
          i++
        ) {
      if (filteredLinks.isEmpty && parentProfiles.isNotEmpty && filteredStudents.isNotEmpty) {
        for (int i = 0; i < min(parentProfiles.length, filteredStudents.length); i++) {
          filteredLinks.add({
            'parent_id': parentProfiles[i]['id'].toString(),
            'student_username': filteredStudents[i]['username'].toString(),
          });
        }
      }

      // Resolve parent messages list using real DB records
      bool dirty = false;
      final Map<String, dynamic> teacherUnreadCounts =
          data['teacher_unread_counts'] ?? {};
      final Map<String, dynamic> teacherUnreadCounts = data['teacher_unread_counts'] ?? {};
      final Map<String, dynamic> urgents = data['urgents'] ?? {};
      final List<Map<String, dynamic>> resolvedParents = [];

      for (int i = 0; i < filteredLinks.length; i++) {
        final link = filteredLinks[i];
        final String studentUname = link['student_username'];
        final String parentId = link['parent_id'];

        final student = filteredStudents
            .cast<Map<String, dynamic>>()
            .firstWhere(
              (s) =>
                  s['username'].toString().toLowerCase().trim() ==
                  studentUname.toLowerCase().trim(),
              orElse: () => <String, dynamic>{},
            );

        final parent = parentProfiles.cast<Map<String, dynamic>>().firstWhere(
          (p) => p['id'].toString() == parentId,
          orElse: () => <String, dynamic>{},
        );

        final String parentSchool =
            parent['school']?.toString().toLowerCase().trim() ?? '';
        if (normalizedTeacherSchool.isNotEmpty &&
            parentSchool.isNotEmpty &&
            parentSchool != normalizedTeacherSchool) {
          continue;
        }

        if (student.containsKey('username') && parent.containsKey('id')) {
          final String studentName =
              student['full_name'] ?? student['username'] ?? 'Student';
          final String parentName =
              parent['full_name'] ?? parent['username'] ?? 'Parent';

        
        final student = filteredStudents.firstWhere(
          (s) => s['username'].toString().toLowerCase().trim() == studentUname.toLowerCase().trim(),
          orElse: () => null,
        );
        
        final parent = parentProfiles.firstWhere(
          (p) => p['id'].toString() == parentId,
          orElse: () => null,
        );
        
        if (student != null && parent != null) {
          final String studentName = student['full_name'] ?? student['username'] ?? 'Student';
          final String parentName = parent['full_name'] ?? parent['username'] ?? 'Parent';
          
          String avatar = 'P';
          final parts = parentName.split(' ');
          if (parts.length >= 2) {
            avatar = "${parts[0][0]}${parts[1][0]}".toUpperCase();
          } else if (parentName.isNotEmpty) {
            avatar = parentName
                .substring(0, min(2, parentName.length))
                .toUpperCase();
          }

          final String chatKey = "${student['username']}_$_teacherId";

          // Do not seed fake conversations; leave chat history empty until there is real data.

            avatar = parentName.substring(0, min(2, parentName.length)).toUpperCase();
          }
          
          final String chatKey = "${student['username']}_$_teacherId";
          
          // Seed conversation if not present
          if (!data.containsKey(chatKey)) {
            final now = DateTime.now();
            if (i == 0) {
              data[chatKey] = [
                {
                  'sender': 'parent',
                  'senderName': parentName,
                  'text': "Re: ${studentName}'s reading progress. Hi teacher, ${studentName} has been practicing reading every night. They are doing much better.",
                  'time': "11:05 AM",
                  'date': now.toIso8601String()
                }
              ];
              teacherUnreadCounts[chatKey] = 1;
            } else if (i == 1) {
              data[chatKey] = [
                {
                  'sender': 'parent',
                  'senderName': parentName,
                  'text': "${studentName} missed school due to illness. They have a fever and we went to the clinic.",
                  'time': "9:50 AM",
                  'date': now.toIso8601String()
                }
              ];
              teacherUnreadCounts[chatKey] = 1;
              urgents[chatKey] = true;
            } else {
              data[chatKey] = [
                {
                  'sender': 'teacher',
                  'senderName': widget.teacherName,
                  'text': "Thank you for the feedback, $parentName! Let me know if ${studentName} needs help.",
                  'time': "Yesterday",
                  'date': now.subtract(const Duration(days: 1)).toIso8601String()
                }
              ];
              teacherUnreadCounts[chatKey] = 0;
            }
            dirty = true;
          }
          
          resolvedParents.add({
            'studentName': studentName,
            'studentUser': student['username'],
            'parentName': parentName,
            'avatar': avatar,
            'level': mapDBLevelToMock(student['level'] ?? 'Standard 4'),
            'status': Random().nextBool() ? 'Online' : 'Offline',
            'chatKey': chatKey,
          });
        }
      }

      // Do not seed default notifications; only preserve notifications created by real interactions.
      // Seed broadcasts list if not present
      if (!data.containsKey('broadcasts')) {
        data['broadcasts'] = [
          {
            'id': 'b1',
            'title': "Term 2 Exam Schedule",
            'message': "Term 2 Exam Schedule has been finalized. Please make sure students revise units 1 to 5.",
            'sentTo': ["Std 4A"],
            'time': "Mon",
            'date': DateTime.now().subtract(const Duration(days: 3)).toIso8601String(),
            'recipientCount': 28
          }
        ];
        dirty = true;
      }

      // Seed default notifications list if not present
      if (!data.containsKey('notifications')) {
        data['notifications'] = [
          {
            'id': 'n1',
            'title': "Mrs. Kamau sent you a message about Amani's assessment results",
            'body': "Std 4A · 10:22 AM",
            'class': "Std 4A",
            'time': "10:22 AM",
            'date': DateTime.now().toIso8601String(),
            'type': "urgent",
            'read': false
          },
          {
            'id': 'n2',
            'title': "Ms. Oloo marked a message urgent — absence follow-up",
            'body': "Std 4A · 9:15 AM",
            'class': "Std 4A",
            'time': "9:15 AM",
            'date': DateTime.now().toIso8601String(),
            'type': "urgent",
            'read': false
          },
          {
            'id': 'n3',
            'title': "Mr. Mwangi replied to your message about the science project",
            'body': "Std 7B · Yesterday 4:30 PM",
            'class': "Std 7B",
            'time': "Yesterday 4:30 PM",
            'date': DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
            'type': "reply",
            'read': false
          },
          {
            'id': 'n4',
            'title': "School broadcast: End-of-term parent meeting on 28 June at 2 PM",
            'body': "Mwangi Primary · Mon",
            'class': "Mwangi Primary",
            'time': "Mon",
            'date': DateTime.now().subtract(const Duration(days: 3)).toIso8601String(),
            'type': "info",
            'read': true
          },
          {
            'id': 'n5',
            'title': "Mr. Njoroge updated the Term 2 timetable",
            'body': "Std 7B · Fri",
            'class': "Std 7B",
            'time': "Fri",
            'date': DateTime.now().subtract(const Duration(days: 5)).toIso8601String(),
            'type': "info",
            'read': true
          }
        ];
        dirty = true;
      }

      if (dirty) {
        await file.writeAsString(jsonEncode(data));
      }

      final List<Map<String, dynamic>> parentConversationsList = [];

      for (var parent in resolvedParents) {
        final String chatKey = parent['chatKey'];
        final List<dynamic> history = data[chatKey] ?? [];
        if (history.isEmpty) {
          continue;
        }

        List<dynamic> history = data[chatKey] ?? [];
        String lastMsgText = "No messages yet";
        String lastMsgTime = "";
        DateTime sortTime = DateTime.fromMillisecondsSinceEpoch(0);

        final lastMsg = history.last;
        lastMsgText = lastMsg['imagePath'] != null
            ? "📷 Attachment"
            : (lastMsg['text'] ?? "");
        lastMsgTime = lastMsg['time'] ?? "";
        if (lastMsg['date'] != null) {
          sortTime = DateTime.parse(lastMsg['date']);
        if (history.isNotEmpty) {
          final lastMsg = history.last;
          lastMsgText = lastMsg['imagePath'] != null ? "📷 Attachment" : (lastMsg['text'] ?? "");
          lastMsgTime = lastMsg['time'] ?? "";
          if (lastMsg['date'] != null) {
            sortTime = DateTime.parse(lastMsg['date']);
          }
        }

        final unreadCount = teacherUnreadCounts[chatKey] ?? 0;
        final isUrgent = urgents[chatKey] ?? false;

        parentConversationsList.add({
          'studentName': parent['studentName'],
          'studentUser': parent['studentUser'],
          'parentName': parent['parentName'],
          'avatar': parent['avatar'],
          'level': parent['level'],
          'status': parent['status'],
          'chatKey': chatKey,
          'lastMessage': lastMsgText,
          'time': lastMsgTime,
          'sortTime': sortTime,
          'unreadCount': unreadCount,
          'isUrgent': isUrgent,
        });
      }

      if (mounted) {
        setState(() {
          _parentMessages = parentConversationsList;
          _availableParentContacts = resolvedParents;
      // Load broadcasts from json
      final List<dynamic> jsonBroadcasts = data['broadcasts'] ?? [];
      final List<Map<String, dynamic>> broadcastsList = jsonBroadcasts.map((b) => Map<String, dynamic>.from(b)).toList();

      if (mounted) {
        setState(() {
          _parentMessages = parentConversationsList;
          _broadcasts = broadcastsList;
          _applyFilters();
          _isLoading = false;
        });
      }

    } catch (e) {
      debugPrint("Error loading teacher chat data: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _applyFilters() {
    List<Map<String, dynamic>> filteredMsg = List.from(_parentMessages);

    // Filter by tab
    if (_activeFilter == "Std 4") {
      filteredMsg = filteredMsg.where((m) => m['level'] == "Std 4").toList();
    } else if (_activeFilter == "Std 7") {
      filteredMsg = filteredMsg.where((m) => m['level'] == "Std 7").toList();
    } else if (_activeFilter == "Unread") {
      filteredMsg = filteredMsg
          .where((m) => (m['unreadCount'] as num) > 0)
          .toList();
    List<Map<String, dynamic>> filteredBrd = List.from(_broadcasts);

    // Filter by tab
    if (_activeFilter == "Std 4A") {
      filteredMsg = filteredMsg.where((m) => m['level'] == "Std 4A").toList();
      filteredBrd = filteredBrd.where((b) => (b['sentTo'] as List).contains("Std 4A")).toList();
    } else if (_activeFilter == "Std 7B") {
      filteredMsg = filteredMsg.where((m) => m['level'] == "Std 7B").toList();
      filteredBrd = filteredBrd.where((b) => (b['sentTo'] as List).contains("Std 7B")).toList();
    } else if (_activeFilter == "Unread") {
      filteredMsg = filteredMsg.where((m) => (m['unreadCount'] as num) > 0).toList();
      filteredBrd = []; // Broadcasts don't have unread counts on teacher side
    }

    // Filter by search
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filteredMsg = filteredMsg.where((m) {
        final parentName = m['parentName'].toString().toLowerCase();
        final text = m['lastMessage'].toString().toLowerCase();
        return parentName.contains(query) || text.contains(query);
      }).toList();

      filteredBrd = filteredBrd.where((b) {
        final title = b['title'].toString().toLowerCase();
        final msg = b['message'].toString().toLowerCase();
        return title.contains(query) || msg.contains(query);
      }).toList();
    }

    setState(() {
      _filteredParentMessages = filteredMsg;
      _filteredBroadcasts = filteredBrd;
    });
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _searchQuery = "";
      _isSearching = false;
    });
    _applyFilters();
  }

  String _t(String en, String sw) {
    return AppSettings.language.value == 'Kiswahili' ? sw : en;
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    const Color primaryNavy = Color(0xFF0F2C59);

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF121212)
          : const Color(0xFFF4F6F9),
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF4F6F9),
      appBar: AppBar(
        backgroundColor: primaryNavy,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: Colors.white, fontSize: 18),
                decoration: InputDecoration(
                  hintText: _t("Search messages...", "Tafuta ujumbe..."),
                  hintStyle: const TextStyle(color: Colors.white54),
                  border: InputBorder.none,
                ),
                onChanged: (val) {
                  setState(() => _searchQuery = val);
                  _applyFilters();
                },
              )
            : Text(
                _t("Messages", "Ujumbe"),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 24,
                  color: Colors.white,
                ),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 24, color: Colors.white),
              ),
        actions: [
          _isSearching
              ? IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: _clearSearch,
                )
              : IconButton(
                  icon: const Icon(
                    Icons.tune,
                    color: Colors.white,
                  ), // Funnel/Filter
                  onPressed: () => setState(() => _isSearching = true),
                ),
          IconButton(
            icon: const Icon(
              Icons.notifications_none_outlined,
              color: Colors.white,
            ),
                  icon: const Icon(Icons.tune, color: Colors.white), // Funnel/Filter
                  onPressed: () => setState(() => _isSearching = true),
                ),
          IconButton(
            icon: const Icon(Icons.notifications_none_outlined, color: Colors.white),
            tooltip: _t("Notifications", "Taarifa"),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const TeacherNotificationsScreen(),
                ),
              );
              _loadData();
            },
          ),
          IconButton(
            icon: const Icon(Icons.message_outlined, color: Colors.white),
            tooltip: _t("New Message", "Ujumbe Mpya"),
            icon: const Icon(Icons.edit_square, color: Colors.white),
            tooltip: _t("Broadcast Message", "Ujumbe wa Tangazo"),
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => TeacherComposeMessageScreen(
                    teacherName: widget.teacherName,
                    teacherId: _teacherId,
                    availableParents: _availableParentContacts,
                  ),
                  builder: (context) => const BroadcastMessageScreen(),
                ),
              );
              if (result == true) {
                _loadData();
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Tabs filter under AppBar
          Container(
            width: double.infinity,
            color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF4F6F9),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: ["All classes", "Std 4", "Std 7", "Unread"].map((
                  filterName,
                ) {
                children: ["All classes", "Std 4A", "Std 7B", "Unread"].map((filterName) {
                  final bool isSelected = _activeFilter == filterName;
                  return GestureDetector(
                    onTap: () {
                      setState(() => _activeFilter = filterName);
                      _applyFilters();
                    },
                    child: Container(
                      margin: const EdgeInsets.only(right: 10),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? primaryNavy
                            : (isDark ? Colors.grey[800] : Colors.white),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          if (!isSelected)
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                        ],
                      ),
                      child: Text(
                        _t(
                          filterName,
                          filterName == "Unread"
                              ? "Ambazo hazijasomwa"
                              : filterName,
                        ),
                        style: TextStyle(
                          color: isSelected
                              ? Colors.white
                              : (isDark ? Colors.white70 : Colors.black87),
                            )
                        ],
                      ),
                      child: Text(
                        _t(filterName, filterName == "Unread" ? "Ambazo hazijasomwa" : filterName),
                        style: TextStyle(
                          color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(primaryNavy),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
          
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(primaryNavy)))
                : ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    children: [
                      // Section 1: PARENT MESSAGES
                      if (_filteredParentMessages.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: Text(
                            _t("PARENT MESSAGES", "UJUMBE WA WAZAZI"),
                            style: TextStyle(
                              color: isDark ? Colors.white54 : Colors.grey[600],
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                        ..._filteredParentMessages.map((parentMsg) {
                          final int unreadCount = parentMsg['unreadCount'];
                          final bool isUrgent = parentMsg['isUrgent'];

                          return Card(
                            elevation: 0,
                            color: isDark
                                ? const Color(0xFF1E1E1E)
                                : Colors.white,
                            margin: const EdgeInsets.only(bottom: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          final bool isOnline = parentMsg['status'] == 'Online';

                          return Card(
                            elevation: 0,
                            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                            margin: const EdgeInsets.only(bottom: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            child: ListTile(
                              onTap: () async {
                                await _markAsRead(parentMsg['chatKey']);
                                if (!context.mounted) return;
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        TeacherConversationScreen(
                                          studentName: parentMsg['studentName'],
                                          studentUser: parentMsg['studentUser'],
                                          parentName: parentMsg['parentName'],
                                          studentLevel: parentMsg['level'],
                                          chatKey: parentMsg['chatKey'],
                                          teacherId: _teacherId,
                                          teacherName: widget.teacherName,
                                        ),
                                    builder: (context) => TeacherConversationScreen(
                                      studentName: parentMsg['studentName'],
                                      studentUser: parentMsg['studentUser'],
                                      parentName: parentMsg['parentName'],
                                      studentLevel: parentMsg['level'],
                                      chatKey: parentMsg['chatKey'],
                                      teacherId: _teacherId,
                                      teacherName: widget.teacherName,
                                    ),
                                  ),
                                );
                                _loadData();
                              },
                              leading: Stack(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: isDark
                                        ? Colors.grey[800]
                                    child: Text(
                                      parentMsg['avatar'] ?? 'P',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: primaryNavy,
                                      ),
                                    ),
                                  ),
                                  if (unreadCount > 0)
                                    Positioned(
                                      right: 0,
                                      top: 0,
                                    backgroundColor: isDark ? Colors.grey[800] : const Color(0xFFE8ECEF),
                                    child: Text(parentMsg['avatar'] ?? 'P', style: const TextStyle(fontWeight: FontWeight.bold, color: primaryNavy)),
                                  if (isOnline)
                                    Positioned(
                                      right: 0,
                                      bottom: 0,
                                      child: Container(
                                        width: 12,
                                        decoration: BoxDecoration(
                                          color: Colors.red,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: isDark
                                                ? const Color(0xFF1E1E1E)
                                                : Colors.white,
                                            width: 2,
                                          ),
                                          color: Colors.green,
                                          shape: BoxShape.circle,
                                          border: Border.all(color: isDark ? const Color(0xFF1E1E1E) : Colors.white, width: 2),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              title: Row(
                                children: [
                                  Text(
                                    parentMsg['parentName'],
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? Colors.grey[850]
                                          : const Color(0xFFE3F2FD),
                                  Text(parentMsg['parentName'], style: const TextStyle(fontWeight: FontWeight.bold)),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isDark ? Colors.grey[850] : const Color(0xFFE3F2FD),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      parentMsg['level'],
                                      style: TextStyle(
                                        color: isDark
                                            ? Colors.white70
                                            : const Color(0xFF1E88E5),
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      style: TextStyle(color: isDark ? Colors.white70 : const Color(0xFF1E88E5), fontSize: 10, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  if (isUrgent) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFD32F2F),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        _t("Urgent", "Haraka"),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(color: const Color(0xFFD32F2F), borderRadius: BorderRadius.circular(4)),
                                      child: Text(_t("Urgent", "Haraka"), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                    ),
                                  ]
                                ],
                              ),
                              subtitle: Text(
                                parentMsg['lastMessage'],
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: unreadCount > 0
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                                style: TextStyle(fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.normal),
                              ),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    parentMsg['time'],
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  Text(parentMsg['time'], style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                  const SizedBox(height: 4),
                                  if (unreadCount > 0)
                                    Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: const BoxDecoration(
                                        color: primaryNavy,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Text(
                                        '$unreadCount',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                      decoration: const BoxDecoration(color: primaryNavy, shape: BoxShape.circle),
                                      child: Text('$unreadCount', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                    )
                                ],
                              ),
                            ),
                          );
                        }),
                      ],
                        }).toList(),
                      ],

                      // Section 2: BROADCASTS SENT
                      if (_filteredBroadcasts.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: Text(
                            _t("BROADCASTS SENT", "TANGAKO ZILIZOTUMWA"),
                            style: TextStyle(
                              color: isDark ? Colors.white54 : Colors.grey[600],
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                        ..._filteredBroadcasts.map((broadcast) {
                          return Card(
                            elevation: 0,
                            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                            margin: const EdgeInsets.only(bottom: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            child: ListTile(
                              leading: const CircleAvatar(
                                backgroundColor: Color(0xFFE3F2FD),
                                child: Icon(Icons.campaign_outlined, color: primaryNavy),
                              ),
                              title: Text(broadcast['title'], style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text(
                                "Sent to all ${broadcast['sentTo']?.join(', ')} · ${broadcast['recipientCount']} delivered",
                                style: const TextStyle(fontSize: 13),
                              ),
                              trailing: Text(broadcast['time'], style: const TextStyle(fontSize: 11, color: Colors.grey)),
                            ),
                          );
                        }).toList(),
                      ]
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _markAsRead(String chatKey) async {
    try {
      final file = await _chatHistoryFile;
      if (await file.exists()) {
        final content = await file.readAsString();
        final Map<String, dynamic> data = jsonDecode(content);
        final Map<String, dynamic> unreadCounts =
            data['teacher_unread_counts'] ?? {};
        final Map<String, dynamic> unreadCounts = data['teacher_unread_counts'] ?? {};
        unreadCounts[chatKey] = 0;
        data['teacher_unread_counts'] = unreadCounts;
        await file.writeAsString(jsonEncode(data));
      }
    } catch (e) {
      debugPrint("Error marking read: $e");
    }
  }
}


// -----------------------------------------------------------------------------
// SCREEN 5 — NOTIFICATIONS
// -----------------------------------------------------------------------------
class TeacherNotificationsScreen extends StatefulWidget {
  const TeacherNotificationsScreen({super.key});

  @override
  State<TeacherNotificationsScreen> createState() =>
      _TeacherNotificationsScreenState();
}

class _TeacherNotificationsScreenState
    extends State<TeacherNotificationsScreen> {
  State<TeacherNotificationsScreen> createState() => _TeacherNotificationsScreenState();
}

class _TeacherNotificationsScreenState extends State<TeacherNotificationsScreen> {
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<File> get _chatHistoryFile async {
    final directory = await AppSettings.getSafeDirectory();
    return File('${directory.path}/parent_chats_config.json');
  }

  Future<void> _loadNotifications() async {
    try {
      final file = await _chatHistoryFile;
      if (await file.exists()) {
        final content = await file.readAsString();
        final Map<String, dynamic> data = jsonDecode(content);
        final List<dynamic> list = data['notifications'] ?? [];
        setState(() {
          _notifications = list
              .map((n) => Map<String, dynamic>.from(n))
              .toList();
          _notifications = list.map((n) => Map<String, dynamic>.from(n)).toList();
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint("Error loading notifications: $e");
      setState(() => _isLoading = false);
    }
  }

  Future<void> _markAllRead() async {
    try {
      final file = await _chatHistoryFile;
      if (await file.exists()) {
        final content = await file.readAsString();
        final Map<String, dynamic> data = jsonDecode(content);
        final List<dynamic> list = data['notifications'] ?? [];

        
        for (var item in list) {
          item['read'] = true;
        }
        data['notifications'] = list;
        await file.writeAsString(jsonEncode(data));

        setState(() {
          _notifications = list
              .map((n) => Map<String, dynamic>.from(n))
              .toList();
        
        setState(() {
          _notifications = list.map((n) => Map<String, dynamic>.from(n)).toList();
        });
      }
    } catch (e) {
      debugPrint("Error marking all read: $e");
    }
  }

  String _t(String en, String sw) {
    return AppSettings.language.value == 'Kiswahili' ? sw : en;
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    const Color primaryNavy = Color(0xFF0F2C59);

    final todayNotifs = _notifications.where((n) {
      final dateStr = n['date'];
      if (dateStr == null) return true;
      final dt = DateTime.parse(dateStr);
      final difference = DateTime.now().difference(dt).inDays;
      return difference == 0;
    }).toList();

    final earlierNotifs = _notifications.where((n) {
      final dateStr = n['date'];
      if (dateStr == null) return false;
      final dt = DateTime.parse(dateStr);
      final difference = DateTime.now().difference(dt).inDays;
      return difference > 0;
    }).toList();

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF121212)
          : const Color(0xFFF4F6F9),
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF4F6F9),
      appBar: AppBar(
        backgroundColor: primaryNavy,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          _t("Notifications", "Taarifa"),
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: _markAllRead,
            child: Text(
              _t("Mark all read", "Zisome zote"),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _notifications.isEmpty
          ? Center(child: Text(_t("No notifications.", "Hakuna taarifa.")))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (todayNotifs.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Text(
                      _t("TODAY", "LEO"),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  ...todayNotifs.map((n) => _buildNotificationTile(n)),
                ],
                if (earlierNotifs.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Text(
                      _t("EARLIER", "ZILIZOPITA"),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  ...earlierNotifs.map((n) => _buildNotificationTile(n)),
                ],
              ],
            ),
              ? Center(child: Text(_t("No notifications.", "Hakuna taarifa.")))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (todayNotifs.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Text(
                          _t("TODAY", "LEO"),
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 12),
                        ),
                      ),
                      ...todayNotifs.map((n) => _buildNotificationTile(n)),
                    ],
                    if (earlierNotifs.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Text(
                          _t("EARLIER", "ZILIZOPITA"),
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 12),
                        ),
                      ),
                      ...earlierNotifs.map((n) => _buildNotificationTile(n)),
                    ],
                  ],
                ),
    );
  }

  Widget _buildNotificationTile(Map<String, dynamic> n) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isRead = n['read'] ?? false;
    final String type = n['type'] ?? 'info';

    
    Color dotColor = Colors.grey;
    if (!isRead) {
      if (type == 'urgent') {
        dotColor = Colors.red;
      } else if (type == 'reply') {
        dotColor = Colors.orange;
      } else {
        dotColor = Colors.green;
      }
    }

    return Card(
      elevation: 0,
      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
        ),
        title: Text(
          n['title'] ?? '',
          style: TextStyle(
            fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
            fontSize: 14,
          ),
        ),
        subtitle: Text(
          n['body'] ?? '',
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        trailing: Text(
          n['time'] ?? '',
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
          style: TextStyle(fontWeight: isRead ? FontWeight.normal : FontWeight.bold, fontSize: 14),
        ),
        subtitle: Text(n['body'] ?? '', style: const TextStyle(fontSize: 12, color: Colors.grey)),
        trailing: Text(n['time'] ?? '', style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// SCREEN 6 — TEACHER COMPOSE MESSAGE
// -----------------------------------------------------------------------------
class TeacherComposeMessageScreen extends StatefulWidget {
  final String teacherName;
  final String teacherId;
  final List<Map<String, dynamic>> availableParents;

  const TeacherComposeMessageScreen({
    super.key,
    required this.teacherName,
    required this.teacherId,
    required this.availableParents,
  });

  @override
  State<TeacherComposeMessageScreen> createState() =>
      _TeacherComposeMessageScreenState();
}

class _TeacherComposeMessageScreenState
    extends State<TeacherComposeMessageScreen> {
  Map<String, dynamic>? _selectedParent;

  @override
  void initState() {
    super.initState();
    if (widget.availableParents.isNotEmpty) {
      _selectedParent = widget.availableParents.first;
    }

// -----------------------------------------------------------------------------
// SCREEN 6 — BROADCAST MESSAGE
// -----------------------------------------------------------------------------
class BroadcastMessageScreen extends StatefulWidget {
  const BroadcastMessageScreen({super.key});

  @override
  State<BroadcastMessageScreen> createState() => _BroadcastMessageScreenState();
}

class _BroadcastMessageScreenState extends State<BroadcastMessageScreen> {
  final TextEditingController _subjectController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();

  final List<String> _selectedGroups = ["All Std 4A parents", "All Std 7B parents"];
  bool _scheduleForLater = false;
  DateTime? _scheduledDate;
  TimeOfDay? _scheduledTime;

  Future<File> get _chatHistoryFile async {
    final directory = await AppSettings.getSafeDirectory();
    return File('${directory.path}/parent_chats_config.json');
  }

  Future<void> _sendBroadcast() async {
    if (_subjectController.text.trim().isEmpty || _messageController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter a subject and a message.")),
      );
      return;
    }

    try {
      final file = await _chatHistoryFile;
      Map<String, dynamic> data = {};
      if (await file.exists()) {
        final content = await file.readAsString();
        data = jsonDecode(content);
      }

      final List<dynamic> broadcasts = data['broadcasts'] ?? [];
      
      final now = DateTime.now();
      final Map<String, dynamic> newBroadcast = {
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'title': _subjectController.text.trim(),
        'message': _messageController.text.trim(),
        'sentTo': _selectedGroups.map((g) => g.replaceAll("All ", "").replaceAll(" parents", "")).toList(),
        'time': DateFormat.jm().format(now),
        'date': now.toIso8601String(),
        'recipientCount': 32
      };

      broadcasts.insert(0, newBroadcast);
      data['broadcasts'] = broadcasts;

      // Broadcast message delivery simulation: append messages to matching group chats
      final targetClasses = _selectedGroups.map((g) => g.replaceAll("All ", "").replaceAll(" parents", "")).toList();
      
      // Seed group/class chats inside JSON
      // Mrs. Kamau matches Greenwood Academy Std 4
      final amaniClassKey = "amani_group_Greenwood Academy_class";
      if (targetClasses.contains("Std 4A")) {
        if (!data.containsKey(amaniClassKey)) {
          data[amaniClassKey] = [];
        }
        final List<dynamic> history = data[amaniClassKey];
        history.add({
          'sender': 'teacher',
          'senderName': 'Mrs. Kamau',
          'text': "📢 BROADCAST: ${_subjectController.text.trim()}\n\n${_messageController.text.trim()}",
          'time': DateFormat.jm().format(now),
          'date': now.toIso8601String(),
        });
        data[amaniClassKey] = history;
      }

      await file.writeAsString(jsonEncode(data));

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint("Error sending broadcast: $e");
    }
  }

  void _showAddGroupDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Add Class Group"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: ["All Std 4B parents", "All Std 7A parents", "All Std 3 parents"].map((g) {
              return ListTile(
                title: Text(g),
                onTap: () {
                  if (!_selectedGroups.contains(g)) {
                    setState(() => _selectedGroups.add(g));
                  }
                  Navigator.pop(context);
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }

  String _t(String en, String sw) {
    return AppSettings.language.value == 'Kiswahili' ? sw : en;
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final parentOptions = widget.availableParents;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF121212)
          : const Color(0xFFF4F6F9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F2C59),
        title: Text(
          'New Message',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Select a parent',
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.grey[800],
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<Map<String, dynamic>>(
              initialValue: _selectedParent,
              items: parentOptions.map((parent) {
                final display =
                    '${parent['parentName'] ?? 'Parent'} — ${parent['studentName'] ?? 'Student'} (${parent['level'] ?? ''})';
                return DropdownMenuItem<Map<String, dynamic>>(
                  value: parent,
                  child: Text(display, overflow: TextOverflow.ellipsis),
                );
              }).toList(),
              decoration: InputDecoration(
                filled: true,
                fillColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (selected) {
                setState(() {
                  _selectedParent = selected;
                });
              },
              hint: const Text('Choose a parent'),
            ),
            const SizedBox(height: 24),
            if (_selectedParent != null) ...[
              Card(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  leading: CircleAvatar(
                    backgroundColor: isDark
                        ? const Color(0xFF1E1E1E)
                        : const Color(0xFFE8ECEF),
                    child: Text(
                      _selectedParent!['avatar'] ?? 'P',
                      style: const TextStyle(
                        color: Color(0xFF0F2C59),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Text(
                    _selectedParent!['parentName'] ?? 'Parent',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    '${_selectedParent!['studentName'] ?? 'Student'} · ${_selectedParent!['level'] ?? ''}',
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () {
                    final parent = _selectedParent!;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => TeacherConversationScreen(
                          studentName: parent['studentName'] ?? 'Student',
                          studentUser: parent['studentUser'] ?? '',
                          parentName: parent['parentName'] ?? 'Parent',
                          studentLevel: parent['level'] ?? '',
                          chatKey:
                              parent['chatKey'] ??
                              '${parent['studentUser']}_${widget.teacherId}',
                          teacherId: widget.teacherId,
                          teacherName: widget.teacherName,
                        ),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F2C59),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Open Chat',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ] else ...[
              Expanded(
                child: Center(
                  child: Text(
                    'No parents are available for this school.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isDark ? Colors.white54 : Colors.grey[600],
                    ),
                  ),
                ),
              ),
            ],
    const Color primaryNavy = Color(0xFF0F2C59);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: primaryNavy),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _t("Broadcast Message", "Tangazo"),
          style: const TextStyle(color: primaryNavy, fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Send To
            Text(_t("Send to", "Tuma Kwa"), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ..._selectedGroups.map((g) {
                  return Chip(
                    label: Text(g, style: const TextStyle(fontSize: 12)),
                    deleteIcon: const Icon(Icons.close, size: 14),
                    onDeleted: () => setState(() => _selectedGroups.remove(g)),
                  );
                }),
                ActionChip(
                  label: const Text("+ Add group", style: TextStyle(fontSize: 12)),
                  onPressed: _showAddGroupDialog,
                )
              ],
            ),
            const SizedBox(height: 6),
            Text(
              "32 parents will receive this message",
              style: TextStyle(color: Colors.grey[600], fontSize: 12, fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 20),

            // Subject
            Text(_t("Subject", "Somo/Kichwa"), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 8),
            TextField(
              controller: _subjectController,
              decoration: InputDecoration(
                hintText: "e.g. End-of-Term Meeting — 28 June",
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
            const SizedBox(height: 20),

            // Message
            Text(_t("Message", "Ujumbe"), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 8),
            TextField(
              controller: _messageController,
              maxLines: 8,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: _t("Type your message here...", "Andika ujumbe wako hapa..."),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.all(16),
              ),
            ),
            const SizedBox(height: 20),

            // Schedule for later
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_t("Schedule for later", "Ratibu kwa ajili ya baadaye"), style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(
                      "Send at a specific time",
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ],
                ),
                Switch(
                  value: _scheduleForLater,
                  onChanged: (val) {
                    setState(() => _scheduleForLater = val);
                  },
                ),
              ],
            ),
            if (_scheduleForLater) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 30)),
                      );
                      if (date != null) setState(() => _scheduledDate = date);
                    },
                    icon: const Icon(Icons.calendar_today),
                    label: Text(_scheduledDate == null ? "Select Date" : DateFormat.yMMMd().format(_scheduledDate!)),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final time = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.now(),
                      );
                      if (time != null) setState(() => _scheduledTime = time);
                    },
                    icon: const Icon(Icons.access_time),
                    label: Text(_scheduledTime == null ? "Select Time" : _scheduledTime!.format(context)),
                  ),
                ],
              )
            ],

            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _sendBroadcast,
                icon: const Icon(Icons.send, color: Colors.white),
                label: Text(
                  _t("Send to 32 parents", "Tuma kwa wazazi 32"),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryNavy,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}


// -----------------------------------------------------------------------------
// TEACHER CONVERSATION DETAIL VIEW
// -----------------------------------------------------------------------------
class TeacherConversationScreen extends StatefulWidget {
  final String studentName;
  final String studentUser;
  final String parentName;
  final String studentLevel;
  final String chatKey;
  final String teacherId;
  final String teacherName;

  const TeacherConversationScreen({
    super.key,
    required this.studentName,
    required this.studentUser,
    required this.parentName,
    required this.studentLevel,
    required this.chatKey,
    required this.teacherId,
    required this.teacherName,
  });

  @override
  State<TeacherConversationScreen> createState() =>
      _TeacherConversationScreenState();
  State<TeacherConversationScreen> createState() => _TeacherConversationScreenState();
}

class _TeacherConversationScreenState extends State<TeacherConversationScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker();
  bool _isLoading = true;
  bool _isTyping = false;
  List<Map<String, dynamic>> _messages = [];
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _loadMessagesSilence();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  bool _useDatabase = false;

  Future<File> get _chatHistoryFile async {
    final directory = await AppSettings.getSafeDirectory();
    return File('${directory.path}/parent_chats_config.json');
  }

  Future<void> _loadMessages() async {
    try {
      final res = await Supabase.instance.client
          .from('messages')
          .select()
          .eq('chat_key', widget.chatKey)
          .order('created_at', ascending: true);

      
      final List<dynamic> data = res as List<dynamic>;
      final List<Map<String, dynamic>> dbMsgs = data.map((item) {
        return {
          'sender': item['sender'].toString(),
          'senderName': item['sender_name'].toString(),
          'text': item['text'].toString(),
          'time': item['created_at'] != null
              ? DateFormat.jm().format(
                  DateTime.parse(item['created_at'].toString()).toLocal(),
                )
          'time': item['created_at'] != null 
              ? DateFormat.jm().format(DateTime.parse(item['created_at'].toString()).toLocal()) 
              : '',
          'date': item['created_at']?.toString() ?? '',
          'subject': item['subject']?.toString() ?? '',
          'priority': item['priority']?.toString() ?? 'Normal',
        };
      }).toList();

      setState(() {
        _messages = dbMsgs;
        _useDatabase = true;
        _isLoading = false;
      });
      _scrollToBottom();
    } catch (e) {
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('pgrst205') ||
          errStr.contains('not find the table') ||
          errStr.contains('404')) {
      if (errStr.contains('pgrst205') || errStr.contains('not find the table') || errStr.contains('404')) {
        debugPrint("Supabase messages table not found. Falling back to JSON.");
      } else {
        debugPrint("Error fetching from Supabase messages table: $e");
      }
      setState(() => _useDatabase = false);
      await _loadMessagesFromJson();
    }
  }

  Future<void> _loadMessagesFromJson() async {
    try {
      final file = await _chatHistoryFile;
      if (await file.exists()) {
        final content = await file.readAsString();
        final Map<String, dynamic> data = jsonDecode(content);
        if (data.containsKey(widget.chatKey)) {
          setState(() {
            _messages = List<Map<String, dynamic>>.from(data[widget.chatKey]);
            _isLoading = false;
          });
          _scrollToBottom();
        } else {
          setState(() => _isLoading = false);
        }
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint("Error loading messages from JSON: $e");
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMessagesSilence() async {
    if (_useDatabase) {
      try {
        final res = await Supabase.instance.client
            .from('messages')
            .select()
            .eq('chat_key', widget.chatKey)
            .order('created_at', ascending: true);
        final List<dynamic> data = res as List<dynamic>;
        final List<Map<String, dynamic>> dbMsgs = data.map((item) {
          return {
            'sender': item['sender'].toString(),
            'senderName': item['sender_name'].toString(),
            'text': item['text'].toString(),
            'time': item['created_at'] != null
                ? DateFormat.jm().format(
                    DateTime.parse(item['created_at'].toString()).toLocal(),
                  )
            'time': item['created_at'] != null 
                ? DateFormat.jm().format(DateTime.parse(item['created_at'].toString()).toLocal()) 
                : '',
            'date': item['created_at']?.toString() ?? '',
            'subject': item['subject']?.toString() ?? '',
            'priority': item['priority']?.toString() ?? 'Normal',
          };
        }).toList();

        if (dbMsgs.length != _messages.length) {
          setState(() {
            _messages = dbMsgs;
          });
          _scrollToBottom();
        }
      } catch (e) {
        debugPrint("Error fetching silence from Supabase: $e");
      }
    } else {
      try {
        final file = await _chatHistoryFile;
        if (await file.exists()) {
          final content = await file.readAsString();
          final Map<String, dynamic> data = jsonDecode(content);
          if (data.containsKey(widget.chatKey)) {
            final List<Map<String, dynamic>> newMsgs =
                List<Map<String, dynamic>>.from(data[widget.chatKey]);
            final List<Map<String, dynamic>> newMsgs = List<Map<String, dynamic>>.from(data[widget.chatKey]);
            if (newMsgs.length != _messages.length) {
              setState(() {
                _messages = newMsgs;
              });
              _scrollToBottom();
            }
          }
        }
      } catch (e) {
        debugPrint("Error loading messages silently: $e");
      }
    }
  }

  Future<void> _saveMessages() async {
    try {
      final file = await _chatHistoryFile;
      Map<String, dynamic> data = {};
      if (await file.exists()) {
        final content = await file.readAsString();
        data = jsonDecode(content);
      }
      data[widget.chatKey] = _messages;
      await file.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint("Error saving messages to JSON: $e");
    }
  }

  Future<void> _incrementParentUnreadCount() async {
    try {
      final file = await _chatHistoryFile;
      final Map<String, dynamic> data = {};
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.isNotEmpty) {
          data.addAll(jsonDecode(content));
        }
      }
      final Map<String, dynamic> unreadCounts = Map<String, dynamic>.from(
        data['unread_counts'] ?? {},
      );
      final int current = (unreadCounts[widget.chatKey] as int?) ?? 0;
      unreadCounts[widget.chatKey] = current + 1;
      data['unread_counts'] = unreadCounts;
      await file.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint("Error incrementing parent unread count: $e");
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
      );
      if (image == null) return;

      final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
      if (image == null) return;
      
      final now = DateTime.now();
      setState(() {
        _messages.add({
          'sender': 'teacher',
          'senderName': widget.teacherName,
          'imagePath': image.path,
          'time': DateFormat.jm().format(now),
          'date': now.toIso8601String(),
        });
      });
      _scrollToBottom();
      await _saveMessages();
      _triggerDelayedResponse("Shared a photo.");
    } catch (e) {
      debugPrint("Error picking image: $e");
    }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.pickFiles();
      if (result == null || result.files.single.path == null) return;

      final filename = result.files.single.name;
      final now = DateTime.now();
      setState(() {
        _messages.add({
          'sender': 'teacher',
          'senderName': widget.teacherName,
          'text': "📎 File: $filename",
          'time': DateFormat.jm().format(now),
          'date': now.toIso8601String(),
        });
      });
      _scrollToBottom();
      await _saveMessages();
      _triggerDelayedResponse("Shared document: $filename");
    } catch (e) {
      debugPrint("Error picking file: $e");
    }
  }

  Future<void> _sendMessage({String? customText}) async {
    final text = customText ?? _messageController.text.trim();
    if (text.isEmpty) return;

    if (customText == null) {
      _messageController.clear();
    }

    final now = DateTime.now();
    final newMsg = {
      'sender': 'teacher',
      'senderName': widget.teacherName,
      'text': text,
      'time': DateFormat.jm().format(now),
      'date': now.toIso8601String(),
    };

    if (_useDatabase) {
      try {
        await Supabase.instance.client.from('messages').insert({
          'chat_key': widget.chatKey,
          'sender': 'teacher',
          'sender_name': widget.teacherName,
          'text': text,
          'subject': '',
          'priority': 'Normal',
          'read': false,
        });
        setState(() {
          _messages.add(newMsg);
        });
        _scrollToBottom();
        await _saveMessages();
      } catch (e) {
        debugPrint("Error saving teacher message to database: $e");
        setState(() {
          _messages.add(newMsg);
        });
        _scrollToBottom();
        await _saveMessages();
      }
    } else {
      setState(() {
        _messages.add(newMsg);
      });
      _scrollToBottom();
      await _saveMessages();
    }

    await _incrementParentUnreadCount();
    // Trigger parent response simulation
    _triggerDelayedResponse(text);
  }

  void _triggerDelayedResponse(String triggerText) {
    setState(() => _isTyping = true);
    _scrollToBottom();

    Future.delayed(const Duration(seconds: 2), () async {
      if (!mounted) return;

      String reply = "";
      final lower = triggerText.toLowerCase();

      if (lower.contains("hello") || lower.contains("habari")) {
        reply = "Hello, teacher! Thank you for checking in. How is David doing in class?";
      } else if (lower.contains("progress") || lower.contains("reading") || lower.contains("performance")) {
        reply = "Thank you so much. We have been reading together daily and his confidence is growing!";
      } else if (lower.contains("homework") || lower.contains("assignment")) {
        reply = "I will sit down with David tonight and ensure he completes the division homework.";
      } else {
        reply = "Thank you, teacher. We appreciate all your guidance and support!";
      }

      final now = DateTime.now();
      final replyMsg = {
        'sender': 'parent',
        'senderName': widget.parentName,
        'text': reply,
        'time': DateFormat.jm().format(now),
        'date': now.toIso8601String(),
      };

      if (_useDatabase) {
        try {
          await Supabase.instance.client.from('messages').insert({
            'chat_key': widget.chatKey,
            'sender': 'parent',
            'sender_name': widget.parentName,
            'text': reply,
            'subject': '',
            'priority': 'Normal',
            'read': false,
          });
          setState(() {
            _messages.add(replyMsg);
            _isTyping = false;
          });
          _scrollToBottom();
        } catch (e) {
          debugPrint("Error saving simulated parent response to database: $e");
          setState(() {
            _messages.add(replyMsg);
            _isTyping = false;
          });
          _scrollToBottom();
          await _saveMessages();
        }
      } else {
        setState(() {
          _messages.add(replyMsg);
          _isTyping = false;
        });
        _scrollToBottom();
        await _saveMessages();
      }
    });
  }

  String _t(String en, String sw) {
    return AppSettings.language.value == 'Kiswahili' ? sw : en;
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    const Color primaryNavy = Color(0xFF0F2C59);

    final quickReplies = [
      {'en': 'Please review today\'s quiz', 'sw': 'Kagua chemsha bongo ya leo'},
      {'en': 'Great progress today!', 'sw': 'Maendeleo mazuri leo!'},
      {
        'en': 'Ensure homework is complete',
        'sw': 'Hakikisha homework imekamilika',
      },
    ];

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF121212)
          : const Color(0xFFF4F6F9),
      {'en': 'Ensure homework is complete', 'sw': 'Hakikisha homework imekamilika'},
    ];

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF4F6F9),
      appBar: AppBar(
        backgroundColor: primaryNavy,
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: Colors.white24,
              child: Text(
                widget.parentName
                    .substring(0, min(2, widget.parentName.length))
                    .toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
                widget.parentName.substring(0, min(2, widget.parentName.length)).toUpperCase(),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.parentName,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    "Parent of ${widget.studentName} · ${widget.studentLevel}",
                    style: const TextStyle(fontSize: 11, color: Colors.white70),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      final bool isMe = msg['sender'] == 'teacher';
                      final bool showSeparator = index == 0;

                      
                      return Column(
                        children: [
                          if (showSeparator)
                            Container(
                              margin: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                _t("Today", "Leo"),
                                style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          Align(
                            alignment: isMe
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.of(context).size.width * 0.75,
                              ),
                              decoration: BoxDecoration(
                                color: isMe
                                    ? primaryNavy
                                    : (isDark
                                          ? const Color(0xFF262626)
                                          : Colors.white),
                                style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ),
                          Align(
                            alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              constraints: BoxConstraints(
                                maxWidth: MediaQuery.of(context).size.width * 0.75,
                              ),
                              decoration: BoxDecoration(
                                color: isMe 
                                    ? primaryNavy 
                                    : (isDark ? const Color(0xFF262626) : Colors.white),
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.04),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                  )
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (msg['imagePath'] != null) ...[
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.file(
                                        io.File(msg['imagePath']!),
                                        fit: BoxFit.cover,
                                        errorBuilder:
                                            (context, error, stackTrace) =>
                                                const Icon(
                                                  Icons.broken_image,
                                                  size: 50,
                                                ),
                                        errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image, size: 50),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                  ],
                                  if (msg['text'] != null)
                                    Text(
                                      msg['text']!,
                                      style: TextStyle(
                                        color: isMe
                                            ? Colors.white
                                            : (isDark
                                                  ? Colors.white70
                                                  : Colors.black87),
                                        color: isMe ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                                        fontSize: 15,
                                      ),
                                    ),
                                  const SizedBox(height: 4),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      const Spacer(),
                                      Text(
                                        msg['time'] ?? '',
                                        style: TextStyle(
                                          color: isMe
                                              ? Colors.white70
                                              : Colors.grey,
                                          color: isMe ? Colors.white70 : Colors.grey,
                                          fontSize: 10,
                                        ),
                                      ),
                                      if (isMe) ...[
                                        const SizedBox(width: 4),
                                        const Text(
                                          "✓✓",
                                          style: TextStyle(
                                            color: Colors.green,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                          style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold),
                                        )
                                      ]
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),

          
          if (_isTyping)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _t("${widget.parentName} is typing...", "${widget.parentName} anaandika..."),
                  style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.grey, fontSize: 12),
                ),
              ),
            ),
            
          // Quick actions for teacher
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: quickReplies.length,
              itemBuilder: (context, index) {
                final item = quickReplies[index];
                final String replyText = _t(item['en']!, item['sw']!);
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    label: Text(
                      replyText,
                      style: const TextStyle(fontSize: 12),
                    ),
                    backgroundColor: isDark
                        ? const Color(0xFF1E1E1E)
                        : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    label: Text(replyText, style: const TextStyle(fontSize: 12)),
                    backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    onPressed: () => _sendMessage(customText: replyText),
                  ),
                );
              },
            ),
          ),

          
          // Bottom Input Bar
          Container(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 24),
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.attach_file, color: Colors.grey),
                  onPressed: _pickFile,
                ),
                IconButton(
                  icon: const Icon(
                    Icons.camera_alt_outlined,
                    color: Colors.grey,
                  ),
                  onPressed: _pickImage,
                ),
                IconButton(
                  icon: const Icon(
                    Icons.description_outlined,
                    color: Colors.grey,
                  ),
                  icon: const Icon(Icons.camera_alt_outlined, color: Colors.grey),
                  onPressed: _pickImage,
                ),
                IconButton(
                  icon: const Icon(Icons.description_outlined, color: Colors.grey),
                  onPressed: _pickFile,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: _t("Type a message...", "Andika ujumbe..."),
                      filled: true,
                      fillColor: isDark
                          ? const Color(0xFF2C2C2C)
                          : const Color(0xFFF1F3F5),
                      fillColor: isDark ? const Color(0xFF2C2C2C) : const Color(0xFFF1F3F5),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: primaryNavy,
                  radius: 22,
                  child: IconButton(
                    icon: const Icon(
                      Icons.send_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                    onPressed: () => _sendMessage(),
                  ),
                ),
              ],
            ),
          ),
                    icon: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                    onPressed: () => _sendMessage(),
                  ),
                )
              ],
            ),
          )
        ],
      ),
    );
  }
}
