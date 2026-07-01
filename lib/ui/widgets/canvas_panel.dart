import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/chat_provider.dart';
import '../../services/workspace_service.dart';
import '../app_theme.dart';

enum CanvasTab { files, code }

class CanvasPanel extends ConsumerStatefulWidget {
  const CanvasPanel({super.key});

  @override
  ConsumerState<CanvasPanel> createState() => _CanvasPanelState();
}

class _CanvasPanelState extends ConsumerState<CanvasPanel> {
  CanvasTab _tab = CanvasTab.files;
  String? _selectedFile;
  String? _fileContent;
  List<FileEntry> _fileTree = [];
  bool _loading = false;
  double _width = 360;
  bool _dragging = false;
  final Set<String> _expandedDirs = {}; // ochiq papkalar (accordion holati)

  void _toggleDir(String path) {
    setState(() {
      if (_expandedDirs.contains(path)) {
        _expandedDirs.remove(path);
      } else {
        _expandedDirs.add(path);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final convoId = ref.read(chatProvider).activeId;
    if (convoId == null) {
      setState(() => _loading = false);
      return;
    }
    final ws = WorkspaceService();
    _fileTree = await ws.getFileTree(convoId);
    setState(() => _loading = false);
  }

  Future<void> _pickFolder() async {
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Loyiha papkasini tanlang',
    );
    if (path == null) return;
    ref.read(chatProvider.notifier).setCustomWorkspacePath(path);
    await _refresh();
  }

  Future<void> _clearFolder() async {
    ref.read(chatProvider.notifier).setCustomWorkspacePath(null);
    await _refresh();
  }

  Future<void> _loadFile(String path) async {
    final convoId = ref.read(chatProvider).activeId;
    if (convoId == null) return;
    setState(() {
      _selectedFile = path;
      _tab = CanvasTab.code;
      _fileContent = null;
    });
    try {
      final content = await WorkspaceService().readFile(convoId, path);
      setState(() => _fileContent = content);
    } catch (e) {
      setState(() => _fileContent = 'Error reading file: $e');
    }
  }

  String _detectLanguage(String path) {
    final ext = path.split('.').last.toLowerCase();
    return switch (ext) {
      'dart' => 'dart',
      'js' || 'jsx' => 'javascript',
      'ts' || 'tsx' => 'typescript',
      'html' => 'html',
      'css' => 'css',
      'py' => 'python',
      'json' => 'json',
      'yaml' || 'yml' => 'yaml',
      'md' => 'markdown',
      'sh' || 'bash' => 'bash',
      'sql' => 'sql',
      _ => 'plaintext',
    };
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(chatProvider, (prev, next) {
      if (prev?.activeId != next.activeId) {
        _selectedFile = null;
        _fileContent = null;
        _fileTree = [];
        _refresh();
      }
    });

    return SizedBox(
      width: _width + 4,
      child: Stack(
      children: [
        // Drag handle
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: 4,
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeColumn,
            child: GestureDetector(
              onHorizontalDragStart: (_) => setState(() => _dragging = true),
              onHorizontalDragEnd: (_) => setState(() => _dragging = false),
              onHorizontalDragUpdate: (d) {
                setState(() {
                  _width = (_width - d.delta.dx).clamp(240.0, 700.0);
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                color: _dragging ? AppColors.accent : AppColors.border,
              ),
            ),
          ),
        ),

        // Panel content
        Positioned(
          left: 4,
          top: 0,
          right: 0,
          bottom: 0,
          child: SizedBox(
            width: _width,
            child: Container(
              color: AppColors.surface,
              child: Column(
                children: [
                  // Header
                  Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: AppColors.border)),
                    ),
                    child: Row(
                      children: [
                        // Tabs
                        _Tab(
                          label: 'Files',
                          icon: Icons.folder_outlined,
                          selected: _tab == CanvasTab.files,
                          onTap: () => setState(() => _tab = CanvasTab.files),
                        ),
                        const SizedBox(width: 4),
                        _Tab(
                          label: 'Code',
                          icon: Icons.code,
                          selected: _tab == CanvasTab.code,
                          onTap: () => setState(() => _tab = CanvasTab.code),
                        ),
                        const SizedBox(width: 8),
                        // Tanlangan papka nomi (markazda, qisqartiriladi)
                        Expanded(
                          child: Consumer(builder: (ctx, ref, _) {
                            final convo = ref.watch(chatProvider).active;
                            final path = convo?.customWorkspacePath;
                            if (path == null) return const SizedBox.shrink();
                            final name = path.split('/').where((s) => s.isNotEmpty).last;
                            return Tooltip(
                              message: path,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.accent.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.folder, size: 11, color: AppColors.accent),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        name,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: AppColors.accent,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                        ),
                        // Papka tanlash
                        Consumer(builder: (ctx, ref, _) {
                          final convo = ref.watch(chatProvider).active;
                          final hasCustom = convo?.customWorkspacePath != null;
                          return Tooltip(
                            message: hasCustom
                                ? 'Loyiha papkasi: ${convo!.customWorkspacePath}\n(o\'ng tugma: olib tashlash)'
                                : 'Loyiha papkasini tanlash',
                            child: InkWell(
                              onTap: _pickFolder,
                              onSecondaryTap: hasCustom ? _clearFolder : null,
                              borderRadius: BorderRadius.circular(6),
                              child: Padding(
                                padding: const EdgeInsets.all(6),
                                child: Icon(
                                  Icons.drive_folder_upload_outlined,
                                  size: 14,
                                  color: hasCustom ? AppColors.accent : AppColors.textDim,
                                ),
                              ),
                            ),
                          );
                        }),
                        // Refresh
                        Tooltip(
                          message: 'Refresh',
                          child: InkWell(
                            onTap: _refresh,
                            borderRadius: BorderRadius.circular(6),
                            child: const Padding(
                              padding: EdgeInsets.all(6),
                              child: Icon(Icons.refresh, size: 14),
                            ),
                          ),
                        ),
                        // Open folder
                        Tooltip(
                          message: 'Open in Finder',
                          child: InkWell(
                            onTap: () {
                              final id = ref.read(chatProvider).activeId;
                              if (id != null) WorkspaceService().openInFinder(id);
                            },
                            borderRadius: BorderRadius.circular(6),
                            child: const Padding(
                              padding: EdgeInsets.all(6),
                              child: Icon(Icons.open_in_new, size: 14),
                            ),
                          ),
                        ),
                        // Close canvas
                        Tooltip(
                          message: 'Close',
                          child: InkWell(
                            onTap: () =>
                                ref.read(chatProvider.notifier).toggleCanvas(),
                            borderRadius: BorderRadius.circular(6),
                            child: const Padding(
                              padding: EdgeInsets.all(6),
                              child: Icon(Icons.close, size: 14),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Content
                  Expanded(
                    child: _loading
                        ? const Center(
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              valueColor: AlwaysStoppedAnimation(AppColors.accent),
                            ),
                          )
                        : _tab == CanvasTab.files
                            ? _FileTree(
                                entries: _fileTree,
                                selected: _selectedFile,
                                onSelect: _loadFile,
                                onPickFolder: _pickFolder,
                                expandedDirs: _expandedDirs,
                                onToggleDir: _toggleDir,
                              )
                            : _CodeViewer(
                                path: _selectedFile,
                                content: _fileContent,
                                language: _selectedFile != null
                                    ? _detectLanguage(_selectedFile!)
                                    : 'plaintext',
                              ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _Tab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.surfaceHigh : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Icon(icon, size: 13,
                color: selected ? AppColors.text : AppColors.textDim),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: selected ? AppColors.text : AppColors.textDim,
                fontWeight: selected ? FontWeight.w500 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FileTree extends StatelessWidget {
  final List<FileEntry> entries;
  final String? selected;
  final void Function(String) onSelect;
  final VoidCallback? onPickFolder;
  final Set<String> expandedDirs;
  final void Function(String) onToggleDir;

  const _FileTree({
    required this.entries,
    this.selected,
    required this.onSelect,
    this.onPickFolder,
    required this.expandedDirs,
    required this.onToggleDir,
  });

  // entry'ning barcha ota-papkalari ochiq (expanded) bo'lsagina ko'rinadi
  bool _isVisible(String path) {
    final parts = path.split('/');
    if (parts.length <= 1) return true; // ildiz darajasi har doim ko'rinadi
    String acc = parts[0];
    if (!expandedDirs.contains(acc)) return false;
    for (int i = 1; i < parts.length - 1; i++) {
      acc = '$acc/${parts[i]}';
      if (!expandedDirs.contains(acc)) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.folder_open_outlined, size: 32, color: AppColors.textDim),
            const SizedBox(height: 8),
            const Text('Hali fayl yo\'q', style: TextStyle(color: AppColors.textDim, fontSize: 13)),
            if (onPickFolder != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onPickFolder,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.accent,
                  side: const BorderSide(color: AppColors.accent),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                ),
                icon: const Icon(Icons.drive_folder_upload_outlined, size: 14),
                label: const Text('Loyiha papkasini tanlash', style: TextStyle(fontSize: 12)),
              ),
            ],
          ],
        ),
      );
    }

    final visible = entries.where((e) => _isVisible(e.path)).toList();

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: visible.length,
      itemBuilder: (ctx, i) {
        final entry = visible[i];
        final isSelected = entry.path == selected;
        final isExpanded = entry.isDir && expandedDirs.contains(entry.path);

        return InkWell(
          onTap: entry.isDir ? () => onToggleDir(entry.path) : () => onSelect(entry.path),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: EdgeInsets.only(
              left: 8.0 + entry.depth * 16.0,
              right: 8,
              top: 5,
              bottom: 5,
            ),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.accent.withValues(alpha: 0.15) : null,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                if (entry.isDir)
                  Icon(
                    isExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                    size: 14,
                    color: AppColors.textDim,
                  )
                else
                  const SizedBox(width: 14),
                const SizedBox(width: 2),
                Icon(
                  entry.isDir
                      ? (isExpanded ? Icons.folder_open : Icons.folder_outlined)
                      : _fileIcon(entry.name),
                  size: 14,
                  color: entry.isDir
                      ? AppColors.yellow
                      : isSelected
                          ? AppColors.accent
                          : AppColors.textDim,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    entry.name,
                    style: TextStyle(
                      fontSize: 13,
                      color: isSelected ? AppColors.accent : AppColors.text,
                    ),
                  ),
                ),
                if (!entry.isDir)
                  Text(
                    _formatSize(entry.size),
                    style: const TextStyle(fontSize: 11, color: AppColors.textDim),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  IconData _fileIcon(String name) {
    final ext = name.split('.').last.toLowerCase();
    return switch (ext) {
      'html' => Icons.language,
      'css' => Icons.style_outlined,
      'js' || 'ts' || 'jsx' || 'tsx' => Icons.javascript,
      'dart' => Icons.code,
      'py' => Icons.code,
      'json' => Icons.data_object,
      'md' => Icons.description_outlined,
      'png' || 'jpg' || 'gif' || 'svg' => Icons.image_outlined,
      _ => Icons.insert_drive_file_outlined,
    };
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)}MB';
  }
}

class _CodeViewer extends StatelessWidget {
  final String? path;
  final String? content;
  final String language;

  const _CodeViewer({this.path, this.content, required this.language});

  @override
  Widget build(BuildContext context) {
    if (path == null) {
      return const Center(
        child: Text(
          'Select a file to view',
          style: TextStyle(color: AppColors.textDim, fontSize: 13),
        ),
      );
    }

    if (content == null) {
      return const Center(
        child: CircularProgressIndicator(
          strokeWidth: 1.5,
          valueColor: AlwaysStoppedAnimation(AppColors.accent),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // File path header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              const Icon(Icons.insert_drive_file_outlined, size: 12, color: AppColors.textDim),
              const SizedBox(width: 6),
              Text(
                path!,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textDim,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),

        // Code content
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: HighlightView(
              content!,
              language: language,
              theme: atomOneDarkTheme,
              textStyle: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12.5,
                height: 1.6,
              ),
              padding: EdgeInsets.zero,
            ),
          ),
        ),
      ],
    );
  }
}
