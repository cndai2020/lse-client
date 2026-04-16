import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/theme/lse_theme.dart';
import '../../../shared/services/transfer_service.dart';
import '../../../shared/services/archive_service.dart';
import '../../../shared/services/notification_service.dart';
import '../../../shared/models/transfer_models.dart';
import '../../../shared/widgets/lse_widgets.dart';

/// 接收端页面
class ReceivePage extends StatefulWidget {
  const ReceivePage({super.key});

  @override
  State<ReceivePage> createState() => _ReceivePageState();
}

class _ReceivePageState extends State<ReceivePage> {
  final TransferService _transferService = TransferService.instance;
  final ArchiveService _archiveService = ArchiveService();
  final NotificationService _notificationService = NotificationService.instance;

  final List<CodeDigitController> _codeControllers = List.generate(
    6,
    (_) => CodeDigitController(),
  );
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  bool _connecting = false;
  String? _errorMsg;
  TransferTask? _task;
  StreamSubscription<TransferTask>? _taskSub;

  @override
  void initState() {
    super.initState();
    _taskSub = _transferService.taskStream.listen((task) {
      setState(() => _task = task);
      if (task.status == TransferStatus.completed) {
        _onTransferComplete(task);
      } else if (task.status == TransferStatus.error) {
        setState(() => _errorMsg = '传输发生错误，请重试');
      }
    });
  }

  @override
  void dispose() {
    _taskSub?.cancel();
    for (final fn in _focusNodes) {
      fn.dispose();
    }
    super.dispose();
  }

  String get _code =>
      _codeControllers.map((c) => c.text).join();

  bool get _codeComplete =>
      _codeControllers.every((c) => c.text.isNotEmpty);

  Future<void> _onCodeDigitChanged(int index, String value) async {
    if (value.isNotEmpty) {
      _focusNodes[index].unfocus();
      if (index < 5) {
        _focusNodes[index + 1].requestFocus();
      } else {
        // 第6位输入完成，触发连接
        if (_codeComplete) {
          _connect();
        }
      }
    }
    setState(() {});
  }

  Future<void> _connect() async {
    if (!_codeComplete) return;

    setState(() {
      _connecting = true;
      _errorMsg = null;
    });

    // 尝试在局域网内发现服务端
    // 简化：需要用户输入发送方 IP，或通过广播发现
    // 此处需要用户提供 IP 地址
    // 先做本地连接测试
    _errorMsg = '请输入发送方 IP 地址';

    // 简化流程：假设已在同一网段，用固定 IP 测试
    // 实际使用时需要用户输入 IP
    final senderIp = await _showIpInputDialog();
    if (senderIp == null) {
      setState(() => _connecting = false);
      return;
    }

    await _doConnect(senderIp);
  }

