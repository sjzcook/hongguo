import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../data/auth/auth_service.dart';
import '../../state/app_state.dart';

/// 手机号 + 验证码登录页。
///
/// 认证方式跟随全局配置：配置了网关就走网关（`/auth/*`），
/// 否则使用完全离线的演示认证（验证码 123456）。
class LoginPage extends StatefulWidget {
  const LoginPage({super.key, this.reason});

  /// 从门禁处跳转时带上原因，例如「登录后可看第 12 集」。
  final String? reason;

  static Future<bool> show(BuildContext context, {String? reason}) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => LoginPage(reason: reason),
        fullscreenDialog: true,
      ),
    );
    return result ?? false;
  }

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _codeFocus = FocusNode();

  bool _agreed = true;
  bool _sending = false;
  bool _submitting = false;
  String? _error;
  int _countdown = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _phone.dispose();
    _code.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      isValidPhone(_phone.text) &&
      isValidCode(_code.text) &&
      _agreed &&
      !_submitting;

  void _startCountdown() {
    _timer?.cancel();
    setState(() => _countdown = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _countdown -= 1);
      if (_countdown <= 0) t.cancel();
    });
  }

  Future<void> _sendCode() async {
    if (_sending || _countdown > 0) return;
    final app = context.read<AppState>();
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final debug = await app.sendLoginCode(_phone.text);
      if (!mounted) return;
      setState(() => _sending = false);
      _startCountdown();
      _codeFocus.requestFocus();
      _toast(debug == null ? '验证码已发送' : '验证码已发送：$debug');
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = e.message;
      });
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!_agreed) {
      setState(() => _error = '请先阅读并同意用户协议与隐私政策');
      return;
    }
    final app = context.read<AppState>();
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await app.login(phone: _phone.text.trim(), code: _code.text.trim());
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = '$e';
      });
    }
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _showTerms(String title, String body) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceHigh,
        title: Text(title, style: const TextStyle(fontSize: 16)),
        content: Text(
          body,
          style: const TextStyle(
            fontSize: 13,
            height: 1.7,
            color: AppColors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    return Scaffold(
      backgroundColor: AppColors.bg,
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          // 顶部暖色光晕，弱化纯黑背景的空洞感。
          Positioned(
            top: -180,
            left: -80,
            right: -80,
            child: Container(
              height: 420,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    AppColors.primary.withValues(alpha: 0.30),
                    AppColors.primary.withValues(alpha: 0.06),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.45, 1.0],
                ),
              ),
            ),
          ),
          SafeArea(
            child: GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.of(context).maybePop(),
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: AppColors.surfaceHigh,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close,
                                size: 18, color: AppColors.textSecondary),
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceHigh,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                app.authMode == 'gateway'
                                    ? Icons.dns_outlined
                                    : Icons.science_outlined,
                                size: 12,
                                color: AppColors.textTertiary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                app.authLabel,
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  color: AppColors.textTertiary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 34),
                    const _Logo(),
                    const SizedBox(height: 22),
                    const Text(
                      '登录红果短剧',
                      style: TextStyle(
                        fontSize: 27,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.reason ?? '登录后解锁全部剧集，收藏与进度云端同步',
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 30),
                    _InputRow(
                      child: Row(
                        children: [
                          const Text(
                            '+86',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            width: 0.7,
                            height: 18,
                            color: AppColors.divider,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _phone,
                              keyboardType: TextInputType.phone,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(11),
                              ],
                              style: const TextStyle(
                                fontSize: 15.5,
                                letterSpacing: 0.6,
                              ),
                              decoration: const InputDecoration(
                                isDense: true,
                                filled: false,
                                border: InputBorder.none,
                                hintText: '请输入手机号',
                                hintStyle: TextStyle(
                                  fontSize: 14.5,
                                  color: AppColors.textTertiary,
                                ),
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _InputRow(
                      child: Row(
                        children: [
                          const Icon(Icons.lock_outline,
                              size: 17, color: AppColors.textTertiary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _code,
                              focusNode: _codeFocus,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(6),
                              ],
                              style: const TextStyle(
                                fontSize: 15.5,
                                letterSpacing: 2,
                              ),
                              decoration: const InputDecoration(
                                isDense: true,
                                filled: false,
                                border: InputBorder.none,
                                hintText: '验证码',
                                hintStyle: TextStyle(
                                  fontSize: 14.5,
                                  letterSpacing: 0,
                                  color: AppColors.textTertiary,
                                ),
                              ),
                              onChanged: (_) => setState(() {}),
                              onSubmitted: (_) {
                                if (_canSubmit) _submit();
                              },
                            ),
                          ),
                          TextButton(
                            onPressed: _countdown > 0
                                ? null
                                : (_sending ? null : _sendCode),
                            style: TextButton.styleFrom(
                              minimumSize: const Size(0, 34),
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 10),
                              tapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              _countdown > 0
                                  ? '${_countdown}s 后重发'
                                  : (_sending ? '发送中…' : '获取验证码'),
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: _countdown > 0
                                    ? AppColors.textTertiary
                                    : AppColors.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 180),
                      alignment: Alignment.topLeft,
                      child: _error == null
                          ? const SizedBox(width: double.infinity)
                          : Padding(
                              padding: const EdgeInsets.only(top: 10, left: 4),
                              child: Row(
                                children: [
                                  const Icon(Icons.error_outline,
                                      size: 13, color: AppColors.primary),
                                  const SizedBox(width: 5),
                                  Expanded(
                                    child: Text(
                                      _error!,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    ),
                    const SizedBox(height: 22),
                    _SubmitButton(
                      enabled: _canSubmit,
                      loading: _submitting,
                      onTap: _submit,
                    ),
                    const SizedBox(height: 16),
                    _Agreement(
                      agreed: _agreed,
                      onChanged: (v) => setState(() => _agreed = v),
                      onOpenTerms: () => _showTerms(
                        '用户协议',
                        '本项目为 Flutter 学习示例，登录仅用于建立与你自己所配置网关的会话。\n\n'
                            '你需保证所使用的数据来源合法合规，不将本客户端用于商业用途、'
                            '批量抓取或任何侵犯第三方权益的行为。',
                      ),
                      onOpenPrivacy: () => _showTerms(
                        '隐私政策',
                        '客户端仅在本机保存：登录凭证（网关下发的 token）、手机号后四位、昵称与头像地址。\n\n'
                            '不采集通讯录、位置、设备标识；不上传观看记录；退出登录会立即清除本地凭证。\n\n'
                            '若接入自建网关，账号信息的处理方式由该网关的运营方负责。',
                      ),
                    ),
                    const SizedBox(height: 28),
                    Center(
                      child: TextButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text(
                          '先随便逛逛',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.info_outline,
                              size: 12, color: AppColors.textTertiary),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              app.authHint,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 11,
                                height: 1.5,
                                color: AppColors.textTertiary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 74,
      height: 74,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFF6A4D), AppColors.primaryDeep],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.35),
            blurRadius: 26,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: const Icon(Icons.play_arrow_rounded, size: 44, color: Colors.white),
    );
  }
}

class _InputRow extends StatelessWidget {
  const _InputRow({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider, width: 0.8),
      ),
      child: Center(child: child),
    );
  }
}

class _SubmitButton extends StatelessWidget {
  const _SubmitButton({
    required this.enabled,
    required this.loading,
    required this.onTap,
  });

  final bool enabled;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 50,
        decoration: BoxDecoration(
          gradient: enabled
              ? const LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryDeep],
                )
              : null,
          color: enabled ? null : AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(25),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.28),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Center(
          child: loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(
                  '登录',
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: enabled
                        ? Colors.white
                        : AppColors.textTertiary,
                  ),
                ),
        ),
      ),
    );
  }
}

