/// LSE 全局常量
class AppConstants {
  AppConstants._();

  // === 版本信息 ===
  static const String appName = 'LocalSend 企业版';
  static const String appVersion = '1.0.0';

  // === 传输参数 ===
  /// 每个块的大小 1MB
  static const int chunkSize = 1024 * 1024;

  /// 口令长度
  static const int codeLength = 6;

  /// 口令有效期（秒）
  static const int codeExpirySeconds = 300; // 5分钟

  /// 传输端口
  static const int transferPort = 41234;

  /// 默认 HTTPS 端口
  static const int defaultHttpsPort = 41234;

  // === 日志 ===
  /// 日志目录
  static const String logDir = '.lse/logs';

  /// 日志文件名格式
  static const String logFileNameFormat = 'lse-yyyy-MM-dd.log';

  /// 日志保留天数
  static const int logRetentionDays = 30;

  /// 进度日志记录间隔（百分比）
  static const int progressLogInterval = 5;

  // === 存储路径 ===
  /// 下载默认目录
  static const String defaultDownloadDir = 'Downloads';

  // === 设备信息 key ===
  static const String deviceIdKey = 'device_id';
  static const String deviceNameKey = 'device_name';
}
