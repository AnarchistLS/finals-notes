import 'package:flutter/material.dart';

import 'ui/home_page.dart';
import 'ui/theme.dart';
import 'ui/widgets/perf_overlay.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  PerfSettings.load();
  runApp(const FinalsNotesApp());
}

class FinalsNotesApp extends StatelessWidget {
  const FinalsNotesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: PerfSettings.showFps,
      builder: (context, showFps, _) {
        return MaterialApp(
          title: 'THE FINALS · Патчноуты',
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          home: const HomePage(),
          // Счётчик кадров рисуется поверх всего, включая страницу патча.
          builder: (context, child) => PerfOverlay(
            enabled: showFps,
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
    );
  }
}
