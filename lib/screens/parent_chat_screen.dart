import 'dart:async';
import 'dart:io' hide File, Directory;
import 'dart:io' as io;
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import '../main.dart';
import '../services/web_safe_file.dart';

// -----------------------------------------------------------------------------
// SCREEN 1 — PARENT INBOX & CONTROLLERS
// -----------------------------------------------------------------------------
class ParentChatScreen extends StatefulWidget {
  final String selectedChild;
  final String currentLevel;
  final String? selectedSchool;

  const ParentChatScreen({
    super.key,
    required this.selectedChild,
    required this.currentLevel,
    this.selectedSchool,
  });

  @override
  State<ParentChatScreen> createState() => _ParentChatScreenState();
}

class _ParentChatScreenState extends State<ParentChatScreen> {
  final supabase = Supabase.instance.client;
  bool _isLoading = true;
  String _schoolName = "";
  String _activeFilter = "All";
  String _searchQuery = "";
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _allConversations = [];
  List<Map<String, dynamic>> _filteredConversations = [];
  
  // Real DB teachers and filtered available ones
  List<Map<String, dynamic>> _dbTeachers = [];
  List<Map<String, dynamic>> _filteredAvailableTeachers = [];

  String _childFullName = "";

  @override
  void initState() {
    super.initState();
    _resolveSchool();
    _loadData();
  }

  void _resolveSchool() {
    if (widget.selectedSchool != null && widget.selectedSchool!.isNotEmpty) {
      _schoolName = widget.selectedSchool!;
    } else {
      _schoolName = "";
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final studentRes = await supabase
          .from('profiles')
          .select('full_name, school')
          .eq('username', widget.selectedChild)
          .maybeSingle();
      if (studentRes != null) {
        _childFullName = studentRes['full_name'] ?? widget.selectedChild;
        if ((_schoolName.isEmpty || _schoolName.trim().isEmpty) &&
            studentRes['school'] != null) {
          _schoolName = studentRes['school'].toString();
        }
      } else {
        _childFullName = widget.selectedChild;
      }
    } catch (e) {
      _childFullName = widget.selectedChild;
      debugPrint("Error fetching child full name in Chat: $e");
    }
    if (_schoolName.isEmpty) {
      _schoolName = widget.selectedChild.toLowerCase().startsWith('a')
          ? 'Mwangi Primary'
          : 'Greenwood Academy';
    }
    await _fetchDBTeachers();
    await _initializeChatConfigAndLoad();
  }

  Future<void> _fetchDBTeachers() async {
    try {
      final res = await supabase
          .from('profiles')
          .select('id, full_name, username, level, school')
          .ilike('role', 'teacher');
      
      final List<dynamic> data = res as List<dynamic>;
      _dbTeachers = data.map((t) {
        final name = t['full_name'] ?? t['username'] ?? 'Teacher';
        String avatar = 'T';
        final parts = name.toString().split(' ');
        if (parts.length >= 2) {
          avatar = "${parts[0][0]}${parts[1][0]}".toUpperCase();
        } else if (name.toString().isNotEmpty) {
          avatar = name.toString().substring(0, min(2, name.toString().length)).toUpperCase();
        }

        return {
          'id': t['id'].toString(),
          'name': name.toString(),
          'level': t['level']?.toString() ?? 'Std 4',
          'school': t['school']?.toString() ?? '',
          'status': Random().nextBool() ? 'Online' : 'Offline',
          'avatar': avatar,
          'subject': 'Mathematics',
          'role': 'Subject Teacher',
        };
      }).toList();

      // Filter DB teachers to match child's school and level
      _filteredAvailableTeachers = _dbTeachers.where((t) {
        final String tSchool = (t['school'] ?? '').toString().toLowerCase().trim();
        final String tLevel = (t['level'] ?? '').toString().toLowerCase().trim();
        final String childSchool = _schoolName.toLowerCase().trim();
        final String childLevel = widget.currentLevel.toLowerCase().trim();

        final bool schoolMatches = childSchool.isNotEmpty &&
            tSchool.isNotEmpty &&
            tSchool == childSchool;

        final bool levelMatches = tLevel.isEmpty ||
            tLevel == 'teacher' ||
            tLevel.contains(childLevel) ||
            childLevel.contains(tLevel);

        return schoolMatches && levelMatches;
      }).toList();
    } catch (e) {
      debugPrint("Error loading DB teachers: $e");
    }
  }

