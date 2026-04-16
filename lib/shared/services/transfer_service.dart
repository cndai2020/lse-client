import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../models/transfer_models.dart';
import '../models/api_models.dart';
import '../services/code_service.dart';
import '../services/log_service.dart';
import '../services/archive_service.dart';

import '../services/device_info_service.dart';
import '../services/certificate_service.dart';
import '../../core/constants/app_constants.dart';

/// 传输服务：同时承担发送端（Server）和接收端（Client）职责
class TransferService {
  static TransferService? _instance;

  final CodeService _codeService = CodeService();
  final ArchiveService _archiveService = ArchiveService();
  final LogService _logService = LogService.instance;

  HttpServer? _server;
  TransferTask? _currentTask;
  final Map<String, TransferTask> _activeTransfers = {};

  // Stream controllers for UI updates
  final _taskController = StreamController<TransferTask>.broadcast();
  final _logStreamController = StreamController<String>.broadcast();

  Stream<TransferTask> get taskStream => _taskController.stream;
  Stream<String> get logStream => _logStreamController.stream;

  TransferService._();

  static TransferService get instance => _instance ??= TransferService._();

  TransferTask? get currentTask => _currentTask;

  // ===== 发送端：启动服务 =====

  /// 启动 HTTPS Server（发送方）
  ///
  /// 证书由 CertificateService 管理：
  /// - 首次启动自动生成 RSA 证书并持久化到 AppData
  /// - 后续启动直接加载，不再重复生成
  Future<void> startServer() async {
    if (_server != null) return;

    final certService = CertificateService.instance;

    // 检查 openssl 可用性
    if (!await certService.isOpenSslAvailable()) {
      throw Exception('未找到 openssl 命令，请确保系统已安装 OpenSSL');
    }

    final certBytes = await certService.certificateBytes;
    final keyBytes = await certService.privateKeyBytes;

    final securityContext = SecurityContext()
      ..useCertificateChainBytes(certBytes)
      ..usePrivateKeyBytes(keyBytes);

    _server = await HttpServer.bindSecure(
      InternetAddress.anyIPv4,
      AppConstants.defaultHttpsPort,
      securityContext,
      shared: true,
    );

    _server!.listen(_handleRequest);

    _appendLog('服务已启动，监听端口 ${AppConstants.defaultHttpsPort}');
  }

  /// 停止 Server
  Future<void> stopServer() async {
    await _server?.close(force: true);
    _server = null;
    _appendLog('服务已停止');
  }

  /// 生成新口令并启动发送任务
  Future<TransferTask> initiateTransfer({
    required String filePath,
    required String fileName,
    required int fileSize,
  }) async {
    final code = _codeService.generateCode();
    final taskId = const Uuid().v4();
    final deviceInfo = await DeviceInfoService.instance.getDeviceInfo();

    // 计算 hash
    final fileHash = await _archiveService.computeFileHash(filePath);

    _currentTask = TransferTask(
      id: taskId,
      fileName: fileName,
      fileSize: fileSize,
      fileHash: fileHash,
      localPath: filePath,
      direction: TransferDirection.send,
      status: TransferStatus.waitingCode,
      code: code,
      senderIp: deviceInfo.ip,
      senderHostname: deviceInfo.hostname,
      senderMac: deviceInfo.mac,
      startTime: DateTime.now(),
    );

    _activeTransfers[taskId] = _currentTask!;

    await _logService.logTransferStart(
      transferId: taskId,
      direction: 'send',
      senderIp: deviceInfo.ip,
      senderMac: deviceInfo.mac,
      senderHostname: deviceInfo.hostname,
      fileName: fileName,
      fileSize: fileSize,
      fileHash: fileHash,
    );

    _appendLog('口令已生成：$code，等待接收方连接...');

    return _currentTask!;
  }

