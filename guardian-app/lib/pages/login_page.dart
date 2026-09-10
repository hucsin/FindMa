import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../state/providers.dart';

/// 登录 / 注册（DESIGN 8.1）
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _registerMode = false;
  bool _busy = false;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final username = _username.text.trim();
    final password = _password.text;

    if (username.length < 3) {
      _toast('用户名至少 3 位');
      return;
    }
    if (password.length < 6) {
      _toast('密码至少 6 位');
      return;
    }

    setState(() => _busy = true);
    try {
      final notifier = ref.read(authProvider.notifier);
      if (_registerMode) {
        await notifier.register(username, password);
      } else {
        await notifier.login(username, password);
      }
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('操作失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(28, 80, 28, 28),
          children: [
            const Icon(Icons.shield_moon_outlined, size: 72, color: Color(0xFF2F6BFF)),
            const SizedBox(height: 12),
            const Text(
              'FindMa 守护',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              '看护家人，随时知道他在哪',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 40),
            TextField(
              controller: _username,
              decoration: const InputDecoration(
                labelText: '用户名',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person_outline),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: '密码',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock_outline),
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(_registerMode ? '注册并登录' : '登录', style: const TextStyle(fontSize: 17)),
              ),
            ),
            TextButton(
              onPressed: _busy ? null : () => setState(() => _registerMode = !_registerMode),
              child: Text(_registerMode ? '已有账号？去登录' : '还没有账号？去注册'),
            ),
            const SizedBox(height: 12),
            const Text(
              '提示：用子女端账号绑定老人设备；登录后点右上角「+」扫码绑定。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.black45),
            ),
          ],
        ),
      ),
    );
  }
}
