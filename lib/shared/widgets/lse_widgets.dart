import 'package:flutter/material.dart';
import '../../core/theme/lse_theme.dart';

/// 统一的卡片容器
class LseCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;

  const LseCard({super.key, required this.child, this.padding});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: padding ?? const EdgeInsets.all(20),
        child: child,
      ),
    );
  }
}

/// 文件大小格式化
String formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

/// 进度条
class LseProgressBar extends StatelessWidget {
  final double progress;
  final String? label;

  const LseProgressBar({super.key, required this.progress, this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(label!, style: const TextStyle(color: LseTheme.textSecondary, fontSize: 13)),
                Text(
                  '${(progress * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                    color: LseTheme.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress.clamp(0.0, 1.0),
            minHeight: 8,
            backgroundColor: LseTheme.border,
            valueColor: const AlwaysStoppedAnimation<Color>(LseTheme.primary),
          ),
        ),
      ],
    );
  }
}

/// 状态标签
class StatusBadge extends StatelessWidget {
  final String text;
  final Color color;

  const StatusBadge({super.key, required this.text, required this.color});

  factory StatusBadge.waiting() => const StatusBadge(text: '等待连接', color: LseTheme.warning);
  factory StatusBadge.transferring() => const StatusBadge(text: '传输中', color: LseTheme.primary);
  factory StatusBadge.completed() => const StatusBadge(text: '已完成', color: LseTheme.success);
  factory StatusBadge.error() => const StatusBadge(text: '错误', color: LseTheme.error);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}
