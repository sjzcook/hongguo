import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/user_profile.dart';

/// 认证失败的分类，UI 按类型给不同文案。
enum AuthErrorKind { network, invalid, throttled, unsupported, unknown }

class AuthException implements Exception {
  const AuthException(this.message, {this.kind = AuthErrorKind.unknown});

  final String message;
  final AuthErrorKind kind;

  @override
  String toString() => message;
}

class AuthSession {
  const AuthSession({required this.token, required this.profile});

  final String token;
  final UserProfile profile;
}

/// 认证能力抽象。客户端只连接已配置的真实网关认证，不提供本地伪造登录。
abstract class AuthService {
  /// 认证方式标识：demo / gateway。
  String get mode;

  /// 展示名，如「演示模式」。
  String get label;

  /// 登录页底部的一行说明。
  String get hint;

  /// 发验证码。返回调试用验证码（网关可下发），没有则返回 null。
  Future<String?> sendCode(String phone);

  Future<AuthSession> login({required String phone, required String code});

  Future<UserProfile> fetchProfile(String token);

  Future<void> logout(String token);

  void dispose();
}

/// 手机号基本格式校验：大陆 11 位。
bool isValidPhone(String phone) =>
    RegExp(r'^1[3-9]\d{9}$').hasMatch(phone.trim());

bool isValidCode(String code) => RegExp(r'^\d{4,6}$').hasMatch(code.trim());

/// 对接自建网关的认证实现。
///
/// 协议（见 README）：
/// ```
/// POST /auth/sms      {"phone": "13800138000"}          -> {"code":0,"data":{"sent":true,"debug_code":"123456"}}
/// POST /auth/login    {"phone": "...", "code": "..."}   -> {"code":0,"data":{"token":"...","user":{...}}}
/// GET  /auth/profile  Authorization: Bearer <token>     -> {"code":0,"data":{...}}
/// POST /auth/logout   Authorization: Bearer <token>     -> {"code":0}
/// ```
class GatewayAuthService implements AuthService {
  GatewayAuthService({
    required this.baseUrl,
    this.apiKey = '',
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final String apiKey;
  final http.Client _client;

  static const _timeout = Duration(seconds: 12);

  @override
  String get mode => 'gateway';

  @override
  String get label => '自建网关';

  @override
  String get hint => '验证码由网关下发，演示网关默认 123456';

  Map<String, String> get _baseHeaders => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (apiKey.isNotEmpty) 'X-API-Key': apiKey,
      };

  Uri _uri(String path) =>
      Uri.parse('${baseUrl.replaceAll(RegExp(r'/+$'), '')}$path');

  @override
  Future<String?> sendCode(String phone) async {
    if (!isValidPhone(phone)) {
      throw const AuthException('请输入正确的手机号', kind: AuthErrorKind.invalid);
    }
    final data = await _post('/auth/sms', {'phone': phone.trim()});
    final debug = data['debug_code'];
    return debug == null ? null : '$debug';
  }

  @override
  Future<AuthSession> login({
    required String phone,
    required String code,
  }) async {
    if (!isValidPhone(phone)) {
      throw const AuthException('请输入正确的手机号', kind: AuthErrorKind.invalid);
    }
    if (!isValidCode(code)) {
      throw const AuthException('请输入正确的验证码', kind: AuthErrorKind.invalid);
    }
    final data = await _post('/auth/login', {
      'phone': phone.trim(),
      'code': code.trim(),
    });
    final token = '${data['token'] ?? ''}';
    if (token.isEmpty) {
      throw const AuthException('网关未返回登录凭证');
    }
    final rawUser = data['user'] ?? data['profile'];
    final profile = rawUser is Map<String, dynamic>
        ? UserProfile.fromJson(rawUser, mode: mode)
        : UserProfile(uid: token, nickname: '果友', phone: phone, mode: mode);
    return AuthSession(token: token, profile: profile);
  }

  @override
  Future<UserProfile> fetchProfile(String token) async {
    final resp = await _send(
      () => _client.get(
        _uri('/auth/profile'),
        headers: {..._baseHeaders, 'Authorization': 'Bearer $token'},
      ).timeout(_timeout),
    );
    final data = _unwrap(resp);
    if (data is! Map<String, dynamic>) {
      throw const AuthException('账号信息格式异常');
    }
    return UserProfile.fromJson(data, mode: mode);
  }

  @override
  Future<void> logout(String token) async {
    try {
      await _send(
        () => _client.post(
          _uri('/auth/logout'),
          headers: {..._baseHeaders, 'Authorization': 'Bearer $token'},
        ).timeout(_timeout),
      );
    } catch (_) {
      // 退出以本地清理为准，网关不可达时不阻塞用户。
    }
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final resp = await _send(
      () => _client
          .post(_uri(path), headers: _baseHeaders, body: jsonEncode(body))
          .timeout(_timeout),
    );
    final data = _unwrap(resp);
    if (data is Map<String, dynamic>) return data;
    return const {};
  }

  Future<http.Response> _send(Future<http.Response> Function() run) async {
    http.Response resp;
    try {
      resp = await run();
    } on TimeoutException {
      throw const AuthException('请求超时，请检查网络', kind: AuthErrorKind.network);
    } catch (e) {
      throw AuthException('网络请求失败：$e', kind: AuthErrorKind.network);
    }
    if (resp.statusCode == 429) {
      throw const AuthException('请求过于频繁，请稍后再试',
          kind: AuthErrorKind.throttled);
    }
    if (resp.statusCode == 401 || resp.statusCode == 403) {
      throw const AuthException('验证码错误或登录已失效',
          kind: AuthErrorKind.invalid);
    }
    if (resp.statusCode != 200) {
      throw AuthException('网关返回 ${resp.statusCode}');
    }
    return resp;
  }

  dynamic _unwrap(http.Response resp) {
    if (resp.bodyBytes.isEmpty) {
      throw const AuthException('网关响应为空');
    }
    final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
    if (decoded is Map<String, dynamic>) {
      final code = decoded['code'];
      if (code is int && code != 0) {
        throw AuthException('${decoded['message'] ?? '认证失败'}');
      }
      return decoded['data'] ?? decoded;
    }
    return decoded;
  }

  @override
  void dispose() => _client.close();
}
