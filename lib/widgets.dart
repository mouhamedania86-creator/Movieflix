import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'api.dart';
import 'details_screen.dart';
import 'player_screen.dart';
import 'store.dart';
import 'strings.dart';

String posterOf(dynamic item) => (item['stream_icon'] ?? item['cover'] ?? '').toString();

String fmtDate(DateTime? d) {
  if (d == null) return '';
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

// ---------------- مقاسات حسب الشاشة (هاتف / كمبيوتر / تلفزة) ----------------
double cardWidth(BuildContext c) {
  final w = MediaQuery.of(c).size.width;
  if (w >= 1400) return 180;
  if (w >= 900) return 150;
  return 120;
}

double cardRowHeight(BuildContext c) => cardWidth(c) * 1.42 + 76;

/// هامش أفقي يخلي المحتوى في الوسط (أقصى عرض 900) على الشاشات الكبيرة.
double pageInset(BuildContext c) => math.max(16.0, (MediaQuery.of(c).size.width - 900) / 2);

double loginInset(BuildContext c) => math.max(24.0, (MediaQuery.of(c).size.width - 420) / 2);

void openItem(BuildContext context, dynamic item, String type) {
  Navigator.push(context, MaterialPageRoute(builder: (_) => DetailsScreen(item: item, type: type)));
}

/// تشغيل فيلم مباشرة (يكمل من آخر نقطة تلقائياً).
void playMovie(BuildContext context, dynamic item) {
  final api = XtreamAPI.instance;
  final w = WatchEntry.forMovie(item);
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => PlayerScreen(url: api.buildMovieUrl(w.mediaId, w.ext), title: w.fullTitle, watch: w),
    ),
  );
}

/// متابعة المشاهدة من "تابع المشاهدة".
void resumeEntry(BuildContext context, WatchEntry e) {
  final api = XtreamAPI.instance;
  final url = e.type == 'vod' ? api.buildMovieUrl(e.mediaId, e.ext) : api.buildSeriesUrl(e.mediaId, e.ext);
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => PlayerScreen(url: url, title: e.fullTitle, watch: e)),
  );
}

/// عنصر قابل للنقر باللمس أو الماوس أو ريموت التلفزة (إطار يبين العنصر المحدد).
class Tappable extends StatefulWidget {
  final VoidCallback onTap;
  final Widget child;
  final double radius;
  const Tappable({super.key, required this.onTap, required this.child, this.radius = 8});

  @override
  State<Tappable> createState() => _TappableState();
}

class _TappableState extends State<Tappable> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      onShowFocusHighlight: (v) => setState(() => _focused = v),
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
          widget.onTap();
          return null;
        }),
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius + 2),
            border: Border.all(
              color: _focused ? const Color(0xFF14B8A6) : Colors.transparent,
              width: 3,
            ),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

class Poster extends StatelessWidget {
  final String url;
  final BoxFit fit;
  final double? width, height;
  const Poster({super.key, required this.url, this.fit = BoxFit.cover, this.width, this.height});

  Widget _placeholder() => Container(
        width: width,
        height: height,
        color: Colors.grey[850],
        child: const Icon(Icons.movie, color: Colors.grey),
      );

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) return _placeholder();
    return CachedNetworkImage(
      imageUrl: url,
      fit: fit,
      width: width,
      height: height,
      errorWidget: (_, __, ___) => _placeholder(),
    );
  }
}

/// بطاقة أفقية (للصفوف) مع خط أحمر للتقدم وعلامة "تمت مشاهدته".
class PosterCard extends StatelessWidget {
  final dynamic item;
  final String type;
  final double? width, height;
  final double? progress;
  final bool watched;
  final String? subtitle;
  final VoidCallback? onTap;
  const PosterCard({
    super.key,
    required this.item,
    required this.type,
    this.width,
    this.height,
    this.progress,
    this.watched = false,
    this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final w = width ?? cardWidth(context);
    final h = height ?? w * 1.42;
    return Tappable(
      onTap: onTap ?? () => openItem(context, item, type),
      child: SizedBox(
        width: w,
        child: Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                children: [
                  Poster(
                    url: posterOf(item),
                    width: w,
                    height: h,
                    fit: type == 'live' ? BoxFit.contain : BoxFit.cover,
                  ),
                  if (progress != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 4,
                        color: Colors.red,
                        backgroundColor: Colors.black54,
                      ),
                    ),
                  if (watched)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(color: Color(0xFF14B8A6), shape: BoxShape.circle),
                        child: const Icon(Icons.check, size: 14, color: Colors.white),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              (item['name'] ?? '').toString(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12),
            ),
            if (subtitle != null && subtitle!.isNotEmpty)
              Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
          ],
        ),
      ),
    );
  }
}

class PosterGrid extends StatelessWidget {
  final List<dynamic> items;
  final String? type; // إذا كان null يؤخذ النوع من الحقل _type
  final String? emptyText;
  const PosterGrid({super.key, required this.items, this.type, this.emptyText});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return Center(child: Text(emptyText ?? S.t('no_content')));
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 170,
        childAspectRatio: 0.6,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final item = items[i];
        final t = (item['_type'] ?? type ?? 'vod').toString();
        return Tappable(
          radius: 10,
          onTap: () => openItem(context, item, t),
          child: Column(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Poster(
                    url: posterOf(item),
                    fit: t == 'live' ? BoxFit.contain : BoxFit.cover,
                    width: double.infinity,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                (item['name'] ?? '').toString(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        );
      },
    );
  }
}

class MessageView extends StatelessWidget {
  final String text;
  final VoidCallback? onRetry;
  const MessageView({super.key, required this.text, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: Text(S.t('retry'))),
          ],
        ],
      ),
    );
  }
}
