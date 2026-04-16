/// 传输任务模型
class TransferTask {
  final String id;
  final String fileName;
  final int fileSize;
  final String fileHash;
  final String localPath;
  final TransferDirection direction;
  final TransferStatus status;
  final String? code;
  final String? senderIp;
  final String? senderHostname;
  final String? senderMac;
  final int bytesTransferred;
  final DateTime startTime;
  final DateTime? endTime;

  TransferTask({
    required this.id,
    required this.fileName,
    required this.fileSize,
    required this.fileHash,
    required this.localPath,
    required this.direction,
    this.status = TransferStatus.pending,
    this.code,
    this.senderIp,
    this.senderHostname,
    this.senderMac,
    this.bytesTransferred = 0,
    required this.startTime,
    this.endTime,
  });

  double get progress =>
      fileSize > 0 ? (bytesTransferred / fileSize).clamp(0.0, 1.0) : 0.0;

  int get progressPercent => (progress * 100).round();

  Duration get elapsed =>
      (endTime ?? DateTime.now()).difference(startTime);

  TransferTask copyWith({
    String? id,
    String? fileName,
    int? fileSize,
    String? fileHash,
    String? localPath,
    TransferDirection? direction,
    TransferStatus? status,
    String? code,
    String? senderIp,
    String? senderHostname,
    String? senderMac,
    int? bytesTransferred,
    DateTime? startTime,
    DateTime? endTime,
  }) {
    return TransferTask(
      id: id ?? this.id,
      fileName: fileName ?? this.fileName,
      fileSize: fileSize ?? this.fileSize,
      fileHash: fileHash ?? this.fileHash,
      localPath: localPath ?? this.localPath,
      direction: direction ?? this.direction,
      status: status ?? this.status,
      code: code ?? this.code,
      senderIp: senderIp ?? this.senderIp,
      senderHostname: senderHostname ?? this.senderHostname,
      senderMac: senderMac ?? this.senderMac,
      bytesTransferred: bytesTransferred ?? this.bytesTransferred,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
    );
  }
}

enum TransferDirection { send, receive }

enum TransferStatus {
  pending,
  waitingCode,
  transferring,
  paused,
  completed,
  error,
}
