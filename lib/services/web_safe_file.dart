import 'dart:convert';
import 'dart:io' as io;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class File {
  final String path;
  File(this.path);

  static SharedPreferences? _prefs;

  static Future<void> _init() async {
    if (_prefs == null) {
      try {
        _prefs = await SharedPreferences.getInstance();
      } catch (e) {
        debugPrint("Error initializing SharedPreferences in File: $e");
      }
    }
  }

  Future<bool> exists() async {
    if (kIsWeb) {
      await _init();
      return _prefs?.containsKey(path) ?? false;
    }
    return io.File(path).exists();
  }

  Future<String> readAsString() async {
    if (kIsWeb) {
      await _init();
      return _prefs?.getString(path) ?? '';
    }
    return io.File(path).readAsString();
  }

  Future<File> writeAsString(String content) async {
    if (kIsWeb) {
      await _init();
      await _prefs?.setString(path, content);
      return this;
    }
    await io.File(path).writeAsString(content);
    return this;
  }

  Future<Uint8List> readAsBytes() async {
    if (kIsWeb) {
      await _init();
      final base64String = _prefs?.getString('$path:bytes') ?? '';
      if (base64String.isEmpty) {
        return Uint8List(0);
      }
      return base64.decode(base64String);
    }
    return io.File(path).readAsBytes();
  }

  Future<File> writeAsBytes(List<int> bytes) async {
    if (kIsWeb) {
      await _init();
      final base64String = base64.encode(bytes);
      await _prefs?.setString('$path:bytes', base64String);
      return this;
    }
    await io.File(path).writeAsBytes(bytes);
    return this;
  }

  Future<void> delete() async {
    if (kIsWeb) {
      await _init();
      await _prefs?.remove(path);
      await _prefs?.remove('$path:bytes');
      return;
    }
    await io.File(path).delete();
  }
}

class Directory {
  final String path;
  Directory(this.path);

  static Directory get systemTemp {
    if (kIsWeb) {
      return Directory('/web_temp');
    }
    return Directory(io.Directory.systemTemp.path);
  }
}
