// ===== API 请求体 =====

/// 发起传输请求
class InitTransferRequest {
  final String code;
  final String fileName;
  final int fileSize;
  final String fileHash;
  final String senderIp;
  final String? senderMac;
  final String senderHostname;

  InitTransferRequest({
    required this.code,
    required this.fileName,
    required this.fileSize,
    required this.fileHash,
    required this.senderIp,
    this.senderMac,
    required this.senderHostname,
  });

  Map<String, dynamic> toJson() => {
        'code': code,
        'fileName': fileName,
        'fileSize': fileSize,
        'fileHash': fileHash,
        'senderInfo': {
          'ip': senderIp,
          'mac': senderMac ?? '',
          'hostname': senderHostname,
        },
      };
}

/// ===== API 响应体 =====

/// 发起传输响应
class InitTransferResponse {
  final String transferId;
  final bool accepted;

  InitTransferResponse({required this.transferId, required this.accepted});

  factory InitTransferResponse.fromJson(Map<String, dynamic> json) =>
      InitTransferResponse(
        transferId: json['transferId'] ?? '',
        accepted: json['accepted'] ?? false,
      );
}

/// 获取传输信息响应
class TransferInfoResponse {
  final String fileName;
  final int fileSize;
  final String fileHash;
  final String senderIp;
  final String? senderMac;
  final String senderHostname;

  TransferInfoResponse({
    required this.fileName,
    required this.fileSize,
    required this.fileHash,
    required this.senderIp,
    this.senderMac,
    required this.senderHostname,
  });

  factory TransferInfoResponse.fromJson(Map<String, dynamic> json) {
    final sender = json['senderInfo'] ?? {};
    return TransferInfoResponse(
      fileName: json['fileName'] ?? '',
      fileSize: json['fileSize'] ?? 0,
      fileHash: json['fileHash'] ?? '',
      senderIp: sender['ip'] ?? '',
      senderMac: sender['mac'],
      senderHostname: sender['hostname'] ?? '',
    );
  }
}

/// 传输块响应
class ChunkResponse {
  final int received;

  ChunkResponse({required this.received});

  factory ChunkResponse.fromJson(Map<String, dynamic> json) => ChunkResponse(
        received: json['received'] ?? 0,
      );
}

/// 完成传输响应
class CompleteTransferResponse {
  final bool success;
  final bool hashVerified;

  CompleteTransferResponse({
    required this.success,
    required this.hashVerified,
  });

  factory CompleteTransferResponse.fromJson(Map<String, dynamic> json) =>
      CompleteTransferResponse(
        success: json['success'] ?? false,
        hashVerified: json['hashVerified'] ?? false,
      );
}
