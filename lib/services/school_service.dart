import 'dart:convert';
import 'dart:io' hide File, Directory;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'audit_log_service.dart';
import 'web_safe_file.dart';

class School {
  final String id;
  final String schoolName;
  final String region;
  final String district;
  final String code;
  final String status; // 'active', 'inactive', 'archived'

  School({
    required this.id,
    required this.schoolName,
    required this.region,
    required this.district,
    required this.code,
    this.status = 'active',
  });

  factory School.fromMap(Map<String, dynamic> map) {
    return School(
      id: map['id']?.toString() ?? '',
      schoolName: map['school_name']?.toString() ?? '',
      region: map['region']?.toString() ?? '',
      district: map['district']?.toString() ?? '',
      code: map['code']?.toString() ?? '',
      status: map['status']?.toString() ?? 'active',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'school_name': schoolName,
      'region': region,
      'district': district,
      'code': code,
      'status': status,
    };
  }
}

class SchoolService {
  static final SupabaseClient _supabase = Supabase.instance.client;

  // Standard premium schools list used as a safe database fallback
  static final List<School> defaultSchools = [
    School(id: '1', schoolName: 'Westfield Academy', region: 'Dar es Salaam', district: 'Kinondoni', code: 'WES001', status: 'active'),
    School(id: '2', schoolName: 'Riverside International', region: 'Dar es Salaam', district: 'Ilala', code: 'RIV002', status: 'active'),
    School(id: '3', schoolName: 'Greenwood Academy', region: 'Arusha', district: 'Arusha City', code: 'GRE003', status: 'active'),
    School(id: '4', schoolName: 'Hillside International', region: 'Mwanza', district: 'Nyamagana', code: 'HIL004', status: 'active'),
    School(id: '5', schoolName: 'Dar es Salaam Academy', region: 'Dar es Salaam', district: 'Temeke', code: 'DAR005', status: 'active'),
  ];

  /// Fetches schools from Supabase database table 'schools'.
  /// Merges with local registered schools and standard defaults, prioritizing local edits first.
  /// If [includeInactiveAndArchived] is false, filters out inactive/archived schools.
  static Future<List<School>> getSchools({bool includeInactiveAndArchived = false}) async {
    List<School> dbSchools = [];
    bool useFallback = false;
    try {
      final List<dynamic> response = await _supabase
          .from('schools')
          .select()
          .order('school_name', ascending: true);
      dbSchools = response.map((item) => School.fromMap(item)).toList();
    } catch (e) {
      debugPrint("[SchoolService] Supabase schools fetch failed/skipped, using fallback: $e");
      useFallback = true;
    }

    final List<School> localSchools = await _loadLocalSchools();
    final Map<String, School> schoolMap = {};

    // 1. Load from DB or default fallbacks first
    if (useFallback) {
      for (var school in defaultSchools) {
        schoolMap[school.id] = school;
      }
    } else {
      for (var school in dbSchools) {
        schoolMap[school.id] = school;
      }
    }

    // 2. Overwrite / Merge with local schools (which contain updates/deletes/status changes)
    for (var school in localSchools) {
      schoolMap[school.id] = school;
    }

    List<School> merged = schoolMap.values.toList();

    // Sort by school name for a clean, premium visual layout
    merged.sort((a, b) => a.schoolName.toLowerCase().compareTo(b.schoolName.toLowerCase()));

    // Filter by status if requested
    if (!includeInactiveAndArchived) {
      return merged.where((s) => s.status == 'active').toList();
    }
    
    // Admin view: include everything except archived (which are soft-deleted)
    return merged.where((s) => s.status != 'archived').toList();
  }

