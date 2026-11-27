import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../sync/sync_service.dart';

String syncStatusText(SyncService s) => switch (s.status) {
      SyncStatus.notConfigured => '未設定同步',
      SyncStatus.signedOut => '未登入 Google',
      SyncStatus.syncing => '同步中…',
      SyncStatus.error => '同步失敗：${s.lastError}',
      SyncStatus.idle => s.lastSync == null
          ? '尚未同步'
          : '上次同步：${DateFormat('M/d HH:mm').format(s.lastSync!)}',
    };

/// 同步狀態的小圖示：同步中會轉圈，失敗會顯示驚嘆號。
class SyncIndicator extends StatelessWidget {
  const SyncIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SyncService>();
    return switch (s.status) {
      SyncStatus.syncing => const SizedBox(
          width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
      SyncStatus.error => Icon(Icons.sync_problem, color: Theme.of(context).colorScheme.error),
      SyncStatus.idle => const Icon(Icons.cloud_done_outlined),
      _ => const Icon(Icons.cloud_off_outlined),
    };
  }
}

/// 首頁右上角的同步按鈕（只有登入後才顯示）。
class SyncButton extends StatelessWidget {
  const SyncButton({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SyncService>();
    if (s.status == SyncStatus.notConfigured || s.status == SyncStatus.signedOut) {
      return const SizedBox.shrink();
    }
    return IconButton(
      tooltip: syncStatusText(s),
      icon: const SyncIndicator(),
      onPressed: s.status == SyncStatus.syncing ? null : s.sync,
    );
  }
}
