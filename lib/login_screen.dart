import 'package:flutter/material.dart';
import 'api.dart';
import 'home_screen.dart';
import 'strings.dart';
import 'widgets.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _server = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _server.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_server.text.trim().isEmpty || _user.text.trim().isEmpty || _pass.text.trim().isEmpty) {
      setState(() => _error = 'fill_all');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final err = await XtreamAPI.instance.login(_server.text, _user.text, _pass.text);
    if (!mounted) return;
    if (err == null) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen()));
    } else {
      setState(() {
        _loading = false;
        _error = err;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: loginInset(context), vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.play_circle_fill, size: 72, color: Color(0xFF14B8A6)),
                const SizedBox(height: 8),
                const Text('MovieFlix',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                const SizedBox(height: 28),
                TextField(
                  controller: _server,
                  keyboardType: TextInputType.url,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(
                    labelText: S.t('login_server'),
                    hintText: 'http://example.com:8080',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _user,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(labelText: S.t('login_user'), border: const OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _pass,
                  obscureText: true,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(labelText: S.t('login_pass'), border: const OutlineInputBorder()),
                  onSubmitted: (_) => _login(),
                ),
                const SizedBox(height: 16),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(S.t(_error!),
                        textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent)),
                  ),
                SizedBox(
                  height: 50,
                  child: FilledButton(
                    onPressed: _loading ? null : _login,
                    child: _loading
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(S.t('login')),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  S.t('own_account'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