class _Agreement extends StatelessWidget {
  const _Agreement({
    required this.agreed,
    required this.onChanged,
    required this.onOpenTerms,
    required this.onOpenPrivacy,
  });

  final bool agreed;
  final ValueChanged<bool> onChanged;
  final VoidCallback onOpenTerms;
  final VoidCallback onOpenPrivacy;

  @override
  Widget build(BuildContext context) {
    const linkStyle = TextStyle(fontSize: 11.5, color: AppColors.gold);
    const textStyle =
        TextStyle(fontSize: 11.5, color: AppColors.textTertiary);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => onChanged(!agreed),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.only(top: 1, right: 7),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 15,
              height: 15,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: agreed ? AppColors.primary : Colors.transparent,
                border: Border.all(
                  color: agreed ? AppColors.primary : AppColors.textTertiary,
                  width: 1.2,
                ),
              ),
              child: agreed
                  ? const Icon(Icons.check, size: 10, color: Colors.white)
                  : null,
            ),
          ),
        ),
        Expanded(
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('我已阅读并同意 ', style: textStyle),
              GestureDetector(
                onTap: onOpenTerms,
                child: const Text('《用户协议》', style: linkStyle),
              ),
              const Text(' 与 ', style: textStyle),
              GestureDetector(
                onTap: onOpenPrivacy,
                child: const Text('《隐私政策》', style: linkStyle),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
