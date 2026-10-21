import 'package:flutter/material.dart';
import 'notifier.dart';
import 'store.dart';
import 'strings.dart';
import 'tmdb.dart';
import 'widgets.dart';

class ComingSoonScreen extends StatefulWidget {
  final Upcoming u;
  const ComingSoonScreen({super.key, required this.u});
  @override
  State<ComingSoonScreen> createState() => _ComingSoonScreenState();
}

class _ComingSoonScreenState extends State<ComingSoonScreen> {
  bool _remind = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final r = await Store.hasReminder(widget.u.id, widget.u.type);
    if (mounted) setState(() => _remind = r);
  }

  Future<void> _toggle() async {
    final u = widget.u;
    final id = Reminder.idFor(u.type, u.id);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);

    if (_remind) {
      await Notifier.cancel(id);
      await Store.removeReminder(id);
      if (mounted) setState(() => _remind = false);
      messenger.showSnackBar(SnackBar(content: Text(S.t('reminder_removed'))));
    } else {
      final date = u.date;
      final now = DateTime.now();
      if (date == null) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      var when = DateTime(date.year, date.month, date.day, 10); // الساعة 10 صباحاً يوم الصدور
      if (when.isBefore(now)) {
        if (date.isBefore(DateTime(now.year, now.month, now.day))) {
          messenger.showSnackBar(SnackBar(content: Text(S.t('already_released'))));
          if (mounted) setState(() => _busy = false);
          return;
        }
        when = now.add(const Duration(minutes: 1));
      }
      final ok = await Notifier.schedule(
        id,
        S.t('notif_title'),
        '${u.title} ${S.t('notif_body')}',
        when,
      );
      await Store.addReminder(Reminder(
        id: id,
        type: u.type,
        tmdbId: u.id,
        title: u.title,
        poster: u.posterUrl,
        dateMs: when.millisecondsSinceEpoch,
        fired: false,
      ));
      await Store.addInbox(S.t('reminder_set'), '${u.title} • ${fmtDate(u.date)}');
      if (mounted) setState(() => _remind = true);
      final msg = !Notifier.supported ? 'reminder_inapp' : (ok ? 'reminder_set' : 'reminder_no_notif');
      messenger.showSnackBar(SnackBar(content: Text(S.t(msg))));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.u;
    final days = u.date == null ? 0 : u.date!.difference(DateTime.now()).inDays + 1;
    final img = u.backdropUrl.isNotEmpty ? u.backdropUrl : u.posterUrl;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 260,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                color: const Color(0xFF0B1220),
                child: Poster(
                  url: img,
                  fit: MediaQuery.of(context).size.width >= 700 ? BoxFit.contain : BoxFit.cover,
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: pageInset(context), vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(u.title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(Icons.event, size: 18, color: Color(0xFF14B8A6)),
                      const SizedBox(width: 6),
                      Text('${S.t('release_date')}: ${fmtDate(u.date)}'),
                      if (days > 0) ...[
                        const SizedBox(width: 8),
                        Text('(${S.t('in_days').replaceAll('{n}', '$days')})',
                            style: const TextStyle(color: Colors.grey)),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (u.overview.isNotEmpty) Text(u.overview, style: const TextStyle(color: Colors.grey)),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _remind ? Colors.grey[800] : const Color(0xFF14B8A6),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _busy ? null : _toggle,
                      icon: Icon(_remind ? Icons.notifications_off : Icons.notifications_active),
                      label: Text(S.t(_remind ? 'cancel_reminder' : 'remind_me')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
