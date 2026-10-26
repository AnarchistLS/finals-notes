/// Загрузка патчей с сайта и локальный кеш для офлайна.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../parser/patch_parser.dart';

class PatchRepository {
  PatchRepository({http.Client? client, this.apiBase = defaultApiBase})
      : _client = client ?? http.Client();

  final http.Client _client;
  final String apiBase;

  static const String _cacheKey = 'finals_patches_v2';

  /// Читает последний удачный ответ из кеша (офлайн-режим).
  Future<List<PatchDoc>> loadCached() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return const [];
      final items = decoded['items'];
      if (items is! List) return const [];
      return items
          .map((e) => PatchDoc.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Скачивает [pages] страниц списка и разбирает их.
  Future<List<PatchDoc>> fetch({int pages = 4}) async {
    final patches = await fetchPatches(
      client: _client,
      apiBase: apiBase,
      pages: pages,
    );
    await _save(patches);
    return patches;
  }

  Future<void> _save(List<PatchDoc> patches) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = jsonEncode({
      'savedAt': DateTime.now().toIso8601String(),
      'items': patches.map((p) => p.toJson()).toList(),
    });
    await prefs.setString(_cacheKey, payload);
  }

  void dispose() => _client.close();
}
