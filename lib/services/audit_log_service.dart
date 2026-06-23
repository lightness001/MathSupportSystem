import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'web_safe_file.dart';

class AuditLogService {
  static final SupabaseClient _supabase = Supabase.instance.client;

  /// Logs an administrative action dynamically.
  /// Automatically captures current actor ID, name, action, details, and timestamp.
  static Future<void> log({
    required String action,
    required String details,
  }) async {
    final user = _supabase.auth.currentUser;
    final String actorId = user?.id ?? 'system';
    final String timestamp = DateTime.now().toIso8601String();

    String actorName = 'System';
    if (user != null) {
      try {
        final profile = await _supabase.from('profiles').select('full_name').eq('id', user.id).maybeSingle();
        actorName = profile?['full_name']?.toString() ?? user.email ?? 'Authenticated Admin';
      } catch (_) {
        actorName = user.email ?? 'Authenticated Admin';
      }
    }

    try {
      await _supabase.from('audit_logs').insert({
        'actor_id': actorId,
        'actor_name': actorName,
        'action': action,
        'details': details,
        'timestamp': timestamp,
      });
      debugPrint("[AuditLog] Logged to Supabase: $action | $details");
    } catch (e) {
      debugPrint("[AuditLog] Supabase log failed, saving locally: $e");
      try {
        final directory = await getApplicationDocumentsDirectory();
        final file = File('${directory.path}/local_audit_logs.json');
        List<dynamic> logs = [];
        if (await file.exists()) {
          logs = jsonDecode(await file.readAsString());
        }
        logs.add({
          'actor_id': actorId,
          'actor_name': actorName,
          'action': action,
          'details': details,
          'timestamp': timestamp,
        });
        await file.writeAsString(jsonEncode(logs));
      } catch (err) {
        debugPrint("[AuditLog] Error saving local audit log: $err");
      }
    }
  }

  /// Retrieves audit logs from Supabase or local fallback.
  static Future<List<Map<String, dynamic>>> getAuditLogs() async {
    try {
      final List<dynamic> response = await _supabase
          .from('audit_logs')
          .select()
          .order('timestamp', ascending: false)
          .limit(100);
      return response.map((item) => Map<String, dynamic>.from(item)).toList();
    } catch (e) {
      debugPrint("[AuditLog] Supabase fetch failed, loading local logs: $e");
      try {
        final directory = await getApplicationDocumentsDirectory();
        final file = File('${directory.path}/local_audit_logs.json');
        if (await file.exists()) {
          final List<dynamic> logs = jsonDecode(await file.readAsString());
          // Sort by timestamp descending
          final List<Map<String, dynamic>> list = logs.map((item) => Map<String, dynamic>.from(item)).toList();
          list.sort((a, b) => b['timestamp'].toString().compareTo(a['timestamp'].toString()));
          return list;
        }
      } catch (err) {
        debugPrint("[AuditLog] Error loading local audit logs: $err");
      }
      return [];
    }
  }
}