  /// Adds a new school to the database table 'schools'.
  /// Validates school code uniqueness before insertion.
  static Future<bool> addSchool({
    required String name,
    required String region,
    required String district,
    required String code,
  }) async {
    final String cleanCode = code.trim().toUpperCase();
    final String cleanName = name.trim();
    final String cleanRegion = region.trim();
    final String cleanDistrict = district.trim();

    // 1. Validate school code uniqueness
    final List<School> existingSchools = await getSchools(includeInactiveAndArchived: true);
    if (existingSchools.any((s) => s.code.toUpperCase() == cleanCode)) {
      throw Exception("A school with code '$cleanCode' is already registered in the system.");
    }

    bool dbSuccess = false;
    try {
      await _supabase.from('schools').insert({
        'school_name': cleanName,
        'region': cleanRegion,
        'district': cleanDistrict,
        'code': cleanCode,
        'status': 'active',
      });
      dbSuccess = true;
      
      // Log creation audit trail
      await AuditLogService.log(
        action: 'CREATE_SCHOOL',
        details: 'Registered school "$cleanName" with code "$cleanCode" in Supabase.',
      );
    } catch (e) {
      debugPrint("[SchoolService] Supabase insert failed, saving to local: $e");
      
      final localSchool = School(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        schoolName: cleanName,
        region: cleanRegion,
        district: cleanDistrict,
        code: cleanCode,
        status: 'active',
      );
      await _saveLocalSchool(localSchool);

      // Log creation audit trail
      await AuditLogService.log(
        action: 'CREATE_SCHOOL_LOCAL',
        details: 'Registered school "$cleanName" with code "$cleanCode" in Local Database (Offline).',
      );
    }
    return dbSuccess;
  }

  /// Updates metadata and status of an existing school.
  static Future<bool> updateSchool({
    required String id,
    required String name,
    required String region,
    required String district,
    required String code,
    required String status,
  }) async {
    final String cleanCode = code.trim().toUpperCase();
    final String cleanName = name.trim();
    final String cleanRegion = region.trim();
    final String cleanDistrict = district.trim();

    // Validate code uniqueness against other schools (different ID)
    final List<School> existingSchools = await getSchools(includeInactiveAndArchived: true);
    if (existingSchools.any((s) => s.id != id && s.code.toUpperCase() == cleanCode)) {
      throw Exception("Another school with code '$cleanCode' is already registered.");
    }

    bool dbSuccess = false;
    try {
      final queryId = int.tryParse(id) ?? id;
      await _supabase.from('schools').update({
        'school_name': cleanName,
        'region': cleanRegion,
        'district': cleanDistrict,
        'code': cleanCode,
        'status': status,
      }).eq('id', queryId);
      dbSuccess = true;

      await AuditLogService.log(
        action: 'UPDATE_SCHOOL',
        details: 'Updated school ID "$id" to "$cleanName" ($cleanCode, status: $status).',
      );
    } catch (e) {
      debugPrint("[SchoolService] Supabase update failed, updating locally: $e");
      await _updateLocalSchoolFields(id, cleanName, cleanRegion, cleanDistrict, cleanCode, status);
      
      await AuditLogService.log(
        action: 'UPDATE_SCHOOL_LOCAL',
        details: 'Updated school ID "$id" to "$cleanName" ($cleanCode, status: $status) locally (Offline).',
      );
    }
    return dbSuccess;
  }

  /// Soft deletes a school by setting its status to 'archived'.
  static Future<bool> softDeleteSchool(String id, String schoolName) async {
    bool dbSuccess = false;
    try {
      final queryId = int.tryParse(id) ?? id;
      await _supabase.from('schools').update({'status': 'archived'}).eq('id', queryId);
      dbSuccess = true;

      await AuditLogService.log(
        action: 'DELETE_SCHOOL',
        details: 'Soft deleted school "$schoolName" (ID: $id).',
      );
    } catch (e) {
      debugPrint("[SchoolService] Supabase delete failed, marking archived locally: $e");
      await _updateLocalSchoolStatus(id, 'archived');
      
      await AuditLogService.log(
        action: 'DELETE_SCHOOL_LOCAL',
        details: 'Soft deleted school "$schoolName" (ID: $id) locally (Offline).',
      );
    }
    return dbSuccess;
  }

  /// Sets school status to 'inactive' (deactivation).
  static Future<bool> deactivateSchool(String id, String schoolName) async {
    bool dbSuccess = false;
    try {
      final queryId = int.tryParse(id) ?? id;
      await _supabase.from('schools').update({'status': 'inactive'}).eq('id', queryId);
      dbSuccess = true;

      await AuditLogService.log(
        action: 'DEACTIVATE_SCHOOL',
        details: 'Deactivated school "$schoolName" (ID: $id).',
      );
    } catch (e) {
      debugPrint("[SchoolService] Supabase deactivation failed, saving locally: $e");
      await _updateLocalSchoolStatus(id, 'inactive');
      
      await AuditLogService.log(
        action: 'DEACTIVATE_SCHOOL_LOCAL',
        details: 'Deactivated school "$schoolName" (ID: $id) locally (Offline).',
      );
    }
    return dbSuccess;
  }

