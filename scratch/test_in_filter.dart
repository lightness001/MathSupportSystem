import 'package:supabase_flutter/supabase_flutter.dart';

void testQuery() {
  final client = Supabase.instance.client;
  client.from('profiles').select('username').inFilter('username', ['tommy']);
}

void main() {
  print("inFilter is syntactically checked.");
}
