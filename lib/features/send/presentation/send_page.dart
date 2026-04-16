import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import '../../../core/theme/lse_theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../../shared/services/transfer_service.dart';
import '../../../shared/services/archive_service.dart';
import '../../../shared/services/device_info_service.dart';
import '../../../shared/models/transfer_models.dart';
import '../../../shared/widgets/lse_widgets.dart';

/// 发送端页面
class SendPage extends StatefulWidget {
  const SendPage({super.key});

  @override
  State<SendPage> createState() => _SendPageState();
}

class _SendPageState extends State<SendPage> {
  final TransferService _transferService = TransferService.instance;
  final ArchiveService _archiveService = ArchiveService();
  final List<String> _logs = [];
  StreamSubscription<TransferTask>? _taskSub;
  StreamSubscription<String>? _logSub;

  TransferTask? _task;
  String? _selectedFilePath;
  String? _selectedFileName;
  int? _selectedFileSize;
  bool _serverStarted = false;
  bool _preparing = false;
  String? _localIp;

  @override
  void initState() {
    super.initState();
    _initServer();
    _listenToStreams();
  }

  Future<void> _initServer() async {
    await _transferService.startServer();
    final ip = await DeviceInfoService.instance.getDeviceInfo();
    setState(() {
      _serverStarted = true;
      _localIp = ip.ip;
    });
    _appendLog('服务已启动，监听端口 ${AppConstants.defaultHttpsPort}');
    _appendLog('本机 IP: ${ip.ip}');
    _appendLog('请将此 IP 地址告知接收方');
  }

  void _reset() {
    setState(() {
      _selectedFilePath = null;
      _selectedFileName = null;
      _selectedFileSize = null;
      _task = null;
    });
  }

  void _listenToStreams() {
    _taskSub = _transferService.taskStream.listen((task) {
      setState(() => _task = task);
    });
    _logSub = _transferService.logStream.listen((line) {
      setState(() {
        _logs.insert(0, line);
        if (_logs.length > 100) _logs.removeLast();
      });
    });
  }

