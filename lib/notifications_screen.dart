import 'package:flutter/material.dart';
import 'notifier.dart';
import 'store.dart';
import 'strings.dart';
import 'widgets.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<InboxItem> _items = [];
  List<Reminder> _reminders = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await Store.processDue();
    final items = await Store.inbox();
    final rem = (await Store.reminders()).where((r) => !r.fired).toList();
    if (!mounted) return;
    setState(() {
      _items = items;
      _reminders = rem;
      _loading = false;
    });
    await Store.markAllRead();
  }

  String _time(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${fmtDate(d)}  ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(S.t('notifications')),
        actions: [
          if (_items.isNotEmpty)
            IconButton(
              tooltip: S.t('clear_all'),
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: () async {
                await Store.clearInbox();
                if (mounted) setState(() => _items = []);
              },
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_items.isEmpty && _reminders.isEmpty)
              ? Center(child: Text(S.t('no_notifications')))
              : ListView(
                  padding: EdgeInsets.symmetric(horizontal: pageInset(context)),
                  children: [
                    if (_reminders.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                        child: Text(S.t('scheduled_reminders'),
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                      for (final r in _reminders)
                        ListTile(
                          leading: const Icon(Icons.alarm, color: Color(0xFF14B8A6)),
                          title: Text(r.title),
                          subtitle: Text(fmtDate(DateTime.fromMillisecondsSinceEpoch(r.dateMs))),
                          trailing: IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () async {
                              await Notifier.cancel(r.id);
                              await Store.removeReminder(r.id);
                              if (mounted) setState(() => _reminders.remove(r));
                            },
                          ),
                        ),
                      const Divider(),
                    ],
                    for (final n in _items)
                      ListTile(
                        leading: Icon(
                          n.read ? Icons.notifications_none : Icons.notifications_active,
                          color: n.read ? Colors.grey : const Color(0xFF14B8A6),
                        ),
                        title: Text(n.title, style: TextStyle(fontWeight: n.read ? FontWeight.normal : FontWeight.bold)),
                        subtitle: Text('${n.body}\n${_time(n.ts)}'),
                        isThreeLine: true,
                      ),
                  ],
                ),
    );
  }
}