  Future<String?> _showIpInputDialog() async {
    final controller = TextEditingController();

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('输入发送方 IP'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '请告知发送方查看其 IP 地址，并在此输入',
              style: TextStyle(color: LseTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                hintText: '例如：192.168.1.100',
                labelText: '发送方 IP',
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('连接'),
          ),
        ],
      ),
    );
  }

  Future<void> _doConnect(String senderIp) async {
    try {
      // 1. 发起连接验证
      final initResp = await _transferService.connectToSender(
        senderIp: senderIp,
        code: _code,
      );

      if (!initResp.accepted) {
        setState(() {
          _connecting = false;
          _errorMsg = '口令无效或已被使用';
        });
        return;
      }

      // 2. 获取文件信息
      final info = await _transferService.getTransferInfo(
        senderIp: senderIp,
        transferId: initResp.transferId,
      );

      // 3. 选择保存位置（简化：默认保存到下载目录）
      final savePath = await _chooseSavePath(info.fileName);
      if (savePath == null) {
        setState(() => _connecting = false);
        return;
      }

      // 4. 开始接收
      setState(() => _connecting = false);

      await _transferService.receiveFile(
        senderIp: senderIp,
        transferId: initResp.transferId,
        fileName: info.fileName,
        fileSize: info.fileSize,
        fileHash: info.fileHash,
        senderHostname: info.senderHostname,
        senderIpAddr: info.senderIp,
        senderMac: info.senderMac,
        savePath: savePath,
      );
    } catch (e) {
      setState(() {
        _connecting = false;
        _errorMsg = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  Future<String?> _chooseSavePath(String fileName) async {
    // 简化：默认保存到下载目录
    try {
      final downloadDir = await _getDownloadDir();
      final path = '$downloadDir/$fileName';
      return path;
    } catch (_) {
      return null;
    }
  }

  Future<String> _getDownloadDir() async {
    if (Platform.isMacOS || Platform.isLinux) {
      final home = Platform.environment['HOME'] ?? '';
      return '$home/Downloads';
    } else if (Platform.isWindows) {
      final userProfile = Platform.environment['USERPROFILE'] ?? '';
      return '$userProfile/Downloads';
    }
    final docs = await getDownloadsDirectory();
    return docs?.path ?? '/tmp';
  }

  Future<void> _onTransferComplete(TransferTask task) async {
    // 自动解压（如果是 zip）
    String finalPath = task.localPath;
    if (task.fileName.toLowerCase().endsWith('.zip')) {
      try {
        final destDir = (await _getDownloadDir());
        final extractedDir = await _archiveService.extractZip(
          task.localPath,
          destDir,
        );
        finalPath = extractedDir;
        // 删除临时 zip
        await File(task.localPath).delete();
      } catch (e) {
        // 解压失败，保留 zip
      }
    }

    // 弹窗通知
    await _notificationService.showTransferComplete(
      fileName: task.fileName,
      fileSize: task.fileSize.toString(),
      senderHostname: task.senderHostname ?? '',
      senderIp: task.senderIp ?? '',
      duration: '${task.elapsed.inSeconds}秒',
      savedPath: finalPath,
    );

    // 显示完成对话框
    if (mounted) {
      _showCompleteDialog(task, finalPath);
    }
  }

  void _showCompleteDialog(TransferTask task, String savedPath) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: LseTheme.success),
            SizedBox(width: 8),
            Text('传输完成'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _infoRow('文件', task.fileName),
            _infoRow('大小', formatFileSize(task.fileSize)),
            _infoRow('发送自', '${task.senderHostname} (${task.senderIp})'),
            _infoRow('用时', '${task.elapsed.inSeconds}秒'),
            _infoRow('保存至', savedPath),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('确定'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _openInFinder(savedPath);
            },
            icon: const Icon(Icons.folder_open, size: 18),
            label: const Text('打开所在文件夹'),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label：',
              style: const TextStyle(color: LseTheme.textSecondary, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  void _openInFinder(String path) {
    // 跨平台打开文件夹
    final dir = File(path).parent.path;
    if (Platform.isMacOS) {
      Process.run('open', [dir]);
    } else if (Platform.isWindows) {
      Process.run('explorer', [dir]);
    } else {
      Process.run('xdg-open', [dir]);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('接收文件')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildCodeInputCard(),
            if (_task != null) ...[
              const SizedBox(height: 16),
              _buildProgressCard(),
            ],
            if (_errorMsg != null) ...[
              const SizedBox(height: 16),
              _buildErrorCard(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCodeInputCard() {
    return LseCard(
      child: Column(
        children: [
          const Icon(Icons.lock_outline, color: LseTheme.primary, size: 40),
          const SizedBox(height: 12),
          const Text(
            '输入发送方提供的口令',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: LseTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '6 位数字，一次性使用',
            style: TextStyle(color: LseTheme.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(6, (i) => _buildDigitBox(i)),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (_connecting || !_codeComplete) ? null : _connect,
              child: _connecting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('确认接收'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDigitBox(int index) {
    return Container(
      width: 48,
      height: 56,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: TextField(
        controller: _codeControllers[index],
        focusNode: _focusNodes[index],
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        maxLength: 1,
        style: const TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          fontFamily: 'monospace',
        ),
        decoration: InputDecoration(
          counterText: '',
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          filled: true,
          fillColor: LseTheme.background,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: LseTheme.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: LseTheme.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: LseTheme.primary, width: 2),
          ),
        ),
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onChanged: (v) => _onCodeDigitChanged(index, v),
      ),
    );
  }

  Widget _buildProgressCard() {
    final task = _task!;

    StatusBadge badge;
    switch (task.status) {
      case TransferStatus.transferring:
        badge = StatusBadge.transferring();
      case TransferStatus.completed:
        badge = StatusBadge.completed();
      case TransferStatus.error:
        badge = StatusBadge.error();
      default:
        badge = StatusBadge.waiting();
    }

    return LseCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('接收进度', style: TextStyle(fontWeight: FontWeight.w600)),
              badge,
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '文件：${task.fileName}',
            style: const TextStyle(fontSize: 13, color: LseTheme.textSecondary),
          ),
          const SizedBox(height: 8),
          LseProgressBar(
            progress: task.progress,
            label: '${task.progressPercent}% (${formatFileSize(task.bytesTransferred)} / ${formatFileSize(task.fileSize)})',
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: LseTheme.error.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: LseTheme.error.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: LseTheme.error),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _errorMsg!,
              style: const TextStyle(color: LseTheme.error, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class CodeDigitController extends TextEditingController {
  CodeDigitController({super.text});
}
