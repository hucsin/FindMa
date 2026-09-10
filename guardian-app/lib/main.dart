import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'pages/device_list_page.dart';
import 'pages/login_page.dart';
import 'state/providers.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // 让 AuthNotifier 能在登录态变化时清掉数据缓存
  final container = ProviderContainer();
  AuthNotifier.attach(container);

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const FindMaApp(),
    ),
  );
}

class FindMaApp extends StatelessWidget {
  const FindMaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FindMa 守护',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF2F6BFF),
        scaffoldBackgroundColor: const Color(0xFFF6F7F9),
        appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
      ),
      home: const _AuthGate(),
    );
  }
}

class _AuthGate extends ConsumerWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    return auth.loggedIn ? const DeviceListPage() : const LoginPage();
  }
}
