import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:my_notes/data/database.dart';
import 'package:my_notes/data/models.dart';
import 'package:my_notes/state/notes_store.dart';
import 'package:my_notes/sync/drive_auth.dart';
import 'package:my_notes/sync/sync_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 模擬 Google Drive 的 appDataFolder：只支援同步用到的 list / 下載 / 建立 / 更新。
class FakeDrive {
  final files = <String, Uint8List>{}; // id -> 內容
  final names = <String, String>{}; // id -> 檔名
  var _next = 0;
  var uploads = 0;

  late final client = MockClient((req) async {
    final path = req.url.path;
    final q = req.url.queryParameters;
    if (req.method == 'GET' && path == '/drive/v3/files') {
      expect(q['spaces'], 'appDataFolder');
      final list = [
        for (final id in files.keys) {'id': id, 'name': names[id]},
      ];
      return http.Response(jsonEncode({'files': list}), 200, headers: _json);
    }
    if (req.method == 'GET' && path.startsWith('/drive/v3/files/') && q['alt'] == 'media') {
      final id = path.split('/').last;
      return http.Response.bytes(files[id]!, 200, headers: {'content-type': 'application/octet-stream'});
    }
    if (path.startsWith('/upload/drive/v3/files')) {
      uploads++;
      final (meta, media) = _parseMultipart(req);
      if (req.method == 'POST') {
        expect(meta['parents'], ['appDataFolder']);
        final id = 'f${_next++}';
        files[id] = media;
        names[id] = meta['name'] as String;
        return http.Response(jsonEncode({'id': id}), 200, headers: _json);
      }
      final id = path.split('/').last;
      files[id] = media;
      return http.Response(jsonEncode({'id': id}), 200, headers: _json);
    }
    return http.Response('not found: ${req.method} ${req.url}', 404);
  });

  static const _json = {'content-type': 'application/json; charset=utf-8'};

  static (Map<String, dynamic>, Uint8List) _parseMultipart(http.Request req) {
    final body = utf8.decode(req.bodyBytes);
    final boundary = RegExp(r'boundary="?([^";]+)').firstMatch(req.headers['content-type']!)!.group(1)!;
    final parts = body.split('--$boundary').where((p) => p.trim().isNotEmpty && p.trim() != '--').toList();
    String content(String part) => part.substring(part.indexOf('\r\n\r\n') + 4).trimRight();
    final meta = jsonDecode(content(parts[0])) as Map<String, dynamic>;
    final media = base64Decode(content(parts[1]));
    return (meta, media);
  }
}

class FakeAuth extends DriveAuth {
  FakeAuth(this.drive);
  final FakeDrive drive;

  @override
  bool get isConfigured => true;
  @override
  bool get signedIn => true;
  @override
  Future<bool> restore() async => true;
  @override
  http.Client get client => drive.client;
}

class FakePaths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  FakePaths(this.dir);
  final String dir;
  @override
  Future<String?> getTemporaryPath() async => dir;
}

void main() {
  setUpAll(sqfliteFfiInit);
  final factory = databaseFactoryFfiNoIsolate;

  test('兩台裝置透過 Drive 同步：新增、修改、刪除都會傳到另一台', () async {
    final tmp = await Directory.systemTemp.createTemp('sync');
    PathProviderPlatform.instance = FakePaths(tmp.path);
    final drive = FakeDrive();

    Future<(NotesStore, SyncService)> device() async {
      final db = await NotesDatabase.open(factory, inMemoryDatabasePath);
      final store = NotesStore(db);
      await store.load();
      final sync = SyncService(store, auth: FakeAuth(drive));
      return (store, sync);
    }

    final (phone, phoneSync) = await device();
    final (pc, pcSync) = await device();

    // 手機新增一則，同步；雲端出現一個檔案
    final n = phone.newNote(NoteType.text)
      ..title = '手機寫的'
      ..plainText = '內容';
    await phone.save(n);
    await phoneSync.sync();
    expect(phoneSync.status, SyncStatus.idle, reason: phoneSync.lastError);
    expect(drive.files.length, 1);
    expect(drive.names.values.single, SyncService.fileName);

    // 電腦同步後拿到這則
    await pcSync.sync();
    expect(pcSync.status, SyncStatus.idle, reason: pcSync.lastError);
    expect(pc.noteById(n.id)!.title, '手機寫的');

    // 電腦修改、手機同時新增另一則；兩邊各自同步後都有全部內容
    final onPc = pc.noteById(n.id)!..title = '電腦改過';
    await pc.save(onPc);
    final m = phone.newNote(NoteType.checklist)
      ..checklistItems = [ChecklistItem(text: '牛奶')];
    await phone.save(m);
    await pcSync.sync();
    await phoneSync.sync();
    await pcSync.sync();
    for (final s in [phone, pc]) {
      expect(s.noteById(n.id)!.title, '電腦改過');
      expect(s.noteById(m.id)!.checklistItems.single.text, '牛奶');
    }

    // 手機永久刪除，電腦同步後也消失
    await phone.moveToTrash(phone.noteById(m.id)!);
    await phone.emptyTrash();
    await phoneSync.sync();
    await pcSync.sync();
    expect(pc.noteById(m.id), isNull);
    expect(drive.files.length, 1);

    await tmp.delete(recursive: true);
  });

  test('沒有設定用戶端 ID 時顯示未設定', () async {
    final db = await NotesDatabase.open(factory, inMemoryDatabasePath);
    final sync = SyncService(NotesStore(db));
    await sync.init();
    expect(sync.status, SyncStatus.notConfigured);
    await db.close();
  });
}
