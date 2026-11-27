import 'dart:async';
import 'dart:io';


import 'package:flutter/foundation.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../state/notes_store.dart';
import 'drive_auth.dart';

enum SyncStatus { notConfigured, signedOut, idle, syncing, error }

/// 透過使用者自己的 Google Drive 同步。
///
/// 做法：Drive 的「應用程式資料夾」（appDataFolder，使用者在雲端硬碟裡看不到，
/// 也不會被誤刪）裡只放一個檔案 notes.mynotes，就是整個資料庫的備份檔。
/// 每次同步：下載 → 跟本機合併（每筆比較修改時間，新的贏；刪除也會套用）
/// → 把合併後的結果上傳。兩台裝置同時同步時，晚上傳的會蓋掉雲端檔案，
/// 但先上傳的那台本機仍保有全部資料，下一次同步就會再合併回去，不會遺失。
class SyncService extends ChangeNotifier {
  SyncService(this.store, {DriveAuth? auth}) : auth = auth ?? DriveAuth();

  final NotesStore store;
  final DriveAuth auth;

  static const fileName = 'notes.mynotes';
  static const _autoDelay = Duration(seconds: 20);
  static const _periodic = Duration(minutes: 5);

  SyncStatus status = SyncStatus.signedOut;
  DateTime? lastSync;
  String? lastError;
  Timer? _debounce;
  Timer? _timer;
  bool _again = false;
  int _seenChanges = 0;

  Future<void> init() async {
    if (!auth.isConfigured) {
      status = SyncStatus.notConfigured;
      notifyListeners();
      return;
    }
    store.addListener(_onStoreChanged);
    _seenChanges = store.localChanges;
    if (await auth.restore()) {
      status = SyncStatus.idle;
      notifyListeners();
      _startTimer();
      unawaited(sync());
    }
  }

  Future<void> signIn() async {
    await auth.signIn();
    status = SyncStatus.idle;
    notifyListeners();
    _startTimer();
    await sync();
  }

  Future<void> signOut() async {
    _timer?.cancel();
    _debounce?.cancel();
    await auth.signOut();
    status = SyncStatus.signedOut;
    lastSync = null;
    lastError = null;
    notifyListeners();
  }

  /// App 回到前景時同步一次。
  void onResumed() {
    if (auth.signedIn) unawaited(sync());
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(_periodic, (_) => sync());
  }

  void _onStoreChanged() {
    // 只在本機資料真的有變動時排程同步（切換檢視、搜尋不算）。
    if (store.localChanges == _seenChanges) return;
    _seenChanges = store.localChanges;
    if (!auth.signedIn) return;
    _debounce?.cancel();
    _debounce = Timer(_autoDelay, sync);
  }

  Future<void> sync() async {
    if (!auth.signedIn) return;
    if (status == SyncStatus.syncing) {
      _again = true;
      return;
    }
    _debounce?.cancel();
    status = SyncStatus.syncing;
    notifyListeners();
    final tmpDir = await getTemporaryDirectory();
    final down = File(p.join(tmpDir.path, 'sync_down.mynotes'));
    final up = File(p.join(tmpDir.path, 'sync_up.mynotes'));
    try {
      final api = drive.DriveApi(auth.client);
      final existing = await _findFile(api);

      if (existing != null) {
        final media = await api.files.get(existing.id!,
            downloadOptions: drive.DownloadOptions.fullMedia) as drive.Media;
        final sink = down.openWrite();
        await sink.addStream(media.stream);
        await sink.close();
        await store.db.mergeFrom(store.db.factory, down.path);
      }

      if (await up.exists()) await up.delete();
      await store.db.exportTo(up.path);
      final media = drive.Media(up.openRead(), await up.length(),
          contentType: 'application/octet-stream');
      if (existing == null) {
        await api.files.create(
          drive.File()
            ..name = fileName
            ..parents = ['appDataFolder'],
          uploadMedia: media,
        );
      } else {
        await api.files.update(drive.File(), existing.id!, uploadMedia: media);
      }

      // 合併後重新載入畫面，但不要因此又觸發一次同步。
      await store.load();
      _seenChanges = store.localChanges;
      lastSync = DateTime.now();
      lastError = null;
      status = SyncStatus.idle;
    } catch (e) {
      lastError = _describe(e);
      status = SyncStatus.error;
    } finally {
      for (final f in [down, up]) {
        if (await f.exists()) await f.delete();
      }
      notifyListeners();
    }
    if (_again) {
      _again = false;
      unawaited(sync());
    }
  }

  Future<drive.File?> _findFile(drive.DriveApi api) async {
    final list = await api.files.list(
      spaces: 'appDataFolder',
      q: "name = '$fileName' and trashed = false",
      $fields: 'files(id, modifiedTime)',
      orderBy: 'modifiedTime desc',
    );
    final files = list.files ?? const [];
    return files.isEmpty ? null : files.first;
  }

  String _describe(Object e) {
    if (e is SocketException || e is HttpException) return '沒有網路連線';
    if (e is drive.DetailedApiRequestError) {
      if (e.status == 401 || e.status == 403) return 'Google 授權失效，請重新登入';
      return 'Google Drive 錯誤 ${e.status}：${e.message}';
    }
    if ('$e'.contains('invalid_grant')) return 'Google 授權失效，請重新登入';
    return '$e';
  }

  @override
  void dispose() {
    _timer?.cancel();
    _debounce?.cancel();
    store.removeListener(_onStoreChanged);
    super.dispose();
  }
}
