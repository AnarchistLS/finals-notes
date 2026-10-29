import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/prefs_cache.dart';
import '../data/settings.dart';
import '../l10n/glossary.dart';
import '../models/models.dart';
import '../services/translator.dart';
import 'theme.dart';
import 'widgets/section_view.dart';
import 'widgets/stat_tile.dart';

class PatchPage extends StatefulWidget {
  const PatchPage({super.key, required this.patch, this.translations});

  final PatchDoc patch;

  /// Готовые переводы из файла Mini App: «оригинал -> русский».
  ///
  /// Если они есть, страница не ходит в сеть за переводом - текст уже русский.
  final Map<String, String>? translations;

  @override
  State<PatchPage> createState() => _PatchPageState();
}

class _PatchPageState extends State<PatchPage> {
  /// Создаётся в [_prepare]: движок и ключ берутся из настроек.
  PatchTranslator? _translator;

  /// Переводы приходят по одной строке (до сотен за патч). Перерисовывать
  /// страницу на каждую — это сотни rebuild'ов подряд и просадка до 30 fps,
  /// поэтому обновления склеиваются и применяются пачкой.
  final Map<String, String> _translations = {};
  Timer? _flush;
  bool _translating = false;
  int _done = 0;
  int _total = 0;

  PatchDoc get patch => widget.patch;

  @override
  void initState() {
    super.initState();
    final preloaded = widget.translations;
    if (preloaded != null && preloaded.isNotEmpty) {
      _translations.addAll(preloaded);
    } else {
      _prepare();
    }
  }

  @override
  void dispose() {
    _flush?.cancel();
    _translator?.dispose();
    super.dispose();
  }

  /// Копит переводы и перерисовывает не чаще, чем раз в [_flushInterval].
  void _applyTranslation(String source, String translated) {
    _translations[source] = translated;
    _done++;
    _scheduleFlush();
  }

  static const Duration _flushInterval = Duration(milliseconds: 150);

  void _scheduleFlush() {
    if (_flush != null) return;
    _flush = Timer(_flushInterval, () {
      _flush = null;
      if (mounted) setState(() {});
    });
  }

  Future<void> _prepare() async {
    final enabled = await Settings.translateEnabled();
    if (!enabled || !mounted) return;

    final translator = PatchTranslator(
      cache: SharedPreferencesCache(),
      backend: TranslationBackend.fromName(await Settings.translationBackend()),
      deeplKey: await Settings.deepLKey(),
      deeplEndpoint: await Settings.deepLEndpoint(),
      context: patch.title,
    );
    if (!mounted) {
      translator.dispose();
      return;
    }
    _translator = translator;

    final texts = <String>{
      if (patch.excerpt.isNotEmpty) patch.excerpt,
      for (final section in patch.sections)
        for (final block in section.blocks)
          if (block.kind == 'p' || block.kind == 'li' || block.kind == 'b')
            if (_needsMachineTranslation(block.text)) block.text,
      // Названия характеристик вроде «Delay until health regeneration kicks in
      // after last taking damage» словарём не переводятся — отправляем их
      // в машинный перевод вместе с остальным текстом.
      for (final stat in patch.stats)
        if (_needsMachineTranslation(stat.stat)) stat.stat,
    };

    if (texts.isEmpty) return;

    setState(() {
      _translating = true;
      _total = texts.length;
      _done = 0;
    });

    try {
      await translator.translateAll(
        texts,
        onResult: (source, translated) {
          if (!mounted) return;
          _applyTranslation(source, translated);
        },
        onProgress: (done, total) {
          if (!mounted) return;
          if (_total != total) {
            _total = total;
            _scheduleFlush();
          }
        },
      );
    } catch (_) {
      // Частично полученные переводы уже показаны — оставляем их.
    } finally {
      _flush?.cancel();
      _flush = null;
      if (mounted) setState(() => _translating = false);
    }
  }

  /// Строки, которые имеет смысл отправлять в сеть: есть латиница и словарь
  /// их не покрывает (заголовки разделов переводятся мгновенно).
  bool _needsMachineTranslation(String text) {
    final value = text.trim();
    if (value.isEmpty) return false;
    if (!RegExp(r'[A-Za-z]').hasMatch(value)) return false;
    return translateHeading(value) == value;
  }