  /// Sets school status to 'active' (reactivation).
  static Future<bool> reactivateSchool(String id, String schoolName) async {
    bool dbSuccess = false;
    try {
      final queryId = int.tryParse(id) ?? id;
      await _supabase.from('schools').update({'status': 'active'}).eq('id', queryId);
      dbSuccess = true;

      await AuditLogService.log(
        action: 'REACTIVATE_SCHOOL',
        details: 'Reactivated school "$schoolName" (ID: $id).',
      );
    } catch (e) {
      debugPrint("[SchoolService] Supabase reactivation failed, saving locally: $e");
      await _updateLocalSchoolStatus(id, 'active');
      
      await AuditLogService.log(
        action: 'REACTIVATE_SCHOOL_LOCAL',
        details: 'Reactivated school "$schoolName" (ID: $id) locally (Offline).',
      );
    }
    return dbSuccess;
  }

  // --- Local Fallback Storage Helpers ---

  static Future<List<School>> _loadLocalSchools() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/local_registered_schools.json');
      if (await file.exists()) {
        final List<dynamic> list = jsonDecode(await file.readAsString());
        return list.map((item) => School.fromMap(item)).toList();
      }
    } catch (e) {
      debugPrint("[SchoolService] Error reading local schools: $e");
    }
    return [];
  }

  static Future<void> _saveLocalSchool(School school) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/local_registered_schools.json');
      List<dynamic> list = [];
      if (await file.exists()) {
        list = jsonDecode(await file.readAsString());
      }
      list.add(school.toMap());
      await file.writeAsString(jsonEncode(list));
    } catch (e) {
      debugPrint("[SchoolService] Error saving local school: $e");
    }
  }

  static Future<void> _updateLocalSchoolFields(
    String id,
    String name,
    String region,
    String district,
    String code,
    String status,
  ) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/local_registered_schools.json');
      List<dynamic> list = [];
      if (await file.exists()) {
        list = jsonDecode(await file.readAsString());
      }
      
      bool found = false;
      final updatedList = list.map((item) {
        if (item['id']?.toString() == id) {
          found = true;
          return {
            'id': id,
            'school_name': name,
            'region': region,
            'district': district,
            'code': code,
            'status': status,
          };
        }
        return item;
      }).toList();
      
      if (!found) {
        // If it wasn't in the local storage yet, add it as a new local school with the updated fields!
        updatedList.add({
          'id': id,
          'school_name': name,
          'region': region,
          'district': district,
          'code': code,
          'status': status,
        });
      }
      
      await file.writeAsString(jsonEncode(updatedList));
    } catch (e) {
      debugPrint("[SchoolService] Error updating local school fields: $e");
    }
  }

  static Future<void> _updateLocalSchoolStatus(String id, String status) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/local_registered_schools.json');
      List<dynamic> list = [];
      if (await file.exists()) {
        list = jsonDecode(await file.readAsString());
      }
      
      bool found = false;
      final updatedList = list.map((item) {
        if (item['id']?.toString() == id) {
          found = true;
          item['status'] = status;
        }
        return item;
      }).toList();
      
      if (!found) {
        // If it wasn't a local school, load all existing schools, find the matching one, and save it locally with the new status!
        final allSchools = await getSchools(includeInactiveAndArchived: true);
        final matching = allSchools.firstWhere(
          (s) => s.id == id, 
          orElse: () => School(id: id, schoolName: '', region: '', district: '', code: '')
        );
        if (matching.schoolName.isNotEmpty) {
          updatedList.add({
            'id': id,
            'school_name': matching.schoolName,
            'region': matching.region,
            'district': matching.district,
            'code': matching.code,
            'status': status,
          });
        }
      }
      
      await file.writeAsString(jsonEncode(updatedList));
    } catch (e) {
      debugPrint("[SchoolService] Error updating local school status: $e");
    }
  }
}
