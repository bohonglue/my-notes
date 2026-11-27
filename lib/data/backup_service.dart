import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'database.dart';
import 'kmnb_import.dart';

/// 備份、還原、匯入：負責選檔、存檔，實際資料處理在 NotesDatabase 和 importKmnb。
class BackupService {
  BackupService(this.db);

  final NotesDatabase db;

  static const backupExtension = 'mynotes';

  /// 匯出備份。回傳存好的位置；使用者取消時回傳 null。
  Future<String?> exportBackup({void Function()? onStart}) async {
    final tmp = await _tempFile('export.$backupExtension');
    await db.exportTo(tmp.path);
    final bytes = await tmp.readAsBytes();
    await tmp.delete();
    final name = '我的筆記備份_${DateFormat('yyyy-MM-dd_HHmm').format(DateTime.now())}.$backupExtension';
    final uri = await FilePicker.saveFile(
      dialogTitle: '儲存備份',
      fileName: name,
      bytes: bytes,
    );
    if (uri == null) return null;
    return uri.scheme == 'file' ? uri.toFilePath() : name;
  }

  /// 從本 app 的備份還原（合併，不會刪掉現有較新的筆記）。回傳更新的筆記數；取消回傳 null。
  Future<int?> restoreBackup({void Function()? onPicked}) async {
    final file = await _pick('restore.$backupExtension');
    if (file == null) return null;
    onPicked?.call();
    try {
      return await db.mergeFrom(db.factory, file.path);
    } finally {
      await file.delete();
    }
  }

  /// 匯入 Keep My Notes 的 .kmnb 備份。取消回傳 null。
  Future<ImportResult?> importKmnbFile({void Function()? onPicked}) async {
    final file = await _pick('import.kmnb');
    if (file == null) return null;
    onPicked?.call();
    try {
      return await importKmnb(db.factory, file.path, db);
    } finally {
      await file.delete();
    }
  }

  /// 讓使用者選一個檔案，複製到暫存檔（Android 的 content:// 沒辦法直接給 SQLite 開）。
  Future<File?> _pick(String tempName) async {
    // 不限副檔名：Android 不認得 .kmnb / .mynotes 的類型，限定的話會選不到。
    final files = await FilePicker.pickFiles(dialogTitle: '選擇備份檔');
    if (files.isEmpty) return null;
    final tmp = await _tempFile(tempName);
    final sink = tmp.openWrite();
    await sink.addStream(files.first.readAsByteStream());
    await sink.close();
    await _checkSqlite(tmp);
    return tmp;
  }

  Future<void> _checkSqlite(File f) async {
    final raf = await f.open();
    final head = await raf.read(16);
    await raf.close();
    if (String.fromCharCodes(head) != 'SQLite format 3\u0000') {
      await f.delete();
      throw const FormatException('檔案格式不對，不是備份檔');
    }
  }

  Future<File> _tempFile(String name) async {
    final dir = await getTemporaryDirectory();
    final f = File(p.join(dir.path, name));
    if (await f.exists()) await f.delete();
    return f;
  }
}