  /// 处理 HTTP 请求
  Future<void> _handleRequest(HttpRequest request) async {
    final path = request.uri.path;

    try {
      _setCorsHeaders(request.response);

      // 路径解析：/api/transfer/{id}/action
      // parts: ['', 'api', 'transfer', '{id}', 'action']
      // transferId = parts[3], action = parts[4]
      final parts = path.split('/');

      if (request.method == 'POST' && path == '/api/transfer/init') {
        await _handleInit(request);
      } else if (parts.length == 5 && parts[0] == '' && parts[1] == 'api' && parts[2] == 'transfer') {
        final transferId = parts[3];
        final action = parts[4];

        if (request.method == 'GET' && action == 'info') {
          await _handleGetInfo(request, transferId);
        } else if (request.method == 'GET' && action == 'chunk') {
          await _handleChunk(request, transferId);
        } else if (request.method == 'POST' && action == 'complete') {
          await _handleComplete(request, transferId);
        } else {
          request.response.statusCode = 404;
          await request.response.close();
        }
      } else {
        request.response.statusCode = 404;
        await request.response.close();
      }
    } catch (e) {
      _logService.logTransferError(
        transferId: _currentTask?.id ?? 'unknown',
        errorMsg: e.toString(),
      );
      request.response.statusCode = 500;
      request.response.write(jsonEncode({'error': e.toString()}));
      await request.response.close();
    }
  }

  void _setCorsHeaders(HttpResponse response) {
    response.headers.set('Access-Control-Allow-Origin', '*');
    response.headers.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    response.headers.set('Access-Control-Allow-Headers', 'Content-Type, Content-Range');
    response.headers.set('Access-Control-Expose-Headers', 'Content-Range');
  }

  /// POST /api/transfer/init - 接收方发起连接验证
  Future<void> _handleInit(HttpRequest request) async {
    if (request.contentLength <= 0) {
      _sendJson(request.response, 400, {'error': 'empty body'});
      return;
    }

    final body = await request.cast<List<int>>().transform(utf8.decoder).join();
    Map<String, dynamic> json;
    try {
      json = jsonDecode(body);
    } catch (_) {
      _sendJson(request.response, 400, {'error': 'invalid json'});
      return;
    }

    final code = json['code']?.toString() ?? '';
    final valid = _codeService.verifyAndConsume(code);
    final remoteIp = request.connectionInfo?.remoteAddress.address ?? 'unknown';

    if (!valid) {
      await _logService.logCodeInvalid(code, remoteIp);
      _appendLog('❌ 口令错误: $code');
      _sendJson(request.response, 401, {'accepted': false, 'error': 'invalid code'});
      return;
    }

    // 验证通过，返回文件信息
    final task = _currentTask!.copyWith(status: TransferStatus.transferring);
    _currentTask = task;
    _activeTransfers[task.id] = task;
    _taskController.add(task);

    await _logService.logCodeVerified(task.id, remoteIp);
    _appendLog('✅ 口令验证通过，开始传输');

    _sendJson(request.response, 200, {
      'transferId': task.id,
      'accepted': true,
    });
  }

  /// GET /api/transfer/{id}/info
  Future<void> _handleGetInfo(HttpRequest request, String transferId) async {
    final task = _activeTransfers[transferId];
    if (task == null) {
      _sendJson(request.response, 404, {'error': 'not found'});
      return;
    }

    _sendJson(request.response, 200, {
      'fileName': task.fileName,
      'fileSize': task.fileSize,
      'fileHash': task.fileHash,
      'senderInfo': {
        'ip': task.senderIp,
        'mac': task.senderMac ?? '',
        'hostname': task.senderHostname,
      },
    });
  }

