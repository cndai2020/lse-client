import 'dart:convert';
import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/log_entry.dart';
import '../../core/constants/app_constants.dart';

/// 日志服务：结构化 JSON Lines 日志
class LogService {
  static LogService? _instance;
  late String _logDir;
  bool _initialized = false;

  LogService._();

  static LogService get instance => _instance ??= LogService._();

  Future<void> init() async {
    if (_initialized) return;

    final homeDir = await _getHomeDir();
    _logDir = p.join(homeDir, AppConstants.logDir);

    final dir = Directory(_logDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    // 清理过期日志
    await _cleanOldLogs();

    _initialized = true;
  }

  /// 写日志
  Future<void> log(LogEntry entry) async {
    await init();

    final dateStr = DateFormat('yyyy-MM-dd').format(entry.timestamp);
    final logFile = File(p.join(_logDir, 'lse-$dateStr.log'));

    final line = const JsonEncoder.withIndent(null).convert(entry.toJson());
    await logFile.writeAsString('$line\n', mode: FileMode.append);
  }

  /// 记录传输开始
  Future<void> logTransferStart({
    required String transferId,
    required String direction,
    String? senderIp,
    String? senderMac,
    String? senderHostname,
    String? receiverIp,
    String? receiverMac,
    String? receiverHostname,
    String? fileName,
    int? fileSize,
    String? fileHash,
  }) async {
    await log(LogEntry(
      timestamp: DateTime.now(),
      event: LogEvent.transferStart,
      transferId: transferId,
      direction: direction,
      senderIp: senderIp,
      senderMac: senderMac,
      senderHostname: senderHostname,
      receiverIp: receiverIp,
      receiverMac: receiverMac,
      receiverHostname: receiverHostname,
      fileName: fileName,
      fileSize: fileSize,
      fileHash: fileHash,
    ));
  }

  /// 记录传输进度（按百分比间隔）
  Future<void> logTransferProgress({
    required String transferId,
    required int progressPercent,
    required int receivedBytes,
  }) async {
    // 只记录整5%节点
    if (progressPercent % AppConstants.progressLogInterval == 0) {
      await log(LogEntry(
        timestamp: DateTime.now(),
        event: LogEvent.transferProgress,
        transferId: transferId,
        progressPercent: progressPercent,
        receivedBytes: receivedBytes,
      ));
    }
  }

  /// 记录传输完成
  Future<void> logTransferComplete({
    required String transferId,
    required bool hashVerified,
    String? fileName,
    int? fileSize,
    String? fileHash,
    String? senderIp,
    String? senderHostname,
    String? receiverIp,
    String? receiverHostname,
  }) async {
    await log(LogEntry(
      timestamp: DateTime.now(),
      event: LogEvent.transferComplete,
      transferId: transferId,
      fileName: fileName,
      fileSize: fileSize,
      fileHash: fileHash,
      senderIp: senderIp,
      senderHostname: senderHostname,
      receiverIp: receiverIp,
      receiverHostname: receiverHostname,
    ));
  }

  /// 记录传输错误
  Future<void> logTransferError({
    required String transferId,
    required String errorMsg,
  }) async {
    await log(LogEntry(
      timestamp: DateTime.now(),
      event: LogEvent.transferError,
      transferId: transferId,
      errorMsg: errorMsg,
    ));
  }

  /// 记录口令验证
  Future<void> logCodeVerified(String transferId, String senderIp) async {
    await log(LogEntry(
      timestamp: DateTime.now(),
      event: LogEvent.codeVerified,
      transferId: transferId,
      senderIp: senderIp,
    ));
  }

  /// 记录口令错误
  Future<void> logCodeInvalid(String code, String senderIp) async {
    await log(LogEntry(
      timestamp: DateTime.now(),
      event: LogEvent.codeInvalid,
      senderIp: senderIp,
    ));
  }

  /// 读取最近日志（用于 UI 显示）
  Future<List<LogEntry>> readRecentLogs({int limit = 50}) async {
    await init();

    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final logFile = File(p.join(_logDir, 'lse-$today.log'));

    if (!await logFile.exists()) return [];

    final lines = await logFile.readAsLines();
    final reversed = lines.reversed.take(limit).toList().reversed;

    return reversed
        .map((line) {
          try {
            final json = jsonDecode(line) as Map<String, dynamic>;
            final event = LogEvent.fromString(json['event'] ?? '');
            return LogEntry(
              timestamp: DateTime.parse(json['timestamp']),
              event: event,
              transferId: json['transferId'],
              direction: json['direction'],
              errorMsg: json['error'],
              progressPercent: json['progressPercent'],
              receivedBytes: json['receivedBytes'],
              fileName: json['file']?['name'],
              fileSize: json['file']?['size'],
              fileHash: json['file']?['hash'],
              senderIp: json['sender']?['ip'],
              senderHostname: json['sender']?['hostname'],
              receiverIp: json['receiver']?['ip'],
              receiverHostname: json['receiver']?['hostname'],
            );
          } catch (_) {
            return null;
          }
        })
        .whereType<LogEntry>()
        .toList();
  }

  /// 清理超过保留期的日志文件
  Future<void> _cleanOldLogs() async {
    final dir = Directory(_logDir);
    if (!await dir.exists()) return;

    final cutoff = DateTime.now()
        .subtract(const Duration(days: AppConstants.logRetentionDays));

    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.log')) {
        final stat = await entity.stat();
        if (stat.modified.isBefore(cutoff)) {
          await entity.delete();
        }
      }
    }
  }

  Future<String> _getHomeDir() async {
    if (Platform.isMacOS || Platform.isLinux) {
      return Platform.environment['HOME'] ?? (await getApplicationDocumentsDirectory()).path;
    } else if (Platform.isWindows) {
      return Platform.environment['USERPROFILE'] ??
          (await getApplicationDocumentsDirectory()).path;
    }
    return (await getApplicationDocumentsDirectory()).path;
  }
}


