import 'dart:convert';
import 'dart:io' hide File, Directory;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/web_safe_file.dart';
import '../services/school_service.dart';
import '../services/audit_log_service.dart';
import '../main.dart';
import 'login_screen.dart';

class AdminDashboard extends StatefulWidget {
  final String adminName;
  final String adminRole;
  final String? adminSchool;

  const AdminDashboard({
    super.key,
    required this.adminName,
    this.adminRole = 'admin',
    this.adminSchool,
  });

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> with SingleTickerProviderStateMixin {
  // Supabase service role key — required for admin password resets via the Auth API.
  static const _supabaseServiceRoleKey = 'supabase_service_key';
  static const _supabaseUrl = 'https://wnxeohqejdiytqkxdcwe.supabase.co';

  late TabController _tabController;
  final List<School> _schoolsList = [];
  List<Map<String, dynamic>> _profilesList = [];
  List<Map<String, dynamic>> _auditLogsList = [];

  bool _isLoadingSchools = true;
  bool _isLoadingProfiles = true;
  bool _isLoadingLogs = true;
  bool _isDbConnected = true;
  String _selectedRoleFilter = 'All';

  // Controllers for registering a new school
  final _nameController = TextEditingController();
  final _regionController = TextEditingController();
  final _districtController = TextEditingController();
  final _codeController = TextEditingController();

  // Controllers for editing a school
  final _editNameController = TextEditingController();
  final _editRegionController = TextEditingController();
  final _editDistrictController = TextEditingController();
  final _editCodeController = TextEditingController();

  // Search controllers for directory lists
  final _userSearchController = TextEditingController();
  final _schoolSearchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      _refreshTabContent();
    });
    _loadAllData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameController.dispose();
    _regionController.dispose();
    _districtController.dispose();
    _codeController.dispose();
    _editNameController.dispose();
    _editRegionController.dispose();
    _editDistrictController.dispose();
    _editCodeController.dispose();
    _userSearchController.dispose();
    _schoolSearchController.dispose();
    super.dispose();
  }

  void _refreshTabContent() {
    if (_tabController.index == 0) {
      _loadSchools();
    } else if (_tabController.index == 1) {
      _loadProfiles();
    } else if (_tabController.index == 2) {
      _loadAuditLogs();
    }
  }

  Future<void> _loadAllData() async {
    await _loadSchools();
    _loadProfiles();
    _loadAuditLogs();
  }

  Future<void> _loadSchools() async {
    setState(() => _isLoadingSchools = true);
    try {
      final list = await SchoolService.getSchools(includeInactiveAndArchived: true);
      if (widget.adminRole == 'school_admin' && widget.adminSchool != null) {
        list.removeWhere((s) => s.schoolName.trim().toLowerCase() != widget.adminSchool!.trim().toLowerCase());
      }
      
      // Connection test
      bool connected = true;
      try {
        await Supabase.instance.client.from('schools').select().limit(1);
      } catch (_) {
        connected = false;
      }

      setState(() {
        _schoolsList.clear();
        _schoolsList.addAll(list);
        _isDbConnected = connected;
        _isLoadingSchools = false;
      });
    } catch (e) {
      setState(() {
        _isDbConnected = false;
        _isLoadingSchools = false;
      });
    }
  }

  Future<void> _loadProfiles() async {
    setState(() => _isLoadingProfiles = true);
    try {
      // 1. Fetch live registered user profiles
      final profilesResponse = await Supabase.instance.client
          .from('profiles')
          .select()
          .order('full_name', ascending: true);
      
      final List<Map<String, dynamic>> loadedProfiles = 
          (profilesResponse as List).map((e) => Map<String, dynamic>.from(e)).toList();

      // 2. Fetch live pre-registered student records
      List<Map<String, dynamic>> loadedRecords = [];
      try {
        final recordsResponse = await Supabase.instance.client
            .from('student_records')
            .select()
            .order('full_name', ascending: true);
        loadedRecords = (recordsResponse as List).map((e) => Map<String, dynamic>.from(e)).toList();
      } catch (err) {
        debugPrint("[AdminDashboard] Supabase student_records fetch failed: $err");
      }

      // Fetch live pre-registered teacher records
      List<Map<String, dynamic>> loadedTeacherRecords = [];
      try {
        final teacherRecordsResponse = await Supabase.instance.client
            .from('teacher_records')
            .select()
            .order('full_name', ascending: true);
        loadedTeacherRecords = (teacherRecordsResponse as List).map((e) => Map<String, dynamic>.from(e)).toList();
      } catch (err) {
        debugPrint("[AdminDashboard] Supabase teacher_records fetch failed: $err");
      }

      // Fetch live pre-registered school admin records
      List<Map<String, dynamic>> loadedSchoolAdminRecords = [];
      if (widget.adminRole == 'admin' || widget.adminRole == 'super_admin') {
        try {
          final schoolAdminsResponse = await Supabase.instance.client
              .from('school_admin_records')
              .select()
              .order('full_name', ascending: true);
          loadedSchoolAdminRecords = (schoolAdminsResponse as List).map((e) => Map<String, dynamic>.from(e)).toList();
        } catch (err) {
          debugPrint("[AdminDashboard] Supabase school_admin_records fetch failed: $err");
        }
      }

      // 3. Fetch offline pre-registered fallback student records
      try {
        final directory = await getApplicationDocumentsDirectory();
        final file = File('${directory.path}/local_student_records_fallback.json');
        if (await file.exists()) {
          final List localRecords = jsonDecode(await file.readAsString());
          for (var local in localRecords) {
            final map = Map<String, dynamic>.from(local);
            if (!loadedRecords.any((r) => r['admission_number'].toString().toUpperCase() == map['admission_number'].toString().toUpperCase())) {
              loadedRecords.add(map);
            }
          }
        }
      } catch (localErr) {
        debugPrint("Error loading offline student records fallback: $localErr");
      }

      // Fetch offline pre-registered fallback teacher records
      try {
        final directory = await getApplicationDocumentsDirectory();
        final file = File('${directory.path}/local_teacher_records_fallback.json');
        if (await file.exists()) {
          final List localRecords = jsonDecode(await file.readAsString());
          for (var local in localRecords) {
            final map = Map<String, dynamic>.from(local);
            if (!loadedTeacherRecords.any((r) => r['employee_number'].toString().toUpperCase() == map['employee_number'].toString().toUpperCase())) {
              loadedTeacherRecords.add(map);
            }
          }
        }
      } catch (localErr) {
        debugPrint("Error loading offline teacher records fallback: $localErr");
      }

      // Fetch offline pre-registered fallback school admin records
      if (widget.adminRole == 'admin' || widget.adminRole == 'super_admin') {
        try {
          final directory = await getApplicationDocumentsDirectory();
          final file = File('${directory.path}/local_school_admin_records_fallback.json');
          if (await file.exists()) {
            final List localRecords = jsonDecode(await file.readAsString());
            for (var local in localRecords) {
              final map = Map<String, dynamic>.from(local);
              if (!loadedSchoolAdminRecords.any((r) => r['username'].toString().toUpperCase() == map['username'].toString().toUpperCase())) {
                loadedSchoolAdminRecords.add(map);
              }
            }
          }
        } catch (localErr) {
          debugPrint("Error loading offline school admin records fallback: $localErr");
        }
      }

      // Filter pre-registered records by school if the user is a school_admin
      if (widget.adminRole == 'school_admin' && widget.adminSchool != null) {
        loadedRecords.removeWhere((r) => r['school']?.toString().trim().toLowerCase() != widget.adminSchool!.trim().toLowerCase());
        loadedTeacherRecords.removeWhere((r) => r['school']?.toString().trim().toLowerCase() != widget.adminSchool!.trim().toLowerCase());
      }

      // 4. Merge pending pre-registered student records into our profiles directory list
      final Set<String> registeredUsernames = loadedProfiles
          .map((p) => p['username']?.toString().toLowerCase() ?? '')
          .toSet();

      for (var record in loadedRecords) {
        final String admissionNum = record['admission_number']?.toString() ?? '';
        final String statusStr = record['status']?.toString() ?? 'pending';

        if (statusStr == 'pending' && !registeredUsernames.contains(admissionNum.toLowerCase())) {
          loadedProfiles.add({
            'id': record['id']?.toString() ?? 'pre_${admissionNum}',
            'full_name': record['full_name']?.toString() ?? 'Authorized Student',
            'role': 'student',
            'username': admissionNum,
            'status': 'authorized',
            'school': record['school']?.toString() ?? '',
            'level': record['level']?.toString() ?? 'Standard 7',
            'is_pre_registered': true,
            'is_teacher_record': false,
            'is_school_admin_record': false,
          });
        }
      }

      // Merge pending pre-registered teacher records into our profiles directory list
      for (var record in loadedTeacherRecords) {
        final String empNum = record['employee_number']?.toString() ?? '';
        final String statusStr = record['status']?.toString() ?? 'pending';

        if (statusStr == 'pending' && !registeredUsernames.contains(empNum.toLowerCase())) {
          loadedProfiles.add({
            'id': record['id']?.toString() ?? 'pre_tch_${empNum}',
            'full_name': record['full_name']?.toString() ?? 'Authorized Teacher',
            'role': 'teacher',
            'username': empNum,
            'status': 'authorized',
            'school': record['school']?.toString() ?? '',
            'level': 'Teacher',
            'is_pre_registered': true,
            'is_teacher_record': true,
            'is_school_admin_record': false,
          });
        }
      }

      // Merge pending pre-registered school admin records into our profiles directory list
      for (var record in loadedSchoolAdminRecords) {
        final String username = record['username']?.toString() ?? '';
        final String statusStr = record['status']?.toString() ?? 'pending';

        if (statusStr == 'pending' && !registeredUsernames.contains(username.toLowerCase())) {
          loadedProfiles.add({
            'id': record['id']?.toString() ?? 'pre_sad_${username}',
            'full_name': record['full_name']?.toString() ?? 'Authorized School Admin',
            'role': 'school_admin',
            'username': username,
            'status': 'authorized',
            'school': record['school']?.toString() ?? '',
            'level': 'School Admin',
            'is_pre_registered': true,
            'is_teacher_record': false,
            'is_school_admin_record': true,
          });
        }
      }

      // Fetch parent-child links to map linked children for Parent cards
      List<Map<String, dynamic>> parentLinks = [];
      try {
        final linksResponse = await Supabase.instance.client
            .from('parent_child_links')
            .select();
        parentLinks = (linksResponse as List).map((e) => Map<String, dynamic>.from(e)).toList();
      } catch (err) {
        debugPrint("[AdminDashboard] Supabase parent_child_links fetch failed: $err");
      }

      // Build a map of username -> fullName
      final Map<String, String> usernameToFullName = {};
      for (var p in loadedProfiles) {
        final String role = p['role']?.toString().toLowerCase() ?? '';
        final String username = p['username']?.toString().toLowerCase() ?? '';
        if (role == 'student' && username.isNotEmpty) {
          usernameToFullName[username] = p['full_name']?.toString() ?? username;
        }
      }
      for (var r in loadedRecords) {
        final String username = r['admission_number']?.toString().toLowerCase() ?? '';
        if (username.isNotEmpty) {
          usernameToFullName[username] = r['full_name']?.toString() ?? username;
        }
      }

      // Build parent_id -> list of child names, child usernames, child schools
      final Map<String, List<String>> parentIdToChildren = {};
      final Map<String, List<String>> parentIdToChildUsernames = {};
      final Map<String, List<String>> parentIdToChildSchools = {};
      for (var link in parentLinks) {
        final String parentId = link['parent_id']?.toString() ?? '';
        final String studentUsername = link['student_username']?.toString().toLowerCase() ?? '';
        final String childSchool = link['school']?.toString() ?? '';
        if (parentId.isNotEmpty && studentUsername.isNotEmpty) {
          final String childName = usernameToFullName[studentUsername] ?? studentUsername;
          parentIdToChildren.putIfAbsent(parentId, () => []).add(childName);
          parentIdToChildUsernames.putIfAbsent(parentId, () => []).add(studentUsername);
          if (childSchool.isNotEmpty) {
            parentIdToChildSchools.putIfAbsent(parentId, () => []).add(childSchool);
          }
        }
      }

      // Inject linked_children into profiles
      for (var p in loadedProfiles) {
        final String role = p['role']?.toString().toLowerCase() ?? '';
        final String id = p['id']?.toString() ?? '';
        if (role == 'parent' && id.isNotEmpty) {
          p['linked_children'] = parentIdToChildren[id] ?? [];
          p['linked_children_usernames'] = parentIdToChildUsernames[id] ?? [];
          p['linked_children_schools'] = parentIdToChildSchools[id] ?? [];
        }
      }

      // 5. Apply the main profile filtering for school_admin
      if (widget.adminRole == 'school_admin' && widget.adminSchool != null) {
        loadedProfiles.removeWhere((p) {
          final role = p['role']?.toString().toLowerCase() ?? '';
          
          if (role == 'student' || role == 'teacher') {
            return p['school']?.toString().trim().toLowerCase() != widget.adminSchool!.trim().toLowerCase();
          }
          
          if (role == 'parent') {
            final List<String> childSchools = List<String>.from(p['linked_children_schools'] ?? []);
            final List<String> childUsernames = List<String>.from(p['linked_children_usernames'] ?? []);
            
            bool hasChildInSchool = childSchools.any((s) => s.trim().toLowerCase() == widget.adminSchool!.trim().toLowerCase());
            
            if (!hasChildInSchool) {
              // Check if any child student is listed in loadedProfiles
              hasChildInSchool = loadedProfiles.any((otherP) => 
                otherP['role'] == 'student' && 
                childUsernames.contains(otherP['username']?.toString().toLowerCase()) &&
                otherP['school']?.toString().trim().toLowerCase() == widget.adminSchool!.trim().toLowerCase()
              );
            }
            return !hasChildInSchool;
          }
          
          // Hide other admin or school admins, only show themselves
          if (role == 'school_admin' || role == 'admin' || role == 'super_admin') {
            if (p['username'] != widget.adminName && p['full_name'] != widget.adminName) {
              return true;
            }
          }
          
          return false;
        });
      }

      // Sort profiles alphabetically by full name
      loadedProfiles.sort((a, b) {
        final String nameA = a['full_name']?.toString().toLowerCase() ?? '';
        final String nameB = b['full_name']?.toString().toLowerCase() ?? '';
        return nameA.compareTo(nameB);
      });

      setState(() {
        _profilesList = loadedProfiles;
        _isLoadingProfiles = false;
      });
    } catch (e) {
      debugPrint("[AdminDashboard] Supabase profiles fetch failed: $e");
      setState(() => _isLoadingProfiles = false);
    }
  }

  Future<void> _loadAuditLogs() async {
    setState(() => _isLoadingLogs = true);
    try {
      var logs = await AuditLogService.getAuditLogs();
      if (widget.adminRole == 'school_admin' && widget.adminSchool != null) {
        logs = logs.where((log) {
          final String details = log['details']?.toString().toLowerCase() ?? '';
          return details.contains(widget.adminSchool!.toLowerCase());
        }).toList();
      }
      setState(() {
        _auditLogsList = logs;
        _isLoadingLogs = false;
      });
    } catch (e) {
      debugPrint("[AdminDashboard] Audit logs fetch failed: $e");
      setState(() => _isLoadingLogs = false);
    }
  }

  // --- SCHOOL OPERATIONS ---

  void _showAddSchoolBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => DraggableScrollableSheet(
          initialChildSize: 0.75,
          maxChildSize: 0.95,
          minChildSize: 0.50,
          builder: (_, scrollCtrl) => Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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
                const SizedBox(height: 24),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.add_business, color: Colors.blue.shade800, size: 28),
                    ),
                    const SizedBox(width: 16),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Register School",
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87),
                        ),
                        Text(
                          "Add a new unique school to the system",
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                TextField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: "School Name",
                    hintText: "e.g., Westfield Academy",
                    prefixIcon: const Icon(Icons.school),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _regionController,
                  decoration: InputDecoration(
                    labelText: "Region",
                    hintText: "e.g., Dar es Salaam",
                    prefixIcon: const Icon(Icons.map),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _districtController,
                  decoration: InputDecoration(
                    labelText: "District",
                    hintText: "e.g., Kinondoni",
                    prefixIcon: const Icon(Icons.location_city),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _codeController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: "School Code (Unique Identifier)",
                    hintText: "e.g., WES001",
                    prefixIcon: const Icon(Icons.qr_code),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: () async {
                      final name = _nameController.text.trim();
                      final region = _regionController.text.trim();
                      final district = _districtController.text.trim();
                      final code = _codeController.text.trim();

                      if (name.isEmpty || region.isEmpty || district.isEmpty || code.isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                            content: Text("All fields are required!"),
                            backgroundColor: Colors.redAccent,
                          ),
                        );
                        return;
                      }

                      try {
                        final success = await SchoolService.addSchool(
                          name: name,
                          region: region,
                          district: district,
                          code: code,
                        );

                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Row(
                                children: [
                                  Icon(
                                    success ? Icons.check_circle : Icons.warning_amber_rounded,
                                    color: Colors.white,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      success
                                          ? "School '$name' registered successfully in Supabase!"
                                          : "Saved locally! Supabase insert was blocked. Click 'Setup SQL' to enable database permissions.",
                                    ),
                                  ),
                                ],
                              ),
                              backgroundColor: success ? Colors.green : Colors.orange.shade800,
                              duration: Duration(seconds: success ? 4 : 6),
                            ),
                          );
                        }

                        _nameController.clear();
                        _regionController.clear();
                        _districtController.clear();
                        _codeController.clear();

                        _loadSchools();
                        _loadAuditLogs();
                      } catch (e) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(
                            content: Text("Failed to register: ${e.toString().replaceAll('Exception:', '')}"),
                            backgroundColor: Colors.redAccent,
                            duration: const Duration(seconds: 4),
                          ),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0D47A1),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 2,
                    ),
                    child: const Text(
                      "Register School Now",
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
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

  void _showEditSchoolBottomSheet(School school) {
    _editNameController.text = school.schoolName;
    _editRegionController.text = school.region;
    _editDistrictController.text = school.district;
    _editCodeController.text = school.code;
    String editStatus = school.status;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => DraggableScrollableSheet(
          initialChildSize: 0.80,
          maxChildSize: 0.95,
          minChildSize: 0.50,
          builder: (_, scrollCtrl) => Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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
                const SizedBox(height: 24),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.edit_note, color: Colors.blue.shade800, size: 28),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Update School",
                            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87),
                          ),
                          Text(
                            "Modifying: ${school.schoolName}",
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                TextField(
                  controller: _editNameController,
                  decoration: InputDecoration(
                    labelText: "School Name",
                    prefixIcon: const Icon(Icons.school),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _editRegionController,
                  decoration: InputDecoration(
                    labelText: "Region",
                    prefixIcon: const Icon(Icons.map),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _editDistrictController,
                  decoration: InputDecoration(
                    labelText: "District",
                    prefixIcon: const Icon(Icons.location_city),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _editCodeController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: "School Code",
                    prefixIcon: const Icon(Icons.qr_code),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
                const SizedBox(height: 18),
                DropdownButtonFormField<String>(
                  value: editStatus,
                  decoration: InputDecoration(
                    labelText: "Operational Status",
                    prefixIcon: const Icon(Icons.settings_power),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'active', child: Text("Active (Operational)")),
                    DropdownMenuItem(value: 'inactive', child: Text("Inactive (Suspended)")),
                  ],
                  onChanged: (val) {
                    setSheetState(() {
                      editStatus = val!;
                    });
                  },
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: () async {
                      final name = _editNameController.text.trim();
                      final region = _editRegionController.text.trim();
                      final district = _editDistrictController.text.trim();
                      final code = _editCodeController.text.trim();

                      if (name.isEmpty || region.isEmpty || district.isEmpty || code.isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                            content: Text("All fields are required!"),
                            backgroundColor: Colors.redAccent,
                          ),
                        );
                        return;
                      }

                      try {
                        final success = await SchoolService.updateSchool(
                          id: school.id,
                          name: name,
                          region: region,
                          district: district,
                          code: code,
                          status: editStatus,
                        );

                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                success
                                    ? "School details updated successfully in database!"
                                    : "Saved locally! pending database SQL Sync.",
                              ),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                        
                        _loadSchools();
                        _loadAuditLogs();
                      } catch (e) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(
                            content: Text("Failed to update: ${e.toString().replaceAll('Exception:', '')}"),
                            backgroundColor: Colors.redAccent,
                          ),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0D47A1),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 2,
                    ),
                    child: const Text(
                      "Update School Information",
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
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

  void _showDeleteSchoolDialog(School school) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red.shade800),
            const SizedBox(width: 10),
            const Text("Soft Delete School"),
          ],
        ),
        content: Text(
          "Are you sure you want to delete '${school.schoolName}'? "
          "This will soft delete (archive) the school. It will immediately vanish from Student/Parent portals but can be audited.",
          style: const TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade800),
            onPressed: () async {
              final success = await SchoolService.softDeleteSchool(school.id, school.schoolName);
              if (ctx.mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      success
                          ? "School successfully archived (soft deleted)."
                          : "School soft-deleted locally (pending sync).",
                    ),
                    backgroundColor: Colors.green,
                  ),
                );
              }
              _loadSchools();
              _loadAuditLogs();
            },
            child: const Text("Delete (Archive)", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _toggleSchoolStatus(School school) async {
    final bool isCurrentlyActive = school.status == 'active';
    final String nextStatusLabel = isCurrentlyActive ? 'deactivate' : 'reactivate';
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("${nextStatusLabel[0].toUpperCase()}${nextStatusLabel.substring(1)} School"),
        content: Text(
          isCurrentlyActive
              ? "Deactivating '${school.schoolName}' will lock out links to this school, making it invisible to new parents/students."
              : "Reactivating '${school.schoolName}' will make it immediately active and visible dynamically.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isCurrentlyActive ? Colors.orange.shade800 : Colors.green.shade800,
            ),
            onPressed: () async {
              bool success = false;
              if (isCurrentlyActive) {
                success = await SchoolService.deactivateSchool(school.id, school.schoolName);
              } else {
                success = await SchoolService.reactivateSchool(school.id, school.schoolName);
              }

              if (ctx.mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      success
                          ? "School successfully ${isCurrentlyActive ? 'deactivated' : 'reactivated'}."
                          : "Saved locally! pending database SQL Sync.",
                    ),
                    backgroundColor: Colors.green,
                  ),
                );
              }
              _loadSchools();
              _loadAuditLogs();
            },
            child: Text(isCurrentlyActive ? "Deactivate" : "Reactivate", style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // --- USER DIRECTORY OPERATIONS ---

  void _showManageUserDialog(Map<String, dynamic> profile) {
    final String userId = profile['id']?.toString() ?? '';
    final String userName = profile['full_name']?.toString() ?? 'User';
    final String userRole = (profile['role']?.toString() ?? 'student').trim().toLowerCase();
    String currentStatus = (profile['status']?.toString() ?? 'active').trim().toLowerCase();

    final bool isStudent = userRole == 'student';
    final List<String> availableStatuses = isStudent
        ? ['active', 'graduated', 'transferred', 'inactive']
        : ['active', 'suspended', 'deleted'];

    // Safely ensure the selected status is valid for the current role list
    if (!availableStatuses.contains(currentStatus)) {
      currentStatus = 'active';
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(Icons.manage_accounts, color: const Color(0xFF0D47A1)),
              const SizedBox(width: 10),
              const Text("Manage Account"),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("User: $userName", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  "ROLE: ${userRole.toUpperCase()}",
                  style: const TextStyle(
                    color: Color(0xFF0D47A1),
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                value: currentStatus,
                decoration: const InputDecoration(
                  labelText: "Account Status",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.shield_outlined),
                ),
                items: availableStatuses.map((st) {
                  return DropdownMenuItem(
                    value: st,
                    child: Text(st[0].toUpperCase() + st.substring(1)),
                  );
                }).toList(),
                onChanged: (val) {
                  setDialogState(() {
                    currentStatus = val!;
                  });
                },
              ),
              const SizedBox(height: 14),
              // ─ Reset Password button ─
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: Icon(Icons.lock_reset, color: Colors.orange.shade800, size: 18),
                  label: Text("Reset Password", style: TextStyle(color: Colors.orange.shade800, fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.orange.shade300),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    Future.delayed(Duration.zero, () => _showResetPasswordDialog(profile));
                  },
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0D47A1),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                try {
                  // Use select() to detect if Row-Level Security (RLS) silently blocked this edit!
                  final response = await Supabase.instance.client.from('profiles').update({
                    'status': currentStatus,
                  }).eq('id', userId).select();
                  
                  if ((response as List).isEmpty) {
                    throw Exception("Supabase Row-Level Security (RLS) silently blocked this update. No rows were modified.");
                  }

                  // Log audit trail
                  await AuditLogService.log(
                    action: 'UPDATE_USER_STATUS',
                    details: 'Updated status of "$userName" (Role: ${userRole.toUpperCase()}) to "${currentStatus.toUpperCase()}".',
                  );

                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text("Successfully updated $userName status to '${currentStatus.toUpperCase()}'."),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                  
                  _loadProfiles();
                  _loadAuditLogs();
                } catch (e) {
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    showDialog(
                      context: context,
                      builder: (errCtx) => AlertDialog(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        title: const Row(
                          children: [
                            Icon(Icons.warning, color: Colors.orange),
                            SizedBox(width: 10),
                            Text("Database Update Blocked"),
                          ],
                        ),
                        content: const Text(
                          "Your Supabase Row-Level Security (RLS) policies currently block administrative changes to the profiles directory.\n\n"
                          "To unlock this, please tap the terminal icon (>_) in the top-right corner of the dashboard, copy the updated SQL Setup script, and run it in your Supabase SQL Editor to enable full administrative control.",
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(errCtx),
                            child: const Text("Got it"),
                          ),
                        ],
                      ),
                    );
                  }
                }
              },
              child: const Text("Apply Status", style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  // --- SQL SETUP PANEL DIALOG ---

  void _showSqlSetupDialog() {
    const String sqlCode = """
-- ==========================================
-- 1. Create the schools table
-- ==========================================
CREATE TABLE IF NOT EXISTS public.schools (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_name TEXT NOT NULL,
    region TEXT NOT NULL,
    district TEXT NOT NULL,
    code TEXT NOT NULL UNIQUE,
    status TEXT NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ DEFAULT now()
);

-- ==========================================
-- 2. Add columns to profiles
-- ==========================================
ALTER TABLE public.profiles 
ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'active';

ALTER TABLE public.profiles 
ADD COLUMN IF NOT EXISTS school TEXT;

-- must_change_password: set to true for temp-password accounts.
-- The login screen forces a password change before any dashboard access.
ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS must_change_password BOOLEAN DEFAULT false;

-- ==========================================
-- 3. Add 'school' column to parent_child_links
-- ==========================================
ALTER TABLE public.parent_child_links 
ADD COLUMN IF NOT EXISTS school TEXT;

-- ==========================================
-- 4. Create the audit_logs table
-- ==========================================
CREATE TABLE IF NOT EXISTS public.audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_id TEXT NOT NULL,
    actor_name TEXT NOT NULL,
    action TEXT NOT NULL,
    details TEXT NOT NULL,
    timestamp TIMESTAMPTZ DEFAULT now()
);

-- ==========================================
-- 5. Create the student_records table
-- ==========================================
CREATE TABLE IF NOT EXISTS public.student_records (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    admission_number TEXT NOT NULL UNIQUE,
    full_name TEXT NOT NULL,
    school TEXT NOT NULL,
    level TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending',
    created_at TIMESTAMPTZ DEFAULT now()
);

-- ==========================================
-- 6. Create the teacher_records table
-- ==========================================
CREATE TABLE IF NOT EXISTS public.teacher_records (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    employee_number TEXT NOT NULL UNIQUE,
    full_name TEXT NOT NULL,
    school TEXT NOT NULL,
    phone_number TEXT,
    classes TEXT[] NOT NULL DEFAULT '{}',
    status TEXT NOT NULL DEFAULT 'pending',
    created_at TIMESTAMPTZ DEFAULT now()
);

-- ==========================================
-- 6b. Create the school_admin_records table
-- ==========================================
CREATE TABLE IF NOT EXISTS public.school_admin_records (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username TEXT NOT NULL UNIQUE,
    full_name TEXT NOT NULL,
    school TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'registered',
    created_at TIMESTAMPTZ DEFAULT now()
);

-- ==========================================
-- 7. Enable Row-Level Security (RLS)
-- ==========================================
ALTER TABLE public.schools ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.student_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.teacher_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.school_admin_records ENABLE ROW LEVEL SECURITY;

-- ==========================================
-- 8. Configure RLS Policies
-- ==========================================

-- Schools Read Policy
DROP POLICY IF EXISTS "Allow public read schools" ON public.schools;
CREATE POLICY "Allow public read schools" 
ON public.schools FOR SELECT USING (true);

-- Schools Modify Policy (Authenticated users only)
DROP POLICY IF EXISTS "Allow auth insert manage schools" ON public.schools;
CREATE POLICY "Allow auth insert manage schools" 
ON public.schools FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- Audit Logs Write Policy (Anyone authenticated can write logs)
DROP POLICY IF EXISTS "Allow auth insert audit logs" ON public.audit_logs;
CREATE POLICY "Allow auth insert audit logs" 
ON public.audit_logs FOR INSERT TO authenticated WITH CHECK (true);

-- Audit Logs Read Policy (Authenticated users can view audit trail)
DROP POLICY IF EXISTS "Allow auth read audit logs" ON public.audit_logs;
CREATE POLICY "Allow auth read audit logs" 
ON public.audit_logs FOR SELECT TO authenticated USING (true);

-- ==========================================
-- 9. Configure RLS Policies on profiles table
-- ==========================================
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow auth select profiles" ON public.profiles;
CREATE POLICY "Allow auth select profiles" 
ON public.profiles FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Allow auth update profiles" ON public.profiles;
CREATE POLICY "Allow auth update profiles" 
ON public.profiles FOR UPDATE TO authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Allow auth insert profiles" ON public.profiles;
CREATE POLICY "Allow auth insert profiles" 
ON public.profiles FOR INSERT TO authenticated WITH CHECK (true);

-- ==========================================
-- 10. Configure RLS Policies on student_records table
-- ==========================================
DROP POLICY IF EXISTS "Allow public read student_records" ON public.student_records;
CREATE POLICY "Allow public read student_records" 
ON public.student_records FOR SELECT USING (true);

DROP POLICY IF EXISTS "Allow auth manage student_records" ON public.student_records;
CREATE POLICY "Allow auth manage student_records" 
ON public.student_records FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- ==========================================
-- 11. Configure RLS Policies on teacher_records table
-- ==========================================
DROP POLICY IF EXISTS "Allow public read teacher_records" ON public.teacher_records;
CREATE POLICY "Allow public read teacher_records" 
ON public.teacher_records FOR SELECT USING (true);

DROP POLICY IF EXISTS "Allow auth manage teacher_records" ON public.teacher_records;
CREATE POLICY "Allow auth manage teacher_records" 
ON public.teacher_records FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- ==========================================
-- 11b. Configure RLS Policies on school_admin_records table
-- ==========================================
DROP POLICY IF EXISTS "Allow public read school_admin_records" ON public.school_admin_records;
CREATE POLICY "Allow public read school_admin_records" 
ON public.school_admin_records FOR SELECT USING (true);

DROP POLICY IF EXISTS "Allow auth manage school_admin_records" ON public.school_admin_records;
CREATE POLICY "Allow auth manage school_admin_records" 
ON public.school_admin_records FOR ALL TO authenticated USING (true) WITH CHECK (true);
""";

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.terminal, color: Color(0xFF0D47A1)),
            const SizedBox(width: 10),
            Text("Supabase SQL Setup"),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Run this script in your Supabase SQL Editor to initialize all statuses, audit logging tables, and RLS security policies:",
                style: TextStyle(fontSize: 13, color: Colors.black87, height: 1.3),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  sqlCode,
                  style: TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 10,
                    fontFamily: "monospace",
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Close"),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Clipboard.setData(const ClipboardData(text: sqlCode));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("SQL script copied to clipboard!"),
                  backgroundColor: Colors.green,
                ),
              );
              Navigator.pop(ctx);
            },
            icon: const Icon(Icons.copy, size: 16, color: Colors.white),
            label: const Text("Copy SQL", style: TextStyle(color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0D47A1),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Logout"),
        content: const Text("Are you sure you want to log out from the Admin Portal?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              await Supabase.instance.client.auth.signOut();
              if (!mounted) return;
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => const LoginScreen()),
                (route) => false,
              );
            },
            child: const Text("Logout", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<bool?> _showExitConfirmationDialog(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.exit_to_app, color: Color(0xFF0D47A1)),
            SizedBox(width: 10),
            Text("Exit App?"),
          ],
        ),
        content: const Text("Are you sure you want to close the homework support system?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD32F2F),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text("Exit", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // --- UI RENDER BUILDERS ---

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'active':
        return Colors.green;
      case 'inactive':
        return Colors.orange.shade800;
      case 'suspended':
        return Colors.red.shade800;
      case 'deleted':
      case 'archived':
        return Colors.grey.shade600;
      case 'graduated':
        return Colors.blue.shade800;
      case 'transferred':
        return Colors.purple.shade800;
      case 'authorized':
        return const Color(0xFF6A1B9A);
      default:
        return Colors.blueGrey;
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color primaryBlue = Color(0xFF0D47A1);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldExit = await _showExitConfirmationDialog(context);
        if (shouldExit == true && context.mounted) {
          await SystemNavigator.pop();
        }
      },
      child: Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text(
          "Admin Portal",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: primaryBlue,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.terminal, color: Colors.white),
            tooltip: "Show Database Setup Script",
            onPressed: _showSqlSetupDialog,
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            tooltip: "Log Out",
            onPressed: _showLogoutDialog,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          tabs: const [
            Tab(icon: Icon(Icons.business), text: "Schools"),
            Tab(icon: Icon(Icons.people_alt), text: "Users"),
            Tab(icon: Icon(Icons.history_toggle_off), text: "Audits"),
          ],
        ),
      ),
      body: Column(
        children: [
          // Connection banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: _isDbConnected ? Colors.green.shade50 : Colors.amber.shade50,
              border: Border(
                bottom: BorderSide(
                  color: _isDbConnected ? Colors.green.shade200 : Colors.amber.shade200,
                  width: 0.5,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _isDbConnected ? Icons.cloud_done : Icons.cloud_off,
                  color: _isDbConnected ? Colors.green.shade800 : Colors.amber.shade800,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _isDbConnected
                        ? "Connected: Schools are securely synced to Supabase."
                        : "Table Pending: Using seamless local database fallback.",
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _isDbConnected ? Colors.green.shade900 : Colors.amber.shade900,
                    ),
                  ),
                ),
                if (!_isDbConnected)
                  TextButton.icon(
                    onPressed: _showSqlSetupDialog,
                    icon: const Icon(Icons.terminal, size: 14),
                    label: const Text("Setup SQL", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      foregroundColor: Colors.amber.shade900,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildSchoolsTab(),
                _buildProfilesTab(),
                _buildAuditLogsTab(),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: _tabController.index == 0 && widget.adminRole != 'school_admin'
          ? FloatingActionButton.extended(
              onPressed: _showAddSchoolBottomSheet,
              backgroundColor: primaryBlue,
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text("Register School", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            )
          : null,
      ),
    );
  }

  // --- SCHOOLS TAB ---
  Widget _buildSchoolsTab() {
    if (_isLoadingSchools) {
      return const Center(child: CircularProgressIndicator());
    }

    final String schoolQuery = _schoolSearchController.text.trim().toLowerCase();
    final List<School> filteredSchools = _schoolsList.where((school) {
      if (schoolQuery.isEmpty) return true;
      final String name = school.schoolName.toLowerCase();
      final String code = school.code.toLowerCase();
      final String region = school.region.toLowerCase();
      final String district = school.district.toLowerCase();
      return name.contains(schoolQuery) ||
             code.contains(schoolQuery) ||
             region.contains(schoolQuery) ||
             district.contains(schoolQuery);
    }).toList();

    return RefreshIndicator(
      onRefresh: _loadSchools,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 8),
          Text(
            "Welcome, ${widget.adminName}",
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87),
          ),
          const SizedBox(height: 6),
          const Text(
            "Add, monitor, and manage official registered schools inside the system database.",
            style: TextStyle(fontSize: 13, color: Colors.grey, height: 1.4),
          ),
          const SizedBox(height: 16),
          // Search input field
          TextField(
            controller: _schoolSearchController,
            onChanged: (val) => setState(() {}),
            decoration: InputDecoration(
              hintText: "Search schools by name, code or region...",
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _schoolSearchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _schoolSearchController.clear();
                        setState(() {});
                      },
                    )
                  : null,
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade200),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: const Color(0xFF0D47A1), width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 16),
          
          if (filteredSchools.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 40.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.business_outlined, size: 64, color: Colors.grey.shade400),
                    const SizedBox(height: 16),
                    const Text("No registered schools found matching search.", style: TextStyle(color: Colors.grey, fontSize: 15)),
                  ],
                ),
              ),
            )
          else
            ...filteredSchools.map((school) {
              final bool isActive = school.status == 'active';

              return Card(
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: Colors.grey.shade200),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: widget.adminRole == 'school_admin' ? null : () => _showEditSchoolBottomSheet(school), // Tapping card opens edit sheet directly!
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: const Color(0xFF0D47A1).withOpacity(0.08),
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: const Icon(Icons.school, color: Color(0xFF0D47A1)),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                school.schoolName,
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.shade50,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      school.region,
                                      style: TextStyle(
                                        color: Colors.blue.shade800,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: school.status.toLowerCase() == 'active'
                                          ? const Color(0xFFF3E5F5) // Soft pastel lavender-pink background
                                          : Colors.orange.shade50,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      school.status.toUpperCase(),
                                      style: TextStyle(
                                        color: school.status.toLowerCase() == 'active'
                                            ? const Color(0xFF6A1B9A) // Rich deep violet-purple text
                                            : Colors.orange.shade800,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text("CODE", style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.grey)),
                              Text(
                                school.code,
                                style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0D47A1), fontSize: 13, fontFamily: "monospace"),
                              ),
                            ],
                          ),
                          if (widget.adminRole != 'school_admin')
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert, color: Colors.blueGrey, size: 22),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            onSelected: (value) {
                              // Wrap callback in Future.delayed to let the popup dismiss completely first
                              Future.delayed(Duration.zero, () {
                                if (value == 'edit') {
                                  _showEditSchoolBottomSheet(school);
                                } else if (value == 'toggle') {
                                  _toggleSchoolStatus(school);
                                } else if (value == 'delete') {
                                  _showDeleteSchoolDialog(school);
                                }
                              });
                            },
                            itemBuilder: (context) => [
                              PopupMenuItem(
                                value: 'edit',
                                child: Row(
                                  children: [
                                    Icon(Icons.edit_outlined, size: 18, color: Colors.blue.shade800),
                                    const SizedBox(width: 10),
                                    const Text("Edit Details"),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'toggle',
                                child: Row(
                                  children: [
                                    Icon(
                                      isActive ? Icons.power_settings_new : Icons.play_arrow_outlined,
                                      size: 18,
                                      color: isActive ? Colors.orange.shade800 : Colors.green.shade800,
                                    ),
                                    const SizedBox(width: 10),
                                    Text(isActive ? "Deactivate" : "Reactivate"),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(Icons.delete_outline, size: 18, color: Colors.red.shade800),
                                    const SizedBox(width: 10),
                                    Text("Delete (Archive)", style: TextStyle(color: Colors.red.shade800)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
            }).toList(),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  // --- PRE-REGISTER STUDENT DIALOG ---
  void _showPreRegisterStudentDialog() {
    final _preNameController = TextEditingController();
    final _preAdmissionController = TextEditingController();
    String selectedSchool = (widget.adminRole == 'school_admin' && widget.adminSchool != null)
        ? widget.adminSchool!
        : (_schoolsList.isNotEmpty 
            ? _schoolsList.first.schoolName 
            : 'Westfield Academy');
    String selectedLevel = 'Standard 7';

    // Auto-generation helper
    void updateSuggestedAdmission() {
      final String schoolCode;
      if (_schoolsList.isNotEmpty) {
        final schoolObj = _schoolsList.firstWhere(
          (s) => s.schoolName == selectedSchool,
          orElse: () => _schoolsList.first,
        );
        // Take first 3 characters of code or name
        schoolCode = schoolObj.code.length >= 3 
            ? schoolObj.code.substring(0, 3).toUpperCase() 
            : schoolObj.schoolName.substring(0, 3).toUpperCase();
      } else {
        schoolCode = selectedSchool.length >= 3
            ? selectedSchool.substring(0, 3).toUpperCase()
            : selectedSchool.toUpperCase();
      }
      final String lvlCode = selectedLevel.replaceAll('Standard ', 'STD');
      final int year = DateTime.now().year;
      
      // Generate a sequential-like random suffix
      final String suffix = (1 + (DateTime.now().millisecond % 99)).toString().padLeft(2, '0');
      _preAdmissionController.text = "$schoolCode-$lvlCode-$year$suffix";
    }

    // Call initially to fill suggested
    updateSuggestedAdmission();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.person_add_alt_1, color: Colors.blue.shade900),
              const SizedBox(width: 12),
              const Text("Pre-register Student"),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "Pre-authorize a student's admission number. The student must use this exact admission number as their username during signup to be approved.",
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _preNameController,
                  decoration: const InputDecoration(
                    labelText: "Student's Full Name",
                    prefixIcon: Icon(Icons.person),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                if (widget.adminRole == 'school_admin')
                  TextField(
                    controller: TextEditingController(text: selectedSchool),
                    decoration: const InputDecoration(
                      labelText: "School",
                      prefixIcon: Icon(Icons.school),
                      border: OutlineInputBorder(),
                      enabled: false,
                    ),
                  )
                else
                  DropdownButtonFormField<String>(
                    value: selectedSchool,
                    decoration: const InputDecoration(
                      labelText: "School",
                      prefixIcon: Icon(Icons.school),
                      border: OutlineInputBorder(),
                    ),
                    items: (_schoolsList.isEmpty
                            ? [
                                'Westfield Academy',
                                'Riverside International',
                                'Greenwood Academy',
                                'Hillside International',
                                'Dar es Salaam Academy'
                              ]
                            : _schoolsList.map((s) => s.schoolName).toList())
                        .map((school) {
                      return DropdownMenuItem(value: school, child: Text(school));
                    }).toList(),
                    onChanged: (val) {
                      setDlgState(() {
                        selectedSchool = val!;
                        updateSuggestedAdmission();
                      });
                    },
                  ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: selectedLevel,
                  decoration: const InputDecoration(
                    labelText: "Class / Level",
                    prefixIcon: Icon(Icons.grade),
                    border: OutlineInputBorder(),
                  ),
                  items: ['Standard 4', 'Standard 7'].map((level) {
                    return DropdownMenuItem(value: level, child: Text(level));
                  }).toList(),
                  onChanged: (val) {
                    setDlgState(() {
                      selectedLevel = val!;
                      updateSuggestedAdmission();
                    });
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _preAdmissionController,
                  decoration: const InputDecoration(
                    labelText: "Admission Number (Username)",
                    prefixIcon: Icon(Icons.badge),
                    border: OutlineInputBorder(),
                    helperText: "Student will use this as username to register.",
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("CANCEL"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade900,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () async {
                final String fullName = _preNameController.text.trim();
                final String admissionNumber = _preAdmissionController.text.trim().toUpperCase();
                
                if (fullName.isEmpty || admissionNumber.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Please fill all fields."), backgroundColor: Colors.red),
                  );
                  return;
                }

                Navigator.pop(ctx);
                
                // Show loading indicator on dashboard
                setState(() => _isLoadingProfiles = true);

                try {
                  // Insert the pre-authorized record
                  await Supabase.instance.client.from('student_records').insert({
                    'admission_number': admissionNumber,
                    'full_name': fullName,
                    'school': selectedSchool,
                    'level': selectedLevel,
                    'status': 'pending',
                  });

                  // Log audit log
                  await AuditLogService.log(
                    action: 'PRE_REGISTER_STUDENT',
                    details: 'Admin "${widget.adminName}" authorized student "$fullName" (Admission: $admissionNumber) for school "$selectedSchool".',
                  );

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text("Successfully pre-registered student: $fullName ($admissionNumber)"),
                      backgroundColor: Colors.green,
                    ),
                  );
                } catch (e) {
                  debugPrint("Pre-register student record failed, saving to local fallback: $e");
                  
                  // Save locally as a fallback
                  try {
                    final directory = await getApplicationDocumentsDirectory();
                    final file = File('${directory.path}/local_student_records_fallback.json');
                    List<dynamic> localRecords = [];
                    if (await file.exists()) {
                      localRecords = jsonDecode(await file.readAsString());
                    }
                    localRecords.add({
                      'admission_number': admissionNumber,
                      'full_name': fullName,
                      'school': selectedSchool,
                      'level': selectedLevel,
                      'status': 'pending',
                    });
                    await file.writeAsString(jsonEncode(localRecords));

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text("Saved to local offline authorized list: $fullName ($admissionNumber)"),
                        backgroundColor: Colors.orange,
                      ),
                    );
                  } catch (localErr) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("Failed to authorize student: $e"), backgroundColor: Colors.red),
                    );
                  }
                } finally {
                  _loadProfiles(); // Refresh user/profiles tab
                }
              },
              child: const Text("AUTHORIZE STUDENT"),
            ),
          ],
        ),
      ),
    );
  }

  void _showPreRegisterTeacherDialog() {
    final _preNameController = TextEditingController();
    final _preEmployeeController = TextEditingController();
    final _prePhoneController = TextEditingController();
    
    String selectedSchool = (widget.adminRole == 'school_admin' && widget.adminSchool != null)
        ? widget.adminSchool!
        : (_schoolsList.isNotEmpty 
            ? _schoolsList.first.schoolName 
            : 'Westfield Academy');

    const allLevels = [
      'Standard 4', 'Standard 7',
    ];
    final Map<String, bool> levelChecks = { for (var l in allLevels) l: true };

    // Auto-generation helper
    void updateSuggestedEmployee() {
      final String schoolPrefix;
      if (_schoolsList.isNotEmpty) {
        final schoolObj = _schoolsList.firstWhere(
          (s) => s.schoolName == selectedSchool,
          orElse: () => _schoolsList.first,
        );
        schoolPrefix = schoolObj.code.length >= 3 
            ? schoolObj.code.substring(0, 3).toUpperCase() 
            : schoolObj.schoolName.substring(0, 3).toUpperCase();
      } else {
        schoolPrefix = selectedSchool.length >= 3 
            ? selectedSchool.substring(0, 3).toUpperCase() 
            : selectedSchool.toUpperCase();
      }
      
      // Sequential number suffix
      final String suffix = (1 + (DateTime.now().millisecond % 99)).toString().padLeft(3, '0');
      _preEmployeeController.text = "${schoolPrefix}-TCH-$suffix";
    }

    // Call initially to fill suggested
    updateSuggestedEmployee();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.co_present, color: Colors.teal.shade800),
              const SizedBox(width: 12),
              const Text("Pre-register Teacher"),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "Pre-authorize a teacher's employee number. The teacher must use this exact employee number as their username during signup to be approved.",
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _preNameController,
                  decoration: const InputDecoration(
                    labelText: "Teacher's Full Name",
                    prefixIcon: Icon(Icons.person),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                if (widget.adminRole == 'school_admin')
                  TextField(
                    controller: TextEditingController(text: selectedSchool),
                    decoration: const InputDecoration(
                      labelText: "School",
                      prefixIcon: Icon(Icons.school),
                      border: OutlineInputBorder(),
                      enabled: false,
                    ),
                  )
                else
                  DropdownButtonFormField<String>(
                    value: selectedSchool,
                    decoration: const InputDecoration(
                      labelText: "School",
                      prefixIcon: Icon(Icons.school),
                      border: OutlineInputBorder(),
                    ),
                    items: (_schoolsList.isEmpty
                            ? [
                                'Westfield Academy',
                                'Riverside International',
                                'Greenwood Academy',
                                'Hillside International',
                                'Dar es Salaam Academy'
                              ]
                            : _schoolsList.map((s) => s.schoolName).toList())
                        .map((school) {
                      return DropdownMenuItem(value: school, child: Text(school));
                    }).toList(),
                    onChanged: (val) {
                      setDlgState(() {
                        selectedSchool = val!;
                        updateSuggestedEmployee();
                      });
                    },
                  ),
                const SizedBox(height: 16),
                TextField(
                  controller: _prePhoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: "Phone Number (Optional)",
                    prefixIcon: Icon(Icons.phone),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _preEmployeeController,
                  decoration: const InputDecoration(
                    labelText: "Employee Number (Username)",
                    prefixIcon: Icon(Icons.badge),
                    border: OutlineInputBorder(),
                    helperText: "Teacher will use this as username to register.",
                  ),
                ),
                const SizedBox(height: 16),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text("Classes / Levels Taught:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                ),
                ...allLevels.map((level) => CheckboxListTile(
                  title: Text(level),
                  value: levelChecks[level] ?? false,
                  activeColor: Colors.teal.shade800,
                  controlAffinity: ListTileControlAffinity.leading,
                  onChanged: (val) {
                    setDlgState(() => levelChecks[level] = val!);
                  },
                )),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("CANCEL"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal.shade800,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () async {
                final String fullName = _preNameController.text.trim();
                final String employeeNumber = _preEmployeeController.text.trim().toUpperCase();
                final String phone = _prePhoneController.text.trim();
                
                if (fullName.isEmpty || employeeNumber.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Please fill all fields."), backgroundColor: Colors.red),
                  );
                  return;
                }

                if (!levelChecks.values.any((v) => v)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Please select at least one class taught."), backgroundColor: Colors.red),
                  );
                  return;
                }

                final List<String> classes = allLevels.where((l) => levelChecks[l] == true).toList();

                Navigator.pop(ctx);
                
                // Show loading indicator on dashboard
                setState(() => _isLoadingProfiles = true);

                try {
                  // Insert the pre-authorized record
                  await Supabase.instance.client.from('teacher_records').insert({
                    'employee_number': employeeNumber,
                    'full_name': fullName,
                    'school': selectedSchool,
                    'phone_number': phone,
                    'classes': classes,
                    'status': 'pending',
                  });

                  // Log audit log
                  await AuditLogService.log(
                    action: 'PRE_REGISTER_TEACHER',
                    details: 'Admin "${widget.adminName}" authorized teacher "$fullName" (Employee: $employeeNumber) for school "$selectedSchool".',
                  );

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text("Successfully pre-registered teacher: $fullName ($employeeNumber)"),
                      backgroundColor: Colors.green,
                    ),
                  );
                } catch (e) {
                  debugPrint("Pre-register teacher record failed, saving to local fallback: $e");
                  
                  // Save locally as a fallback
                  try {
                    final directory = await getApplicationDocumentsDirectory();
                    final file = File('${directory.path}/local_teacher_records_fallback.json');
                    List<dynamic> localRecords = [];
                    if (await file.exists()) {
                      localRecords = jsonDecode(await file.readAsString());
                    }
                    localRecords.add({
                      'employee_number': employeeNumber,
                      'full_name': fullName,
                      'school': selectedSchool,
                      'phone_number': phone,
                      'classes': classes,
                      'status': 'pending',
                    });
                    await file.writeAsString(jsonEncode(localRecords));

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text("Saved to local offline authorized list: $fullName ($employeeNumber)"),
                        backgroundColor: Colors.orange,
                      ),
                    );
                  } catch (localErr) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("Failed to authorize teacher: $e"), backgroundColor: Colors.red),
                    );
                  }
                } finally {
                  _loadProfiles(); // Refresh user/profiles tab
                }
              },
              child: const Text("AUTHORIZE TEACHER"),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CREATE SCHOOL ADMIN (by Super Admin only)
  // Directly provisions a Supabase Auth account + profile record.
  // No self-registration required — credentials are handed to the admin.
  // ─────────────────────────────────────────────────────────────────────────
  void _showCreateSchoolAdminDialog() {
    final nameCtrl = TextEditingController();
    final usernameCtrl = TextEditingController();
    final tempPassCtrl = TextEditingController();
    String selectedSchool = _schoolsList.isNotEmpty
        ? _schoolsList.first.schoolName
        : 'Westfield Academy';
    bool isCreating = false;
    bool passVisible = false;
    String? createdCredentials;

    void _generateSuggestedUsername() {
      final schoolObj = _schoolsList.firstWhere(
        (s) => s.schoolName == selectedSchool,
        orElse: () => School(id: '', schoolName: selectedSchool, region: '', district: '', code: selectedSchool.substring(0, 3)),
      );
      final prefix = schoolObj.code.length >= 3
          ? schoolObj.code.substring(0, 3).toLowerCase()
          : schoolObj.schoolName.substring(0, 3).toLowerCase();
      final suffix = (DateTime.now().millisecond % 99 + 1).toString().padLeft(2, '0');
      usernameCtrl.text = '${prefix}_admin$suffix';
    }

    void _generateTempPassword() {
      final schoolObj = _schoolsList.firstWhere(
        (s) => s.schoolName == selectedSchool,
        orElse: () => School(id: '', schoolName: selectedSchool, region: '', district: '', code: selectedSchool.substring(0, 3)),
      );
      final prefix = schoolObj.code.length >= 3
          ? schoolObj.code.substring(0, 3).toUpperCase()
          : schoolObj.schoolName.substring(0, 3).toUpperCase();
      tempPassCtrl.text = '${prefix}admin#${DateTime.now().year}';
    }

    _generateSuggestedUsername();
    _generateTempPassword();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.purple.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.admin_panel_settings, color: Colors.purple.shade800, size: 26),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Create School Admin", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    Text("Credentials created by Super Admin", style: TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: createdCredentials != null
                // ── Step 2: Show generated credentials to copy ──
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.green.shade300),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.check_circle, color: Colors.green.shade700, size: 18),
                                const SizedBox(width: 8),
                                const Text("Account Created Successfully!",
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F172A),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                createdCredentials!,
                                style: const TextStyle(
                                  color: Colors.greenAccent,
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                  height: 1.6,
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              "⚠️ Share these credentials securely with the School Admin. They will be forced to change their password on first login.",
                              style: TextStyle(fontSize: 11, color: Colors.black54, height: 1.4),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.copy, size: 16),
                          label: const Text("Copy Credentials"),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: createdCredentials!));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("Credentials copied to clipboard!"), backgroundColor: Colors.green),
                            );
                          },
                        ),
                      ),
                    ],
                  )
                // ── Step 1: Input form ──
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          "School Admin accounts are created directly by Super Admin. The admin logs in using the credentials below — no registration form needed.",
                          style: TextStyle(fontSize: 12, color: Colors.black87, height: 1.4),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: nameCtrl,
                        decoration: InputDecoration(
                          labelText: "Full Name",
                          prefixIcon: const Icon(Icons.person),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: selectedSchool,
                        decoration: InputDecoration(
                          labelText: "Assigned School",
                          prefixIcon: const Icon(Icons.school),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        items: (_schoolsList.isEmpty
                                ? ['Westfield Academy']
                                : _schoolsList.map((s) => s.schoolName).toList())
                            .map((s) => DropdownMenuItem(value: s, child: Text(s, overflow: TextOverflow.ellipsis)))
                            .toList(),
                        onChanged: (val) {
                          setDlgState(() {
                            selectedSchool = val!;
                            _generateSuggestedUsername();
                            _generateTempPassword();
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: usernameCtrl,
                        decoration: InputDecoration(
                          labelText: "Username (Login ID)",
                          prefixIcon: const Icon(Icons.badge),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          helperText: "Admin uses this to log in",
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: tempPassCtrl,
                        obscureText: !passVisible,
                        decoration: InputDecoration(
                          labelText: "Temporary Password",
                          prefixIcon: const Icon(Icons.lock_outline),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          helperText: "Admin must change this on first login",
                          suffixIcon: IconButton(
                            icon: Icon(passVisible ? Icons.visibility_off : Icons.visibility),
                            onPressed: () => setDlgState(() => passVisible = !passVisible),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
          actions: createdCredentials != null
              ? [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0D47A1),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text("DONE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ]
              : [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text("Cancel"),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple.shade800,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: isCreating
                        ? null
                        : () async {
                            final fullName = nameCtrl.text.trim();
                            final username = usernameCtrl.text.trim().toLowerCase();
                            final tempPass = tempPassCtrl.text.trim();

                            if (fullName.isEmpty || username.isEmpty || tempPass.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text("All fields are required."), backgroundColor: Colors.red),
                              );
                              return;
                            }
                            if (tempPass.length < 8) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text("Temporary password must be at least 8 characters."), backgroundColor: Colors.red),
                              );
                              return;
                            }

                            setDlgState(() => isCreating = true);

                            try {
                              // Build the synthetic email used for Supabase Auth
                              final email = '${username}_private_app@mathsupport.tz';

                              // 1. Create Supabase Auth user
                              final res = await Supabase.instance.client.auth.signUp(
                                email: email,
                                password: tempPass,
                              );

                              if (res.user == null) throw Exception('Auth signup returned null user.');

                              // 2. Insert profile record
                              await Supabase.instance.client.from('profiles').insert({
                                'id': res.user!.id,
                                'full_name': fullName,
                                'role': 'school_admin',
                                'username': username,
                                'level': 'Admin',
                                'school': selectedSchool,
                                'status': 'active',
                                'must_change_password': true,
                              });

                              // 3. Mark in school_admin_records as registered
                              try {
                                await Supabase.instance.client.from('school_admin_records').insert({
                                  'username': username,
                                  'full_name': fullName,
                                  'school': selectedSchool,
                                  'status': 'registered',
                                });
                              } catch (_) {}

                              // 4. Audit log
                              await AuditLogService.log(
                                action: 'CREATE_SCHOOL_ADMIN',
                                details: 'Super Admin "${widget.adminName}" created school admin "$fullName" (Username: $username) for "$selectedSchool". Temp password issued.',
                              );

                              final credentials =
                                  'School: $selectedSchool\nName: $fullName\nUsername: $username\nTemp Password: $tempPass\nNote: Must change password on first login.';

                              setDlgState(() {
                                isCreating = false;
                                createdCredentials = credentials;
                              });

                              _loadProfiles();
                            } catch (e) {
                              setDlgState(() => isCreating = false);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Failed to create account: ${e.toString().replaceAll('Exception:', '').trim()}'),
                                  backgroundColor: Colors.red,
                                  duration: const Duration(seconds: 5),
                                ),
                              );
                              debugPrint('[CreateSchoolAdmin] Error: $e');
                            }
                          },
                    child: isCreating
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text("CREATE ACCOUNT"),
                  ),
                ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ADMIN SETTINGS DIALOG
  // Configure Supabase Service Role Key (needed for password resets).
  // ─────────────────────────────────────────────────────────────────────────
  void _showAdminSettingsDialog() {
    final keyCtrl = TextEditingController(text: AppSettings.supabaseServiceRoleKey.value);
    bool keyVisible = false;
    bool isSaving = false;
    bool saved = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.settings, color: Colors.blue.shade800, size: 22),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Admin Settings", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    Text("Supabase configuration", style: TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.amber.shade300),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline, size: 16, color: Colors.amber),
                          SizedBox(width: 6),
                          Text("Why is this needed?", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        ],
                      ),
                      SizedBox(height: 6),
                      Text(
                        "The Service Role Key is required to reset passwords for other users. "
                        "Without it, the Reset Password function cannot update Supabase Auth.\n\n"
                        "🔑 Where to find it:\n"
                        "Supabase Dashboard → Project Settings → API → service_role (secret) key",
                        style: TextStyle(fontSize: 12, height: 1.5, color: Colors.black87),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: keyCtrl,
                  obscureText: !keyVisible,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  decoration: InputDecoration(
                    labelText: "Supabase Service Role Key",
                    hintText: "eyJhbGciOiJIUz...",
                    prefixIcon: const Icon(Icons.vpn_key_outlined),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    helperText: "Stored locally on this device only",
                    suffixIcon: IconButton(
                      icon: Icon(keyVisible ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setDlgState(() => keyVisible = !keyVisible),
                    ),
                  ),
                ),
                if (saved) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.shade300),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.green.shade700, size: 16),
                        const SizedBox(width: 8),
                        const Text("Key saved! Password resets are now enabled.", style: TextStyle(fontSize: 12, color: Colors.black87)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Close")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0D47A1),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: isSaving
                  ? null
                  : () async {
                      setDlgState(() => isSaving = true);
                      await AppSettings.updateSupabaseServiceRoleKey(keyCtrl.text.trim());
                      setDlgState(() {
                        isSaving = false;
                        saved = true;
                      });
                    },
              child: isSaving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text("Save Key"),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ADMIN RESET PASSWORD
  // Admin issues a new temporary password for any managed user.
  // On next login, the user is forced to create their own password.
  // ─────────────────────────────────────────────────────────────────────────
  void _showResetPasswordDialog(Map<String, dynamic> profile) {
    final String userId = profile['id']?.toString() ?? '';
    final String userName = profile['full_name']?.toString() ?? 'User';
    final String userRole = (profile['role']?.toString() ?? 'student').toLowerCase();
    final String username = profile['username']?.toString() ?? '';
    final String userSchool = profile['school']?.toString() ?? '';

    // ── School Admin scope check: only allow resetting users of their school ──
    if (widget.adminRole == 'school_admin' && widget.adminSchool != null) {
      final bool sameSchool = userSchool.trim().toLowerCase() == widget.adminSchool!.trim().toLowerCase();
      if (!sameSchool) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Access Denied: You can only reset passwords for users in your school."),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    final tempPassCtrl = TextEditingController();
    bool passVisible = false;
    bool isResetting = false;
    String? successMsg;

    // Generate a sensible default temp password
    final prefix = username.length >= 3 ? username.substring(0, 3).toUpperCase() : 'TMP';
    tempPassCtrl.text = '${prefix}Temp#${DateTime.now().year}';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.orange.shade50, shape: BoxShape.circle),
                child: Icon(Icons.lock_reset, color: Colors.orange.shade800, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Reset Password", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    Text(userName, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
            ],
          ),
          content: successMsg != null
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.green.shade300),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Icon(Icons.check_circle, color: Colors.green.shade700, size: 18),
                              const SizedBox(width: 8),
                              const Text("Password reset successfully!",
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              successMsg!,
                              style: const TextStyle(color: Colors.greenAccent, fontFamily: 'monospace', fontSize: 12, height: 1.5),
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            "Share this temporary password securely. The user will be required to change it on next login.",
                            style: TextStyle(fontSize: 11, color: Colors.black54, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.copy, size: 14),
                        label: const Text("Copy"),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: successMsg!));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("Copied to clipboard!"), backgroundColor: Colors.green),
                          );
                        },
                      ),
                    ),
                  ],
                )
              : SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: Text(
                          "You are resetting the password for $userName (${userRole.toUpperCase()}). They will be required to change this temporary password on their next login.",
                          style: const TextStyle(fontSize: 12, color: Colors.black87, height: 1.4),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: tempPassCtrl,
                        obscureText: !passVisible,
                        decoration: InputDecoration(
                          labelText: "New Temporary Password",
                          prefixIcon: const Icon(Icons.lock_outline),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          helperText: "Min. 8 characters",
                          suffixIcon: IconButton(
                            icon: Icon(passVisible ? Icons.visibility_off : Icons.visibility),
                            onPressed: () => setDlgState(() => passVisible = !passVisible),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
          actions: successMsg != null
              ? [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0D47A1),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text("DONE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ]
              : [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange.shade800,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: isResetting
                        ? null
                        : () async {
                            final tempPass = tempPassCtrl.text.trim();
                            if (tempPass.length < 8) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text("Password must be at least 8 characters."), backgroundColor: Colors.red),
                              );
                              return;
                            }
                            setDlgState(() => isResetting = true);
                            try {
                              // ─── STEP 1: Change the REAL Supabase Auth password ───
                              final authApiUrl = Uri.parse('$_supabaseUrl/auth/v1/admin/users/$userId');
                              final authResponse = await http.put(
                                authApiUrl,
                                headers: {
                                  'Content-Type': 'application/json',
                                  'apikey': _supabaseServiceRoleKey,
                                  'Authorization': 'Bearer $_supabaseServiceRoleKey',
                                },
                                body: jsonEncode({'password': tempPass}),
                              );

                              if (authResponse.statusCode != 200) {
                                final body = jsonDecode(authResponse.statusCode == 200
                                    ? authResponse.body
                                    : authResponse.body);
                                throw Exception(
                                  'Supabase Auth API error (${authResponse.statusCode}): '
                                  '${body['message'] ?? body['error_description'] ?? authResponse.body}',
                                );
                              }

                              // ─── STEP 2: Flag must_change_password so user is forced to set a personal password ───
                              await Supabase.instance.client
                                  .from('profiles')
                                  .update({'must_change_password': true})
                                  .eq('id', userId);

                              // ─── STEP 3: Audit log ───
                              await AuditLogService.log(
                                action: 'ADMIN_RESET_PASSWORD',
                                details: 'Admin "${widget.adminName}" reset password for "$userName" (Role: ${userRole.toUpperCase()}, Username: $username). Temporary password issued. User must change on next login.',
                              );

                              final msg = 'User: $userName\nUsername: $username\nTemp Password: $tempPass\nNote: Must change on next login.';
                              setDlgState(() {
                                isResetting = false;
                                successMsg = msg;
                              });
                              _loadAuditLogs();
                            } catch (e) {
                              setDlgState(() => isResetting = false);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Reset failed: ${e.toString().replaceAll('Exception:', '').trim()}'),
                                  backgroundColor: Colors.red,
                                  duration: const Duration(seconds: 8),
                                ),
                              );
                            }
                          },
                    child: isResetting
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text("RESET PASSWORD"),
                  ),
                ],
        ),
      ),
    );
  }

  Future<void> _revokePreRegistration(Map<String, dynamic> profile) async {
    final String name = profile['full_name']?.toString() ?? 'User';
    final String admission = profile['username']?.toString() ?? '';
    final bool isTeacher = profile['is_teacher_record'] == true;
    final bool isSchoolAdmin = profile['is_school_admin_record'] == true;
    final String table = isSchoolAdmin ? 'school_admin_records' : (isTeacher ? 'teacher_records' : 'student_records');
    final String keyColumn = isSchoolAdmin ? 'username' : (isTeacher ? 'employee_number' : 'admission_number');
    final String fallbackFile = isSchoolAdmin ? 'local_school_admin_records_fallback.json' : (isTeacher ? 'local_teacher_records_fallback.json' : 'local_student_records_fallback.json');

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Revoke Authorization?"),
        content: Text("Are you sure you want to revoke registration approval for $name ($admission)? They will no longer be allowed to sign up."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("CANCEL")),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("REVOKE", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoadingProfiles = true);
      try {
        // Delete record from Supabase
        await Supabase.instance.client
            .from(table)
            .delete()
            .eq(keyColumn, admission.toUpperCase());

        // Delete from local cache
        try {
          final directory = await getApplicationDocumentsDirectory();
          final file = File('${directory.path}/$fallbackFile');
          if (await file.exists()) {
            final List local = jsonDecode(await file.readAsString());
            local.removeWhere((r) => r[keyColumn].toString().toUpperCase() == admission.toUpperCase());
            await file.writeAsString(jsonEncode(local));
          }
        } catch (_) {}

        // Log audit trail
        await AuditLogService.log(
          action: isSchoolAdmin ? 'REVOKE_SCHOOL_ADMIN_AUTH' : (isTeacher ? 'REVOKE_TEACHER_AUTH' : 'REVOKE_STUDENT_AUTH'),
          details: 'Admin "${widget.adminName}" revoked registration approval for $name ($admission).',
        );

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Revoked registration approval for $name"), backgroundColor: Colors.red),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to revoke: $e"), backgroundColor: Colors.red),
        );
      } finally {
        _loadProfiles();
      }
    }
  }

  // --- PROFILES TAB ---
  Widget _buildProfilesTab() {
    if (_isLoadingProfiles) {
      return const Center(child: CircularProgressIndicator());
    }

    // Filters user list based on segmented selector & search query
    final String query = _userSearchController.text.trim().toLowerCase();
    final List<Map<String, dynamic>> filteredList = _profilesList.where((p) {
      // 1. Role Filter check
      final String role = p['role']?.toString().toLowerCase() ?? '';
      if (_selectedRoleFilter != 'All') {
        if (_selectedRoleFilter == 'Students' && role != 'student') return false;
        if (_selectedRoleFilter == 'Teachers' && role != 'teacher') return false;
        if (_selectedRoleFilter == 'Parents' && role != 'parent') return false;
        if (_selectedRoleFilter == 'School Admins' && role != 'school_admin') return false;
        if (_selectedRoleFilter == 'Admins' && role != 'admin') return false;
      }
      
      // 2. Search query check
      if (query.isNotEmpty) {
        final String name = p['full_name']?.toString().toLowerCase() ?? '';
        final String username = p['username']?.toString().toLowerCase() ?? '';
        if (!name.contains(query) && !username.contains(query)) {
          return false;
        }
      }
      return true;
    }).toList();

    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.people_alt_outlined, size: 20, color: Color(0xFF0D47A1)),
                  const SizedBox(width: 8),
                  const Text(
                    "User Directory",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF0D47A1)),
                  ),
                  const Spacer(),
                  PopupMenuButton<String>(
                    offset: const Offset(0, 45),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    onSelected: (val) {
                      if (val == 'student') {
                        _showPreRegisterStudentDialog();
                      } else if (val == 'teacher') {
                        _showPreRegisterTeacherDialog();
                      } else if (val == 'school_admin') {
                        _showCreateSchoolAdminDialog();
                      }
                    },
                    itemBuilder: (ctx) => [
                      PopupMenuItem(
                        value: 'student',
                        child: Row(
                          children: [
                            Icon(Icons.person_add_alt_1, color: Colors.blue.shade900, size: 18),
                            const SizedBox(width: 10),
                            const Text("Pre-register Student", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'teacher',
                        child: Row(
                          children: [
                            Icon(Icons.co_present, color: Colors.teal.shade800, size: 18),
                            const SizedBox(width: 10),
                            const Text("Pre-register Teacher", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      if (widget.adminRole == 'admin' || widget.adminRole == 'super_admin')
                        PopupMenuItem(
                          value: 'school_admin',
                          child: Row(
                            children: [
                              Icon(Icons.admin_panel_settings, color: Colors.purple.shade800, size: 18),
                              const SizedBox(width: 10),
                              const Text("Create School Admin", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                    ],
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.blue.shade900,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add_moderator, size: 16, color: Colors.white),
                          SizedBox(width: 6),
                          Text("Pre-register", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                          SizedBox(width: 4),
                          Icon(Icons.arrow_drop_down, size: 16, color: Colors.white),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Segmented Role pills selector
              Align(
                alignment: Alignment.centerLeft,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      'All',
                      'Students',
                      'Teachers',
                      'Parents',
                      if (widget.adminRole == 'admin' || widget.adminRole == 'super_admin') 'School Admins',
                      'Admins'
                    ].map((role) {
                      // Adjust matching selected state for dropdown legacy initialization 'Student', 'Teacher', etc.
                      final bool isSelected = _selectedRoleFilter == role || 
                        (_selectedRoleFilter == 'Student' && role == 'Students') ||
                        (_selectedRoleFilter == 'Teacher' && role == 'Teachers') ||
                        (_selectedRoleFilter == 'Parent' && role == 'Parents') ||
                        (_selectedRoleFilter == 'School Admin' && role == 'School Admins') ||
                        (_selectedRoleFilter == 'Admin' && role == 'Admins');

                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedRoleFilter = role;
                          });
                        },
                        child: Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: isSelected ? const Color(0xFF0D47A1) : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isSelected ? const Color(0xFF0D47A1) : Colors.grey.shade300,
                            ),
                          ),
                          child: Text(
                            role,
                            style: TextStyle(
                              color: isSelected ? Colors.white : Colors.grey.shade700,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Search input field
              TextField(
                controller: _userSearchController,
                onChanged: (val) => setState(() {}),
                decoration: InputDecoration(
                  hintText: "Search by name or username...",
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _userSearchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _userSearchController.clear();
                            setState(() {});
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF0D47A1), width: 1.5),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: filteredList.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.people_outline, size: 48, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      const Text("No users found for this role.", style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadProfiles,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: filteredList.length,
                    itemBuilder: (context, index) {
                      final profile = filteredList[index];
                      final String role = profile['role']?.toString().toUpperCase() ?? 'STUDENT';
                      final String status = profile['status']?.toString() ?? 'active';
                      final String name = profile['full_name']?.toString() ?? 'User';
                      final String username = profile['username']?.toString() ?? '-';

                      return Card(
                        elevation: 0,
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(color: Colors.grey.shade200),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: role == 'TEACHER'
                                      ? Colors.green.shade50
                                      : (role == 'PARENT'
                                          ? Colors.amber.shade100
                                          : (role == 'ADMIN'
                                              ? Colors.indigo.shade50
                                              : Colors.blue.shade50)),
                                  shape: BoxShape.circle,
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  name.isNotEmpty ? name[0].toUpperCase() : 'U',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: role == 'TEACHER'
                                        ? Colors.green.shade800
                                        : (role == 'PARENT'
                                            ? Colors.amber.shade900
                                            : (role == 'ADMIN'
                                                ? Colors.indigo.shade900
                                                : const Color(0xFF0D47A1))),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87)),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.grey.shade100,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(role, style: TextStyle(color: Colors.grey.shade800, fontSize: 9, fontWeight: FontWeight.bold)),
                                        ),
                                        const SizedBox(width: 6),
                                        Text("id: $username", style: const TextStyle(color: Colors.grey, fontSize: 11)),
                                      ],
                                    ),
                                    if (role == 'TEACHER') ...[
                                      const SizedBox(height: 6),
                                      if (profile['school']?.toString().isNotEmpty == true)
                                        Row(
                                          children: [
                                            const Icon(Icons.school, size: 13, color: Colors.grey),
                                            const SizedBox(width: 4),
                                            Expanded(
                                              child: Text(
                                                profile['school'].toString(),
                                                style: const TextStyle(color: Colors.black54, fontSize: 12),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                    ],
                                    if (role == 'STUDENT') ...[
                                      const SizedBox(height: 6),
                                      if (profile['level']?.toString().isNotEmpty == true)
                                        Row(
                                          children: [
                                            const Icon(Icons.class_, size: 13, color: Colors.grey),
                                            const SizedBox(width: 4),
                                            Text(
                                              profile['level'].toString(),
                                              style: const TextStyle(color: Colors.black54, fontSize: 12),
                                            ),
                                          ],
                                        ),
                                      const SizedBox(height: 4),
                                      if (profile['school']?.toString().isNotEmpty == true)
                                        Row(
                                          children: [
                                            const Icon(Icons.school, size: 13, color: Colors.grey),
                                            const SizedBox(width: 4),
                                            Expanded(
                                              child: Text(
                                                profile['school'].toString(),
                                                style: const TextStyle(color: Colors.black54, fontSize: 12),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                    ],
                                    if (role == 'PARENT') ...[
                                      if (profile['linked_children'] != null && (profile['linked_children'] as List).isNotEmpty) ...[
                                        const SizedBox(height: 8),
                                        const Text(
                                          "Linked Children:",
                                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black54),
                                        ),
                                        const SizedBox(height: 4),
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: (profile['linked_children'] as List).map<Widget>((childName) {
                                            return Padding(
                                              padding: const EdgeInsets.only(bottom: 2.0),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const Icon(Icons.check, size: 12, color: Colors.green),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    childName.toString(),
                                                    style: const TextStyle(fontSize: 12, color: Colors.black87),
                                                  ),
                                                ],
                                              ),
                                            );
                                          }).toList(),
                                        ),
                                      ],
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: _getStatusColor(status).withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      status.toUpperCase(),
                                      style: TextStyle(color: _getStatusColor(status), fontSize: 10, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  if (profile['is_pre_registered'] == true)
                                    TextButton.icon(
                                      style: TextButton.styleFrom(
                                        padding: EdgeInsets.zero,
                                        minimumSize: Size.zero,
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        foregroundColor: Colors.red.shade800,
                                      ),
                                      onPressed: () => _revokePreRegistration(profile),
                                      icon: const Icon(Icons.delete_forever, size: 14),
                                      label: const Text("Revoke", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                    )
                                  else
                                    TextButton.icon(
                                      style: TextButton.styleFrom(
                                        padding: EdgeInsets.zero,
                                        minimumSize: Size.zero,
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      onPressed: () => _showManageUserDialog(profile),
                                      icon: const Icon(Icons.settings, size: 14),
                                      label: const Text("Manage", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  // --- AUDITS TAB ---
  Widget _buildAuditLogsTab() {
    if (_isLoadingLogs) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_auditLogsList.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history_toggle_off, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            const Text("Audit trails are clean. No actions logged yet.", style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAuditLogs,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _auditLogsList.length,
        itemBuilder: (context, index) {
          final log = _auditLogsList[index];
          final String action = log['action']?.toString() ?? 'SYSTEM_EVENT';
          final String actor = log['actor_name']?.toString() ?? 'System';
          final String details = log['details']?.toString() ?? '-';
          final String timestamp = log['timestamp']?.toString() ?? '';
          
          DateTime? parsedTime;
          String formattedTime = '';
          try {
            parsedTime = DateTime.parse(timestamp).toLocal();
            formattedTime = "${parsedTime.hour.toString().padLeft(2, '0')}:${parsedTime.minute.toString().padLeft(2, '0')} | ${parsedTime.day}/${parsedTime.month}/${parsedTime.year}";
          } catch (_) {
            formattedTime = timestamp;
          }

          final bool isLocal = action.endsWith('_LOCAL');

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: isLocal ? Colors.amber.withOpacity(0.3) : Colors.white10),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isLocal ? Colors.amber.shade900.withOpacity(0.3) : Colors.blue.shade900.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: isLocal ? Colors.amber.shade800 : Colors.blue.shade800),
                        ),
                        child: Text(
                          action,
                          style: TextStyle(
                            color: isLocal ? Colors.amber.shade400 : Colors.blue.shade300,
                            fontFamily: "monospace",
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                          ),
                        ),
                      ),
                      Text(
                        formattedTime,
                        style: const TextStyle(color: Colors.white38, fontSize: 11, fontFamily: "monospace"),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    details,
                    style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 13, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.person_pin, color: Colors.greenAccent, size: 14),
                      const SizedBox(width: 6),
                      Text(
                        "Actor: $actor",
                        style: const TextStyle(
                          color: Colors.greenAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                          fontFamily: "monospace",
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
