import 'dart:async';
import 'package:flutter/material.dart';
import 'api.dart';
import 'coming_soon_screen.dart';
import 'notifications_screen.dart';
import 'settings_screen.dart';
import 'store.dart';
import 'strings.dart';
import 'tmdb.dart';
import 'widgets.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;
  final Set<int> _visited = {0}; // التبويبات تتحمل عند أول زيارة فقط
  int _favVersion = 0;

  void _select(int i) => setState(() {
        _index = i;
        _visited.add(i);
        if (i == 4) _favVersion++; // تحديث المفضلة عند فتحها
      });

  Widget _tab(int i) {
    if (!_visited.contains(i)) return const SizedBox.shrink();
    switch (i) {
      case 0:
        return const HomeTab();
      case 1:
        return const CategoryTab(type: 'vod');
      case 2:
        return const CategoryTab(type: 'series');
      case 3:
        return const CategoryTab(type: 'live');
      default:
        return FavoritesTab(key: ValueKey(_favVersion));
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 700; // كمبيوتر / تلفزة / تابلت
    const icons = [Icons.home, Icons.movie, Icons.tv, Icons.live_tv, Icons.favorite];
    final labels = [S.t('home'), S.t('movies'), S.t('series'), S.t('live'), S.t('favorites')];

    final content = Column(
      children: [
        ValueListenableBuilder<bool>(
          valueListenable: XtreamAPI.instance.offline,
          builder: (context, off, _) => off
              ? Container(
                  width: double.infinity,
                  color: Colors.orange.shade800,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(S.t('offline'),
                      textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
                )
              : const SizedBox.shrink(),
        ),
        Expanded(child: IndexedStack(index: _index, children: List.generate(5, _tab))),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('MovieFlix'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => showSearch(context: context, delegate: ItemSearchDelegate()),
          ),
          ValueListenableBuilder<int>(
            valueListenable: Store.unread,
            builder: (context, n, _) => IconButton(
              icon: Badge(
                isLabelVisible: n > 0,
                label: Text('$n'),
                child: const Icon(Icons.notifications_outlined),
              ),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NotificationsScreen()),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: wide
          ? Row(
              children: [
                NavigationRail(
                  backgroundColor: const Color(0xFF1E293B),
                  selectedIndex: _index,
                  onDestinationSelected: _select,
                  labelType: NavigationRailLabelType.all,
                  destinations: [
                    for (var i = 0; i < 5; i++)
                      NavigationRailDestination(icon: Icon(icons[i]), label: Text(labels[i])),
                  ],
                ),
                Expanded(child: content),
              ],
            )
          : content,
      bottomNavigationBar: wide
          ? null
          : BottomNavigationBar(
              backgroundColor: const Color(0xFF1E293B),
              selectedItemColor: const Color(0xFF14B8A6),
              unselectedItemColor: Colors.grey,
              type: BottomNavigationBarType.fixed,
              currentIndex: _index,
              onTap: _select,
              items: [
                for (var i = 0; i < 5; i++)
                  BottomNavigationBarItem(icon: Icon(icons[i]), label: labels[i]),
              ],
            ),
    );
  }
}

// ======================= الرئيسية (مثل Netflix) =======================
class HomeTab extends StatefulWidget {
  const HomeTab({super.key});
  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  final api = XtreamAPI.instance;
  List<dynamic> _movies = [], _series = [], _latestM = [], _latestS = [];
  List<dynamic> _vodCats = [], _serCats = [];
  List<WatchEntry> _history = [];
  List<Upcoming> _upcoming = [];
  bool _needKey = false;
  bool _loading = true, _error = false;

  @override
  void initState() {
    super.initState();
    Store.historyVersion.addListener(_loadHistory);
    _loadHistory();
    _load();
  }

  @override
  void dispose() {
    Store.historyVersion.removeListener(_loadHistory);
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final h = await Store.history();
    if (mounted) setState(() => _history = h);
  }

  List<dynamic> _latest(List<dynamic> l, String key) {
    final c = List<dynamic>.from(l);
    int v(dynamic x) => int.tryParse('${x[key]}') ?? 0;
    c.sort((a, b) => v(b).compareTo(v(a)));
    return c.take(15).toList();
  }

  Future<void> _load() async {
    try {
      final m = await api.getStreams('vod');
      final s = await api.getStreams('series');
      if (!mounted) return;
      setState(() {
        _movies = m;
        _series = s;
        _latestM = _latest(m, 'added');
        _latestS = _latest(s, 'last_modified');
        _loading = false;
        _error = false;
      });
      _loadExtras();
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = true;
        });
      }
    }
  }

  Future<void> _loadExtras() async {
    Store.processDue();
    final vc = await api.getCategories('vod');
    final sc = await api.getCategories('series');
    if (mounted) {
      setState(() {
        _vodCats = vc;
        _serCats = sc;
      });
    }
    _checkNew();
    _loadUpcoming();
  }

  /// إذا ظهر محتوى جديد من آخر زيارة نزيدو في الإشعارات.
  Future<void> _checkNew() async {
    final seen = await Store.seenIds();
    final keys = <String, String>{};
    for (final it in _latestM.take(10)) {
      keys['vod_${XtreamAPI.idOf(it, 'vod')}'] = (it['name'] ?? '').toString();
    }
    for (final it in _latestS.take(10)) {
      keys['series_${XtreamAPI.idOf(it, 'series')}'] = (it['name'] ?? '').toString();
    }
    if (seen.isNotEmpty) {
      var n = 0;
      for (final e in keys.entries) {
        if (!seen.contains(e.key) && n < 3) {
          await Store.addInbox(S.t('new_added'), e.value);
          n++;
        }
      }
    }
    await Store.setSeenIds({...seen, ...keys.keys});
  }

  Future<void> _loadUpcoming() async {
    final key = await Store.tmdbKey();
    if (key.isEmpty) {
      if (mounted) setState(() => _needKey = true);
      return;
    }
    try {
      final l = await Tmdb.upcoming(key, S.tmdbLang);
      if (mounted) {
        setState(() {
          _upcoming = l;
          _needKey = false;
        });
      }
    } catch (_) {}
  }

  static bool _isAdult(String name) =>
      RegExp(r'xxx|adult|porn|18\+|sex', caseSensitive: false).hasMatch(name);

  List<Map<String, dynamic>> _heroEntries() {
    final out = <Map<String, dynamic>>[];
    for (var i = 0; i < 4; i++) {
      if (i < _latestM.length) out.add({'item': _latestM[i], 'type': 'vod'});
      if (i < _latestS.length) out.add({'item': _latestS[i], 'type': 'series'});
    }
    return out;
  }

  Widget _row(String title, List<Widget> cards) {
    if (cards.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
          child: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        ),
        SizedBox(
          height: cardRowHeight(context),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: cards.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) => cards[i],
          ),
        ),
      ],
    );
  }

  List<Widget> _categoryRows(List<dynamic> items, List<dynamic> cats, String type, int maxRows) {
    final byCat = <String, List<dynamic>>{};
    for (final it in items) {
      (byCat['${it['category_id']}'] ??= <dynamic>[]).add(it);
    }
    final rows = <Widget>[];
    for (final c in cats) {
      if (rows.length >= maxRows) break;
      final name = (c['category_name'] ?? '').toString();
      if (name.isEmpty || _isAdult(name)) continue;
      final list = byCat['${c['category_id']}'];
      if (list == null || list.length < 6) continue;
      final label = '${S.t(type == 'vod' ? 'movies' : 'series')} • $name';
      rows.add(_row(label, list.take(15).map<Widget>((it) => PosterCard(item: it, type: type)).toList()));
    }
    return rows;
  }

  Widget _comingSoon() {
    if (_needKey) {
      return Card(
        margin: const EdgeInsets.all(16),
        child: ListTile(
          leading: const Icon(Icons.event_available),
          title: Text(S.t('coming_soon')),
          subtitle: Text(S.t('tmdb_need_key')),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SettingsScreen()),
          ),
        ),
      );
    }
    return _row(S.t('coming_soon'), _upcoming.map<Widget>((u) => _UpcomingCard(u: u)).toList());
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error || (_movies.isEmpty && _series.isEmpty)) {
      return MessageView(
        text: S.t('load_fail'),
        onRetry: () {
          setState(() {
            _loading = true;
            _error = false;
          });
          _load();
        },
      );
    }

    final cont = Store.continueList(_history);
    final watched = Store.watchedList(_history);
    final hero = _heroEntries();

    return RefreshIndicator(
      onRefresh: () async {
        api.clearMemory();
        await _load();
      },
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          if (hero.isNotEmpty) HeroCarousel(entries: hero),
          if (cont.isNotEmpty)
            _row(
              S.t('continue_watching'),
              cont
                  .map<Widget>((e) => PosterCard(
                        item: e.item,
                        type: e.type,
                        progress: e.fraction,
                        subtitle: e.subtitle,
                        onTap: () => resumeEntry(context, e),
                      ))
                  .toList(),
            ),
          _comingSoon(),
          ..._categoryRows(_movies, _vodCats, 'vod', 4),
          ..._categoryRows(_series, _serCats, 'series', 3),
          if (watched.isNotEmpty)
            _row(
              S.t('watched'),
              watched
                  .map<Widget>((e) => PosterCard(item: e.item, type: e.type, watched: true, subtitle: e.subtitle))
                  .toList(),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _UpcomingCard extends StatelessWidget {
  final Upcoming u;
  const _UpcomingCard({required this.u});

  @override
  Widget build(BuildContext context) {
    final w = cardWidth(context);
    return Tappable(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ComingSoonScreen(u: u))),
      child: SizedBox(
        width: w,
        child: Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                children: [
                  Poster(url: u.posterUrl, width: w, height: w * 1.42),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      color: Colors.black54,
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Text(fmtDate(u.date),
                          textAlign: TextAlign.center, style: const TextStyle(fontSize: 11)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(u.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

// ----------- شريط الأفلام/المسلسلات الأحدث (يتبدل كل 5 ثواني) -----------
class HeroCarousel extends StatefulWidget {
  final List<Map<String, dynamic>> entries; // {item, type}
  const HeroCarousel({super.key, required this.entries});
  @override
  State<HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<HeroCarousel> {
  final PageController _pc = PageController();
  Timer? _timer;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_pc.hasClients || widget.entries.isEmpty) return;
      final next = (_page + 1) % widget.entries.length;
      _pc.animateToPage(next, duration: const Duration(milliseconds: 500), curve: Curves.easeInOut);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pc.dispose();
    super.dispose();
  }

  Widget _buttons(dynamic item, String type, MainAxisAlignment align) {
    return Row(
      mainAxisAlignment: align,
      children: [
        FilledButton.icon(
          onPressed: () => type == 'vod' ? playMovie(context, item) : openItem(context, item, type),
          icon: const Icon(Icons.play_arrow),
          label: Text(S.t('play')),
        ),
        const SizedBox(width: 10),
        OutlinedButton.icon(
          onPressed: () => openItem(context, item, type),
          icon: const Icon(Icons.info_outline),
          label: Text(S.t('info')),
        ),
      ],
    );
  }

  Widget _narrow(dynamic item, String type, String name) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Poster(url: posterOf(item), fit: BoxFit.cover),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x66000000), Colors.transparent, Color(0xFF0F172A)],
              stops: [0, 0.4, 1],
            ),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 36,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(S.t(type == 'vod' ? 'movies' : 'series'), style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 12),
              _buttons(item, type, MainAxisAlignment.center),
            ],
          ),
        ),
      ],
    );
  }

  Widget _wide(dynamic item, String type, String name) {
    return Container(
      color: const Color(0xFF111827),
      padding: const EdgeInsets.fromLTRB(48, 24, 48, 36),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(S.t(type == 'vod' ? 'movies' : 'series'),
                    style: const TextStyle(color: Color(0xFF14B8A6), fontSize: 16)),
                const SizedBox(height: 8),
                Text(name,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                _buttons(item, type, MainAxisAlignment.start),
              ],
            ),
          ),
          const SizedBox(width: 24),
          AspectRatio(
            aspectRatio: 2 / 3,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Poster(url: posterOf(item), fit: BoxFit.cover),
            ),
          ),
        ],
      ),
    );
  }

  Widget _page0(Map<String, dynamic> e) {
    final item = e['item'];
    final type = e['type'] as String;
    final name = (item['name'] ?? '').toString();
    final wide = MediaQuery.of(context).size.width >= 700;
    return GestureDetector(
      onTap: () => openItem(context, item, type),
      child: wide ? _wide(item, type, name) : _narrow(item, type, name),
    );
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.entries.length;
    final wide = MediaQuery.of(context).size.width >= 700;
    return SizedBox(
      height: wide ? 380 : 440,
      child: Stack(
        children: [
          Listener(
            onPointerDown: (_) => _start(), // إعادة العد بعد اللمس
            child: PageView.builder(
              controller: _pc,
              itemCount: n,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (_, i) => _page0(widget.entries[i]),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 12,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                n,
                (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _page ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == _page ? const Color(0xFF14B8A6) : Colors.white38,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ======================= أفلام / مسلسلات / مباشر مع الفئات =======================
class CategoryTab extends StatefulWidget {
  final String type; // vod | series | live
  const CategoryTab({super.key, required this.type});
  @override
  State<CategoryTab> createState() => _CategoryTabState();
}

class _CategoryTabState extends State<CategoryTab> {
  final api = XtreamAPI.instance;
  List<dynamic> _cats = [], _items = [];
  String? _cat;
  bool _loading = true, _error = false;

  @override
  void initState() {
    super.initState();
    _loadCats();
    _loadItems();
  }

  Future<void> _loadCats() async {
    final c = await api.getCategories(widget.type);
    if (mounted) setState(() => _cats = c);
  }

  Future<void> _loadItems() async {
    try {
      final l = await api.getStreams(widget.type, categoryId: _cat);
      if (!mounted) return;
      setState(() {
        _items = l;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = true;
        });
      }
    }
  }

  void _select(String? id) {
    setState(() {
      _cat = id;
      _loading = true;
      _error = false;
    });
    _loadItems();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (_cats.isNotEmpty)
          SizedBox(
            height: 50,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _cats.length + 1,
              itemBuilder: (context, i) {
                final String? id = i == 0 ? null : _cats[i - 1]['category_id'].toString();
                final label = i == 0 ? S.t('all') : (_cats[i - 1]['category_name'] ?? '').toString();
                return Padding(
                  padding: const EdgeInsets.all(6),
                  child: ChoiceChip(
                    label: Text(label),
                    selected: _cat == id,
                    onSelected: (_) => _select(id),
                  ),
                );
              },
            ),
          ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error
                  ? MessageView(text: S.t('load_fail'), onRetry: () => _select(_cat))
                  : PosterGrid(items: _items, type: widget.type),
        ),
      ],
    );
  }
}

// ======================= المفضلة =======================
class FavoritesTab extends StatefulWidget {
  const FavoritesTab({super.key});
  @override
  State<FavoritesTab> createState() => _FavoritesTabState();
}

class _FavoritesTabState extends State<FavoritesTab> {
  late final Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = XtreamAPI.instance.getFavorites();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        return PosterGrid(items: snap.data ?? [], emptyText: S.t('no_favs'));
      },
    );
  }
}

// ======================= البحث =======================
class ItemSearchDelegate extends SearchDelegate<void> {
  @override
  String get searchFieldLabel => S.t('search');

  @override
  List<Widget> buildActions(BuildContext context) => [
        if (query.isNotEmpty) IconButton(icon: const Icon(Icons.clear), onPressed: () => query = ''),
      ];

  @override
  Widget buildLeading(BuildContext context) =>
      IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => close(context, null));

  @override
  Widget buildSuggestions(BuildContext context) => Center(child: Text(S.t('search_prompt')));

  @override
  Widget buildResults(BuildContext context) {
    if (query.trim().length < 2) return Center(child: Text(S.t('search_min')));
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: XtreamAPI.instance.search(query),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        return PosterGrid(items: snap.data ?? [], emptyText: S.t('search_none'));
      },
    );
  }
}
