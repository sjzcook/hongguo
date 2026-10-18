import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'data/local/local_store.dart';
import 'features/shell/main_shell.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.surface,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  final store = await LocalStore.open();
  final state = AppState(store);
  // 已登录时后台复核一次凭证（仅网关模式生效）。
  unawaited(state.refreshProfile());
  runApp(HongguoApp(state: state));
}

class HongguoApp extends StatelessWidget {
  const HongguoApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: state,
      child: MaterialApp(
        title: '红果短剧',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        home: const MainShell(),
      ),
    );
  }
}
