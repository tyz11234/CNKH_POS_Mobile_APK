import 'package:flutter/material.dart';

/// A footer must measure its content, not consume the Scaffold body height.
class PagedListFooter extends StatelessWidget {
  const PagedListFooter({
    super.key,
    required this.page,
    this.onPrevious,
    this.onNext,
  });
  final int page;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Row(
        children: [
          OutlinedButton(onPressed: onPrevious, child: const Text('上一页')),
          Expanded(
            child: Center(heightFactor: 1, child: Text('第 ${page + 1} 页')),
          ),
          OutlinedButton(onPressed: onNext, child: const Text('下一页')),
        ],
      ),
    ),
  );
}

class ListLoadMessage extends StatelessWidget {
  const ListLoadMessage({super.key, required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('重试 / Retry')),
        ],
      ),
    ),
  );
}
