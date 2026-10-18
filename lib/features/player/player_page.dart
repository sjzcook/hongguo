import 'dart:async';

import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/drama.dart';
import '../../state/app_state.dart';
import '../../widgets/drama_cover.dart';
import '../login/login_page.dart';

/// 竖屏播放器：上滑下一集、单击唤出控制栏、进度自动续播。
class PlayerPage extends StatefulWidget {
  const PlayerPage({
    super.key,
    required this.drama,
    required this.episodes,
    this.initialIndex = 1,
    this.startPosition = Duration.zero,
  });

  final Drama drama;
  final List<Episode> episodes;
  final int initialIndex;
  final Duration startPosition;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  VideoPlayerController? _controller;

  /// 播放器在 dispose 时还要落盘一次进度，不能再用 context，先把状态存下来。
  late final AppState _app;

  late int _index;
  bool _controlsVisible = true;
  bool _initializing = true;
  String? _error;
  Timer? _saveTimer;
  Timer? _hideTimer;

  static const _speeds = [0.75, 1.0, 1.25, 1.5, 2.0];

  Episode get _episode => widget.episodes[_index - 1];

  bool get _platformSupported {
    if (kIsWeb) return true;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }

  @override
  void initState() {
    super.initState();
    _app = context.read<AppState>();
    _index = widget.initialIndex.clamp(1, widget.episodes.length);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _openEpisode(_index, position: widget.startPosition);
    _saveTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _persistProgress(),
    );
    _scheduleHide();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _hideTimer?.cancel();
    _persistProgress();
    _controller?.dispose();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _openEpisode(int index, {Duration position = Duration.zero}) async {
    final old = _controller;
    setState(() {
      _index = index.clamp(1, widget.episodes.length);
      _initializing = true;
      _error = null;
    });

    // 付费集且未登录：不加载视频，直接展示登录门禁。
    if (!_app.canWatch(_episode)) {
      await old?.dispose();
      if (!mounted) return;
      setState(() {
        _controller = null;
        _initializing = false;
      });
      _scheduleHide();
      return;
    }

    if (!_platformSupported) {
      await old?.dispose();
      if (!mounted) return;
      setState(() {
        _controller = null;
        _initializing = false;
      });
      return;
    }

    final url = _episode.videoUrl;
    if (url.isEmpty) {
      await old?.dispose();
      if (!mounted) return;
      setState(() {
        _controller = null;
        _initializing = false;
        _error = '该集暂无播放地址';
      });
      return;
    }

    try {
      final controller = VideoPlayerController.networkUrl(Uri.parse(url));
      await controller.initialize();
      await controller.setLooping(false);
      if (position > Duration.zero) {
        await controller.seekTo(position);
      }
      final speed = _app.speed;
      await controller.setPlaybackSpeed(speed);
      await controller.play();
      controller.addListener(_onPlayerTick);

      await old?.dispose();
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _initializing = false;
      });
    } catch (e) {
      await old?.dispose();
      if (!mounted) return;
      setState(() {
        _controller = null;
        _initializing = false;
        _error = '播放失败：$e';
      });
    }
  }

  void _onPlayerTick() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (c.value.hasError) {
      setState(() => _error = c.value.errorDescription ?? '播放出错');
      return;
    }
    final v = c.value;
    if (v.duration.inMilliseconds > 0 &&
        v.position >= v.duration - const Duration(milliseconds: 350)) {
      if (_app.autoPlay && _index < widget.episodes.length) {
        _next();
      }
    }
  }

  void _persistProgress() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final v = c.value;
    if (v.position.inMilliseconds <= 0) return;
    _app.saveProgress(
          drama: widget.drama,
          episodeIndex: _index,
          position: v.position,
          duration: v.duration,
        );
  }

  void _next() {
    if (_index >= widget.episodes.length) {
      _toast('已经是最后一集了');
      return;
    }
    _persistProgress();
    _openEpisode(_index + 1);
    _scheduleHide();
  }

  void _prev() {
    if (_index <= 1) {
      _toast('已经是第一集了');
      return;
    }
    _persistProgress();
    _openEpisode(_index - 1);
    _scheduleHide();
  }

  /// 登录门禁：登录成功后自动续上本集。
  Future<void> _unlock() async {
    final ok = await LoginPage.show(
      context,
      reason: '登录后可看第 $_index 集及后续剧集',
    );
    if (!ok || !mounted) return;
    setState(() {});
    await _openEpisode(_index);
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && (_controller?.value.isPlaying ?? false)) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleHide();
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(text),
        duration: const Duration(milliseconds: 1200),
      ));
  }

  Future<void> _pickSpeed() async {
    final app = _app;
    final picked = await showModalBottomSheet<double>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text('播放速度',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ),
            for (final s in _speeds)
              ListTile(
                dense: true,
                title: Text('${s}x',
                    style: TextStyle(
                      color: s == app.speed
                          ? AppColors.primary
                          : AppColors.textPrimary,
                    )),
                trailing: s == app.speed
                    ? const Icon(Icons.check, size: 18, color: AppColors.primary)
                    : null,
                onTap: () => Navigator.pop(context, s),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked != null) {
      await app.setSpeed(picked);
      final c = _controller;
      if (c != null && c.value.isInitialized) {
        await c.setPlaybackSpeed(picked);
        _toast('已切换到 ${picked}x');
      }
    }
  }

  Future<void> _pickEpisode() async {
    final target = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, controller) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(
                '选集 · 共 ${widget.episodes.length} 集',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
            Expanded(
              child: GridView.builder(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 5,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.55,
                ),
                itemCount: widget.episodes.length,
                itemBuilder: (context, i) {
                  final ep = widget.episodes[i];
                  final current = ep.index == _index;
                  return GestureDetector(
                    onTap: () => Navigator.pop(context, ep.index),
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: current
                            ? AppColors.primary.withValues(alpha: 0.16)
                            : AppColors.surfaceHigh,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: current ? AppColors.primary : Colors.transparent,
                        ),
                      ),
                      child: Text(
                        '${ep.index}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight:
                              current ? FontWeight.w700 : FontWeight.w400,
                          color: current
                              ? AppColors.primary
                              : AppColors.textPrimary,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (target != null && target != _index) {
      _persistProgress();
      _openEpisode(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final fav = app.isFavorite(widget.drama.id);
    final controller = _controller;
    final gated = !app.canWatch(_episode);

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleControls,
        onVerticalDragEnd: (details) {
          final v = details.primaryVelocity ?? 0;
          if (v < -220) _next();
          if (v > 220) _prev();
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildVideo(controller),
            if (_controlsVisible || gated) _buildTopBar(context),
            if (!gated) ...[
              if (_controlsVisible &&
                  controller != null &&
                  controller.value.isInitialized)
                _buildCenterPlay(controller),
              if (_controlsVisible) _buildRightRail(fav, app),
              if (_controlsVisible &&
                  controller != null &&
                  controller.value.isInitialized)
                _buildBottomBar(controller, app),
              if (_initializing)
                const Center(
                  child: SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              if (_error != null) _buildError(),
            ],
            if (gated) _buildGate(context),
          ],
        ),
      ),
    );
  }

  /// 登录门禁浮层。
  Widget _buildGate(BuildContext context) {
    return Positioned.fill(
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xF0000000), Color(0xFF120608)],
          ),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 34),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.gold.withValues(alpha: 0.12),
                    border: Border.all(
                      color: AppColors.gold.withValues(alpha: 0.45),
                    ),
                  ),
                  child: const Icon(Icons.lock_outline,
                      size: 28, color: AppColors.gold),
                ),
                const SizedBox(height: 18),
                Text(
                  '第 $_index 集为登录专享',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '登录后可观看完整剧集\n收藏与观看进度会一并同步',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.7,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 24),
                GestureDetector(
                  onTap: _unlock,
                  child: Container(
                    width: 190,
                    height: 45,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.primary, AppColors.primaryDeep],
                      ),
                      borderRadius: BorderRadius.circular(23),
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      '立即登录',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text(
                    '返回详情',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVideo(VideoPlayerController? controller) {
    if (controller == null || !controller.value.isInitialized) {
      return Stack(
        fit: StackFit.expand,
        children: [
          DramaCover(drama: widget.drama, radius: 0),
          const DecoratedBox(
            decoration: BoxDecoration(color: Color(0xCC000000)),
          ),
        ],
      );
    }
    final size = controller.value.size;
    return Center(
      child: AspectRatio(
        aspectRatio: size.width / size.height,
        child: VideoPlayer(controller),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 6,
          left: 8,
          right: 16,
          bottom: 24,
        ),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xB3000000), Colors.transparent],
          ),
        ),
        child: Row(
          children: [
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back_ios_new, size: 18),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.drama.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '第 $_index 集 / 共 ${widget.episodes.length} 集',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () => _toast('分享链接已复制（演示）'),
              icon: const Icon(Icons.ios_share, size: 19),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCenterPlay(VideoPlayerController controller) {
    final playing = controller.value.isPlaying;
    return Center(
      child: GestureDetector(
        onTap: () {
          if (playing) {
            controller.pause();
            setState(() => _controlsVisible = true);
          } else {
            controller.play();
            _scheduleHide();
          }
          setState(() {});
        },
        child: Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.38),
            shape: BoxShape.circle,
          ),
          child: Icon(
            playing ? Icons.pause : Icons.play_arrow_rounded,
            size: 34,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildRightRail(bool fav, AppState app) {
    return Positioned(
      right: 12,
      bottom: 120,
      child: Column(
        children: [
          _RailButton(
            icon: fav ? Icons.favorite : Icons.favorite_border,
            label: fav ? '已收藏' : '收藏',
            color: fav ? AppColors.primary : Colors.white,
            onTap: () => app.toggleFavorite(widget.drama.id),
          ),
          const SizedBox(height: 18),
          _RailButton(
            icon: Icons.format_list_numbered,
            label: '选集',
            onTap: _pickEpisode,
          ),
          const SizedBox(height: 18),
          _RailButton(
            icon: Icons.skip_next,
            label: '下一集',
            onTap: _next,
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(VideoPlayerController controller, AppState app) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: EdgeInsets.only(
          left: 14,
          right: 14,
          bottom: MediaQuery.of(context).padding.bottom + 10,
          top: 18,
        ),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Color(0xCC000000), Colors.transparent],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  _fmt(controller.value.position),
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2.5,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 5),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 12),
                      activeTrackColor: AppColors.primary,
                      inactiveTrackColor: Colors.white24,
                      thumbColor: Colors.white,
                    ),
                    child: Slider(
                      value: controller.value.position.inMilliseconds
                          .clamp(
                            0,
                            controller.value.duration.inMilliseconds == 0
                                ? 1
                                : controller.value.duration.inMilliseconds,
                          )
                          .toDouble(),
                      max: controller.value.duration.inMilliseconds
                          .clamp(1, 1 << 31)
                          .toDouble(),
                      onChanged: (v) => controller.seekTo(
                        Duration(milliseconds: v.round()),
                      ),
                    ),
                  ),
                ),
                Text(
                  _fmt(controller.value.duration),
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                _BottomChip(
                  label: '${app.speed}x',
                  onTap: _pickSpeed,
                ),
                const SizedBox(width: 8),
                _BottomChip(
                  label: app.autoPlay ? '自动连播 开' : '自动连播 关',
                  onTap: () => app.setAutoPlay(!app.autoPlay),
                ),
                const Spacer(),
                _BottomChip(
                  label: '上一集',
                  onTap: _prev,
                  outlined: true,
                ),
                const SizedBox(width: 8),
                _BottomChip(
                  label: '下一集',
                  onTap: _next,
                  filled: true,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.72),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(30),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.play_disabled,
                    size: 38, color: AppColors.textTertiary),
                const SizedBox(height: 12),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlinedButton(
                      onPressed: () => _openEpisode(_index),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary),
                      ),
                      child: const Text('重试'),
                    ),
                    const SizedBox(width: 10),
                    TextButton(
                      onPressed: _next,
                      child: const Text('下一集'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = Colors.white,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.32),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 21, color: color),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(fontSize: 10, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _BottomChip extends StatelessWidget {
  const _BottomChip({
    required this.label,
    required this.onTap,
    this.filled = false,
    this.outlined = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool filled;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: filled
              ? AppColors.primary
              : (outlined ? Colors.transparent : Colors.white.withValues(alpha: 0.14)),
          borderRadius: BorderRadius.circular(14),
          border: outlined ? Border.all(color: Colors.white24) : null,
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 11.5,
            color: Colors.white,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
