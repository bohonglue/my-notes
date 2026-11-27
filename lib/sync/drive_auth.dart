import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

/// Google 登入。用 OAuth「電腦版應用程式」用戶端 + 本機回呼（loopback），
/// Android 和 Windows 都走同一套流程：開瀏覽器登入，登入完回到 app。
///
/// 用戶端 ID 和密鑰在建置時用 --dart-define 帶入（GitHub Actions 從 secrets 讀）。
/// 桌面版用戶端的「密鑰」依 Google 文件並不算機密，只是識別用。
class DriveAuth {
  DriveAuth({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();

  static const clientIdValue = String.fromEnvironment('GOOGLE_CLIENT_ID');
  static const clientSecretValue = String.fromEnvironment('GOOGLE_CLIENT_SECRET');
  static const scopes = [drive.DriveApi.driveAppdataScope, 'email'];
  static const _key = 'google_credentials';

  final FlutterSecureStorage _storage;
  AutoRefreshingAuthClient? _client;
  String? email;

  static bool get configured => clientIdValue.isNotEmpty;

  /// 這個版本能不能同步（測試時可覆寫）。
  bool get isConfigured => configured;

  ClientId get _clientId => ClientId(clientIdValue, clientSecretValue.isEmpty ? null : clientSecretValue);

  bool get signedIn => _client != null;


  /// 用存起來的憑證恢復登入狀態。回傳是否成功。
  Future<bool> restore() async {
    if (!configured) return false;
    final raw = await _storage.read(key: _key);
    if (raw == null) return false;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final creds = AccessCredentials.fromJson(j['credentials'] as Map<String, dynamic>);
      email = j['email'] as String?;
      _use(autoRefreshingClient(_clientId, creds, http.Client()));
      return true;
    } catch (_) {
      await _storage.delete(key: _key);
      return false;
    }
  }

  /// 開瀏覽器讓使用者登入 Google。
  Future<void> signIn() async {
    if (!configured) {
      throw StateError('這個版本沒有設定 Google 用戶端 ID，無法同步');
    }
    final base = http.Client();
    final creds = await obtainAccessCredentialsViaUserConsent(
      _clientId,
      scopes,
      base,
      (url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      customPostAuthPage: _donePage,
    );
    email = await _fetchEmail(creds, base);
    _use(autoRefreshingClient(_clientId, creds, base));
    await _persist(creds);
  }

  Future<void> signOut() async {
    _client?.close();
    _client = null;
    email = null;
    await _storage.delete(key: _key);
  }

  http.Client get client {
    final c = _client;
    if (c == null) throw StateError('尚未登入 Google');
    return c;
  }

  void _use(AutoRefreshingAuthClient c) {
    _client?.close();
    _client = c;
    c.credentialUpdates.listen(_persist);
  }

  Future<void> _persist(AccessCredentials creds) => _storage.write(
        key: _key,
        value: jsonEncode({'credentials': creds.toJson(), 'email': email}),
      );

  static Future<String?> _fetchEmail(AccessCredentials creds, http.Client base) async {
    try {
      final r = await base.get(
        Uri.parse('https://www.googleapis.com/oauth2/v3/userinfo'),
        headers: {'Authorization': 'Bearer ${creds.accessToken.data}'},
      );
      if (r.statusCode != 200) return null;
      return (jsonDecode(r.body) as Map<String, dynamic>)['email'] as String?;
    } catch (_) {
      return null;
    }
  }

  static const _donePage = '''<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>登入完成</title></head>
<body style="font-family:sans-serif;text-align:center;padding:48px 16px">
<h2>登入完成</h2><p>可以關掉這個分頁，回到「我的筆記」。</p></body></html>''';
}
