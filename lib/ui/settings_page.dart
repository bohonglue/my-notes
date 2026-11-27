import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/backup_service.dart';
import '../state/notes_store.dart';
import '../state/settings_store.dart';
import '../sync/sync_service.dart';
import 'sync_indicator.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsStore>();
    final store = context.read<NotesStore>();
    final backup = BackupService(store.db);

    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: ListView(
        children: [
          const _Header('外觀'),
          RadioGroup<ThemeMode>(
            groupValue: s.themeMode,
            onChanged: (m) => s.setThemeMode(m!),
            child: const Column(children: [
              RadioListTile(value: ThemeMode.system, title: Text('跟隨系統')),
              RadioListTile(value: ThemeMode.light, title: Text('淺色')),
              RadioListTile(value: ThemeMode.dark, title: Text('深色')),
            ]),
          ),
          const Divider(),
          const _Header('Google Drive 同步'),
          const _SyncSection(),
          const Divider(),
          const _Header('備份與還原'),
          ListTile(
            leading: const Icon(Icons.save_alt),
            title: const Text('匯出備份'),
            subtitle: const Text('把所有筆記、資料夾、圖片存成一個 .mynotes 檔'),
            onTap: () => _run(context, '正在匯出…', (busy) async {
              final where = await backup.exportBackup(onStart: busy);
              return where == null ? null : '備份已儲存：$where';
            }),
          ),
          ListTile(
            leading: const Icon(Icons.settings_backup_restore),
            title: const Text('從備份還原'),
            subtitle: const Text('選一個 .mynotes 檔合併進來，較新的版本會保留，不會刪掉你現有的筆記'),
            onTap: () => _run(context, '正在還原…', (busy) async {
              final n = await backup.restoreBackup(onPicked: busy);
              if (n == null) return null;
              await store.load();
              return '還原完成，更新了 $n 則筆記';
            }),
          ),
          ListTile(
            leading: const Icon(Icons.move_to_inbox_outlined),
            title: const Text('匯入 Keep My Notes 備份'),
            subtitle: const Text('選擇 .kmnb 檔。重複匯入同一份不會產生重複的筆記'),
            onTap: () => _run(context, '正在匯入…', (busy) async {
              final r = await backup.importKmnbFile(onPicked: busy);
              if (r == null) return null;
              await store.load();
              final extra = [
                if (r.skippedUnchanged > 0) '${r.skippedUnchanged} 則已經匯入過、沒有變更，略過',
                if (r.skippedLocked > 0) '${r.skippedLocked} 則在原 app 上了鎖，無法匯入，請先在原 app 解鎖再備份',
              ];
              return '匯入完成：$r'
                  '${r.trashed > 0 ? '\n原本在垃圾桶的筆記放在垃圾桶裡，30 天後自動清除。' : ''}'
                  '${extra.isEmpty ? '' : '\n${extra.join('\n')}'}';
            }),
          ),
        ],
      ),
    );
  }

  /// 執行備份相關的工作。[task] 選好檔案後呼叫 showBusy() 顯示「處理中」，
  /// 回傳要顯示的結果；回傳 null 代表使用者取消。
  Future<void> _run(
    BuildContext context,
    String busy,
    Future<String?> Function(void Function() showBusy) task,
  ) async {
    final nav = Navigator.of(context);
    var dialogOpen = false;
    void showBusy() {
      dialogOpen = true;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => PopScope(
          canPop: false,
          child: AlertDialog(
            content: Row(children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 20),
              Text(busy),
            ]),
          ),
        ),
      );
    }

    String? message;
    try {
      message = await task(showBusy);
    } on FormatException catch (e) {
      message = '失敗：${e.message}';
    } catch (e) {
      message = '失敗：$e';
    } finally {
      if (dialogOpen) nav.pop();
    }
    if (message == null || !context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(message!),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('好'))],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            )),
      );
}

class _SyncSection extends StatelessWidget {
  const _SyncSection();

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncService>();
    switch (sync.status) {
      case SyncStatus.notConfigured:
        return const ListTile(
          leading: Icon(Icons.cloud_off_outlined),
          title: Text('這個版本沒有設定 Google 用戶端'),
          subtitle: Text('需要先在 Google Cloud 建立 OAuth 用戶端並加到 GitHub secrets，重新打包後才能同步。'),
        );
      case SyncStatus.signedOut:
        return ListTile(
          leading: const Icon(Icons.cloud_outlined),
          title: const Text('登入 Google 開始同步'),
          subtitle: const Text('筆記只會存在你自己 Google Drive 的 app 專用資料夾，雲端硬碟裡看不到，也不會被誤刪。'),
          onTap: () => _signIn(context, sync),
        );
      default:
        return Column(children: [
          ListTile(
            leading: const SyncIndicator(),
            title: Text(sync.auth.email ?? '已登入 Google'),
            subtitle: Text(syncStatusText(sync)),
            trailing: TextButton(
              onPressed: sync.status == SyncStatus.syncing ? null : sync.sync,
              child: const Text('立即同步'),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('登出 Google'),
            subtitle: const Text('停止同步。這台裝置上的筆記會留著。'),
            onTap: sync.signOut,
          ),
        ]);
    }
  }

  Future<void> _signIn(BuildContext context, SyncService sync) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('已開啟瀏覽器，登入後回到這裡')));
    try {
      await sync.signIn();
      messenger.showSnackBar(const SnackBar(content: Text('登入成功，已開始同步')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('登入失敗：$e')));
    }
  }
}
