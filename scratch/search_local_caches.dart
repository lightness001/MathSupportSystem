import 'dart:io';

void main() async {
  print("=== Advanced Scanning for parent cache files ===");

  final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '';
  print("Home directory: $home");

  if (home.isEmpty) {
    print("Home is empty.");
    return;
  }

  // Scan AppData/Local and Documents with filters to avoid scanning millions of files
  final searchDirs = [
    Directory("$home/AppData/Local"),
    Directory("$home/Documents"),
    Directory("$home/AppData/Roaming"),
  ];

  for (final dir in searchDirs) {
    if (await dir.exists()) {
      print("Scanning in ${dir.path}...");
      try {
        // List subdirectories first, filter for app-related names
        final List<FileSystemEntity> subEntities = await dir.list(recursive: false).toList();
        for (final entity in subEntities) {
          if (entity is Directory) {
            final pathName = entity.path.toLowerCase();
            // Look for directories that might contain our app name or package
            if (pathName.contains("homework") || 
                pathName.contains("support") || 
                pathName.contains("math") || 
                pathName.contains("example") ||
                pathName.contains("flutter") ||
                pathName.contains("packages")) {
              
              print("  Deep scanning directory: ${entity.path}");
              try {
                await for (final subFile in entity.list(recursive: true, followLinks: false)) {
                  if (subFile is File) {
                    final name = subFile.path.split(Platform.pathSeparator).last;
                    if (name.contains("parent_signup_cache") || 
                        name.contains("parent_schools_config") || 
                        name.contains("cache.json") ||
                        name.contains("config.json")) {
                      print("  [FOUND FILE] Path: ${subFile.path}");
                      try {
                        final content = await subFile.readAsString();
                        print("  [CONTENT]: $content");
                      } catch (e) {
                        print("  Error reading: $e");
                      }
                    }
                  }
                }
              } catch (_) {}
            }
          } else if (entity is File) {
            final name = entity.path.split(Platform.pathSeparator).last;
            if (name.contains("parent_signup_cache") || name.contains("parent_schools_config")) {
              print("  [FOUND FILE] Path: ${entity.path}");
              final content = await entity.readAsString();
              print("  [CONTENT]: $content");
            }
          }
        }
      } catch (e) {
        print("Error listing ${dir.path}: $e");
      }
    }
  }

  print("=== Advanced Scan completed ===");
}
