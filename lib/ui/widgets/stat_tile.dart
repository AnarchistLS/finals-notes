import 'package:flutter/material.dart';

import '../../l10n/glossary.dart';
import '../../models/models.dart';
import '../theme.dart';

class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.change, this.translations = const {}});

  final StatChange change;

  /// Переводы названий характеристик (оригинал -> русский).
  final Map<String, String> translations;

  Color get _color => switch (change.impact) {
        Impact.buff => AppColors.buff,
        Impact.nerf => AppColors.nerf,
        Impact.neutral => AppColors.textDim,
      };

  IconData get _icon => switch (change.impact) {
        Impact.buff => Icons.trending_up_rounded,
        Impact.nerf => Icons.trending_down_rounded,
        Impact.neutral => Icons.remove_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final color = _color;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withAlpha(70)),
      ),
      child: Row(
        children: [
          Icon(_icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayStatName(change.stat, translations),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.25),
                ),
                if (change.item.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    change.item,
                    style: const TextStyle(fontSize: 11, color: AppColors.textDim),
                  ),
                ],
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
                      fontSize: 14,
                      color: AppColors.textDim,
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(Icons.arrow_forward_rounded, size: 13, color: AppColors.textDim),
                  ),
                  Text(
                    change.afterText,
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: color),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withAlpha(28),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  change.deltaText,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
