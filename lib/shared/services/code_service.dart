import 'dart:math';
import '../../core/constants/app_constants.dart';

/// 口令服务：生成 + 验证 6位一次性口令
class CodeService {
  /// 内存中的活跃口令缓存：code -> expiry
  final Map<String, DateTime> _activeCodes = {};
  final Random _random = Random.secure();

  /// 生成 6 位数字口令
  String generateCode() {
    final code = List.generate(
      AppConstants.codeLength,
      (_) => _random.nextInt(10),
    ).join();

    _activeCodes[code] =
        DateTime.now().add(const Duration(seconds: AppConstants.codeExpirySeconds));

    // 清理过期口令
    _cleanExpiredCodes();

    return code;
  }

  /// 验证口令
  /// 返回 true 表示有效并自动失效（一次性）
  bool verifyAndConsume(String code) {
    _cleanExpiredCodes();

    if (_activeCodes.containsKey(code)) {
      _activeCodes.remove(code);
      return true;
    }
    return false;
  }

  /// 验证口令（不消费，用于查询文件信息）
  bool verifyOnly(String code) {
    _cleanExpiredCodes();
    return _activeCodes.containsKey(code);
  }

  /// 主动使口令失效（发送方取消传输）
  void invalidateCode(String code) {
    _activeCodes.remove(code);
  }

  /// 获取当前有效口令数
  int get activeCodeCount => _activeCodes.length;

  void _cleanExpiredCodes() {
    final now = DateTime.now();
    _activeCodes.removeWhere((_, expiry) => now.isAfter(expiry));
  }
}