  @override
  void dispose() {
    _taskSub?.cancel();
    _logSub?.cancel();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result != null && result.files.isNotEmpty) {
      final file = result.files.first;
      setState(() {
        _selectedFilePath = file.path;
        _selectedFileName = file.name;
        _selectedFileSize = file.size;
        _task = null;
      });
    }
  }

  Future<void> _pickFolder() async {
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir != null) {
      final directory = Directory(dir);
      final name = p.basename(dir);
      int size = 0;
      await for (final f in directory.list(recursive: true)) {
        if (f is File) {
          size += await f.length();
        }
      }
      setState(() {
        _selectedFilePath = dir;
        _selectedFileName = name;
        _selectedFileSize = size;
        _task = null;
      });
    }
  }

  Future<void> _startTransfer() async {
    if (_selectedFilePath == null) return;
    setState(() => _preparing = true);

    try {
      // 如果是文件夹，先压缩
      String filePath = _selectedFilePath!;
      String fileName = _selectedFileName!;
      int fileSize = _selectedFileSize!;

      if (FileSystemEntity.isDirectorySync(filePath)) {
        _appendLog('正在压缩文件夹...');
        filePath = await _archiveService.compressFolder(filePath);
        fileName = '$_selectedFileName.zip';
        final file = File(filePath);
        fileSize = await file.length();
        _appendLog('压缩完成: ${formatFileSize(fileSize)}');
      }

      final task = await _transferService.initiateTransfer(
        filePath: filePath,
        fileName: fileName,
        fileSize: fileSize,
      );

      setState(() {
        _task = task;
        _preparing = false;
      });
    } catch (e) {
      _appendLog('❌ 启动失败: $e');
      setState(() => _preparing = false);
    }
  }

  Future<void> _copyCode() async {
    if (_task?.code != null) {
      await Clipboard.setData(ClipboardData(text: _task!.code!));
      _appendLog('口令已复制到剪贴板');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('发送文件'),
            if (_localIp != null)
              Text(
                '本机 IP: $_localIp',
                style: const TextStyle(fontSize: 11, color: LseTheme.textSecondary, fontWeight: FontWeight.normal),
              ),
          ],
        ),
        actions: [
          if (_serverStarted)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Chip(
                label: Text('服务运行中', style: TextStyle(fontSize: 12)),
                backgroundColor: Color(0xFFDCFCE7),
                side: BorderSide.none,
              ),
            ),
          if (_task != null)
            IconButton(
              onPressed: _reset,
              icon: const Icon(Icons.refresh),
              tooltip: '重新发送',
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 文件选择区
            _buildFileSelectArea(),
            const SizedBox(height: 16),

            // 文件信息
            if (_task != null) ...[
              _buildCodeCard(),
              const SizedBox(height: 16),
              _buildProgressCard(),
              const SizedBox(height: 16),
            ],

            // 传输日志
            _buildLogCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildFileSelectArea() {
    return LseCard(
      child: Column(
        children: [
          const Text(
            '选择要发送的文件或文件夹',
            style: TextStyle(
              color: LseTheme.textSecondary,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickFile,
                  icon: const Icon(Icons.insert_drive_file_outlined),
                  label: const Text('选择文件'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickFolder,
                  icon: const Icon(Icons.folder_outlined),
                  label: const Text('选择文件夹'),
                ),
              ),
            ],
          ),
          if (_selectedFileName != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: LseTheme.background,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: LseTheme.border),
              ),
              child: Row(
                children: [
                  Icon(
                    FileSystemEntity.isDirectorySync(_selectedFilePath!) == true
                        ? Icons.folder
                        : Icons.insert_drive_file,
                    color: LseTheme.primary,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _selectedFileName!,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          formatFileSize(_selectedFileSize ?? 0),
                          style: const TextStyle(
                            color: LseTheme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _preparing ? null : _startTransfer,
                child: _preparing
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('开始发送'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCodeCard() {
    final code = _task?.code ?? '------';
    return LseCard(
      child: Column(
        children: [
          const Text(
            '请将此口令告知接收方',
            style: TextStyle(color: LseTheme.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _copyCode,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: LseTheme.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: LseTheme.primary.withOpacity(0.2)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    code,
                    style: const TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 12,
                      color: LseTheme.primary,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Icon(Icons.copy, color: LseTheme.primary, size: 20),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '点击复制',
            style: TextStyle(color: LseTheme.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressCard() {
    final task = _task;
    if (task == null) return const SizedBox.shrink();

    String statusText;
    StatusBadge badge;
    switch (task.status) {
      case TransferStatus.waitingCode:
        statusText = '等待接收方输入口令...';
        badge = StatusBadge.waiting();
        break;
      case TransferStatus.transferring:
        statusText = '传输中...';
        badge = StatusBadge.transferring();
        break;
      case TransferStatus.completed:
        statusText = '传输完成';
        badge = StatusBadge.completed();
        break;
      case TransferStatus.error:
        statusText = '传输失败';
        badge = StatusBadge.error();
        break;
      default:
        statusText = '';
        badge = StatusBadge.waiting();
    }

    return LseCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('传输进度', style: TextStyle(fontWeight: FontWeight.w600)),
              badge,
            ],
          ),
          const SizedBox(height: 12),
          if (task.status != TransferStatus.waitingCode &&
              task.status != TransferStatus.completed)
            LseProgressBar(
              progress: task.progress,
              label: '${task.progressPercent}% (${formatFileSize(task.bytesTransferred)} / ${formatFileSize(task.fileSize)})',
            )
          else
            Text(statusText, style: const TextStyle(color: LseTheme.textSecondary)),
          if (task.status == TransferStatus.completed) ...[
            const SizedBox(height: 8),
            Text(
              '用时: ${task.elapsed.inSeconds}s',
              style: const TextStyle(color: LseTheme.success, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLogCard() {
    return LseCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '传输日志',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              Text(
                '${_logs.length} 条',
                style: const TextStyle(color: LseTheme.textSecondary, fontSize: 12),
              ),
            ],
          ),
          const Divider(height: 16),
          Container(
            height: 200,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(8),
            ),
            child: _logs.isEmpty
                ? const Center(
                    child: Text(
                      '暂无日志',
                      style: TextStyle(color: LseTheme.textSecondary, fontSize: 12),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: _logs.length,
                    itemBuilder: (ctx, i) {
                      final log = _logs[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          log,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: LseTheme.textPrimary,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _appendLog(String msg) {
    setState(() {
      _logs.insert(0, '${DateTime.now().toString().substring(11, 19)} $msg');
      if (_logs.length > 100) _logs.removeLast();
    });
  }
}
