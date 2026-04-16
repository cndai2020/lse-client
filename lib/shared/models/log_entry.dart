/// 日志事件类型
enum LogEvent {
  transferStart('transfer_start'),
  transferProgress('transfer_progress'),
  transferPause('transfer_pause'),
  transferResume('transfer_resume'),
  transferComplete('transfer_complete'),
  transferError('transfer_error'),
  codeVerified('code_verified'),
  codeInvalid('code_invalid');

  final String value;
  const LogEvent(this.value);

  static LogEvent fromString(String v) =>
      LogEvent.values.firstWhere((e) => e.value == v);
}

/// 日志条目
class LogEntry {
  final DateTime timestamp;
  final LogEvent event;
  final String? transferId;
  final String? direction; // 'send' | 'receive'
  final String? senderIp;
  final String? senderMac;
  final String? senderHostname;
  final String? receiverIp;
  final String? receiverMac;
  final String? receiverHostname;
  final String? fileName;
  final int? fileSize;
  final String? fileHash;
  final String? errorMsg;
  final int? progressPercent;
  final int? receivedBytes;

  LogEntry({
    required this.timestamp,
    required this.event,
    this.transferId,
    this.direction,
    this.senderIp,
    this.senderMac,
    this.senderHostname,
    this.receiverIp,
    this.receiverMac,
    this.receiverHostname,
    this.fileName,
    this.fileSize,
    this.fileHash,
    this.errorMsg,
    this.progressPercent,
    this.receivedBytes,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'timestamp': timestamp.toIso8601String(),
      'event': event.value,
    };
    if (transferId != null) map['transferId'] = transferId;
    if (direction != null) map['direction'] = direction;
    if (senderIp != null || senderMac != null || senderHostname != null) {
      map['sender'] = {
        'ip': senderIp,
        'mac': senderMac,
        'hostname': senderHostname,
      };
    }
    if (receiverIp != null || receiverMac != null || receiverHostname != null) {
      map['receiver'] = {
        'ip': receiverIp,
        'mac': receiverMac,
        'hostname': receiverHostname,
      };
    }
    if (fileName != null || fileSize != null || fileHash != null) {
      map['file'] = {
        'name': fileName,
        'size': fileSize,
        'hash': fileHash,
      };
    }
    if (errorMsg != null) map['error'] = errorMsg;
    if (progressPercent != null) map['progressPercent'] = progressPercent;
    if (receivedBytes != null) map['receivedBytes'] = receivedBytes;
    return map;
  }
}
