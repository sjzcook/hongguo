/// Values recovered from MiniReel-0.3.2's assets/config/sources.json.
///
/// Keep the upstream playback endpoint configurable: endpoint availability and
/// response shape can change independently of the Flutter client.
class HongguoGatewayConfig {
  HongguoGatewayConfig._();

  static const enabled = true;
  static const websiteBaseUrl = 'https://hongguoduanju.com';
  static const playbackEndpoint = String.fromEnvironment(
    'HONGGUO_PLAYBACK_ENDPOINT',
    defaultValue: 'https://djapi.999888456.xyz/api/hongguo/play',
  );
  static const referer = 'https://hongguoduanju.com/';
  static const mediaReferer = 'https://novel.snssdk.com/';
  static const maxPages = 20;
  static const pageSize = 24;
  static const timeoutSeconds = 12;
  static const retries = 3;
  static const appBaseUrl =
      'https://api5-normal-sinfonlineb.fqnovel.com';
  static const appUserAgent =
      'com.phoenix.read/73532 (Linux; U; Android 16; zh_CN; 25053RT47C; Build/BP2A.250605.031.A3; Cronet/TTNetVersion:04657795 2026-01-23 QuicVersion:c67e9834 2025-09-08)';

  /// Static app/device parameters from the packaged configuration.
  /// These are configuration values, not a guarantee that upstream requests
  /// will be accepted; private signing/session requirements may still apply.
  static const appParameters = <String, String>{
    'app_name': 'novelread',
    'os_version': '16',
    'ac': 'wifi',
    'version_code': '73532',
    'update_version_code': '73532',
    'manifest_version_code': '73532',
    'aid': '8662',
    'os_api': '36',
    'resolution': '1280*2772',
    'ssmix': 'a',
    'language': 'zh',
    'device_brand': 'Redmi',
    'device_type': '25053RT47C',
    'dpi': '520',
    'version_name': '7.3.5.32',
    'device_platform': 'android',
    'channel': 'update_64',
    'os': 'android',
  };
}