  Future<File> get _chatHistoryFile async {
    final directory = await AppSettings.getSafeDirectory();
    return File('${directory.path}/parent_chats_config.json');
  }

  void _purgeOldSeededChats(Map<String, dynamic> data) {
    final seededPatterns = [
      'Good morning! I wanted to share that',
      'needs a bit more practice on fractions',
      'Thank you so much',
      'Kindly confirm attendance for the upcoming parent-teacher conference',
      'Your child was absent today',
      'Term 2 schedule has been updated',
    ];

    final keysToRemove = <String>[];
    for (var entry in data.entries) {
      if (entry.key == 'unread_counts' || entry.key == 'urgents' || entry.key == 'notifications') {
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

    for (final key in keysToRemove) {
      data.remove(key);
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
      _purgeOldSeededChats(data);

      bool dirty = false;
      final Map<String, dynamic> unreadCounts = data['unread_counts'] ?? {};
      final Map<String, dynamic> urgents = data['urgents'] ?? {};

      // Seed initial messages using the real database teachers
      for (int i = 0; i < _filteredAvailableTeachers.length; i++) {
        final teacher = _filteredAvailableTeachers[i];
        final String chatKey = "${widget.selectedChild}_${teacher['id']}";
        
        // Do not seed fake conversations; leave chat history empty until there is real data.
      }

      data['unread_counts'] = unreadCounts;
      data['urgents'] = urgents;

      if (dirty) {
        await file.writeAsString(jsonEncode(data));
      }

      // Build unified conversations list
      final List<Map<String, dynamic>> conversations = [];
      
      // Remove duplicates by ID
      final Map<String, Map<String, dynamic>> uniqueTeachersMap = {};
      for (var t in _filteredAvailableTeachers) {
        uniqueTeachersMap[t['id']] = t;
      }

      for (var teacherId in uniqueTeachersMap.keys) {
        final teacher = uniqueTeachersMap[teacherId]!;
        final String chatKey = "${widget.selectedChild}_$teacherId";
        
        final List<dynamic> history = data[chatKey] ?? [];
        if (history.isEmpty) {
          continue;
        }

        final lastMsg = history.last;
        final String lastMsgText = lastMsg['imagePath'] != null
            ? "📷 Attachment"
            : (lastMsg['text'] ?? "");
        final String lastMsgTime = lastMsg['time'] ?? "";
        DateTime sortTime = DateTime.fromMillisecondsSinceEpoch(0);
        if (lastMsg['date'] != null) {
          sortTime = DateTime.parse(lastMsg['date']);
        }

        final unreadCount = unreadCounts[chatKey] ?? 0;
        final isUrgent = urgents[chatKey] ?? false;

        conversations.add({
          'teacher': teacher,
          'chatKey': chatKey,
          'lastMessage': lastMsgText,
          'time': lastMsgTime,
          'sortTime': sortTime,
          'unreadCount': unreadCount,
          'isUrgent': isUrgent,
        });
      }

      // Sort: urgent first, then by last message timestamp (most recent first)
      conversations.sort((a, b) {
        final bool aUrgent = a['isUrgent'];
        final bool bUrgent = b['isUrgent'];
        if (aUrgent && !bUrgent) return -1;
        if (!aUrgent && bUrgent) return 1;
        return (b['sortTime'] as DateTime).compareTo(a['sortTime'] as DateTime);
      });

      if (mounted) {
        setState(() {
          _allConversations = conversations;
          _applyFilters();
          _isLoading = false;
        });
      }

    } catch (e) {
      debugPrint("Error loading chat config: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _applyFilters() {
    List<Map<String, dynamic>> results = List.from(_allConversations);

    // Filter by tab
    if (_activeFilter == "Unread") {
      results = results.where((c) => (c['unreadCount'] as num) > 0).toList();
    } else if (_activeFilter == "Std 4") {
      results = results.where((c) => c['teacher']['level'].toString().contains("4")).toList();
    } else if (_activeFilter == "Std 7") {
      results = results.where((c) => c['teacher']['level'].toString().contains("7")).toList();
    }

    // Filter by search query
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      results = results.where((c) {
        final name = c['teacher']['name'].toString().toLowerCase();
        final msg = c['lastMessage'].toString().toLowerCase();
        return name.contains(query) || msg.contains(query);
      }).toList();
    }

    setState(() {
      _filteredConversations = results;
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
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 24, color: Colors.white),
              ),
        actions: [
          _isSearching
              ? IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: _clearSearch,
                )
              : IconButton(
                  icon: const Icon(Icons.search, color: Colors.white),
                  onPressed: () => setState(() => _isSearching = true),
                ),
          IconButton(
            icon: const Icon(Icons.edit_square, color: Colors.white),
            tooltip: _t("New Message", "Ujumbe Mpya"),
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ParentComposeMessageScreen(
                    selectedChild: widget.selectedChild,
                    childFullName: _childFullName.isNotEmpty ? _childFullName : widget.selectedChild,
                    childLevel: widget.currentLevel,
                    schoolName: _schoolName,
                    availableTeachers: _filteredAvailableTeachers,
                  ),
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
          // Filter Chips Container (Light Gray Background)
          Container(
            width: double.infinity,
            color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF4F6F9),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: ["All", "Unread", "Std 4", "Std 7"].map((filterName) {
                  final bool isSelected = _activeFilter == filterName;
                  return GestureDetector(
                    onTap: () {
                      setState(() => _activeFilter = filterName);
                      _applyFilters();
                    },
                    child: Container(
                      margin: const EdgeInsets.only(right: 10),
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
          
          // RECENT CONVERSATIONS text label
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              _t("RECENT CONVERSATIONS", "MAZUNGUMZO YA HIVI KARIBUNI"),
              style: TextStyle(
                color: isDark ? Colors.white54 : Colors.grey[600],
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
              ),
            ),
          ),
          
          // Conversation List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(primaryNavy)))
                : _filteredConversations.isEmpty
                    ? Center(
                        child: Text(
                          _t("No conversations found.", "Hakuna mazungumzo yaliyopatikana."),
                          style: const TextStyle(color: Colors.grey, fontSize: 16),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: _filteredConversations.length,
                        separatorBuilder: (context, index) => const Divider(height: 1, color: Colors.black12),
                        itemBuilder: (context, index) {
                          final item = _filteredConversations[index];
                          final teacher = item['teacher'];
                          final String chatKey = item['chatKey'];
                          final int unreadCount = item['unreadCount'];
                          final bool isUrgent = item['isUrgent'];
                          final bool isOnline = teacher['status'] == 'Online';

                          return Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () async {
                                // Mark as read locally first
                                await _markConversationAsRead(chatKey);
                                
                                if (!context.mounted) return;
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => ParentChatConversationScreen(
                                      selectedChild: widget.selectedChild,
                                      childFullName: _childFullName.isNotEmpty ? _childFullName : widget.selectedChild,
                                      currentLevel: widget.currentLevel,
                                      schoolName: _schoolName,
                                      teacher: teacher,
                                      chatKey: chatKey,
                                    ),
                                  ),
                                );
                                _loadData(); // Reload inbox on return
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 12.0),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    // Avatar Stack (Initials + Status Indicator)
                                    Stack(
                                      children: [
                                        CircleAvatar(
                                          radius: 26,
                                          backgroundColor: isDark ? const Color(0xFF2C2C2C) : const Color(0xFFE8ECEF),
                                          child: Text(
                                            teacher['avatar'] ?? 'T',
                                            style: TextStyle(
                                              color: isDark ? Colors.white : primaryNavy,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 18,
                                            ),
                                          ),
                                        ),
                                        if (isOnline)
                                          Positioned(
                                            right: 1,
                                            bottom: 1,
                                            child: Container(
                                              width: 14,
                                              height: 14,
                                              decoration: BoxDecoration(
                                                color: Colors.green,
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: isDark ? const Color(0xFF121212) : Colors.white,
                                                  width: 2,
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(width: 14),
                                    
                                    // Info Column
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Text(
                                                teacher['name'],
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              
                                              // Level Tag (e.g. Std 4)
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: isDark ? const Color(0xFF333333) : const Color(0xFFE3F2FD),
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  teacher['level'] ?? 'Std 4',
                                                  style: TextStyle(
                                                    color: isDark ? Colors.white70 : const Color(0xFF1E88E5),
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              
                                              // Urgent Tag
                                              if (isUrgent)
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                                          ),
                                          const SizedBox(height: 6),
                                          
                                          // Last Message snippet
                                          Text(
                                            item['lastMessage'],
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: unreadCount > 0
                                                  ? (isDark ? Colors.white : Colors.black87)
                                                  : (isDark ? Colors.white60 : Colors.grey[600]),
                                              fontSize: 14,
                                              fontWeight: unreadCount > 0 ? FontWeight.w600 : FontWeight.normal,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    
                                    // Time and Badge Column
                                    const SizedBox(width: 8),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          item['time'],
                                          style: TextStyle(
                                            color: unreadCount > 0
                                                ? (isDark ? Colors.white : Colors.black87)
                                                : Colors.grey,
                                            fontSize: 11,
                                            fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        if (unreadCount > 0)
                                          Container(
                                            padding: const EdgeInsets.all(6),
                                            decoration: const BoxDecoration(
                                              color: primaryNavy,
                                              shape: BoxShape.circle,
                                            ),
                                            constraints: const BoxConstraints(
                                              minWidth: 20,
                                              minHeight: 20,
                                            ),
                                            child: Center(
                                              child: Text(
                                                '$unreadCount',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Future<void> _markConversationAsRead(String chatKey) async {
    try {
      final file = await _chatHistoryFile;
      if (await file.exists()) {
        final content = await file.readAsString();
        final Map<String, dynamic> data = jsonDecode(content);
        final Map<String, dynamic> unreadCounts = data['unread_counts'] ?? {};
        
        unreadCounts[chatKey] = 0;
        data['unread_counts'] = unreadCounts;
        
        await file.writeAsString(jsonEncode(data));
      }
    } catch (e) {
      debugPrint("Error marking read: $e");
    }
  }
}


// -----------------------------------------------------------------------------
// SCREEN 2 — CONVERSATION THREAD
// -----------------------------------------------------------------------------
class ParentChatConversationScreen extends StatefulWidget {
  final String selectedChild;
  final String childFullName;
  final String currentLevel;
  final String schoolName;
  final Map<String, dynamic> teacher;
  final String chatKey;

  const ParentChatConversationScreen({
    super.key,
    required this.selectedChild,
    required this.childFullName,
    required this.currentLevel,
    required this.schoolName,
    required this.teacher,
    required this.chatKey,
  });

  @override
  State<ParentChatConversationScreen> createState() => _ParentChatConversationScreenState();
}

class _ParentChatConversationScreenState extends State<ParentChatConversationScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker();
  bool _isLoading = true;
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

  Future<void> _incrementTeacherUnreadCount() async {
    try {
      final file = await _chatHistoryFile;
      final Map<String, dynamic> data = {};
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.isNotEmpty) {
          data.addAll(jsonDecode(content));
        }
      }
      final Map<String, dynamic> unreadCounts = Map<String, dynamic>.from(data['teacher_unread_counts'] ?? {});
      final int current = (unreadCounts[widget.chatKey] as int?) ?? 0;
      unreadCounts[widget.chatKey] = current + 1;
      data['teacher_unread_counts'] = unreadCounts;
      await file.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint("Error incrementing teacher unread count: $e");
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
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
      if (image == null) return;
      
      final now = DateTime.now();
      setState(() {
        _messages.add({
          'sender': 'parent',
          'senderName': 'You',
          'imagePath': image.path,
          'time': DateFormat.jm().format(now),
          'date': now.toIso8601String(),
        });
      });
      _scrollToBottom();
      await _saveMessages();
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
          'sender': 'parent',
          'senderName': 'You',
          'text': "📎 File: $filename",
          'time': DateFormat.jm().format(now),
          'date': now.toIso8601String(),
        });
      });
      _scrollToBottom();
      await _saveMessages();
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
      'sender': 'parent',
      'senderName': 'You',
      'text': text,
      'time': DateFormat.jm().format(now),
      'date': now.toIso8601String(),
    };

    if (_useDatabase) {
      try {
        await Supabase.instance.client.from('messages').insert({
          'chat_key': widget.chatKey,
          'sender': 'parent',
          'sender_name': 'You',
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
        debugPrint("Error saving sent message to database: $e");
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

    await _incrementTeacherUnreadCount();
  }

  String _t(String en, String sw) {
    return AppSettings.language.value == 'Kiswahili' ? sw : en;
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    const Color primaryNavy = Color(0xFF0F2C59);
    final String teacherName = widget.teacher['name'];
    final String teacherRole = widget.teacher['role'] ?? "Subject Teacher";

    final quickReplies = [
      {'en': 'Hello Teacher', 'sw': 'Habari Mwalimu'},
      {'en': 'Thank you for the update', 'sw': 'Asante kwa taarifa'},
      {'en': 'Will work on fractions', 'sw': 'Tutafanya fractions'},
    ];

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF4F6F9),
      appBar: AppBar(
        backgroundColor: primaryNavy,
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Row(
          children: [
            // Teacher Avatar in top bar
            CircleAvatar(
              radius: 18,
              backgroundColor: Colors.white24,
              child: Text(
                widget.teacher['avatar'] ?? 'T',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    teacherName,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    teacherRole,
                    style: const TextStyle(fontSize: 11, color: Colors.white70),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onPressed: () {},
          )
        ],
      ),
      body: Column(
        children: [
          // Sub-header details
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "${_t("Child", "Mtoto")}: ${widget.childFullName}",
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[600], fontSize: 12),
                ),
                Text(
                  "${_t("Class", "Darasa")}: ${widget.currentLevel}",
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[600], fontSize: 12),
                ),
              ],
            ),
          ),
          
          // Messages list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      final bool isMe = msg['sender'] == 'parent';
                      
                      // Render Date Separator for "Today"
                      final bool showSeparator = index == 0;
                      
                      return Column(
                        children: [
                          if (showSeparator)
                            Container(
                              margin: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                _t("Today", "Leo"),
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
                                        errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image, size: 50),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                  ],
                                  if (msg['text'] != null)
                                    Text(
                                      msg['text']!,
                                      style: TextStyle(
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
                                          color: isMe ? Colors.white70 : Colors.grey,
                                          fontSize: 10,
                                        ),
                                      ),
                                      if (isMe) ...[
                                        const SizedBox(width: 4),
                                        const Text(
                                          "✓✓",
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
          
          // Quick replies chips
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
                    label: Text(replyText, style: const TextStyle(fontSize: 12)),
                    backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    onPressed: () => _sendMessage(customText: replyText),
                  ),
                );
              },
            ),
          ),
          
          // Bottom input bar
          Container(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 24),
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            child: Row(
              children: [
                // Attach file
                IconButton(
                  icon: const Icon(Icons.attach_file, color: Colors.grey),
                  onPressed: _pickFile,
                ),
                // Camera
                IconButton(
                  icon: const Icon(Icons.camera_alt_outlined, color: Colors.grey),
                  onPressed: _pickImage,
                ),
                // Document
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
                      fillColor: isDark ? const Color(0xFF2C2C2C) : const Color(0xFFF1F3F5),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
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


// -----------------------------------------------------------------------------
// SCREEN 3 — COMPOSE MESSAGE
// -----------------------------------------------------------------------------
class ParentComposeMessageScreen extends StatefulWidget {
  final String selectedChild;
  final String childFullName;
  final String childLevel;
  final String schoolName;
  final List<Map<String, dynamic>> availableTeachers;

  const ParentComposeMessageScreen({
    super.key,
    required this.selectedChild,
    required this.childFullName,
    required this.childLevel,
    required this.schoolName,
    required this.availableTeachers,
  });

  @override
  State<ParentComposeMessageScreen> createState() => _ParentComposeMessageScreenState();
}

class _ParentComposeMessageScreenState extends State<ParentComposeMessageScreen> {
  final TextEditingController _subjectController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();

  Map<String, dynamic>? _selectedTeacher;
  String _selectedSchool = "";
  String _selectedPriority = "Normal";
  final TextEditingController _teacherSearchController = TextEditingController();
  final FocusNode _teacherSearchFocusNode = FocusNode();
  bool _showTeacherDropdown = false;

  @override
  void initState() {
    super.initState();
    _selectedSchool = widget.schoolName;
  }

  @override
  void dispose() {
    _subjectController.dispose();
    _messageController.dispose();
    _teacherSearchController.dispose();
    _teacherSearchFocusNode.dispose();
    super.dispose();
  }

  Future<File> get _chatHistoryFile async {
    final directory = await AppSettings.getSafeDirectory();
    return File('${directory.path}/parent_chats_config.json');
  }

  Future<void> _sendNewMessage() async {
    if (_selectedTeacher == null || _messageController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select a teacher and type a message.")),
      );
      return;
    }

    final String teacherId = _selectedTeacher!['id'];
    final String chatKey = "${widget.selectedChild}_$teacherId";

    // Try inserting message into Supabase first
    try {
      await Supabase.instance.client.from('messages').insert({
        'chat_key': chatKey,
        'sender': 'parent',
        'sender_name': 'You',
        'text': _messageController.text.trim(),
        'subject': _subjectController.text.trim(),
        'priority': _selectedPriority,
        'read': false,
      });
    } catch (e) {
      debugPrint("Supabase messages table insert failed, falling back to JSON only: $e");
    }

    try {
      final file = await _chatHistoryFile;
      Map<String, dynamic> data = {};
      if (await file.exists()) {
        final content = await file.readAsString();
        data = jsonDecode(content);
      }

      List<dynamic> history = data[chatKey] ?? [];
      
      final now = DateTime.now();
      final newMsg = {
        'sender': 'parent',
        'senderName': 'You',
        'text': _messageController.text.trim(),
        'subject': _subjectController.text.trim(),
        'priority': _selectedPriority,
        'time': DateFormat.jm().format(now),
        'date': now.toIso8601String(),
      };

      history.add(newMsg);
      data[chatKey] = history;

      // Update urgency state
      final Map<String, dynamic> urgents = data['urgents'] ?? {};
      urgents[chatKey] = _selectedPriority == "Urgent";
      data['urgents'] = urgents;

      // Update unread count (none for parent since parent sent it)
      final Map<String, dynamic> unreadCounts = data['unread_counts'] ?? {};
      unreadCounts[chatKey] = 0;
      data['unread_counts'] = unreadCounts;

      // Also trigger a simulated notification on the teacher side!
      if (!data.containsKey('notifications')) {
        data['notifications'] = [];
      }
      final List<dynamic> notifications = data['notifications'];
      
      notifications.insert(0, {
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'title': "${widget.selectedChild}'s Parent sent a message",
        'body': "${_selectedPriority == 'Urgent' ? '🔴 URGENT: ' : ''}${_messageController.text.trim()}",
        'class': _selectedTeacher!['level'] ?? 'Std 4A',
        'time': DateFormat.jm().format(now),
        'date': now.toIso8601String(),
        'type': _selectedPriority == 'Urgent' ? 'urgent' : 'reply',
        'read': false
      });
      data['notifications'] = notifications;

      await file.writeAsString(jsonEncode(data));

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint("Error sending new message: $e");
    }
  }

  String _t(String en, String sw) {
    return AppSettings.language.value == 'Kiswahili' ? sw : en;
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
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
          _t("New Message", "Ujumbe Mpya"),
          style: const TextStyle(color: primaryNavy, fontWeight: FontWeight.bold),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12.0, top: 10, bottom: 10),
            child: ElevatedButton(
              onPressed: _sendNewMessage,
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryNavy,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text(_t("Send", "Tuma"), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _teacherSearchController,
                  focusNode: _teacherSearchFocusNode,
                  style: TextStyle(color: isDark ? Colors.white : Colors.black),
                  decoration: InputDecoration(
                    labelText: _selectedTeacher != null 
                        ? "${_selectedTeacher!['name']} (${_selectedTeacher!['subject']} · ${_selectedTeacher!['level']})"
                        : _t("Select a teacher...", "Mchague mwalimu..."),
                    labelStyle: TextStyle(
                      color: _selectedTeacher != null ? primaryNavy : Colors.grey,
                      fontWeight: _selectedTeacher != null ? FontWeight.bold : FontWeight.normal
                    ),
                    hintText: _t("Type teacher's name or subject...", "Andika jina la mwalimu au somo..."),
                    prefixIcon: const Icon(Icons.person_outline, color: Colors.grey),
                    suffixIcon: IconButton(
                      icon: Icon(_showTeacherDropdown ? Icons.arrow_drop_up : Icons.arrow_drop_down, color: primaryNavy),
                      onPressed: () {
                        setState(() {
                          _showTeacherDropdown = !_showTeacherDropdown;
                        });
                      },
                    ),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  onChanged: (val) {
                    setState(() {
                      _showTeacherDropdown = true;
                    });
                  },
                ),
                if (_showTeacherDropdown) ...[
                  const SizedBox(height: 4),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 200),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF2C2C2C) : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isDark ? Colors.grey[800]! : Colors.grey[300]!),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.15),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ListView(
                      shrinkWrap: true,
                      children: widget.availableTeachers.where((t) {
                        final query = _teacherSearchController.text.toLowerCase();
                        final name = (t['name'] ?? '').toString().toLowerCase();
                        final subject = (t['subject'] ?? '').toString().toLowerCase();
                        return name.contains(query) || subject.contains(query);
                      }).map((t) {
                        final bool isSelected = _selectedTeacher == t;
                        return ListTile(
                          title: Text(
                            t['name'],
                            style: TextStyle(
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              color: isDark ? Colors.white : Colors.black,
                            ),
                          ),
                          subtitle: Text(
                            "${t['subject']} · ${t['level'] ?? 'Std 4'}",
                            style: const TextStyle(color: Colors.grey),
                          ),
                          selected: isSelected,
                          selectedColor: primaryNavy,
                          onTap: () {
                            setState(() {
                              _selectedTeacher = t;
                              _teacherSearchController.clear();
                              _showTeacherDropdown = false;
                              _teacherSearchFocusNode.unfocus();
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 20),

            // School & Child selectors in Row
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _t("School", "Shule"),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: _selectedSchool,
                        isExpanded: true,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                        ),
                        items: {"Mwangi Primary", "Greenwood Academy", "Hillside International", "Dar es Salaam Academy", _selectedSchool}
                            .where((s) => s.isNotEmpty)
                            .map((s) => DropdownMenuItem(value: s, child: Text(s, overflow: TextOverflow.ellipsis)))
                            .toList(),
                        onChanged: (val) => setState(() => _selectedSchool = val!),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _t("Child", "Mtoto"),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: widget.selectedChild,
                        isExpanded: true,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                        ),
                        items: [widget.selectedChild]
                            .map((c) => DropdownMenuItem(value: c, child: Text("${widget.childFullName} · ${widget.childLevel}", overflow: TextOverflow.ellipsis)))
                            .toList(),
                        onChanged: (val) {},
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Subject input
            Text(
              _t("Subject", "Somo/Mada"),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _subjectController,
              decoration: InputDecoration(
                hintText: _t("Regarding homework assignment...", "Kuhusu kazi ya nyumbani..."),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
            const SizedBox(height: 20),

            // Priority Selector
            Text(
              _t("Priority", "Kipaumbele"),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: ["Urgent", "Normal"].map((p) {
                final bool isSelected = _selectedPriority == p;
                final bool isUrgent = p == "Urgent";
                return GestureDetector(
                  onTap: () => setState(() => _selectedPriority = p),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? (isUrgent ? const Color(0xFFD32F2F) : Colors.grey[400])
                          : Colors.grey[200],
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _t(p, p == "Urgent" ? "Haraka" : "Kawaida"),
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.black87,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // Message text area
            Text(
              _t("Message", "Ujumbe"),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _messageController,
              maxLines: 8,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: _t("Write your message here...", "Andika ujumbe wako hapa..."),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.all(16),
              ),
            ),
            const SizedBox(height: 20),

            // Attach file button
            OutlinedButton.icon(
              onPressed: () async {
                final result = await FilePicker.pickFiles();
                if (result != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Attached: ${result.files.single.name}")),
                  );
                }
              },
              icon: const Icon(Icons.attach_file, color: Colors.grey),
              label: Text(_t("Attach file", "Weka faili"), style: const TextStyle(color: Colors.grey)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.grey),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
