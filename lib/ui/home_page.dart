import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/published.dart';
import '../data/repository.dart';
import '../l10n/glossary.dart';
import '../models/models.dart';
import 'patch_page.dart';
import 'settings_sheet.dart';
import 'theme.dart';
import 'widgets/patch_card.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final PatchRepository _repository = PatchRepository();
  final PublishedRepository _published = PublishedRepository();
  final TextEditingController _searchController = TextEditingController();

  List<PatchDoc> _patches = const [];
  bool _loading = true;
  String? _error;
  String _query = '';

  /// Mini App читает готовый переведённый файл вместо сайта.
  bool _isPublished = false;
  DateTime? _updatedAt;

  /// Переводы из готового файла: id патча -> «оригинал -> русский».
  final Map<String, Map<String, String>> _translations = {};

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _repository.dispose();
    _published.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    // В Mini App сначала пробуем готовый файл: он уже переведён и лежит на
    // том же домене, поэтому не упирается в CORS сайта и грузится мгновенно.
    // Сначала - свежий вариант (?v=…): он обходит кеш service worker и
    // кеш GitHub Pages, поэтому новый патч виден сразу после открытия,
    // а не после свайпа вниз или следующего перезапуска.
    if (kIsWeb) {
      var snapshot = await _published.load(fresh: true);
      snapshot ??= await _published.load();
      if (!mounted) return;
      if (snapshot != null) {
        _applyPublished(snapshot);
        return;
      }
    }

    final cached = await _repository.loadCached();
    if (!mounted) return;
    if (cached.isNotEmpty) {
      setState(() {
        _patches = cached;
        _loading = false;
      });
    }
    await _refresh(silent: cached.isNotEmpty);
  }

  void _applyPublished(PublishedSnapshot snapshot) {
    setState(() {
      _isPublished = true;
      _updatedAt = snapshot.generatedAt;
      _translations
        ..clear()
        ..addEntries(
          snapshot.patches.map((item) => MapEntry(item.doc.id, item.translations)),
        );
      _patches = snapshot.patches.map((item) => item.doc).toList();
      _loading = false;
      _error = null;
    });
  }

  Future<void> _refresh({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    if (_isPublished) {
      final snapshot = await _published.load(fresh: true);
      if (!mounted) return;
      if (snapshot != null) {
        _applyPublished(snapshot);
      } else {
        setState(() {
          _loading = false;
          _error = 'Не удалось обновить данные приложения';
        });
      }
      return;
    }

    try {
      final fresh = await _repository.fetch(pages: 4);
      if (!mounted) return;
      setState(() {
        _patches = fresh;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  String get _subtitle {
    if (_patches.isEmpty) return 'Загрузка обновлений…';
    final updated = _updatedAt;
    if (_isPublished && updated != null) {
      final day = updated.day.toString().padLeft(2, '0');
      final month = updated.month.toString().padLeft(2, '0');
      final hour = updated.hour.toString().padLeft(2, '0');
      final minute = updated.minute.toString().padLeft(2, '0');
      return 'Обновлено $day.$month в $hour:$minute';
    }
    return 'Изменения баланса и правки игры';
  }

  List<PatchDoc> get _visible {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return _patches;
    return _patches.where((patch) {
      if (patch.title.toLowerCase().contains(query)) return true;
      if (translateTitle(patch.title).toLowerCase().contains(query)) return true;
      if (patch.version.toLowerCase().contains(query)) return true;
      for (final stat in patch.stats) {
        if (stat.item.toLowerCase().contains(query)) return true;
        if (stat.stat.toLowerCase().contains(query)) return true;
        if (translateStatName(stat.stat).toLowerCase().contains(query)) return true;
      }
      return false;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppColors.accent,
          backgroundColor: AppColors.surface,
          onRefresh: _refresh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: _header()),
              SliverToBoxAdapter(child: _searchField()),
              if (_loading && _patches.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: CircularProgressIndicator(color: AppColors.accent),
                  ),
                )
              else if (_patches.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _emptyState(context),
                )
              else if (visible.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Text(
                      'Ничего не нашлось по «$_query»',
                      style: const TextStyle(color: AppColors.textDim),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                  sliver: SliverList.builder(
                    itemCount: visible.length,
                    itemBuilder: (context, index) {
                      final patch = visible[index];
                      return PatchCard(
                        patch: patch,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => PatchPage(
                                patch: patch,
                                translations: _translations[patch.id],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'THE FINALS',
                      style: TextStyle(
                        fontSize: 13,
                        letterSpacing: 4,
                        fontWeight: FontWeight.w700,
                        color: AppColors.accent,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Патчноуты',
                      style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, height: 1.05),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _subtitle,
                      style: const TextStyle(color: AppColors.textDim, fontSize: 13),
                    ),
                  ],
                ),
              ),
              // В Mini App перевод уже готов, поэтому настройки движка и ключей
              // там не нужны - оставляем только обновление.
              if (!_isPublished) ...[
                IconButton(
                  onPressed: _openSettings,
                  tooltip: 'Настройки',
                  icon: const Icon(Icons.tune_rounded),
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.surface,
                    foregroundColor: AppColors.textDim,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              IconButton(
                onPressed: () => _refresh(),
                tooltip: 'Обновить',
                icon: const Icon(Icons.refresh_rounded),
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.surface,
                  foregroundColor: AppColors.accent,
                ),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            _errorBanner(_error!),
          ],
        ],
      ),
    );
  }

  Future<void> _openSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const SettingsSheet(),
    );
  }

  Widget _errorBanner(String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.nerf.withAlpha(20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.nerf.withAlpha(80)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.wifi_off_rounded, size: 18, color: AppColors.nerf),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$message\nПоказаны сохранённые данные.',
              style: const TextStyle(fontSize: 12, color: AppColors.textDim, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
      child: TextField(
        controller: _searchController,
        onChanged: (value) => setState(() => _query = value),
        textInputAction: TextInputAction.search,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Оружие, показатель или версия…',
          prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textDim),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  color: AppColors.textDim,
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _query = '');
                  },
                ),
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.article_outlined, size: 46, color: AppColors.textDim),
          const SizedBox(height: 14),
          Text(
            _error == null ? 'Пока пусто' : 'Не удалось загрузить патчноуты',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            'Потяните вниз, чтобы повторить загрузку',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textDim, fontSize: 13),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textDim, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}
