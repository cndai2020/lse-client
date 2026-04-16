import 'dart:io';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// 打包服务：文件夹 zip 压缩 / zip 解压
class ArchiveService {
  /// 将文件夹压缩为 zip，返回 zip 文件路径
  Future<String> compressFolder(String folderPath) async {
    final folder = Directory(folderPath);
    if (!await folder.exists()) {
      throw Exception('文件夹不存在: $folderPath');
    }

    final archive = Archive();
    final folderName = p.basename(folderPath);

    await for (final entity in folder.list(recursive: true)) {
      if (entity is File) {
        final relativePath = p.join(
          folderName,
          p.relative(entity.path, from: folderPath),
        );
        final bytes = await entity.readAsBytes();
        archive.addFile(ArchiveFile(relativePath, bytes.length, bytes));
      }
    }

    final zipData = ZipEncoder().encode(archive);
    if (zipData == null) {
      throw Exception('压缩失败');
    }

    final zipPath = '$folderPath.zip';
    final zipFile = File(zipPath);
    await zipFile.writeAsBytes(zipData);

    return zipPath;
  }

  /// 将单个文件复制到临时 zip（保持接口一致，单文件不压缩）
  Future<String> prepareSingleFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('文件不存在: $filePath');
    }
    // 单文件不压缩，直接返回原路径
    return filePath;
  }

  /// 解压 zip 到目标目录，返回解压后的根目录路径
  Future<String> extractZip(String zipPath, String destDir) async {
    final zipFile = File(zipPath);
    if (!await zipFile.exists()) {
      throw Exception('ZIP 文件不存在: $zipPath');
    }

    final bytes = await zipFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    final createdDirs = <String>{};

    for (final file in archive) {
      final filePath = p.join(destDir, file.name);

      if (file.isFile) {
        // 确保父目录存在
        final parentDir = Directory(p.dirname(filePath));
        if (!await parentDir.exists()) {
          await parentDir.create(recursive: true);
        }

        final outFile = File(filePath);
        await outFile.writeAsBytes(file.content as List<int>);
      } else {
        // 目录
        final dir = Directory(filePath);
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        createdDirs.add(filePath);
      }
    }

    // 返回顶层目录（ZIP 内第一个目录名）
    if (archive.files.isNotEmpty) {
      final firstName = archive.files.first.name;
      final topDir = p.join(destDir, firstName.split('/').first);
      if (await Directory(topDir).exists()) {
        return topDir;
      }
    }
    return destDir;
  }

  /// 计算文件 SHA256 hash（分块流式计算，避免大文件内存溢出）
  Future<String> computeFileHash(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('文件不存在: $filePath');
    }

    final output = _HashSink();
    final input = sha256.startChunkedConversion(output);

    await for (final chunk in file.openRead()) {
      input.add(chunk);
    }
    input.close();

    return 'sha256:${output.hex}';
  }
}

/// 分块 hash 输出 sink：接收 sha256 的字节输出
class _HashSink implements Sink<Digest> {
  Digest? _digest;

  @override
  void add(Digest data) {
    _digest = data;
  }

  @override
  void close() {}

  String get hex => _digest?.toString() ?? '';
}