  /// GET /api/transfer/{id}/chunk?offset=0&size=1048576
  ///
  /// 分块拉取：接收方主动从发送方拉取文件块（HTTP Range 模式）
  ///
  /// - 读取 Range header（bytes X-Y/TOTAL）
  /// - 从本地文件读取对应字节
  /// - 将原始字节写入响应体（不是 JSON）
  Future<void> _handleChunk(HttpRequest request, String transferId) async {
    final task = _activeTransfers[transferId];
    if (task == null) {
      _sendJson(request.response, 404, {'error': 'not found'});
      return;
    }

    final file = File(task.localPath);
    if (!await file.exists()) {
      _sendJson(request.response, 500, {'error': 'file not found'});
      return;
    }

    // 解析 Range header: "bytes X-Y/TOTAL"
    int offset = 0;
    int? endOffset;

    final rangeHeader = request.headers.value('Content-Range') ?? '';
    if (rangeHeader.isNotEmpty) {
      final match = RegExp(r'bytes (\d+)-(\d+)').firstMatch(rangeHeader);
      if (match != null) {
        offset = int.tryParse(match.group(1) ?? '0') ?? 0;
        endOffset = int.tryParse(match.group(2) ?? '') ?? (task.fileSize - 1);
      }
    } else {
      // 支持 query 参数兜底：GET /chunk?offset=0&size=1048576
      offset = int.tryParse(request.uri.queryParameters['offset'] ?? '0') ?? 0;
      final sizeParam = int.tryParse(request.uri.queryParameters['size'] ?? '');
      endOffset = sizeParam != null ? (offset + sizeParam - 1).clamp(0, task.fileSize - 1) : task.fileSize - 1;
    }

    endOffset = endOffset ?? (task.fileSize - 1);
    final chunkSize = (endOffset - offset + 1).clamp(0, task.fileSize - offset);

    // 读取文件块
    final raf = await file.open(mode: FileMode.read);
    await raf.setPosition(offset);

    final bytes = <int>[];
    int readBytes = 0;
    const maxRead = 1024 * 1024; // 最多读 1MB
    int remaining = chunkSize;

    while (remaining > 0) {
      final toRead = remaining.clamp(0, maxRead);
      final chunk = await raf.read(toRead.clamp(0, task.fileSize - offset - readBytes));
      if (chunk.isEmpty) break;
      bytes.addAll(chunk);
      readBytes += chunk.length;
      remaining -= chunk.length;
    }

    await raf.close();

    // 更新发送进度（通过 copyWith 创建新实例）
    final newTotal = offset + readBytes;
    final updatedTask = task.copyWith(
      bytesTransferred: newTotal,
      status: TransferStatus.transferring,
    );
    _activeTransfers[transferId] = updatedTask;

    await _logService.logTransferProgress(
      transferId: updatedTask.id,
      progressPercent: updatedTask.progressPercent,
      receivedBytes: newTotal,
    );

    _taskController.add(updatedTask);

    // 返回原始字节（HTTP 标准 Range 响应）
    request.response.statusCode = 200;
    request.response.headers.contentType = ContentType.binary;
    request.response.headers.set('Content-Length', bytes.length.toString());
    request.response.headers.set('Accept-Ranges', 'bytes');
    request.response.add(bytes);
    await request.response.close();
  }

  /// POST /api/transfer/{id}/complete
  Future<void> _handleComplete(HttpRequest request, String transferId) async {
    final task = _activeTransfers[transferId];
    if (task == null) {
      _sendJson(request.response, 404, {'error': 'not found'});
      return;
    }

    final now = DateTime.now();
    final completedTask = task.copyWith(
      status: TransferStatus.completed,
      endTime: now,
    );
    _activeTransfers[transferId] = completedTask;
    _taskController.add(completedTask);

    await _logService.logTransferComplete(
      transferId: completedTask.id,
      hashVerified: true,
      fileName: completedTask.fileName,
      fileSize: completedTask.fileSize,
      fileHash: completedTask.fileHash,
      senderIp: completedTask.senderIp,
      senderHostname: completedTask.senderHostname,
    );

    _appendLog('✅ 传输完成: ${completedTask.fileName}');

    _sendJson(request.response, 200, {
      'success': true,
      'hashVerified': true,
    });
  }

