import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../domain/custom_source.dart';
import 'custom_source_provider.dart';

class CustomSourceScreen extends ConsumerWidget {
  const CustomSourceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sources = ref.watch(customSourcesProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D0D),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          '自定义源',
          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_open, color: Colors.white),
            tooltip: '导入本地脚本',
            onPressed: () => _pickAndImportFile(context, ref),
          ),
          IconButton(
            icon: const Icon(Icons.cloud_download, color: Colors.white),
            tooltip: '通过链接导入',
            onPressed: () => _showUrlImportDialog(context, ref),
          ),
          IconButton(
            icon: const Icon(Icons.add, color: Colors.white),
            tooltip: '手动添加',
            onPressed: () => _showAddDialog(context, ref),
          ),
          IconButton(
            icon: const Icon(Icons.link, color: Colors.white),
            tooltip: '粘贴脚本',
            onPressed: () => _showImportDialog(context, ref),
          ),
        ],
      ),
      body: sources.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.code, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('暂无自定义源', style: TextStyle(color: Colors.grey, fontSize: 16)),
                  SizedBox(height: 8),
                  Text('点击右上角 + 添加自定义源', style: TextStyle(color: Colors.grey, fontSize: 14)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: sources.length,
              itemBuilder: (context, index) {
                final source = sources[index];
                return _buildSourceItem(context, ref, source);
              },
            ),
    );
  }

  Widget _buildSourceItem(BuildContext context, WidgetRef ref, CustomSource source) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      source.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'v${source.version} · ${source.author}',
                      style: TextStyle(color: Colors.grey[500], fontSize: 12),
                    ),
                  ],
                ),
              ),
              Switch(
                value: source.isEnabled,
                activeColor: const Color(0xFF6366F1),
                onChanged: (value) {
                  ref.read(customSourcesProvider.notifier).toggleSource(source.id);
                },
              ),
            ],
          ),
          if (source.description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              source.description,
              style: TextStyle(color: Colors.grey[400], fontSize: 14),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                icon: const Icon(Icons.terminal, size: 16),
                label: const Text('日志'),
                onPressed: () => _showLogDialog(context, ref, source),
              ),
              TextButton.icon(
                icon: const Icon(Icons.edit, size: 16),
                label: const Text('编辑'),
                onPressed: () => _showEditDialog(context, ref, source),
              ),
              TextButton.icon(
                icon: const Icon(Icons.share, size: 16),
                label: const Text('导出'),
                onPressed: () => _showExportDialog(context, ref, source),
              ),
              TextButton.icon(
                icon: const Icon(Icons.delete, size: 16, color: Colors.red),
                label: const Text('删除', style: TextStyle(color: Colors.red)),
                onPressed: () => _showDeleteDialog(context, ref, source),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pickAndImportFile(BuildContext context, WidgetRef ref) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['js'],
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final content = await file.readAsString();
        
        final success = await ref.read(customSourcesProvider.notifier).importLxMusicScript(content);
        
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(success ? '导入脚本成功' : '导入失败，脚本格式错误'),
              backgroundColor: success ? Colors.green : Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('读取文件失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showAddDialog(BuildContext context, WidgetRef ref) {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    final authorController = TextEditingController();
    final scriptController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('添加自定义源', style: TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildTextField(nameController, '源名称'),
              const SizedBox(height: 8),
              _buildTextField(descController, '描述'),
              const SizedBox(height: 8),
              _buildTextField(authorController, '作者'),
              const SizedBox(height: 8),
              _buildTextField(scriptController, '脚本', maxLines: 10),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              if (nameController.text.isNotEmpty && scriptController.text.isNotEmpty) {
                final source = CustomSource(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  name: nameController.text,
                  description: descController.text,
                  version: '1.0.0',
                  author: authorController.text,
                  script: scriptController.text,
                  createdAt: DateTime.now(),
                  updatedAt: DateTime.now(),
                );
                ref.read(customSourcesProvider.notifier).addSource(source);
                Navigator.pop(context);
              }
            },
            child: const Text('添加', style: TextStyle(color: Color(0xFF6366F1))),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(BuildContext context, WidgetRef ref, CustomSource source) {
    final nameController = TextEditingController(text: source.name);
    final descController = TextEditingController(text: source.description);
    final authorController = TextEditingController(text: source.author);
    final scriptController = TextEditingController(text: source.script);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('编辑自定义源', style: TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildTextField(nameController, '源名称'),
              const SizedBox(height: 8),
              _buildTextField(descController, '描述'),
              const SizedBox(height: 8),
              _buildTextField(authorController, '作者'),
              const SizedBox(height: 8),
              _buildTextField(scriptController, '脚本', maxLines: 10),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              final updated = source.copyWith(
                name: nameController.text,
                description: descController.text,
                author: authorController.text,
                script: scriptController.text,
              );
              ref.read(customSourcesProvider.notifier).updateSource(updated);
              Navigator.pop(context);
            },
            child: const Text('保存', style: TextStyle(color: Color(0xFF6366F1))),
          ),
        ],
      ),
    );
  }

  void _showUrlImportDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: const Text('通过链接导入', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '请输入脚本文件的直接下载链接',
                style: TextStyle(color: Colors.grey[400], fontSize: 12),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                style: const TextStyle(color: Colors.white),
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'https://...',
                  hintStyle: TextStyle(color: Colors.grey[600]),
                  filled: true,
                  fillColor: const Color(0xFF2A2A2A),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
              if (isLoading) ...[
                const SizedBox(height: 16),
                const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF6366F1)),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: isLoading ? null : () => Navigator.pop(context),
              child: const Text('取消', style: TextStyle(color: Colors.grey)),
            ),
            TextButton(
              onPressed: isLoading
                  ? null
                  : () async {
                      final url = controller.text.trim();
                      if (url.isEmpty || !url.startsWith('http')) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('请输入有效的 HTTP 链接')),
                        );
                        return;
                      }

                      setState(() => isLoading = true);
                      final success = await ref.read(customSourcesProvider.notifier).importSourceFromUrl(url);
                      setState(() => isLoading = false);

                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(success ? '导入成功' : '导入失败，请检查链接或脚本格式'),
                            backgroundColor: success ? Colors.green : Colors.red,
                          ),
                        );
                      }
                    },
              child: const Text('导入', style: TextStyle(color: Color(0xFF6366F1))),
            ),
          ],
        ),
      ),
    );
  }

  void _showImportDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('导入自定义源', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '支持 LX Music 格式脚本',
              style: TextStyle(color: Colors.grey[400], fontSize: 12),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white, fontFamily: 'monospace'),
              maxLines: 10,
              decoration: InputDecoration(
                hintText: '粘贴 LX Music 脚本或 JSON 配置...',
                hintStyle: TextStyle(color: Colors.grey[600]),
                filled: true,
                fillColor: const Color(0xFF2A2A2A),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () async {
              final text = controller.text.trim();
              bool success = false;
              
              // 检查是否是 LX Music 格式脚本
              if (text.contains('globalThis.lx') || text.contains('EVENT_NAMES')) {
                success = await ref.read(customSourcesProvider.notifier).importLxMusicScript(text);
              } else {
                success = await ref.read(customSourcesProvider.notifier).importSource(text);
              }
              
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(success ? '导入成功' : '导入失败，请检查脚本格式'),
                  backgroundColor: success ? Colors.green : Colors.red,
                ),
              );
            },
            child: const Text('导入', style: TextStyle(color: Color(0xFF6366F1))),
          ),
        ],
      ),
    );
  }

  void _showExportDialog(BuildContext context, WidgetRef ref, CustomSource source) {
    final jsonStr = const JsonEncoder.withIndent('  ').convert(source.toJson());

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('导出自定义源', style: TextStyle(color: Colors.white)),
        content: Container(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Text(
              jsonStr,
              style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭', style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(BuildContext context, WidgetRef ref, CustomSource source) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('删除自定义源', style: TextStyle(color: Colors.white)),
        content: Text('确定要删除"${source.name}"吗？', style: TextStyle(color: Colors.grey[400])),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              ref.read(customSourcesProvider.notifier).deleteSource(source.id);
              Navigator.pop(context);
            },
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showLogDialog(BuildContext context, WidgetRef ref, CustomSource source) {
    showDialog(
      context: context,
      builder: (context) => _LogConsole(source: source),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, {int maxLines = 1}) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey[500]),
        filled: true,
        fillColor: const Color(0xFF2A2A2A),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
      ),
    );
  }
}

