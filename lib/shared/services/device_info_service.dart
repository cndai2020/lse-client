import 'dart:io';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:uuid/uuid.dart';
import '../models/device_info.dart';

/// 设备信息服务
class DeviceInfoService {
  static DeviceInfoService? _instance;
  DeviceInfo? _cachedInfo;

  DeviceInfoService._();

  static DeviceInfoService get instance =>
      _instance ??= DeviceInfoService._();

  /// 获取本地设备信息（带缓存）
  Future<DeviceInfo> getDeviceInfo() async {
    if (_cachedInfo != null) return _cachedInfo!;

    final uuid = _getOrCreateDeviceId();
    final hostname = _getHostname();
    final ip = await _getLocalIp();
    final mac = await _getMacAddress();
    final platform = _getPlatform();

    _cachedInfo = DeviceInfo(
      id: uuid,
      hostname: hostname,
      ip: ip,
      mac: mac,
      platform: platform,
    );

    return _cachedInfo!;
  }

  String _getOrCreateDeviceId() {
    // 简化版：每次生成新的 UUID 标识
    // 企业场景可对接 AD/设备管理平台做持久化
    return const Uuid().v4();
  }

  String _getHostname() {
    try {
      return Platform.localHostname;
    } catch (_) {
      return 'UNKNOWN';
    }
  }

  Future<String> _getLocalIp() async {
    try {
      final wifiIP = await NetworkInfo().getWifiIP();
      return wifiIP ?? '127.0.0.1';
    } catch (_) {
      // 回退：尝试从网络接口获取
      try {
        final interfaces = await NetworkInterface.list(
          type: InternetAddressType.IPv4,
          includeLoopback: false,
        );
        for (final iface in interfaces) {
          for (final addr in iface.addresses) {
            if (!addr.isLoopback) {
              return addr.address;
            }
          }
        }
      } catch (_) {}
      return '127.0.0.1';
    }
  }

  Future<String?> _getMacAddress() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        if (iface.name.toLowerCase().contains('en') ||
            iface.name.toLowerCase().contains('eth') ||
            iface.name.toLowerCase().contains('wlan')) {
          // mac 地址无法通过 Dart 直接获取，此处返回 iface name 作为标识
          return iface.name;
        }
      }
    } catch (_) {}
    return null;
  }

  String _getPlatform() {
    return Platform.operatingSystem;
  }
}
