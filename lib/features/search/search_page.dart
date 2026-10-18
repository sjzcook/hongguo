import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/drama.dart';
import '../../state/app_state.dart';
import '../../widgets/drama_card.dart';
import '../detail/detail_page.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  final _history = <String>[];

  Timer? _debounce;
  List<Drama> _results = const [];
  bool _loading = false;
  bool _searched = false;

  static const _hotWords = [
    '龙王归来',
    '闪婚',
    '重生',
    '赘婿',
    '萌宝',
    '神医',
    '穿越',
    '悬疑',
  ];

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    setState(() {});
    if (value.trim().isEmpty) {
      setState(() {
        _results = const [];
        _searched = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 320), () => _search(value));
  }

  Future<void> _search(String keyword) async {
    final q = keyword.trim();
    if (q.isEmpty) return;
    setState(() => _loading = true);
    try {
      final data = await context.read<AppState>().source.search(q);
      if (!mounted) return;
      setState(() {
        _results = data;
        _loading = false;
        _searched = true;
        _history.remove(q);
        _history.insert(0, q);
        if (_history.length > 8) _history.removeLast();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _searched = true;
        _results = const [];
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  void _submit(String word) {
    _controller.text = word;
    _controller.selection =
        TextSelection.collapsed(offset: word.length);
    _focus.unfocus();
    _search(word);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        titleSpacing: 0,
        title: Container(
          height: 38,
          decoration: BoxDecoration(
            color: AppColors.surfaceHigh,
            borderRadius: BorderRadius.circular(19),
          ),
          child: TextField(
            controller: _controller,
            focusNode: _focus,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onChanged: _onChanged,
            onSubmitted: _submit,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: '搜索短剧、演员、题材',
              prefixIcon: const Icon(Icons.search,
                  size: 19, color: AppColors.textTertiary),
              suffixIcon: _controller.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close,
                          size: 17, color: AppColors.textTertiary),
                      onPressed: () {
                        _controller.clear();
                        _onChanged('');
                      },
                    ),
              contentPadding: const EdgeInsets.symmetric(vertical: 9),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => _submit(_controller.text),
            child: const Text('搜索',
                style: TextStyle(fontSize: 13.5, color: AppColors.primary)),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.primary,
          ),
        ),
      );
    }

    if (!_searched) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (_history.isNotEmpty) ...[
            Row(
              children: [
                const Text('搜索历史',
                    style:
                        TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                const Spacer(),
                GestureDetector(
                  onTap: () => setState(_history.clear),
                  child: const Icon(Icons.delete_outline,
                      size: 17, color: AppColors.textTertiary),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final h in _history)
                  _WordChip(text: h, onTap: () => _submit(h), muted: true),
              ],
            ),
            const SizedBox(height: 24),
          ],
          const Text('热门搜索',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final w in _hotWords)
                _WordChip(text: w, onTap: () => _submit(w)),
            ],
          ),
        ],
      );
    }

    if (_results.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 38, color: AppColors.textTertiary),
            SizedBox(height: 10),
            Text('没有找到相关短剧',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
      itemCount: _results.length,
      separatorBuilder: (_, _) => const Divider(),
      itemBuilder: (context, i) {
        final drama = _results[i];
        return DramaWideCard(
          drama: drama,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => DetailPage(drama: drama)),
          ),
        );
      },
    );
  }
}

class _WordChip extends StatelessWidget {
  const _WordChip({
    required this.text,
    required this.onTap,
    this.muted = false,
  });

  final String text;
  final VoidCallback onTap;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: muted ? AppColors.surfaceHigh : AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12.5,
            color: muted ? AppColors.textSecondary : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}
