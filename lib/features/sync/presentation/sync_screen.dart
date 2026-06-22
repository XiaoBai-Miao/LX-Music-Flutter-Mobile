import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../settings/presentation/settings_provider.dart';
import '../domain/sync_service.dart';
import 'sync_provider.dart';

class SyncScreen extends ConsumerStatefulWidget {
  const SyncScreen({super.key});

  @override
  ConsumerState<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends ConsumerState<SyncScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoginMode = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final syncStatus = ref.watch(syncStatusProvider);
    final isConnected = syncStatus.whenOrNull<SyncStatus>(
          data: (s) => s,
        ) == SyncStatus.connected ||
        syncStatus.whenOrNull<SyncStatus>(
          data: (s) => s,
        ) == SyncStatus.synced;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('同步', style: TextStyle(color: AppColors.textPrimary)),
        backgroundColor: AppColors.surfaceDark,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildServerConfigCard(),
          const SizedBox(height: 16),
          _buildStatusCard(syncStatus),
          const SizedBox(height: 16),
          if (!isConnected) ...[
            _buildAuthCard(),
            const SizedBox(height: 16),
          ],
          if (isConnected) ...[
            _buildSyncActions(),
            const SizedBox(height: 16),
          ],
          _buildInfoCard(),
        ],
      ),
    );
  }

  Widget _buildServerConfigCard() {
    final serverUrl = ref.watch(syncServerUrlProvider);
    return Card(
      color: AppColors.surfaceDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: const Icon(Icons.dns_outlined, color: AppColors.amber),
        title: const Text('同步服务器', style: TextStyle(color: AppColors.textPrimary)),
        subtitle: Text(serverUrl ?? '未配置', style: TextStyle(color: serverUrl != null ? AppColors.textMuted : Colors.red, fontSize: 13)),
        trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted),
        onTap: () => _showServerUrlDialog(),
      ),
    );
  }

  void _showServerUrlDialog() {
    final controller = TextEditingController(text: ref.read(syncServerUrlProvider) ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('同步服务器地址', style: TextStyle(color: AppColors.textPrimary)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: const InputDecoration(
            hintText: '例如: http://192.168.1.100:23330',
            hintStyle: TextStyle(color: AppColors.textMuted),
            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.amber)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消', style: TextStyle(color: AppColors.textMuted))),
          TextButton(
            onPressed: () {
              ref.read(syncServerUrlProvider.notifier).setUrl(controller.text.trim());
              Navigator.pop(ctx);
            },
            child: const Text('保存', style: TextStyle(color: AppColors.amber)),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard(AsyncValue<SyncStatus> syncStatus) {
    final status = syncStatus.whenOrNull<SyncStatus>(data: (s) => s) ?? SyncStatus.disconnected;
    final statusInfo = _getStatusInfo(status);

    return Card(
      color: AppColors.surfaceDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(statusInfo.$1, color: statusInfo.$2, size: 32),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(statusInfo.$3, style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(statusInfo.$4, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
                ],
              ),
            ),
            if (status == SyncStatus.connected || status == SyncStatus.synced)
              TextButton(
                onPressed: () => ref.read(syncConnectionProvider.notifier).disconnect(),
                child: const Text('断开', style: TextStyle(color: AppColors.amber)),
              ),
          ],
        ),
      ),
    );
  }

  (IconData, Color, String, String) _getStatusInfo(SyncStatus status) {
    switch (status) {
      case SyncStatus.disconnected:
        return (Icons.cloud_off, AppColors.textMuted, '未连接', '请配置同步服务器并登录');
      case SyncStatus.connecting:
        return (Icons.cloud_sync, AppColors.amber, '正在连接...', '正在建立连接');
      case SyncStatus.connected:
        return (Icons.cloud_done, Colors.green, '已连接', '服务器连接正常');
      case SyncStatus.syncing:
        return (Icons.sync, AppColors.amber, '同步中...', '正在同步数据');
      case SyncStatus.synced:
        return (Icons.cloud_done, Colors.green, '已同步', '数据已是最新');
      case SyncStatus.error:
        return (Icons.error_outline, Colors.red, '连接错误', '请检查服务器地址和网络');
    }
  }

  Widget _buildAuthCard() {
    return Card(
      color: AppColors.surfaceDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_isLoginMode ? '登录' : '注册', style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            TextField(
              controller: _usernameController,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                labelText: '用户名',
                labelStyle: TextStyle(color: AppColors.textMuted),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.border)),
                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.amber)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              obscureText: true,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                labelText: '密码',
                labelStyle: TextStyle(color: AppColors.textMuted),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.border)),
                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.amber)),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _onAuth,
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.amber, foregroundColor: Colors.black),
                    child: Text(_isLoginMode ? '登录' : '注册'),
                  ),
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: () => setState(() => _isLoginMode = !_isLoginMode),
                  child: Text(_isLoginMode ? '没有账号？注册' : '已有账号？登录', style: const TextStyle(color: AppColors.amber)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onAuth() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();
    if (username.isEmpty || password.isEmpty) return;

    final notifier = ref.read(syncConnectionProvider.notifier);
    bool ok;

    if (_isLoginMode) {
      ok = await notifier.login(username, password);
    } else {
      ok = await notifier.register(username, password);
      if (ok) {
        ok = await notifier.login(username, password);
      }
    }

    if (ok) {
      await notifier.connect();
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? (_isLoginMode ? '登录成功' : '注册并登录成功') : '操作失败，请检查用户名和密码')),
      );
    }
  }

  Widget _buildSyncActions() {
    return Card(
      color: AppColors.surfaceDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('手动同步', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _onPushSync,
                    icon: const Icon(Icons.upload, size: 18),
                    label: const Text('推送数据'),
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.amber, side: const BorderSide(color: AppColors.amber)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _onPullSync,
                    icon: const Icon(Icons.download, size: 18),
                    label: const Text('拉取数据'),
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.amber, side: const BorderSide(color: AppColors.amber)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onPushSync() async {
    final ok = await ref.read(syncConnectionProvider.notifier).pushSync();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? '推送成功' : '推送失败')),
      );
    }
  }

  Future<void> _onPullSync() async {
    final data = await ref.read(syncConnectionProvider.notifier).pullSync();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(data != null ? '拉取成功' : '拉取失败')),
      );
    }
  }

  Widget _buildInfoCard() {
    return Card(
      color: AppColors.surfaceDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('同步说明', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            _buildInfoRow('连接方式', 'HTTP REST API'),
            _buildInfoRow('同步数据', '歌单、播放历史'),
            _buildInfoRow('冲突策略', '时间戳最新优先'),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 80, child: Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 13))),
          Expanded(child: Text(value, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13))),
        ],
      ),
    );
  }
}
