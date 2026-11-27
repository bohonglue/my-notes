import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 一個可下載的新版本。
class AppRelease {
  AppRelease({required this.version, required this.build, required this.notes, required this.assetUrl});

  final String version;
  final int build;
  final String notes;
  final Uri assetUrl;
}

enum UpdateState { idle, checking, upToDate, available, downloading, installing, error }

/// 檢查並安裝新版本。
///
/// 新版本由 GitHub Actions 發佈到公開的 my-notes-releases（只有安裝檔）。
/// 版本號是 `1.0.<build>`，build 每次打包加一，用它來比較新舊。
class UpdateService extends ChangeNotifier {
  UpdateService({http.Client? client, this.releasesApi = defaultApi}) : _http = client ?? http.Client();

  static const defaultApi = 'https://api.github.com/repos/bohonglue/my-notes-releases/releases/latest';

  final http.Client _http;
  final String releasesApi;

  UpdateState state = UpdateState.idle;
  AppRelease? available;
  double progress = 0;
  String? error;
  int? currentBuild;
  String? currentVersion;

  Future<void> loadCurrent() async {
    final info = await PackageInfo.fromPlatform();
    currentVersion = info.version;
    currentBuild = int.tryParse(info.buildNumber) ?? 0;
    notifyListeners();
  }

  /// 檢查有沒有新版。[silent] 時發生錯誤不改變狀態（開 app 時的自動檢查用）。
  Future<AppRelease?> check({bool silent = false}) async {
    if (currentBuild == null) await loadCurrent();
    state = UpdateState.checking;
    error = null;
    notifyListeners();
    try {
      final r = await _http.get(Uri.parse(releasesApi), headers: {'Accept': 'application/vnd.github+json'});
      if (r.statusCode == 404) {
        state = UpdateState.upToDate;
        available = null;
        return null;
      }
      if (r.statusCode != 200) throw HttpException('GitHub 回應 ${r.statusCode}');
      final rel = parseRelease(jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>, platformAssetSuffix);
      if (rel != null && rel.build > currentBuild!) {
        available = rel;
        state = UpdateState.available;
      } else {
        available = null;
        state = UpdateState.upToDate;
      }
      return available;
    } catch (e) {
      if (silent) {
        state = UpdateState.idle;
      } else {
        error = e is SocketException ? '沒有網路連線' : '$e';
        state = UpdateState.error;
      }
      return null;
    } finally {
      notifyListeners();
    }
  }

  static String get platformAssetSuffix => Platform.isWindows ? '.zip' : '.apk';

  /// 解析 GitHub release，找出這個平台的安裝檔。版本格式 `v1.0.<build>`。
  @visibleForTesting
  static AppRelease? parseRelease(Map<String, dynamic> j, String suffix) {
    final tag = (j['tag_name'] as String? ?? '').replaceFirst(RegExp('^v'), '');
    final build = int.tryParse(tag.split('.').last);
    if (build == null) return null;
    for (final a in (j['assets'] as List? ?? const [])) {
      final m = a as Map<String, dynamic>;
      final name = m['name'] as String? ?? '';
      if (name.endsWith(suffix)) {
        return AppRelease(
          version: tag,
          build: build,
          notes: j['body'] as String? ?? '',
          assetUrl: Uri.parse(m['browser_download_url'] as String),
        );
      }
    }
    return null;
  }

  /// 下載並安裝。Android：開啟系統安裝畫面。Windows：解壓縮後由批次檔覆蓋並重新開啟。
  Future<void> downloadAndInstall() async {
    final rel = available;
    if (rel == null) return;
    state = UpdateState.downloading;
    progress = 0;
    error = null;
    notifyListeners();
    try {
      final dir = await getTemporaryDirectory();
      final file = File(p.join(dir.path, 'update$platformAssetSuffix'));
      await _download(rel.assetUrl, file);
      state = UpdateState.installing;
      notifyListeners();
      if (Platform.isWindows) {
        await _installWindows(file);
      } else {
        final res = await OpenFilex.open(file.path, type: 'application/vnd.android.package-archive');
        if (res.type != ResultType.done) {
          throw Exception(res.type == ResultType.permissionDenied
              ? '請允許「我的筆記」安裝應用程式後再試一次'
              : res.message);
        }
        state = UpdateState.available;
      }
    } catch (e) {
      error = '更新失敗：$e';
      state = UpdateState.error;
    } finally {
      notifyListeners();
    }
  }

  Future<void> _download(Uri url, File file) async {
    final resp = await _http.send(http.Request('GET', url));
    if (resp.statusCode != 200) throw HttpException('下載失敗（${resp.statusCode}）');
    final total = resp.contentLength ?? 0;
    var got = 0;
    final sink = file.openWrite();
    await for (final chunk in resp.stream) {
      sink.add(chunk);
      got += chunk.length;
      if (total > 0) {
        progress = got / total;
        notifyListeners();
      }
    }
    await sink.close();
  }

  /// Windows：把新版解壓到暫存資料夾，寫一個批次檔：等這個程式結束、
  /// 把新檔案複製到目前的程式資料夾、再重新開啟，然後結束目前的程式。
  Future<void> _installWindows(File zip) async {
    final exe = Platform.resolvedExecutable;
    final appDir = p.dirname(exe);
    final staging = Directory(p.join(p.dirname(zip.path), 'update_files'));
    if (await staging.exists()) await staging.delete(recursive: true);
    await extractFileToDisk(zip.path, staging.path);
    final script = File(p.join(p.dirname(zip.path), 'update.bat'));
    await script.writeAsString([
      '@echo off',
      'chcp 65001 >nul',
      'timeout /t 2 /nobreak >nul',
      ':wait',
      'tasklist /fi "PID eq $pid" | find "$pid" >nul && (timeout /t 1 /nobreak >nul & goto wait)',
      'robocopy "${staging.path}" "$appDir" /E /NFL /NDL /NJH /NJS >nul',
      'start "" "$exe"',
      'rmdir /s /q "${staging.path}"',
      'del "%~f0"',
    ].join('\r\n'));
    await Process.start('cmd', ['/c', script.path], mode: ProcessStartMode.detached);
    exit(0);
  }
}
