import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../state/app_state.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('设置', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 32),
        children: [
          const _SectionTitle('站源'),
          ...app.sourceOptions.map((s) => _SourceTile(option: s, app: app)),
          const SizedBox(height: 20),
          const _SectionTitle('播放'),
          _SettingTile(
            title: '自动连播',
            subtitle: '一集播完自动进入下一集',
            trailing: Switch(
              value: app.autoPlay,
              activeThumbColor: AppColors.primary,
              onChanged: (v) => app.setAutoPlay(v),
            ),
          ),
          _SettingTile(
            title: '播放速度',
            subtitle: '默认 ${app.speed}x',
            trailing: DropdownButton<double>(
              value: app.speed,
              underline: const SizedBox.shrink(),
              dropdownColor: AppColors.surfaceHigh,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textPrimary,
              ),
              items: const [0.75, 1.0, 1.25, 1.5, 2.0]
                  .map((s) => DropdownMenuItem(value: s, child: Text('${s}x')))
                  .toList(),
              onChanged: (v) {
                if (v != null) app.setSpeed(v);
              },
            ),
          ),
          const SizedBox(height: 20),
          const _SectionTitle('数据'),
          _SettingTile(
            title: '清空观看历史',
            subtitle: '共 ${app.history.length} 条记录',
            trailing: TextButton(
              onPressed: () => _confirmClear(context, app),
              child: const Text('清空',
                  style: TextStyle(fontSize: 13, color: AppColors.primary)),
            ),
          ),
          const SizedBox(height: 20),
          const _SectionTitle('关于'),
          const _SettingTile(
            title: '版本',
            subtitle: '红果短剧 Flutter 1.0.0',
            trailing: Text(
              'Flutter 3.47',
              style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 15, color: AppColors.gold),
                    SizedBox(width: 6),
                    Text('免责声明',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                ),
                SizedBox(height: 8),
                Text(
                  '本项目为学习 Flutter 而写的第三方客户端示例，与红果短剧官方无任何关联。'
                  '内置演示站源仅用于功能调试，不提供任何官方内容。'
                  '接入真实站源时请遵守平台用户协议与当地法律法规，'
                  '不得用于商业用途或大规模抓取。',
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.65,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context, AppState app) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceHigh,
        title: const Text('清空观看历史', style: TextStyle(fontSize: 16)),
        content: const Text('清空后断点续播记录将无法恢复，确定继续？',
            style: TextStyle(fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空',
                style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
    if (ok == true) await app.clearHistory();
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({required this.option, required this.app});

  final SourceOption option;
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final active = app.source.id == option.id;
    return InkWell(
      onTap: option.ready
          ? () => app.switchSource(option.id)
          : () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('该站源需要先配置网关地址，见 README'),
                ),
              ),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: active
                    ? AppColors.primary.withValues(alpha: 0.16)
                    : AppColors.surfaceHigh,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(
                option.id == 'hongguo' ? Icons.play_circle_fill : Icons.movie_filter,
                size: 18,
                color: active ? AppColors.primary : AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(option.name,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w500)),
                      if (!option.ready) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceHigher,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('未配置',
                              style: TextStyle(
                                  fontSize: 9.5, color: AppColors.textTertiary)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(option.description,
                      style: const TextStyle(
                          fontSize: 11.5, color: AppColors.textTertiary)),
                ],
              ),
            ),
            if (active)
              const Icon(Icons.check_circle,
                  size: 19, color: AppColors.primary),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, left: 2),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.textTertiary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _SettingTile extends StatelessWidget {
  const _SettingTile({
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: const TextStyle(
                        fontSize: 11.5, color: AppColors.textTertiary)),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
