import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'notifier.dart';
import 'store.dart';
import 'strings.dart';
import 'widgets.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final api = XtreamAPI.instance;
  String _tmdb = '';

  @override
  void initState() {
    super.initState();
    _loadKey();
  }

  Future<void> _loadKey() async {
    final k = await Store.tmdbKey();
    if (mounted) setState(() => _tmdb = k);
  }

  Future<void> _pickLanguage() async {
    final nav = Navigator.of(context);
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(S.t('choose_language')),
        children: S.supported.entries
            .map((e) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, e.key),
                  child: Text(e.value, style: const TextStyle(fontSize: 16)),
                ))
            .toList(),
      ),
    );
    if (choice == null || choice == S.lang.value) return;
    await S.setLang(choice);
    // نعاود بناء التطبيق باش كل الشاشات تاخذ اللغة الجديدة
    nav.pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const HomeScreen()), (r) => false);
  }

  Future<void> _editTmdb() async {
    final ctrl = TextEditingController(text: _tmdb);
    final messenger = ScaffoldMessenger.of(context);
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.t('tmdb_key')),
        content: TextField(
          controller: ctrl,
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(hintText: S.t('tmdb_hint')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(S.t('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(S.t('save'))),
        ],
      ),
    );
    if (saved == true) {
      await Store.setTmdbKey(ctrl.text);
      await _loadKey();
      messenger.showSnackBar(SnackBar(content: Text(S.t('tmdb_saved'))));
    }
  }

  void _about() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('MovieFlix'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${S.t('version')} 1.0.0'),
            const SizedBox(height: 10),
            Text(S.t('about_text')),
            const SizedBox(height: 10),
            Text(S.t('tmdb_credit'), style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
  }

  Future<void> _openInstagram() async {
    await launchUrl(Uri.parse('https://www.instagram.com/sxnaxke'), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.t('settings'))),
      body: ListView(
        padding: EdgeInsets.symmetric(horizontal: pageInset(context)),
        children: [
          ListTile(
            leading: const Icon(Icons.dns),
            title: Text(S.t('server')),
            subtitle: Text(api.server, textDirection: TextDirection.ltr),
          ),
          ListTile(
            leading: const Icon(Icons.person),
            title: Text(S.t('account')),
            subtitle: Text(api.username, textDirection: TextDirection.ltr),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.language),
            title: Text(S.t('language')),
            subtitle: Text(S.supported[S.lang.value] ?? ''),
            onTap: _pickLanguage,
          ),
          ListTile(
            leading: const Icon(Icons.event_available),
            title: Text(S.t('tmdb_key')),
            subtitle: Text(_tmdb.isEmpty ? S.t('tmdb_hint') : '••••••••'),
            onTap: _editTmdb,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(S.t('about')),
            onTap: _about,
          ),
          ListTile(
            leading: const Icon(Icons.code),
            title: Text(S.t('developer')),
            subtitle: const Text('sxnaxke'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: _openInstagram,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: Text(S.t('clear_data')),
            onTap: () async {
              final messenger = ScaffoldMessenger.of(context);
              for (final r in await Store.reminders()) {
                await Notifier.cancel(r.id);
              }
              await Store.clearUserData();
              messenger.showSnackBar(SnackBar(content: Text(S.t('cleared'))));
            },
          ),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.redAccent),
            title: Text(S.t('logout'), style: const TextStyle(color: Colors.redAccent)),
            onTap: () async {
              final nav = Navigator.of(context);
              await api.logout();
              nav.pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            },
          ),
        ],
      ),
    );
  }
}
