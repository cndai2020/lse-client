/// 设备信息模型
class DeviceInfo {
  final String id;
  final String hostname;
  final String ip;
  final String? mac;
  final String platform; // 'windows' | 'macos' | 'linux'

  DeviceInfo({
    required this.id,
    required this.hostname,
    required this.ip,
    this.mac,
    required this.platform,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'hostname': hostname,
        'ip': ip,
        'mac': mac,
        'platform': platform,
      };

  factory DeviceInfo.fromJson(Map<String, dynamic> json) => DeviceInfo(
        id: json['id'] ?? '',
        hostname: json['hostname'] ?? '',
        ip: json['ip'] ?? '',
        mac: json['mac'],
        platform: json['platform'] ?? 'unknown',
      );
}