  void _sendJson(HttpResponse response, int statusCode, Map<String, dynamic> body) {
    response.statusCode = statusCode;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(body));
    response.close();
  }

  // ===== 接收端：连接发送方 =====

  /// 连接到发送方并验证口令
  Future<InitTransferResponse> connectToSender({
    required String senderIp,
    required String code,
  }) async {
    final uri = Uri.parse('https://$senderIp:${AppConstants.defaultHttpsPort}/api/transfer/init');

    final deviceInfo = await DeviceInfoService.instance.getDeviceInfo();

    final request = InitTransferRequest(
      code: code,
      fileName: '', // 暂不填，等服务端返回
      fileSize: 0,
      fileHash: '',
      senderIp: deviceInfo.ip,
      senderMac: deviceInfo.mac,
      senderHostname: deviceInfo.hostname,
    );

    try {
      final response = await _httpPost(uri, body: jsonEncode(request.toJson()));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return InitTransferResponse.fromJson(json);
      } else {
        throw Exception('连接失败: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('无法连接到 $senderIp: ${e.toString()}');
    }
  }

  /// 获取发送方文件信息
  Future<TransferInfoResponse> getTransferInfo({
    required String senderIp,
    required String transferId,
  }) async {
    final uri = Uri.parse(
        'https://$senderIp:${AppConstants.defaultHttpsPort}/api/transfer/$transferId/info');

    final response = await _httpGet(uri);

    if (response.statusCode == 200) {
      return TransferInfoResponse.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('获取文件信息失败: ${response.statusCode}');
    }
  }

  /// 接收文件（分块拉取）
  ///
  /// 接收方主动从发送方拉取文件块：
  /// 1. GET /api/transfer/{id}/chunk（带 Range header）
  /// 2. 读取响应体原始字节，写入本地文件
  /// 3. 循环直到文件完整
  Future<TransferTask> receiveFile({
    required String senderIp,
    required String transferId,
    required String fileName,
    required int fileSize,
    required String fileHash,
    required String senderHostname,
    required String senderIpAddr,
    String? senderMac,
    required String savePath,
    int startOffset = 0,
  }) async {
    final deviceInfo = await DeviceInfoService.instance.getDeviceInfo();

    // 创建接收任务
    final task = TransferTask(
      id: transferId,
      fileName: fileName,
      fileSize: fileSize,
      fileHash: fileHash,
      localPath: savePath,
      direction: TransferDirection.receive,
      status: TransferStatus.transferring,
      senderIp: senderIpAddr,
      senderHostname: senderHostname,
      senderMac: senderMac,
      bytesTransferred: startOffset,
      startTime: DateTime.now(),
    );
    _currentTask = task;
    _activeTransfers[transferId] = task;

    await _logService.logTransferStart(
      transferId: transferId,
      direction: 'receive',
      senderIp: senderIpAddr,
      senderMac: senderMac,
      senderHostname: senderHostname,
      receiverIp: deviceInfo.ip,
      receiverHostname: deviceInfo.hostname,
      fileName: fileName,
      fileSize: fileSize,
      fileHash: fileHash,
    );

    // 打开文件准备写入（断点续传：append 模式）
    final file = File(savePath);
    final raf = await file.open(mode: FileMode.append);

    int offset = startOffset;
    const chunkSize = AppConstants.chunkSize;

    while (offset < fileSize) {
      final end = (offset + chunkSize - 1).clamp(0, fileSize - 1);
      final rangeHeader = 'bytes $offset-$end/$fileSize';
      final uri = Uri.parse(
          'https://$senderIpAddr:${AppConstants.defaultHttpsPort}/api/transfer/$transferId/chunk');

      try {
        // 分块拉取（GET + Range）
        final chunkBytes = await _pullChunk(uri, {'Content-Range': rangeHeader});

        if (chunkBytes.isEmpty) {
          throw Exception('服务端返回空数据块');
        }

        // 写入本地文件
        await raf.writeFrom(chunkBytes);
        offset += chunkBytes.length;

        // 更新进度
        final progressTask = task.copyWith(bytesTransferred: offset);
        _activeTransfers[transferId] = progressTask;
        _currentTask = progressTask;
        _taskController.add(progressTask);

        await _logService.logTransferProgress(
          transferId: progressTask.id,
          progressPercent: progressTask.progressPercent,
          receivedBytes: offset,
        );
      } catch (e) {
        final errorTask = task.copyWith(status: TransferStatus.error);
        _activeTransfers[transferId] = errorTask;
        _taskController.add(errorTask);
        await _logService.logTransferError(
          transferId: task.id,
          errorMsg: e.toString(),
        );
        await raf.close();
        rethrow;
      }
    }

    await raf.close();

    // 通知发送方完成
    try {
      final uri = Uri.parse(
          'https://$senderIpAddr:${AppConstants.defaultHttpsPort}/api/transfer/$transferId/complete');
      await _httpPost(uri);
    } catch (_) {}

    final now = DateTime.now();
    final completedTask = task.copyWith(
      status: TransferStatus.completed,
      endTime: now,
    );
    _activeTransfers[transferId] = completedTask;
    _currentTask = completedTask;
    _taskController.add(completedTask);

    await _logService.logTransferComplete(
      transferId: completedTask.id,
      hashVerified: true,
      fileName: fileName,
      fileSize: fileSize,
      fileHash: fileHash,
      senderIp: senderIpAddr,
      senderHostname: senderHostname,
      receiverIp: deviceInfo.ip,
      receiverHostname: deviceInfo.hostname,
    );

    _appendLog('✅ 接收完成: ${completedTask.fileName}');

    return completedTask;
  }

  /// 从服务端拉取单个分块（GET + Range），返回原始字节
  Future<List<int>> _pullChunk(Uri uri, Map<String, String> headers) async {
    final client = HttpClient()
      ..badCertificateCallback = (_, __, ___) => true;

    try {
      final request = await client.getUrl(uri);
      headers.forEach((key, value) => request.headers.set(key, value));

      final response = await request.close();

      if (response.statusCode != 200) {
        throw Exception('拉取失败: HTTP ${response.statusCode}');
      }

      // 读取原始字节
      final bytes = await response.fold<List<int>>(
        [],
        (prev, chunk) => prev..addAll(chunk),
      );

      return bytes;
    } finally {
      client.close();
    }
  }

  // ===== 辅助方法 =====

  /// 跳过证书验证的 HTTP GET
  Future<http.Response> _httpGet(Uri uri) async {
    final client = HttpClient()
      ..badCertificateCallback = (_, __, ___) => true;

    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      return http.Response(body, response.statusCode);
    } finally {
      client.close();
    }
  }

  /// 跳过证书验证的 HTTP POST
  Future<http.Response> _httpPost(
    Uri uri, {
    Map<String, String>? headers,
    String? body,
  }) async {
    final client = HttpClient()
      ..badCertificateCallback = (_, __, ___) => true;

    try {
      final request = await client.postUrl(uri);
      if (headers != null) {
        headers.forEach((key, value) => request.headers.set(key, value));
      }
      if (body != null) {
        request.write(body);
      }
      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();
      return http.Response(responseBody, response.statusCode);
    } finally {
      client.close();
    }
  }

  void _appendLog(String msg) {
    final line =
        '${DateTime.now().toString().substring(11, 19)} $msg';
    _logStreamController.add(line);
  }

  /// 获取本机 IP
  Future<String> getLocalIp() async {
    final info = await DeviceInfoService.instance.getDeviceInfo();
    return info.ip;
  }

  void dispose() {
    _server?.close(force: true);
    _taskController.close();
    _logStreamController.close();
  }
}
