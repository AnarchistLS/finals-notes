import 'package:flutter/material.dart';

import '../../l10n/glossary.dart';
import '../../models/models.dart';
import '../theme.dart';

class StatTile extends StatelessWidget {
  const StatTile(
      {super.key, required this.change, this.translations = const {}});

  final StatChange change;

  /// Переводы названий характеристик (оригинал -> русский).
  final Map<String, String> translations;

  Color get _color => switch (change.impact) {
        Impact.buff => AppColors.buff,
        Impact.nerf => AppColors.nerf,
        Impact.neutral => AppColors.textDim,
      };

  IconData get _icon => switch (change.impact) {
        Impact.buff => Icons.arrow_upward_rounded,
        Impact.nerf => Icons.arrow_downward_rounded,
        Impact.neutral => Icons.remove_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final color = _color;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 9, 12, 9),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.stroke.withAlpha(120)),
      ),
      child: Row(
        children: [
          // Цветной скруглённый квадрат со стрелкой — фирменный маркер
          // изменения у Darkside.
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(
              _icon,
              size: 18,
              color: Colors.black,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (change.item.isNotEmpty)
                  Text(
                    change.item,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.accent,
                      height: 1.2,
                    ),
                  ),
                Text(
                  displayStatName(change.stat, translations),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                children: [
                  Text(
                    change.beforeText,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accent,
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 5),
                    child: Icon(Icons.arrow_forward_rounded,
                        size: 12, color: AppColors.textDim),
                  ),
                  Text(
                    change.afterText,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: color),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                change.deltaText,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: color.withAlpha(200)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
