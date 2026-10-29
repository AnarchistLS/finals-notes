import 'package:flutter/material.dart';

import '../../l10n/glossary.dart';
import '../../models/models.dart';
import '../theme.dart';

class PatchCard extends StatelessWidget {
  const PatchCard({super.key, required this.patch, required this.onTap});

  final PatchDoc patch;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  // Рамка обложки «плавает» внутри карточки с отступом от
                  // кромок — иначе скруглённые углы карточки срезали
                  // белый контур сверху.
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Container(
                      // Тонкая кремовая рамка вокруг обложки — как у картинок
                      // в постах Darkside.
                      foregroundDecoration: BoxDecoration(
                        border:
                            Border.all(color: AppColors.textPrimary, width: 2),
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _cover(context),
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Colors.transparent, Color(0xDE131313)],
                                stops: [0.35, 1],
                              ),
                            ),
                          ),
                          Positioned(
                            left: 12,
                            top: 12,
                            child: Row(
                              children: [
                                if (patch.version.isNotEmpty)
                                  _badge(patch.version, filled: true),
                                if (patch.isStore) ...[
                                  const SizedBox(width: 6),
                                  _badge('МАГАЗИН'),
                                ],
                              ],
                            ),
                          ),
                          Positioned(
                            left: 14,
                            right: 14,
                            bottom: 12,
                            child: Text(
                              translateTitle(patch.title),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                height: 1.15,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                  child: Row(
                    children: [
                      Text(
                        patch.dateText,
                        style: const TextStyle(
                            color: AppColors.textDim, fontSize: 12),
                      ),
                      const SizedBox(width: 12),
                      if (patch.buffCount > 0)
                        _counter('▲ ${patch.buffCount}', AppColors.buff),
                      if (patch.buffCount > 0 && patch.nerfCount > 0)
                        const SizedBox(width: 6),
                      if (patch.nerfCount > 0)
                        _counter('▼ ${patch.nerfCount}', AppColors.nerf),
                      const Spacer(),
                      if (patch.stats.isEmpty)
                        const Text(
                          'без изменения статов',
                          style:
                              TextStyle(color: AppColors.textDim, fontSize: 11),
                        )
                      else
                        Text(
                          '${patch.stats.length} изм.',
                          style: const TextStyle(
                              color: AppColors.textDim, fontSize: 11),
                        ),
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right_rounded,
                          size: 18, color: AppColors.textDim),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _cover(BuildContext context) {
    final url = patch.cover;
    if (url == null || url.isEmpty) {
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1B1B25), Color(0xFF0E0E14)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Text(
            patch.version.isEmpty ? 'THE FINALS' : patch.version,
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w900,
              color: Colors.white.withAlpha(24),
            ),
          ),
        ),
      );
    }
    return Image.network(
      url,
      fit: BoxFit.cover,
      // Обложки на сайте крупные (1500+ px). Декодируем под ширину экрана,
      // иначе каждая картинка съедает десятки мегабайт и подгрузка при
      // скролле заметно роняет fps.
      cacheWidth: _decodeWidth(context),
      filterQuality: FilterQuality.low,
      errorBuilder: (_, __, ___) => Container(color: AppColors.surfaceAlt),
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Container(color: AppColors.surfaceAlt);
      },
    );
  }

  int _decodeWidth(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return (size.width * dpr).round();
  }

  Widget _badge(String text, {bool filled = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: filled ? AppColors.accent : Colors.black.withAlpha(150),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: filled ? AppColors.accent : Colors.white.withAlpha(60),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
          color: filled ? Colors.black : Colors.white,
        ),
      ),
    );
  }

  Widget _counter(String text, Color color) {
    return Text(
      text,
      style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
    );
  }
}
