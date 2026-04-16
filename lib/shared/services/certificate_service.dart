import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// 证书服务：管理 HTTPS 自签名证书的生成与持久化
///
/// 策略：
/// - 首次启动时通过 openssl 生成 RSA 证书对
/// - 持久化到 AppData 目录，后续启动直接加载，不再重复生成
/// - 证书有效期 10 年，企业内网使用足够
class CertificateService {
  static CertificateService? _instance;
  static CertificateService get instance => _instance ??= CertificateService._();
  CertificateService._();

  /// 证书文件存放目录（AppData/lse_client/certs/）
  Future<Directory> get _certDir async {
    final appDir = await getApplicationSupportDirectory();
    final certDir = Directory(p.join(appDir.path, 'certs'));
    if (!await certDir.exists()) {
      await certDir.create(recursive: true);
    }
    return certDir;
  }

  /// 获取证书文件路径
  Future<String> get _certPath async => p.join((await _certDir).path, 'server.crt');

  /// 获取私钥文件路径
  Future<String> get _keyPath async => p.join((await _certDir).path, 'server.key');

  /// 加载证书字节（供 SecurityContext 使用）
  Future<Uint8List> get certificateBytes async {
    await _ensureCertificate();
    return Uint8List.fromList(await File(await _certPath).readAsBytes());
  }

  /// 加载私钥字节（供 SecurityContext 使用）
  Future<Uint8List> get privateKeyBytes async {
    await _ensureCertificate();
    return Uint8List.fromList(await File(await _keyPath).readAsBytes());
  }

  /// 确保证书存在，不存在则生成
  Future<void> _ensureCertificate() async {
    final certFile = File(await _certPath);
    final keyFile = File(await _keyPath);

    if (await certFile.exists() && await keyFile.exists()) {
      // 证书已存在，直接使用
      return;
    }

    // 生成证书
    await _generateSelfSignedCert(
      certPath: await _certPath,
      keyPath: await _keyPath,
    );
  }

  /// 通过 openssl 命令生成自签名 RSA 证书
  ///
  /// 生成参数说明：
  /// - 2048 位 RSA 密钥（安全与性能平衡）
  /// - SHA256 签名算法
  /// - 有效期 3650 天（约 10 年）
  /// - CN=localhost + IP=127.0.0.1（兼容本机连接）
  /// - 允许私钥密码为空（企业内网场景简化）
  Future<void> _generateSelfSignedCert({
    required String certPath,
    required String keyPath,
  }) async {
    // Step 1: 生成 RSA 私钥
    final keyResult = await Process.run('openssl', [
      'genrsa',
      '-out', keyPath,
      '2048',
    ]);
    if (keyResult.exitCode != 0) {
      throw Exception('生成私钥失败: ${keyResult.stderr}');
    }

    // Step 2: 生成自签名证书
    final certResult = await Process.run('openssl', [
      'req',
      '-new',
      '-x509',
      '-key', keyPath,
      '-out', certPath,
      '-days', '3650',
      '-subj', '/CN=LocalSendEnterprise/O=Enterprise/C=CN',
      '-addext', 'subjectAltName=IP:127.0.0.1,IP:0.0.0.0',
    ]);
    if (certResult.exitCode != 0) {
      throw Exception('生成证书失败: ${certResult.stderr}');
    }
  }

  /// 检查 openssl 是否可用（跨平台兼容性检查）
  Future<bool> isOpenSslAvailable() async {
    try {
      final result = await Process.run('openssl', ['version']);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}
