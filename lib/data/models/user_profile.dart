import 'dart:convert';

/// 登录后的账号信息。
///
/// 字段名同时兼容网关的多种写法（`uid`/`user_id`、`nickname`/`name`），
/// 这样自建网关不用为了迁就客户端改字段。
class UserProfile {
  const UserProfile({
    required this.uid,
    required this.nickname,
    this.avatar = '',
    this.phone = '',
    this.vipLevel = 0,
    this.expiresAt,
    this.mode = 'demo',
  });

  final String uid;
  final String nickname;
  final String avatar;
  final String phone;
  final int vipLevel;
  final DateTime? expiresAt;

  /// 认证方式：`demo` 本地演示 / `gateway` 自建网关。
  final String mode;

  bool get isVip => vipLevel > 0;

  bool get isExpired {
    final e = expiresAt;
    return e != null && e.isBefore(DateTime.now());
  }

  String get maskedPhone {
    if (phone.length < 7) return phone;
    return '${phone.substring(0, 3)}****${phone.substring(phone.length - 4)}';
  }

  /// 昵称首字，没有头像时用作占位。
  String get initial => nickname.isEmpty ? '果' : nickname.substring(0, 1);

  String get modeLabel => mode == 'gateway' ? '网关账号' : '演示账号';

  factory UserProfile.fromJson(
    Map<String, dynamic> json, {
    String mode = 'gateway',
  }) {
    final rawVip = json['vip_level'] ?? json['vipLevel'] ?? json['is_vip'] ?? 0;
    final vip = rawVip is bool
        ? (rawVip ? 1 : 0)
        : (int.tryParse('$rawVip') ?? 0);
    final rawExpire =
        json['vip_expire'] ?? json['vip_expire_at'] ?? json['expires_at'];
    return UserProfile(
      uid: '${json['uid'] ?? json['user_id'] ?? json['id'] ?? ''}',
      nickname:
          '${json['nickname'] ?? json['name'] ?? json['nick_name'] ?? '果友'}',
      avatar:
          '${json['avatar'] ?? json['avatar_url'] ?? json['head_url'] ?? ''}',
      phone: '${json['phone'] ?? json['mobile'] ?? ''}',
      vipLevel: vip,
      expiresAt: _parseTime(rawExpire),
      mode: '${json['mode'] ?? mode}',
    );
  }

  factory UserProfile.fromStorage(String raw) => UserProfile.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'nickname': nickname,
        'avatar': avatar,
        'phone': phone,
        'vip_level': vipLevel,
        'expires_at': expiresAt?.toIso8601String(),
        'mode': mode,
      };

  String encode() => jsonEncode(toJson());

  static DateTime? _parseTime(dynamic value) {
    if (value == null) return null;
    if (value is int) {
      // 秒级时间戳常见于网关；毫秒级做一次容错。
      if (value > 1000000000000) {
        return DateTime.fromMillisecondsSinceEpoch(value);
      }
      if (value > 1000000000) {
        return DateTime.fromMillisecondsSinceEpoch(value * 1000);
      }
      return null;
    }
    return DateTime.tryParse('$value');
  }
} 