class _LogConsole extends ConsumerStatefulWidget {
  final CustomSource source;
  const _LogConsole({required this.source});

  @override
  ConsumerState<_LogConsole> createState() => _LogConsoleState();
}

class _LogConsoleState extends ConsumerState<_LogConsole> {
  final List<Map<String, dynamic>> _logs = [];
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _listenLogs();
  }

  void _listenLogs() {
    ref.read(customSourcesProvider.notifier)
        .getEventStream(widget.source.id)
        .listen((event) {
          if (mounted) {
            setState(() {
              _logs.add({
                ...event,
                'timestamp': DateTime.now(),
              });
              // 自动滚动到底部
              Future.delayed(const Duration(milliseconds: 100), () {
                if (_scrollController.hasClients) {
                  _scrollController.animateTo(
                    _scrollController.position.maxScrollExtent,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                  );
                }
              });
            });
          }
        });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A1A),
      title: Row(
        children: [
          const Icon(Icons.terminal, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Text('${widget.source.name} 日志', style: const TextStyle(color: Colors.white, fontSize: 16)),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.delete_sweep, color: Colors.grey, size: 20),
            onPressed: () => setState(() => _logs.clear()),
          ),
        ],
      ),
      content: Container(
        width: double.maxFinite,
        height: 400,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(8),
        ),
        child: _logs.isEmpty
            ? const Center(child: Text('暂无日志', style: TextStyle(color: Colors.grey)))
            : ListView.builder(
                controller: _scrollController,
                itemCount: _logs.length,
                itemBuilder: (context, index) {
                  final log = _logs[index];
                  final type = log['type'];
                  Color color = Colors.white70;
                  if (type == 'error') color = Colors.redAccent;
                  if (type == 'event') color = Colors.blueAccent;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: RichText(
                      text: TextSpan(
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                        children: [
                          TextSpan(
                            text: '[${_formatTime(log['timestamp'])}] ',
                            style: const TextStyle(color: Colors.grey),
                          ),
                          TextSpan(
                            text: '${log['message'] ?? log['event'] ?? ''}\n',
                            style: TextStyle(color: color),
                          ),
                          if (log['data'] != null)
                            TextSpan(
                              text: '  ${json.encode(log['data'])}\n',
                              style: const TextStyle(color: Colors.grey, fontSize: 11),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭', style: TextStyle(color: Colors.grey)),
        ),
      ],
    );
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }
}
