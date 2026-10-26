import 'package:flutter/material.dart';

import '../data/settings.dart';
import '../services/deepl.dart';
import 'theme.dart';
import 'widgets/perf_overlay.dart';

/// Шторка настроек: перевод, движок, ключ DeepL и диагностика.
class SettingsSheet extends StatefulWidget {
  const SettingsSheet({super.key});

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  final TextEditingController _keyController = TextEditingController();
  final TextEditingController _endpointController = TextEditingController();

  bool _translateEnabled = true;
  bool _showKey = false;
  bool _checking = false;
  String _backend = 'deepl';
  String? _status;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _keyController.dispose();
    _endpointController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final enabled = await Settings.translateEnabled();
    final backend = await Settings.translationBackend();
    final key = await Settings.deepLKey();
    final endpoint = await Settings.deepLEndpoint();
    if (!mounted) return;
    setState(() {
      _translateEnabled = enabled;
      _backend = backend;
      _keyController.text = key;
      _endpointController.text = endpoint;
    });
  }

  Future<void> _checkKey() async {
    setState(() {
      _checking = true;
      _status = null;
    });

    DeepLStatus.reset();
    final client = DeepLClient(
      apiKey: _keyController.text,
      endpoint: _endpointController.text,
    );

    String status;
    try {
      final usage = await client.usage();
      status = 'Ключ работает. Израсходовано ${_format(usage.count)} '
          'из ${_format(usage.limit)} символов.';
    } on DeepLException catch (error) {
      if (error.regionBlocked) {
        status = 'DeepL недоступен в вашем регионе (451). Нужен VPN или прокси — '
            'пока перевод идёт через Google.';
      } else if (error.quotaExceeded) {
        status = 'Квота на этот месяц исчерпана (456). Перевод пойдёт через Google.';
      } else if (error.authFailed) {
        status = 'Ключ не принят (${error.statusCode}). Проверьте, что скопирован целиком.';
      } else {
        status = 'DeepL ответил ошибкой ${error.statusCode}: ${error.message}';
      }
    } catch (_) {
      status = 'Не удалось связаться с DeepL. Проверьте интернет.';
    } finally {
      client.dispose();
    }

    if (!mounted) return;
    setState(() {
      _checking = false;
      _status = status;
    });
  }

  String _format(int value) {
    final digits = value.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('\u2009');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 18, 20, 28 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Настройки',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          const Text(
            'Текст патчей переводится автоматически. Названия предметов, карт, '
            'классов и специализаций остаются как в игре.',
            style: TextStyle(fontSize: 12, color: AppColors.textDim, height: 1.5),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Переводить патчноуты', style: TextStyle(fontSize: 15)),
            subtitle: const Text(
              'Перевод с кешем на устройстве',
              style: TextStyle(fontSize: 11, color: AppColors.textDim),
            ),
            value: _translateEnabled,
            activeThumbColor: AppColors.accent,
            onChanged: (value) async {
              await Settings.setTranslateEnabled(value);
              if (!mounted) return;
              setState(() => _translateEnabled = value);
            },
          ),
          const Divider(height: 26),
          const Text('Движок перевода', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'deepl', label: Text('DeepL')),
              ButtonSegment(value: 'google', label: Text('Google')),
            ],
            selected: {_backend},
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              backgroundColor: AppColors.surfaceAlt,
              foregroundColor: AppColors.textPrimary,
              selectedBackgroundColor: AppColors.accent,
              selectedForegroundColor: Colors.black,
              side: const BorderSide(color: AppColors.stroke),
              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            onSelectionChanged: (selection) async {
              final value = selection.first;
              await Settings.setTranslationBackend(value);
              if (!mounted) return;
              setState(() {
                _backend = value;
                _status = null;
              });
            },
          ),
          const SizedBox(height: 8),
          Text(
            _backend == 'deepl'
                ? 'DeepL точнее на связном тексте. Без ключа или при недоступности '
                    'сервиса приложение само переключится на Google.'
                : 'Google работает без ключа и без лимитов, но переводит суше.',
            style: const TextStyle(fontSize: 11, color: AppColors.textDim, height: 1.5),
          ),
          if (_backend == 'deepl') ...[
            const SizedBox(height: 14),
            TextField(
              controller: _keyController,
              obscureText: !_showKey,
              autocorrect: false,
              enableSuggestions: false,
              onChanged: Settings.setDeepLKey,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                labelText: 'Ключ DeepL API',
                hintText: 'xxxxxxxx-xxxx-…:fx',
                isDense: true,
                suffixIcon: IconButton(
                  icon: Icon(
                    _showKey ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                    size: 18,
                    color: AppColors.textDim,
                  ),
                  onPressed: () => setState(() => _showKey = !_showKey),
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _endpointController,
              autocorrect: false,
              enableSuggestions: false,
              onChanged: Settings.setDeepLEndpoint,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                labelText: 'Прокси (необязательно)',
                hintText: 'https://ваш-прокси.example.com',
                helperText: 'Если DeepL недоступен в регионе — адрес своего прокси, '
                    'совместимого с DeepL API',
                helperMaxLines: 2,
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _checking ? null : _checkKey,
                  icon: _checking
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.bolt_rounded, size: 18),
                  label: const Text('Проверить ключ'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.accent,
                    side: const BorderSide(color: AppColors.stroke),
                    textStyle: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
            if (_status != null) ...[
              const SizedBox(height: 8),
              Text(
                _status!,
                style: const TextStyle(fontSize: 11, color: AppColors.textDim, height: 1.5),
              ),
            ],
          ],
          const Divider(height: 26),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Счётчик FPS', style: TextStyle(fontSize: 15)),
            subtitle: const Text(
              'Частота кадров и частота экрана поверх интерфейса',
              style: TextStyle(fontSize: 11, color: AppColors.textDim),
            ),
            value: PerfSettings.showFps.value,
            activeThumbColor: AppColors.accent,
            onChanged: (value) async {
              await PerfSettings.set(value);
              if (!mounted) return;
              setState(() {});
            },
          ),
        ],
      ),
    );
  }
}
