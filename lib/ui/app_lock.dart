import 'dart:io';

import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:provider/provider.dart';

import '../state/settings_store.dart';

/// 用指紋、臉、手機螢幕鎖（Android）或 Windows Hello（電腦）解鎖。
class DeviceAuth {
  DeviceAuth([LocalAuthentication? auth]) : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  static String get methodName => Platform.isWindows ? 'Windows Hello' : '指紋或螢幕鎖';

  Future<bool> isSupported() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  /// 回傳 null 代表成功；否則回傳要顯示的錯誤訊息（使用者取消時回傳空字串）。
  Future<String?> authenticate() async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: '解鎖「我的筆記」',
        persistAcrossBackgrounding: true,
      );
      return ok ? null : '';
    } on LocalAuthException catch (e) {
      return switch (e.code) {
        LocalAuthExceptionCode.userCanceled ||
        LocalAuthExceptionCode.systemCanceled ||
        LocalAuthExceptionCode.timeout ||
        LocalAuthExceptionCode.authInProgress =>
          '',
        LocalAuthExceptionCode.noCredentialsSet ||
        LocalAuthExceptionCode.noBiometricHardware ||
        LocalAuthExceptionCode.noBiometricsEnrolled =>
          '這台裝置沒有設定$methodName，請先到系統設定裡設定',
        LocalAuthExceptionCode.temporaryLockout || LocalAuthExceptionCode.biometricLockout =>
          '嘗試太多次，請稍後再試，或用螢幕鎖密碼解鎖',
        _ => '解鎖失敗：${e.description ?? e.code.name}',
      };
    } catch (e) {
      return '解鎖失敗：$e';
    }
  }
}

/// 包在整個 app 外面：上鎖時蓋上一層解鎖畫面，筆記內容不會露出來。
/// 解鎖後回到原本的畫面（正在編輯的筆記不會關掉）。
class AppLock extends StatefulWidget {
  const AppLock({super.key, required this.child, this.auth});

  final Widget child;
  final DeviceAuth? auth;

  @override
  State<AppLock> createState() => _AppLockState();
}

class _AppLockState extends State<AppLock> {
  late final DeviceAuth _auth = widget.auth ?? DeviceAuth();
  late final AppLifecycleListener _lifecycle;
  late bool _locked;
  bool _authenticating = false;
  DateTime? _backgroundSince;
  String? _error;

  @override
  void initState() {
    super.initState();
    _locked = context.read<SettingsStore>().lockEnabled;
    _lifecycle = AppLifecycleListener(onHide: _onHide, onShow: _onShow);
    if (_locked) WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _onHide() {
    // 解鎖對話框本身也會讓 app 暫時進背景，那不算。
    if (_authenticating) return;
    _backgroundSince ??= DateTime.now();
  }

  void _onShow() {
    final since = _backgroundSince;
    _backgroundSince = null;
    if (_authenticating || since == null || _locked) return;
    final settings = context.read<SettingsStore>();
    if (!settings.lockEnabled) return;
    if (DateTime.now().difference(since) >= settings.lockAfter) {
      setState(() => _locked = true);
      _unlock();
    }
  }

  Future<void> _unlock() async {
    if (_authenticating) return;
    setState(() {
      _authenticating = true;
      _error = null;
    });
    final err = await _auth.authenticate();
    if (!mounted) return;
    setState(() {
      _authenticating = false;
      if (err == null) {
        _locked = false;
      } else {
        _error = err.isEmpty ? null : err;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 上鎖時不畫出底下的內容，也不讓它接收觸控或鍵盤。
        Offstage(offstage: _locked, child: TickerMode(enabled: !_locked, child: widget.child)),
        if (_locked) _LockScreen(busy: _authenticating, error: _error, onUnlock: _unlock),
      ],
    );
  }
}

class _LockScreen extends StatelessWidget {
  const _LockScreen({required this.busy, required this.error, required this.onUnlock});

  final bool busy;
  final String? error;
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline, size: 64, color: theme.colorScheme.primary),
                const SizedBox(height: 16),
                Text('我的筆記已上鎖', style: theme.textTheme.titleLarge),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: busy ? null : onUnlock,
                  icon: Icon(Platform.isWindows ? Icons.face_outlined : Icons.fingerprint),
                  label: Text('用${DeviceAuth.methodName}解鎖'),
                ),
                if (error != null) ...[
                  const SizedBox(height: 16),
                  Text(error!, textAlign: TextAlign.center, style: TextStyle(color: theme.colorScheme.error)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
