import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../update/update_service.dart';

/// 顯示「有新版本」的對話框，裡面可以直接下載並安裝。
Future<void> showUpdateDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _UpdateDialog(),
  );
}

class _UpdateDialog extends StatelessWidget {
  const _UpdateDialog();

  @override
  Widget build(BuildContext context) {
    final u = context.watch<UpdateService>();
    final rel = u.available;
    final busy = u.state == UpdateState.downloading || u.state == UpdateState.installing;
    return AlertDialog(
      title: Text(rel == null ? '已經是最新版本' : '有新版本 ${rel.version}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('目前版本：${u.currentVersion ?? ''}'),
          if (rel != null && rel.notes.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: SingleChildScrollView(child: Text(rel.notes.trim())),
            ),
          ],
          if (u.state == UpdateState.downloading) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(value: u.progress > 0 ? u.progress : null),
            const SizedBox(height: 4),
            Text('下載中 ${(u.progress * 100).round()}%'),
          ],
          if (u.state == UpdateState.installing) ...[
            const SizedBox(height: 16),
            const Text('正在安裝…'),
          ],
          if (u.error != null) ...[
            const SizedBox(height: 12),
            Text(u.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: Text(rel == null ? '好' : '稍後'),
        ),
        if (rel != null)
          FilledButton(
            onPressed: busy ? null : u.downloadAndInstall,
            child: const Text('下載並安裝'),
          ),
      ],
    );
  }
}

/// 設定頁「關於」區塊：目前版本、檢查更新。
class UpdateTile extends StatelessWidget {
  const UpdateTile({super.key});

  @override
  Widget build(BuildContext context) {
    final u = context.watch<UpdateService>();
    final checking = u.state == UpdateState.checking;
    return ListTile(
      leading: const Icon(Icons.system_update_outlined),
      title: Text('目前版本 ${u.currentVersion ?? ''}'),
      subtitle: Text(switch (u.state) {
        UpdateState.checking => '檢查中…',
        UpdateState.upToDate => '已經是最新版本',
        UpdateState.available => '有新版本 ${u.available!.version}',
        UpdateState.error => u.error ?? '',
        _ => '開啟 app 時會自動檢查',
      }),
      trailing: TextButton(
        onPressed: checking
            ? null
            : () async {
                await u.check();
                if (context.mounted && u.state != UpdateState.error) await showUpdateDialog(context);
              },
        child: const Text('檢查更新'),
      ),
    );
  }
}
