import 'dart:io' hide File, Directory;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart';
import '../services/web_safe_file.dart';
import 'student_dashboard.dart';
import 'teacher_dashboard.dart';
import 'parent_schools_screen.dart';
import 'admin_dashboard.dart';
import '../services/school_service.dart';
import '../services/audit_log_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _nameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();
  final _studentUsernameController = TextEditingController();

  String _selectedRole = 'Student';
  String _selectedLevel = 'Standard 7';
  String _selectedSchool = 'Westfield Academy';
  final List<Map<String, String>> _registerChildren = [
  List<String> _teacherClasses = []; // classes assigned by admin during pre-registration
  List<Map<String, String>> _registerChildren = [
    {'username': '', 'school': 'Westfield Academy'}
  ];
  bool _isLogin = true;
  bool _isLoading = false;
  bool _obscurePassword = true;
  List<School> _availableSchools = [];

  @override
  void initState() {
    super.initState();
    _loadAvailableSchools();
  }

  Future<void> _loadAvailableSchools() async {
    final list = await SchoolService.getSchools();
    if (mounted) {
      setState(() {
        _availableSchools = list;
        if (_availableSchools.isNotEmpty) {
          _selectedSchool = _availableSchools.first.schoolName;
          for (var child in _registerChildren) {
            if (child['school'] == null || !_availableSchools.any((s) => s.schoolName == child['school'])) {
              child['school'] = _availableSchools.first.schoolName;
            }
          }
        }
      });
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(msg)),
          ],
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _handleAuth() async {
    final rawUsername = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text.trim();
    String fullName = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final String effectiveUsername = (_selectedRole == 'Parent' && !_isLogin)
        ? phone
        : rawUsername;

    // --- 1. PRE-VALIDATION CHECK (THE "NO EMOJI" RULE) ---
    if (!_isLogin && _selectedRole == 'Parent') {
      for (var childEntry in _registerChildren) {
        final childUser = childEntry['username']!.trim().toLowerCase();
        if (childUser.isEmpty) {
          _showError("Please enter a username for all children.");
          return;
        }
        if (!RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(childUser)) {
          _showError(
            "Child's username '$childUser' can only contain letters, numbers, dots, underscores, and hyphens. No emojis or spaces.",
          );
          return;
        }
      }
    }

    if (!_isLogin) {
      if (fullName.isEmpty) {
        _showError("Please enter your Full Name");
        return;
      }
      if (_selectedRole == 'Parent') {
        if (phone.isEmpty) {
          _showError("Please enter your Phone Number");
          return;
        }
        if (phone.length != 10 || !RegExp(r'^\d{10}$').hasMatch(phone)) {
          _showError("Phone Number must be exactly 10 digits and contain only numbers");
          return;
        }
      } else {
        if (rawUsername.isEmpty) {
          _showError("Please choose a username");
          return;
        }
      }
    } else {
      if (rawUsername.isEmpty) {
        _showError(
          _selectedRole == 'Parent'
              ? "Please enter your Phone Number"
              : "Please enter your username",
        );
        return;
      }
      final bool isNumeric = RegExp(r'^\d+$').hasMatch(rawUsername);
      if (isNumeric && rawUsername.length != 10) {
        _showError("Phone Number must be exactly 10 digits");
        return;
      }
      if (RegExp(r'^\d').hasMatch(rawUsername) && !isNumeric) {
        _showError("Phone Number must contain only numbers");
        return;
      }
    }

    if (password.length < 8) {
      _showError("Password must be at least 8 characters long");
      return;
    }

    if (_isLogin) {
      final lockoutDuration = await LoginLockout.getRemainingLockout(effectiveUsername);
      if (lockoutDuration != null) {
        final minutes = lockoutDuration.inMinutes;
        final seconds = lockoutDuration.inSeconds % 60;
        final timeStr = minutes > 0 ? "$minutes minutes" : "$seconds seconds";
        _showError("Too many failed login attempts. Temporarily locked out. Please try again in $timeStr.");
        return;
      }
    }

    final email = "${effectiveUsername}_private_app@mathsupport.tz";

    setState(() => _isLoading = true);

    try {
      if (_isLogin) {
        final response = await Supabase.instance.client.auth.signInWithPassword(
          email: email,
          password: password,
        );

        if (response.user != null) {
          await LoginLockout.recordSuccess(effectiveUsername);
          final userData = await Supabase.instance.client
              .from('profiles')
              .select()
              .eq('id', response.user!.id)
              .single();

          final String dbRole = userData['role'].toString().toLowerCase();
          final String dbStatus = (userData['status']?.toString() ?? 'active').trim().toLowerCase();
          final bool mustChangePassword = userData['must_change_password'] == true;

          if (!mounted) return;

          if (dbStatus == 'suspended') {
            setState(() => _isLoading = false);
            _showError("Access Denied: Your account has been suspended.");
            await Supabase.instance.client.auth.signOut();
            return;
          }
          if (dbStatus == 'deleted') {
            setState(() => _isLoading = false);
            _showError("Access Denied: Your account has been deleted.");
            await Supabase.instance.client.auth.signOut();
            return;
          }
          if (dbStatus == 'inactive') {
            setState(() => _isLoading = false);
            _showError("Access Denied: Your student account is currently inactive.");
            await Supabase.instance.client.auth.signOut();
            return;
          }

          // ── First-Login Security: Force password change if flagged ──
          if (mustChangePassword) {
            setState(() => _isLoading = false);
            if (!mounted) return;
            await _showForceChangePasswordDialog(
              userId: response.user!.id,
              userRole: dbRole,
              userData: userData,
            );
            return;
          }

          if (dbRole == 'student') {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => StudentDashboard(
                  userName: userData['full_name'] ?? '',
                  studentLevel: userData['level'] ?? '',
                ),
              ),
            );
          } else if (dbRole == 'teacher') {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    TeacherDashboard(userName: userData['full_name'] ?? ''),
              ),
            );
          } else if (dbRole == 'admin' || dbRole == 'super_admin' || dbRole == 'school_admin') {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => AdminDashboard(
                  adminName: userData['full_name'] ?? 'Admin',
                  adminRole: dbRole,
                  adminSchool: userData['school']?.toString(),
                ),
              ),
            );
          } else {
            // SYNC parent children cache under authenticated session BEFORE navigation
            try {
              final directory = await AppSettings.getSafeDirectory();
              final file = File('${directory.path}/parent_signup_cache.json');
              if (await file.exists()) {
                debugPrint("DEBUG LoginScreen: Found parent signup cache on login, syncing...");
                final Map<String, dynamic> cache = jsonDecode(await file.readAsString());
                final List children = cache['children'] ?? [];
                
                bool allSuccessful = true;
                for (var child in children) {
                  final String username = child['username']?.toString() ?? '';
                  final String school = child['school']?.toString() ?? 'Westfield Academy';
                  final String level = child['level']?.toString() ?? 'Standard 7';

                  if (username.isNotEmpty) {
                    try {
                      await Supabase.instance.client.from('parent_child_links').insert({
                        'parent_id': response.user!.id,
                        'student_username': username,
                        'student_level': level,
                        'school': school,
                      });
                      debugPrint("DEBUG LoginScreen: Synced child '$username' with school '$school'");
                    } catch (dbErr) {
                      debugPrint("DEBUG LoginScreen: Sync insert with school failed, trying fallback: $dbErr");
                      try {
                        await Supabase.instance.client.from('parent_child_links').insert({
                          'parent_id': response.user!.id,
                          'student_username': username,
                          'student_level': level,
                        });
                        // Save locally
                        final sFile = File('${directory.path}/parent_schools_config.json');
                        Map<String, dynamic> localData = {};
                        if (await sFile.exists()) {
                          localData = jsonDecode(await sFile.readAsString());
                        }
                        localData[username] = school;
                        await sFile.writeAsString(jsonEncode(localData));
                      } catch (e) {
                        debugPrint("DEBUG LoginScreen: Fallback link sync failed: $e");
                        allSuccessful = false;
                      }
                    }
                  }
                }
                
                // ONLY delete cache if all sync inserts were successful!
                if (allSuccessful) {
                  await file.delete();
                  debugPrint("DEBUG LoginScreen: Deleted parent signup cache because all synced successfully!");
                } else {
                  debugPrint("DEBUG LoginScreen: Kept parent signup cache because some synced failed.");
                }
              }
            } catch (syncErr) {
              debugPrint("DEBUG LoginScreen: Error in sync parent cache: $syncErr");
            }

            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const ParentSchoolsScreen()),
            );
          }
        }
      } else {
        // --- 2. DYNAMIC LEVEL & EXISTENCE CHECK (THE "PROFESSIONAL" FIX) ---
        final Map<String, String> childActualLevels = {};

        if (_selectedRole == 'Parent') {
          for (var childEntry in _registerChildren) {
            final username = childEntry['username']!.trim().toLowerCase();
            final studentData = await Supabase.instance.client
                .from('profiles')
                .select('level')
                .eq('username', username)
                .maybeSingle();

            if (studentData == null) {
              _showError(
                "Can't find the school. Student '$username' does not exist.",
              );
              setState(() => _isLoading = false);
              return;
            }
            childActualLevels[username] = studentData['level'] ?? 'Standard 7';
          }
        }

        if (!_isLogin && _selectedRole == 'Student') {
          // Verify admission number in student_records
          bool admissionValid = false;
          String dbStudentName = '';
          String dbStudentLevel = '';

          try {
            final record = await Supabase.instance.client
                .from('student_records')
                .select()
                .eq('admission_number', effectiveUsername.toUpperCase())
                .maybeSingle();

            if (record != null) {
              final String recordSchool = record['school']?.toString().trim().toLowerCase() ?? '';
              final String selectedSchoolLower = _selectedSchool.trim().toLowerCase();

              // Verify the school matches!
              if (recordSchool == selectedSchoolLower) {
                admissionValid = true;
                dbStudentName = record['full_name']?.toString() ?? fullName;
                dbStudentLevel = record['level']?.toString() ?? _selectedLevel;
              } else {
                _showError("Admission Number exists, but is assigned to a different school.");
                setState(() => _isLoading = false);
                return;
              }
            }
          } catch (e) {
            debugPrint("Admission number validation fetch failed, testing local fallback: $e");
            
            // Check local fallback config list to support offline sandbox testing perfectly!
            try {
              final directory = await getApplicationDocumentsDirectory();
              final file = File('${directory.path}/local_student_records_fallback.json');
              if (await file.exists()) {
                final List localRecords = jsonDecode(await file.readAsString());
                final match = localRecords.firstWhere(
                  (r) => r['admission_number'].toString().toUpperCase() == effectiveUsername.toUpperCase() &&
                         r['school'].toString().trim().toLowerCase() == _selectedSchool.trim().toLowerCase(),
                  orElse: () => null,
                );
                if (match != null) {
                  admissionValid = true;
                  dbStudentName = match['full_name']?.toString() ?? fullName;
                  dbStudentLevel = match['level']?.toString() ?? _selectedLevel;
                }
              }
            } catch (localErr) {
              debugPrint("Local admission list check failed: $localErr");
            }
          }

          if (!admissionValid) {
            _showError("Invalid Admission Number: The entered Admission Number does not exist for the selected school.");
            setState(() => _isLoading = false);
            return;
          }

          // Automatically override registered name and level with official records
          fullName = dbStudentName;
          _selectedLevel = dbStudentLevel;
        }

        if (!_isLogin && _selectedRole == 'Teacher') {
          // Verify employee number in teacher_records
          bool employeeValid = false;
          String dbTeacherName = '';
          List<String> dbTeacherClasses = []; // ← capture assigned classes

          try {
            final record = await Supabase.instance.client
                .from('teacher_records')
                .select()
                .eq('employee_number', effectiveUsername.toUpperCase())
                .maybeSingle();

            if (record != null) {
              final String recordSchool = record['school']?.toString().trim().toLowerCase() ?? '';
              final String selectedSchoolLower = _selectedSchool.trim().toLowerCase();

              // Verify the school matches!
              if (recordSchool == selectedSchoolLower) {
                employeeValid = true;
                dbTeacherName = record['full_name']?.toString() ?? fullName;
                // Pull the classes the admin assigned to this teacher
                final rawClasses = record['classes'];
                if (rawClasses is List) {
                  dbTeacherClasses = rawClasses.map((e) => e.toString()).toList();
                } else if (rawClasses is String && rawClasses.isNotEmpty) {
                  dbTeacherClasses = [rawClasses];
                }
              } else {
                _showError("Employee Number exists, but is assigned to a different school.");
                setState(() => _isLoading = false);
                return;
              }
            }
          } catch (e) {
            debugPrint("Employee number validation fetch failed, testing local fallback: $e");
            
            // Check local fallback config list to support offline sandbox testing perfectly!
            try {
              final directory = await getApplicationDocumentsDirectory();
              final file = File('${directory.path}/local_teacher_records_fallback.json');
              if (await file.exists()) {
                final List localRecords = jsonDecode(await file.readAsString());
                final match = localRecords.firstWhere(
                  (r) => r['employee_number'].toString().toUpperCase() == effectiveUsername.toUpperCase() &&
                         r['school'].toString().trim().toLowerCase() == _selectedSchool.trim().toLowerCase(),
                  orElse: () => null,
                );
                if (match != null) {
                  employeeValid = true;
                  dbTeacherName = match['full_name']?.toString() ?? fullName;
                  final rawClasses = match['classes'];
                  if (rawClasses is List) {
                    dbTeacherClasses = rawClasses.map((e) => e.toString()).toList();
                  } else if (rawClasses is String && rawClasses.isNotEmpty) {
                    dbTeacherClasses = [rawClasses];
                  }
                }
              }
            } catch (localErr) {
              debugPrint("Local teacher list check failed: $localErr");
            }
          }

          if (!employeeValid) {
            _showError("Invalid Employee Number: The entered Employee Number does not exist for the selected school.");
            setState(() => _isLoading = false);
            return;
          }

          // Automatically override registered name with official records
          fullName = dbTeacherName;
          // Store classes into a state variable so the profile builder below can use them
          _teacherClasses = dbTeacherClasses;
        }

        if (!_isLogin && _selectedRole == 'School Admin') {
          // Verify School Admin username and school match in school_admin_records!
          bool adminValid = false;
          String dbAdminName = '';

          try {
            final record = await Supabase.instance.client
                .from('school_admin_records')
                .select()
                .eq('username', effectiveUsername.toUpperCase())
                .maybeSingle();

            if (record != null) {
              final String recordSchool = record['school']?.toString().trim().toLowerCase() ?? '';
              final String selectedSchoolLower = _selectedSchool.trim().toLowerCase();

              // Verify the school matches!
              if (recordSchool == selectedSchoolLower) {
                adminValid = true;
                dbAdminName = record['full_name']?.toString() ?? fullName;
              } else {
                _showError("School Admin Username exists, but is assigned to a different school.");
                setState(() => _isLoading = false);
                return;
              }
            }
          } catch (e) {
            debugPrint("School Admin validation fetch failed, testing local fallback: $e");
            
            // Check local fallback config list to support offline sandbox testing perfectly!
            try {
              final directory = await getApplicationDocumentsDirectory();
              final file = File('${directory.path}/local_school_admin_records_fallback.json');
              if (await file.exists()) {
                final List localRecords = jsonDecode(await file.readAsString());
                final match = localRecords.firstWhere(
                  (r) => r['username'].toString().toUpperCase() == effectiveUsername.toUpperCase() &&
                         r['school'].toString().trim().toLowerCase() == _selectedSchool.trim().toLowerCase(),
                  orElse: () => null,
                );
                if (match != null) {
                  adminValid = true;
                  dbAdminName = match['full_name']?.toString() ?? fullName;
                }
              }
            } catch (localErr) {
              debugPrint("Local school admin list check failed: $localErr");
            }
          }

          if (!adminValid) {
            _showError("Invalid School Admin Username: The entered Username is not authorized for the selected school.");
            setState(() => _isLoading = false);
            return;
          }

          // Automatically override registered name with official records
          fullName = dbAdminName;
        }

        final res = await Supabase.instance.client.auth.signUp(
          email: email,
          password: password,
        );

        if (res.user != null) {
          if (!_isLogin && _selectedRole == 'Student') {
            // Mark as registered in student_records
            try {
              await Supabase.instance.client
                  .from('student_records')
                  .update({'status': 'registered'})
                  .eq('admission_number', effectiveUsername.toUpperCase());
            } catch (e) {
              debugPrint("Failed to update student record status: $e");
            }
          }

          if (!_isLogin && _selectedRole == 'Teacher') {
            // Mark as registered in teacher_records
            try {
              await Supabase.instance.client
                  .from('teacher_records')
                  .update({'status': 'registered'})
                  .eq('employee_number', effectiveUsername.toUpperCase());
            } catch (e) {
              debugPrint("Failed to update teacher record status: $e");
            }
          }

          if (!_isLogin && _selectedRole == 'School Admin') {
            // Mark as registered in school_admin_records
            try {
              await Supabase.instance.client
                  .from('school_admin_records')
                  .update({'status': 'registered'})
                  .eq('username', effectiveUsername.toUpperCase());
            } catch (e) {
              debugPrint("Failed to update school admin record status: $e");
            }
          }

          final String resolvedRole = _selectedRole == 'School Admin'
              ? 'school_admin'
              : _selectedRole.toLowerCase();

          // Resolve teacher's level: use assigned classes (comma-separated) so the
          // dashboard knows the exact class(es) immediately on first login.
          String teacherLevelValue;
          if (_selectedRole == 'Teacher') {
            teacherLevelValue = _teacherClasses.isNotEmpty
                ? _teacherClasses.join(',')
                : 'Teacher'; // fallback — teacher_dashboard will resolve via DB
          } else {
            teacherLevelValue = 'Teacher'; // not reached, but safe
          }

          // 1. Create the Main Profile (with resilient School column support)
          final Map<String, dynamic> profileData = {
            'id': res.user!.id,
            'full_name': fullName,
            'role': resolvedRole,
            'username': effectiveUsername,
            'level': _selectedRole == 'Parent'
                ? 'Parent'
                : (_selectedRole == 'Teacher'
                    ? 'Teacher'
                    ? teacherLevelValue
                    : (_selectedRole == 'Admin' || _selectedRole == 'School Admin' ? 'Admin' : _selectedLevel)),
          };
          if (_selectedRole == 'Student' || _selectedRole == 'Teacher' || _selectedRole == 'School Admin') {
            profileData['school'] = _selectedSchool;
          }

          try {
            await Supabase.instance.client.from('profiles').insert(profileData);
          } catch (dbErr) {
            debugPrint("Insert profile with school failed, retrying without school: $dbErr");
            profileData.remove('school');
            await Supabase.instance.client.from('profiles').insert(profileData);
            
            // Save the school selection locally as a fallback
            try {
              final directory = await getApplicationDocumentsDirectory();
              final sFile = File('${directory.path}/student_schools_config.json');
              Map<String, dynamic> localData = {};
              if (await sFile.exists()) {
                localData = jsonDecode(await sFile.readAsString());
              }
              localData[effectiveUsername] = _selectedSchool;
              await sFile.writeAsString(jsonEncode(localData));
            } catch (e) {
              debugPrint("Failed to write local student school config: $e");
            }
          }

          // 2. Insert linked children directly & cache locally with safe directory
          if (_selectedRole == 'Parent') {
            for (var childEntry in _registerChildren) {
              final String username = childEntry['username']!.trim().toLowerCase();
              final String school = childEntry['school'] ?? 'Westfield Academy';
              final String level = childActualLevels[username] ?? 'Standard 7';
              try {
                await Supabase.instance.client.from('parent_child_links').insert({
                  'parent_id': res.user!.id,
                  'student_username': username,
                  'student_level': level,
                  'school': school,
                });
                debugPrint("DEBUG LoginScreen: Directly linked child '$username' on registration");
              } catch (dbErr) {
                debugPrint("DEBUG LoginScreen: Direct link on registration failed, will rely on sync/fallback: $dbErr");
              }
            }

            try {
              final directory = await AppSettings.getSafeDirectory();
              final file = File('${directory.path}/parent_signup_cache.json');
              final cacheData = {
                'parent_phone': effectiveUsername,
                'children': _registerChildren.map((c) => {
                  'username': c['username']!.trim().toLowerCase(),
                  'school': c['school'] ?? 'Westfield Academy',
                  'level': childActualLevels[c['username']!.trim().toLowerCase()] ?? 'Standard 7',
                }).toList()
              };
              await file.writeAsString(jsonEncode(cacheData));
              debugPrint("DEBUG LoginScreen: Successfully cached parent registration children: $cacheData");
            } catch (e) {
              debugPrint("DEBUG LoginScreen: Error writing parent registration cache: $e");
            }
          }

          _showSuccess("Registration complete! You can now login.");
          setState(() {
            _isLogin = true;
            _passwordController.clear();
          });
        }
      }
    } on AuthException catch (error) {
      _showError(error.message);
    } catch (e) {
      if (_isLogin) {
        await LoginLockout.recordFailure(effectiveUsername);
      }
      _showError(error.message);
    } catch (e) {
      if (_isLogin) {
        await LoginLockout.recordFailure(effectiveUsername);
      }
      debugPrint("Auth Process Error: $e");
      _showError("An error occurred during setup. Please try again.");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FIRST-LOGIN FORCE PASSWORD CHANGE
  // Called when must_change_password == true in the user's profile.
  // The user CANNOT dismiss this dialog — they must set a new password.
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _showForceChangePasswordDialog({
    required String userId,
    required String userRole,
    required Map<String, dynamic> userData,
  }) async {
    final newPassCtrl = TextEditingController();
    final confirmPassCtrl = TextEditingController();
    bool isUpdating = false;
    bool showNew = false;
    bool showConfirm = false;
    String? errorMsg;

    await showDialog(
      context: context,
      barrierDismissible: false, // Cannot dismiss — security requirement
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.lock_reset, color: Colors.orange.shade800, size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      "Password Change Required",
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: const Text(
                  "Your account uses a temporary password. For security, you must create a new personal password before continuing.",
                  style: TextStyle(fontSize: 12, color: Colors.black87, height: 1.4),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 4),
                TextField(
                  controller: newPassCtrl,
                  obscureText: !showNew,
                  decoration: InputDecoration(
                    labelText: "New Password",
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(showNew ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setDlgState(() => showNew = !showNew),
                    ),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    helperText: "Minimum 8 characters",
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: confirmPassCtrl,
                  obscureText: !showConfirm,
                  decoration: InputDecoration(
                    labelText: "Confirm New Password",
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(showConfirm ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setDlgState(() => showConfirm = !showConfirm),
                    ),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                if (errorMsg != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, color: Colors.red.shade700, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            errorMsg!,
                            style: TextStyle(color: Colors.red.shade700, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0D47A1),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: isUpdating
                    ? null
                    : () async {
                        final newPass = newPassCtrl.text.trim();
                        final confirmPass = confirmPassCtrl.text.trim();

                        if (newPass.length < 8) {
                          setDlgState(() => errorMsg = "Password must be at least 8 characters.");
                          return;
                        }
                        if (newPass != confirmPass) {
                          setDlgState(() => errorMsg = "Passwords do not match. Please try again.");
                          return;
                        }

                        setDlgState(() {
                          isUpdating = true;
                          errorMsg = null;
                        });

                        try {
                          // 1. Update Supabase Auth password
                          await Supabase.instance.client.auth.updateUser(
                            UserAttributes(password: newPass),
                          );

                          // 2. Clear the must_change_password flag in profiles
                          await Supabase.instance.client
                              .from('profiles')
                              .update({'must_change_password': false})
                              .eq('id', userId);

                          // 3. Log the password change
                          await AuditLogService.log(
                            action: 'FIRST_LOGIN_PASSWORD_CHANGED',
                            details: 'User "${userData['full_name']}" (Role: ${userRole.toUpperCase()}) changed their temporary password on first login.',
                          );

                          if (ctx.mounted) Navigator.of(ctx).pop();

                          if (!mounted) return;
                          _showSuccess("Password updated successfully! Welcome.");

                          // 4. Navigate to the appropriate dashboard
                          if (!mounted) return;
                          if (userRole == 'student') {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (context) => StudentDashboard(
                                  userName: userData['full_name'] ?? '',
                                  studentLevel: userData['level'] ?? '',
                                ),
                              ),
                            );
                          } else if (userRole == 'teacher') {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    TeacherDashboard(userName: userData['full_name'] ?? ''),
                              ),
                            );
                          } else if (userRole == 'admin' || userRole == 'super_admin' || userRole == 'school_admin') {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (context) => AdminDashboard(
                                  adminName: userData['full_name'] ?? 'Admin',
                                  adminRole: userRole,
                                  adminSchool: userData['school']?.toString(),
                                ),
                              ),
                            );
                          } else {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(builder: (context) => const ParentSchoolsScreen()),
                            );
                          }
                        } catch (e) {
                          setDlgState(() {
                            isUpdating = false;
                            errorMsg = "Failed to update password. Please try again.";
                          });
                          debugPrint("Force password change error: $e");
                        }
                      },
                child: isUpdating
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        "SET NEW PASSWORD",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const Color primaryBlue = Color(0xFF0D47A1);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(30.0),
          child: Column(
            children: [
              const SizedBox(height: 40),
              ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: Image.asset(
                  'assets/images/logo.jpg',
                  height: 100,
                  width: 120,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return const Icon(Icons.calculate, size: 100, color: primaryBlue);
                  },
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                "MathSupport System",
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: primaryBlue,
                ),
              ),
              Text(
                _isLogin ? "Secure Academic Portal" : "Create New Account",
                _isLogin ? "Academic Portal" : "Create New Account",
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 15),
              if (!_isLogin) ...[
                DropdownButtonFormField<String>(
                  initialValue: _selectedRole,
                  value: _selectedRole,
                  decoration: const InputDecoration(
                    labelText: "I am a...",
                    border: OutlineInputBorder(),
                  ),
                  // Only Student, Teacher, and Parent can self-register.
                  // School Admin and Super Admin accounts are created exclusively
                  // by the Super Admin through the Admin Portal → User Directory.
                  items: ['Student', 'Teacher', 'Parent'].map((role) {
                    return DropdownMenuItem(value: role, child: Text(role));
                  }).toList(),
                  onChanged: (val) => setState(() => _selectedRole = val!),
                ),
                const SizedBox(height: 20),
              ],
              if (!_isLogin) ...[
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: "Full Name",
                    prefixIcon: Icon(Icons.badge),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                if (_selectedRole == 'Parent') ...[
                  TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(10),
                    ],
                    decoration: const InputDecoration(
                      labelText: "Phone Number",
                      prefixIcon: Icon(Icons.phone),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
                  const SizedBox(height: 20),
                  const Text(
                    "Link Children & Schools",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87),
                  ),
                  const SizedBox(height: 10),
                  ...List.generate(_registerChildren.length, (index) {
                    final child = _registerChildren[index];
                    return Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        side: BorderSide(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  "Child #${index + 1}",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue.shade900,
                                  ),
                                ),
                                if (_registerChildren.length > 1)
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                                    onPressed: () {
                                      setState(() {
                                        _registerChildren.removeAt(index);
                                      });
                                    },
                                  ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            TextField(
                              onChanged: (val) {
                                child['username'] = val.trim();
                              },
                              decoration: const InputDecoration(
                                labelText: "Child's Student Username",
                                prefixIcon: Icon(Icons.child_care),
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              initialValue: child['school'],
                              value: child['school'],
                              decoration: const InputDecoration(
                                labelText: "Child's School Name",
                                prefixIcon: Icon(Icons.school),
                                border: OutlineInputBorder(),
                              ),
                              items: (_availableSchools.isEmpty
                                      ? [
                                          'Westfield Academy',
                                          'Riverside International',
                                          'Greenwood Academy',
                                          'Hillside International',
                                          'Dar es Salaam Academy'
                                        ]
                                      : _availableSchools.map((s) => s.schoolName).toList())
                                  .map((school) {
                                return DropdownMenuItem(value: school, child: Text(school));
                              }).toList(),
                              onChanged: (val) {
                                setState(() {
                                  child['school'] = val!;
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 4),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.blue.shade900,
                      side: BorderSide(color: Colors.blue.shade900),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.add),
                    label: const Text("Add Another Child"),
                    onPressed: () {
                      setState(() {
                        _registerChildren.add({
                          'username': '',
                          'school': 'Westfield Academy',
                        });
                      });
                    },
                  ),
                  const SizedBox(height: 20),
                ],
                if (_selectedRole == 'Student') ...[
                  DropdownButtonFormField<String>(
                    initialValue: _selectedLevel,
                    value: _selectedLevel,
                    decoration: const InputDecoration(
                      labelText: "Education Level",
                      border: OutlineInputBorder(),
                    ),
                    items: ['Standard 4', 'Standard 7'].map((level) {
                      return DropdownMenuItem(value: level, child: Text(level));
                    }).toList(),
                    onChanged: (val) => setState(() => _selectedLevel = val!),
                  ),
                  const SizedBox(height: 20),
                ],
                if (_selectedRole == 'Student' || _selectedRole == 'Teacher' || _selectedRole == 'School Admin') ...[
                  DropdownButtonFormField<String>(
                    initialValue: _selectedSchool,
                    value: _selectedSchool,
                    decoration: const InputDecoration(
                      labelText: "School Name",
                      prefixIcon: Icon(Icons.school),
                      border: OutlineInputBorder(),
                    ),
                    items: (_availableSchools.isEmpty
                            ? [
                                'Westfield Academy',
                                'Riverside International',
                                'Greenwood Academy',
                                'Hillside International',
                                'Dar es Salaam Academy'
                              ]
                            : _availableSchools.map((s) => s.schoolName).toList())
                        .map((school) {
                      return DropdownMenuItem(value: school, child: Text(school));
                    }).toList(),
                    onChanged: (val) {
                      setState(() {
                        _selectedSchool = val!;
                      });
                    },
                  ),
                  const SizedBox(height: 20),
                ],
              ],
              if (!(_selectedRole == 'Parent' && !_isLogin))
                TextField(
                  controller: _emailController,
                  decoration: InputDecoration(
                    labelText: _isLogin ? "Username" : "Choose Username",
                    prefixIcon: const Icon(Icons.person),
                    border: const OutlineInputBorder(),
                  ),
                ),
              if (!(_selectedRole == 'Parent' && !_isLogin))
                const SizedBox(height: 20),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: "Password",
                  prefixIcon: Icon(Icons.lock),
                  border: OutlineInputBorder(),
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: "Password",
                  prefixIcon: const Icon(Icons.lock),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword ? Icons.visibility_off : Icons.visibility,
                      color: Colors.grey,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                  ),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _handleAuth,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryBlue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(
                          _isLogin ? "LOGIN SECURELY" : "REGISTER NOW",
                          _isLogin ? "LOGIN " : "REGISTER NOW",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 20),
              TextButton(
                onPressed: () {
                  setState(() {
                    _isLogin = !_isLogin;
                  });
                },
                child: Text(
                  _isLogin
                      ? "New here? Create Account"
                      : "Already have an account? Login here",
                  style: const TextStyle(
                    color: primaryBlue,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LoginLockout {
  static final Map<String, int> _tempAttempts = {};
  static final Map<String, DateTime> _tempLockoutUntil = {};

  static Future<File> _getFile() async {
    final directory = await AppSettings.getSafeDirectory();
    return File('${directory.path}/login_lockout_records.json');
  }

  static Future<Map<String, dynamic>> _readRecords() async {
    try {
      final file = await _getFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.isNotEmpty) {
          return jsonDecode(content) as Map<String, dynamic>;
        }
      }
    } catch (e) {
      debugPrint("Error reading lockout records: $e");
    }
    return {};
  }

  static Future<void> _writeRecords(Map<String, dynamic> records) async {
    try {
      final file = await _getFile();
      await file.writeAsString(jsonEncode(records));
    } catch (e) {
      debugPrint("Error writing lockout records: $e");
    }
  }

  /// Checks if the username is locked out.
  /// Returns null if not locked out, or the remaining Duration if locked out.
  static Future<Duration?> getRemainingLockout(String username) async {
    final cleanUsername = username.trim().toLowerCase();
    
    // In-memory check first (fast)
    final memoryLock = _tempLockoutUntil[cleanUsername];
    if (memoryLock != null) {
      final now = DateTime.now();
      if (memoryLock.isAfter(now)) {
        return memoryLock.difference(now);
      } else {
        // Expired
        _tempLockoutUntil.remove(cleanUsername);
        _tempAttempts[cleanUsername] = 0;
      }
    }

    // Persistent check
    final records = await _readRecords();
    if (records.containsKey(cleanUsername)) {
      final data = records[cleanUsername] as Map<String, dynamic>;
      final lockoutStr = data['lockout_until'];
      if (lockoutStr != null) {
        final lockoutTime = DateTime.parse(lockoutStr);
        final now = DateTime.now();
        if (lockoutTime.isAfter(now)) {
          // Update memory cache
          _tempLockoutUntil[cleanUsername] = lockoutTime;
          return lockoutTime.difference(now);
        } else {
          // Expired
          records.remove(cleanUsername);
          await _writeRecords(records);
        }
      }
    }
    return null;
  }

  /// Registers a failed attempt. Lockout if attempts >= 5.
  static Future<void> recordFailure(String username) async {
    final cleanUsername = username.trim().toLowerCase();
    
    // 1. Update in-memory
    final currentAttempts = (_tempAttempts[cleanUsername] ?? 0) + 1;
    _tempAttempts[cleanUsername] = currentAttempts;

    // 2. Update persistent storage
    final records = await _readRecords();
    final userRecord = (records[cleanUsername] as Map<String, dynamic>?) ?? {
      'failed_attempts': 0,
      'lockout_until': null,
    };

    final persistentAttempts = (userRecord['failed_attempts'] as int? ?? 0) + 1;
    userRecord['failed_attempts'] = persistentAttempts;

    final maxAttempts = 5;
    if (persistentAttempts >= maxAttempts || currentAttempts >= maxAttempts) {
      final lockoutUntil = DateTime.now().add(const Duration(minutes: 15));
      userRecord['lockout_until'] = lockoutUntil.toIso8601String();
      
      _tempLockoutUntil[cleanUsername] = lockoutUntil;
      debugPrint("User $cleanUsername locked out until $lockoutUntil");
    }

    records[cleanUsername] = userRecord;
    await _writeRecords(records);
  }

  /// Clears failed attempts. Called upon successful login.
  static Future<void> recordSuccess(String username) async {
    final cleanUsername = username.trim().toLowerCase();
    _tempAttempts.remove(cleanUsername);
    _tempLockoutUntil.remove(cleanUsername);

    final records = await _readRecords();
    if (records.containsKey(cleanUsername)) {
      records.remove(cleanUsername);
      await _writeRecords(records);
    }
  }
}
