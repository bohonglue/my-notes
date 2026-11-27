import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:my_notes/data/database.dart';
import 'package:my_notes/state/settings_store.dart';
import 'package:my_notes/ui/app_lock.dart';
import 'package:my_notes/update/update_service.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class FakeDeviceAuth extends DeviceAuth {
  FakeDeviceAuth(this.results);
  final List<String?> results;
  int calls = 0;

  @override
  Future<bool> isSupported() async => true;

  @override
  Future<String?> authenticate() async => results[calls++];
}

Map<String, dynamic> _release(String tag) => {
      'tag_name': tag,
      'body': '新增功能',
      'assets': [
        {'name': 'my-notes-windows-1.0.9.zip', 'browser_download_url': 'https://x/w.zip'},
        {'name': 'my-notes-1.0.9.apk', 'browser_download_url': 'https://x/a.apk'},
      ],
    };

void main() {
  setUpAll(sqfliteFfiInit);

  group('更新', () {
    test('解析 release，依平台挑對的安裝檔', () {
      final apk = UpdateService.parseRelease(_release('v1.0.9'), '.apk')!;
      expect((apk.version, apk.build, apk.assetUrl.toString()), ('1.0.9', 9, 'https://x/a.apk'));
      final zip = UpdateService.parseRelease(_release('v1.0.9'), '.zip')!;
      expect(zip.assetUrl.toString(), 'https://x/w.zip');
      expect(UpdateService.parseRelease(_release('nightly'), '.apk'), isNull);
    });

    UpdateService service(http.Response Function() respond, int current) =>
        UpdateService(client: MockClient((_) async => respond()))
          ..currentBuild = current
          ..currentVersion = '1.0.$current';

    test('有比較新的版本才算有更新', () async {
      final body = utf8.encode(jsonEncode(_release('v1.0.9')));
      final older = service(() => http.Response.bytes(body, 200), 5);
      expect(await older.check(), isNotNull, reason: older.error);
      expect(older.state, UpdateState.available);

      final same = service(() => http.Response.bytes(body, 200), 9);
      expect(await same.check(), isNull);
      expect(same.state, UpdateState.upToDate);
    });

    test('還沒發佈過任何版本（404）時顯示已是最新；網路錯誤時顯示錯誤', () async {
      final none = service(() => http.Response('', 404), 1);
      await none.check();
      expect(none.state, UpdateState.upToDate);

      final broken = service(() => http.Response('oops', 500), 1);
      await broken.check();
      expect(broken.state, UpdateState.error);
      await broken.check(silent: true);
      expect(broken.state, UpdateState.idle);
    });
  });

  group('解鎖', () {
    late NotesDatabase db;
    late SettingsStore settings;

    setUp(() async {
      db = await NotesDatabase.open(databaseFactoryFfiNoIsolate, inMemoryDatabasePath);
      settings = SettingsStore(db);
    });

    tearDown(() => db.close());

    Widget app(DeviceAuth auth) => ChangeNotifierProvider.value(
          value: settings,
          child: MaterialApp(
            builder: (context, child) => AppLock(auth: auth, child: child!),
            home: const Scaffold(body: Text('秘密筆記')),
          ),
        );

    testWidgets('沒開啟上鎖時直接顯示內容', (tester) async {
      final auth = FakeDeviceAuth([]);
      await tester.pumpWidget(app(auth));
      await tester.pumpAndSettle();
      expect(find.text('秘密筆記'), findsOneWidget);
      expect(auth.calls, 0);
    });

    testWidgets('開啟上鎖時先蓋住內容，取消後還是鎖著，解鎖成功才顯示', (tester) async {
      await tester.runAsync(() => settings.setLockEnabled(true));
      final auth = FakeDeviceAuth(['', null]);
      await tester.pumpWidget(app(auth));
      await tester.pumpAndSettle();
      // 開啟時自動跳出一次解鎖，使用者取消
      expect(auth.calls, 1);
      expect(find.text('我的筆記已上鎖'), findsOneWidget);
      expect(find.text('秘密筆記'), findsNothing);

      await tester.tap(find.textContaining('解鎖').last);
      await tester.pumpAndSettle();
      expect(auth.calls, 2);
      expect(find.text('秘密筆記'), findsOneWidget);
      expect(find.text('我的筆記已上鎖'), findsNothing);
    });

    testWidgets('解鎖失敗時顯示原因', (tester) async {
      await tester.runAsync(() => settings.setLockEnabled(true));
      final auth = FakeDeviceAuth(['這台裝置沒有設定指紋或螢幕鎖，請先到系統設定裡設定']);
      await tester.pumpWidget(app(auth));
      await tester.pumpAndSettle();
      expect(find.textContaining('這台裝置沒有設定'), findsOneWidget);
    });
  });
}
