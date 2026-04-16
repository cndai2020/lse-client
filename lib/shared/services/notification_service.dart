import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// 通知服务：传输完成弹窗
class NotificationService {
  static NotificationService? _instance;
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  NotificationService._();

  static NotificationService get instance =>
      _instance ??= NotificationService._();

  Future<void> init() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(initSettings);
    _initialized = true;
  }

  /// 通知传输完成
  Future<void> showTransferComplete({
    required String fileName,
    required String fileSize,
    required String senderHostname,
    required String senderIp,
    required String duration,
    String? savedPath,
  }) async {
    await init();

    final sizeStr = _formatFileSize(int.tryParse(fileSize) ?? 0);

    await _plugin.show(
      0,
      '✅ 传输完成',
      '$fileName ($sizeStr)\n来自：$senderHostname ($senderIp)\n用时：$duration',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'lse_transfer',
          '传输通知',
          channelDescription: '文件传输完成通知',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );
  }

  /// 通知收到新传输请求
  Future<void> showIncomingTransfer({
    required String senderHostname,
    required String senderIp,
    required String fileName,
    required String fileSize,
  }) async {
    await init();

    final sizeStr = _formatFileSize(int.tryParse(fileSize) ?? 0);

    await _plugin.show(
      1,
      '📥 收到传输请求',
      '$senderHostname ($senderIp) 想要发送：\n$fileName ($sizeStr)',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'lse_incoming',
          '接收通知',
          channelDescription: '收到传输请求通知',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );
  }

  /// 通知传输错误
  Future<void> showTransferError({
    required String fileName,
    required String errorMsg,
  }) async {
    await init();

    await _plugin.show(
      2,
      '❌ 传输失败',
      '$fileName\n$errorMsg',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'lse_error',
          '错误通知',
          channelDescription: '传输错误通知',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: false,
          presentSound: true,
        ),
      ),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
