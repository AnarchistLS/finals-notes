import 'dart:ui' show FramePhase;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../data/settings.dart';
import '../theme.dart';

/// Настройка диагностического счётчика кадров.
///
/// Живёт вне дерева виджетов: переключатель в шторке настроек не должен
/// пересобирать весь `MaterialApp`, достаточно перерисовать оверлей.
class PerfSettings {
  static final ValueNotifier<bool> showFps = ValueNotifier<bool>(false);

  static Future<void> load() async {
    showFps.value = await Settings.showFps();
  }

  static Future<void> set(bool value) async {
    showFps.value = value;
    await Settings.setShowFps(value);
  }
}

/// Счётчик кадров поверх интерфейса.
///
/// Нужен, чтобы отличить две разные проблемы: «приложение рисует 30 кадров»
/// и «телефон отдаёт приложению 60 Гц, хотя экран умеет 120». Показывает
/// реальный fps и частоту, которую система сообщает приложению.
class PerfOverlay extends StatefulWidget {
  const PerfOverlay({super.key, required this.enabled, required this.child});

  final bool enabled;
  final Widget child;

  @override
  State<PerfOverlay> createState() => _PerfOverlayState();
}

class _PerfOverlayState extends State<PerfOverlay> {
  /// Окно усреднения: полсекунды — достаточно, чтобы цифра не дёргалась.
  static const int _windowUs = 500000;

  double _fps = 0;
  int _frames = 0;
  int _windowStartUs = 0;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    super.dispose();
  }

  void _onTimings(List<FrameTiming> timings) {
    if (!widget.enabled || timings.isEmpty) return;
    final last = timings.last.timestampInMicroseconds(FramePhase.rasterFinish);
    if (_windowStartUs == 0) {
      _windowStartUs = last;
      _frames = 0;
      return;
    }
    _frames += timings.length;
    final elapsed = last - _windowStartUs;
    if (elapsed < _windowUs) return;
    final fps = _frames * 1000000 / elapsed;
    _windowStartUs = last;
    _frames = 0;
    if (mounted) setState(() => _fps = fps);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    final refresh = View.of(context).display.refreshRate;
    final target = refresh > 0 ? refresh : 60.0;
    final color = _fps >= target * 0.9
        ? AppColors.buff
        : _fps >= target * 0.55
            ? AppColors.accent
            : AppColors.nerf;
    final fpsText = _fps == 0 ? '— fps' : '${_fps.round()} fps';

    return Stack(
      fit: StackFit.expand,
      alignment: Alignment.topLeft,
      children: [
        widget.child,
        Positioned(
          top: MediaQuery.paddingOf(context).top + 6,
          right: 8,
          child: IgnorePointer(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withAlpha(170),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color.withAlpha(130)),
              ),
              child: Text(
                '$fpsText · ${refresh.round()} Гц',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