  @override
  Widget build(BuildContext context) {
    // Статы, привязавшиеся к блокам внутри разделов, рисует SectionView.
    // В отдельном блоке наверху остаются только те, чей предмет и строка
    // не найдены ни в одном разделе — иначе карточки дублируются.
    final sectionItems = {
      for (final section in patch.sections)
        for (final block in section.blocks)
          if (block.kind == 'b') block.text,
    };
    final sectionRaws = {
      for (final section in patch.sections)
        for (final block in section.blocks)
          if (block.kind == 'li') block.text,
    };
    final loose = patch.stats
        .where((s) =>
            !sectionItems.contains(s.item) && !sectionRaws.contains(s.raw))
        .toList();

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 240,
            backgroundColor: AppColors.bg,
            surfaceTintColor: Colors.transparent,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => Navigator.of(context).pop(),
            ),
            flexibleSpace: FlexibleSpaceBar(background: _hero(context)),
          ),
          SliverToBoxAdapter(child: _meta(context)),
          if (loose.isNotEmpty)
            SliverToBoxAdapter(child: _statsBlock(context, loose)),
          for (final section in patch.sections)
            SliverToBoxAdapter(
              // Раздел — это готовая колонка текста. Без границы отрисовки при
              // скролле перерисовывается весь вьюпорт целиком (каждый глиф
              // заново), из-за чего на средних телефонах fps падает вдвое.
              child: RepaintBoundary(
                child: SectionView(
                  section: section,
                  stats: patch.stats,
                  translations: _translations,
                ),
              ),
            ),
          SliverToBoxAdapter(child: _footer(context)),
          const SliverToBoxAdapter(child: SizedBox(height: 36)),
        ],
      ),
    );
  }

  Widget _hero(BuildContext context) {
    final cover = patch.cover;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final decodeWidth = (MediaQuery.sizeOf(context).width * dpr).round();
    return Stack(
      fit: StackFit.expand,
      children: [
        if (cover != null && cover.isNotEmpty)
          Image.network(
            cover,
            fit: BoxFit.cover,
            cacheWidth: decodeWidth,
            filterQuality: FilterQuality.low,
            errorBuilder: (_, __, ___) =>
                Container(color: AppColors.surfaceAlt),
          )
        else
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1B1B25), Color(0xFF0B0B11)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x66000000), Color(0xEE131313)],
              stops: [0.2, 1],
            ),
          ),
        ),
      ],
    );
  }

  Widget _meta(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (patch.version.isNotEmpty) _versionBadge(),
              if (patch.isStore) ...[
                const SizedBox(width: 8),
                _tag('МАГАЗИН', AppColors.textDim),
              ],
              const Spacer(),
              Text(
                patch.dateText,
                style: const TextStyle(color: AppColors.textDim, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            translateTitle(patch.title),
            style: const TextStyle(
                fontSize: 26, fontWeight: FontWeight.w800, height: 1.12),
          ),
          if (patch.excerpt.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              _translations[patch.excerpt] ?? patch.excerpt,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: AppColors.textDim, fontSize: 13, height: 1.5),
            ),
          ],
          if (_translating) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.accent),
                ),
                const SizedBox(width: 10),
                Text(
                  'Переводим текст… ${_total == 0 ? '' : '$_done из $_total'}',
                  style:
                      const TextStyle(fontSize: 11, color: AppColors.textDim),
                ),
              ],
            ),
          ],
          if (patch.images.length > 1) ...[
            const SizedBox(height: 16),
            SizedBox(
              height: 92,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: patch.images.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final url = patch.images[index];
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      url,
                      width: 150,
                      height: 92,
                      fit: BoxFit.cover,
                      cacheWidth: (150 * MediaQuery.devicePixelRatioOf(context))
                          .round(),
                      errorBuilder: (_, __, ___) => const SizedBox(
                          width: 150,
                          child: ColoredBox(color: AppColors.surfaceAlt)),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _versionBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.accent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        patch.version,
        style: const TextStyle(
          color: Colors.black,
          fontSize: 13,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  Widget _tag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(90)),
      ),
      child: Text(
        text,
        style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8),
      ),
    );
  }

  Widget _statsBlock(BuildContext context, List<StatChange> stats) {
    final groups = <String, List<StatChange>>{};
    for (final stat in stats) {
      groups.putIfAbsent(stat.groupKey, () => <StatChange>[]).add(stat);
    }
    final buffCount = stats.where((s) => s.impact == Impact.buff).length;
    final nerfCount = stats.where((s) => s.impact == Impact.nerf).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Тот же «пирожок-лента», что и у разделов статьи.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            color: AppColors.tape,
            child: const Text(
              'ИЗМЕНЕНИЯ ХАРАКТЕРИСТИК',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                fontStyle: FontStyle.italic,
                letterSpacing: 0.8,
                color: Colors.black,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            height: 1,
            width: double.infinity,
            color: AppColors.textPrimary.withAlpha(60),
          ),
          const SizedBox(height: 8),
          Text(
            '▲ $buffCount   ▼ $nerfCount · зелёный — улучшили, красный — ухудшили.',
            style: const TextStyle(fontSize: 12, color: AppColors.textDim),
          ),
          const SizedBox(height: 14),
          for (final entry in groups.entries) _group(entry.key, entry.value),
        ],
      ),
    );
  }

  Widget _group(String key, List<StatChange> changes) {
    final parts = key.split('\u0000');
    final category = parts.isNotEmpty ? parts[0] : '';
    final item = parts.length > 1 ? parts[1] : '';

    final header =
        item.isNotEmpty ? item : (category.isNotEmpty ? category : 'Общее');

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 2),
            child: Row(
              children: [
                if (item.isEmpty)
                  Container(width: 3, height: 16, color: AppColors.textPrimary)
                else ...[
                  Text(
                    header,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.accent,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    translateHeading(category),
                    style:
                        const TextStyle(fontSize: 11, color: AppColors.textDim),
                  ),
                ],
                if (item.isEmpty) ...[
                  const SizedBox(width: 8),
                  Text(
                    header,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ],
              ],
            ),
          ),
          for (final change in changes)
            StatTile(change: change, translations: _translations),
        ],
      ),
    );
  }

  Widget _footer(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () => launchUrl(Uri.parse(patch.url)),
          icon: const Icon(Icons.open_in_new_rounded, size: 16),
          label: const Text('Открыть оригинал на reachthefinals.com'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textPrimary,
            side: const BorderSide(color: AppColors.stroke),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ),
    );
  }
}
