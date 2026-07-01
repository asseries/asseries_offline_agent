import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

// Fayl daraxtida ko'rsatilmaydigan og'ir/keraksiz papkalar
const _ignoredDirs = {
  'node_modules', '.git', '.dart_tool', 'build', '.gradle', 'Pods',
  'dist', 'target', 'vendor', '__pycache__', '.venv', 'venv', '.idea',
  '.vscode', 'DerivedData', '.next', '.cache', 'coverage', '.pub-cache',
};

const _maxTreeEntries = 400; // fayl daraxtida ko'rsatiladigan max element

class WorkspaceService {
  static final WorkspaceService _instance = WorkspaceService._();
  WorkspaceService._();
  factory WorkspaceService() => _instance;

  // conversationId -> foydalanuvchi tanlagan haqiqiy papka yo'li
  final Map<String, String> _customPaths = {};

  void setCustomPath(String conversationId, String? path) {
    if (path == null) {
      _customPaths.remove(conversationId);
    } else {
      _customPaths[conversationId] = path;
    }
  }

  String? getCustomPath(String conversationId) => _customPaths[conversationId];

  Future<String> getWorkspacePath(String conversationId) async {
    final custom = _customPaths[conversationId];
    if (custom != null) {
      await Directory(custom).create(recursive: true);
      return custom;
    }
    final base = await _baseDir();
    final dir = Directory(p.join(base, conversationId));
    await dir.create(recursive: true);
    return dir.path;
  }

  Future<String> _baseDir() async {
    final docs = await getApplicationSupportDirectory();
    return p.join(docs.path, 'workspaces');
  }

  String _safePath(String workspacePath, String relPath) {
    final normalized = p.normalize(p.join(workspacePath, relPath));
    if (!normalized.startsWith(workspacePath)) {
      throw Exception('Path escape not allowed: $relPath');
    }
    return normalized;
  }

  void _ensureNotDirectory(String fullPath, String relPath) {
    if (FileSystemEntity.typeSync(fullPath) == FileSystemEntityType.directory) {
      throw Exception(
          "'$relPath' is a directory, not a file. Use list_files to see what's "
          'inside it, then target a specific file path.');
    }
  }

  Future<void> writeFile(
      String conversationId, String relPath, String content) async {
    final wsPath = await getWorkspacePath(conversationId);
    final fullPath = _safePath(wsPath, relPath);
    _ensureNotDirectory(fullPath, relPath);
    final file = File(fullPath);
    await file.parent.create(recursive: true);
    // Atomic write: write to temp then rename
    final tmp = File('$fullPath.tmp');
    await tmp.writeAsString(content, flush: true);
    await tmp.rename(fullPath);
  }

  Future<String> readFile(String conversationId, String relPath) async {
    final wsPath = await getWorkspacePath(conversationId);
    final fullPath = _safePath(wsPath, relPath);
    _ensureNotDirectory(fullPath, relPath);
    return File(fullPath).readAsString();
  }

  Future<void> deleteFile(String conversationId, String relPath) async {
    final wsPath = await getWorkspacePath(conversationId);
    final fullPath = _safePath(wsPath, relPath);
    final entity = FileSystemEntity.typeSync(fullPath);
    if (entity == FileSystemEntityType.directory) {
      await Directory(fullPath).delete(recursive: true);
    } else if (entity == FileSystemEntityType.file) {
      await File(fullPath).delete();
    }
  }

  bool _isIgnored(String relPath) {
    final parts = relPath.split('/');
    return parts.any((p) => _ignoredDirs.contains(p));
  }

  Future<List<String>> listFiles(String conversationId) async {
    final wsPath = await getWorkspacePath(conversationId);
    final dir = Directory(wsPath);
    if (!dir.existsSync()) return [];
    final files = <String>[];
    await for (final entity in dir.list(recursive: true)) {
      final rel = entity.path.replaceFirst('$wsPath/', '');
      if (_isIgnored(rel)) continue;
      if (entity is File) {
        files.add(rel);
        if (files.length >= _maxTreeEntries) break;
      }
    }
    files.sort();
    return files;
  }

  Future<List<FileEntry>> getFileTree(String conversationId) async {
    final wsPath = await getWorkspacePath(conversationId);
    final dir = Directory(wsPath);
    if (!dir.existsSync()) return [];
    final entries = <FileEntry>[];

    Future<void> walk(Directory current, int depth) async {
      if (entries.length >= _maxTreeEntries) return;
      List<FileSystemEntity> children;
      try {
        children = await current.list().toList();
      } catch (_) {
        return;
      }
      // Papkalarni avval, keyin fayllarni alfabetik tartiblaymiz
      children.sort((a, b) {
        final aIsDir = FileSystemEntity.isDirectorySync(a.path);
        final bIsDir = FileSystemEntity.isDirectorySync(b.path);
        if (aIsDir && !bIsDir) return -1;
        if (!aIsDir && bIsDir) return 1;
        return a.path.compareTo(b.path);
      });

      for (final entity in children) {
        if (entries.length >= _maxTreeEntries) return;
        final rel = entity.path.replaceFirst('$wsPath/', '');
        final name = rel.split('/').last;
        if (name.startsWith('.') && name != '.env') continue; // dotfiles yashirin
        if (_ignoredDirs.contains(name)) continue;

        if (entity is Directory) {
          entries.add(FileEntry(path: rel, isDir: true));
          await walk(entity, depth + 1);
        } else if (entity is File) {
          int size = 0;
          try {
            size = await entity.length();
          } catch (_) {}
          entries.add(FileEntry(path: rel, isDir: false, size: size));
        }
      }
    }

    await walk(dir, 0);
    return entries;
  }

  Future<void> openInFinder(String conversationId) async {
    final wsPath = await getWorkspacePath(conversationId);
    await Process.run('open', [wsPath]);
  }
}

class FileEntry {
  final String path;
  final bool isDir;
  final int size;

  FileEntry({required this.path, required this.isDir, this.size = 0});

  String get name => path.split('/').last;
  int get depth => '/'.allMatches(path).length;
}
