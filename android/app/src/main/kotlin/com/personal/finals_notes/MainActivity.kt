package com.personal.finals_notes

import android.os.Build
import android.os.Bundle
import android.view.Surface
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import android.view.ViewGroup
import io.flutter.embedding.android.FlutterActivity

/**
 * Включаем максимальную частоту обновления экрана.
 *
 * Движок Flutter не голосует за частоту кадров (в нём нет вызова
 * Surface.setFrameRate), поэтому Android по умолчанию держит окно приложения
 * на 60 Гц даже на 120-герцовой панели: экран работает на 120, а кадров
 * приложение получает 60. Здесь мы выбираем режим экрана с максимальной
 * частотой и голосуем за неё на поверхности отрисовки.
 */
class MainActivity : FlutterActivity() {

    /** Частота выбранного режима экрана, например 120.0. */
    private var targetRate = 0f

    private val surfaceViews = mutableListOf<SurfaceView>()
    private val watched = HashSet<SurfaceView>()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        pickBestMode()
        // Поверхность Flutter появляется только после первого layout.
        window.decorView.post { collectSurfaces(window.decorView) }
    }

    override fun onResume() {
        super.onResume()
        // Система может сбросить голос при возврате в приложение — повторяем.
        window.decorView.post { voteAll() }
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) window.decorView.post { voteAll() }
    }

    /** Просим у окна режим с самой высокой частотой обновления. */
    private fun pickBestMode() {
        val modes = currentDisplay()?.supportedModes ?: return
        val best = modes.maxByOrNull { it.refreshRate } ?: return
        targetRate = best.refreshRate

        val params = window.attributes
        params.preferredDisplayModeId = best.modeId
        params.preferredRefreshRate = best.refreshRate
        window.attributes = params
    }

    private fun currentDisplay() =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            display
        } else {
            @Suppress("DEPRECATION")
            windowManager.defaultDisplay
        }

    private fun collectSurfaces(root: View) {
        if (root is SurfaceView && watched.add(root)) {
            surfaceViews.add(root)
            root.holder.addCallback(object : SurfaceHolder.Callback {
                override fun surfaceCreated(holder: SurfaceHolder) = vote(holder.surface)
                override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) =
                    vote(holder.surface)
                override fun surfaceDestroyed(holder: SurfaceHolder) = Unit
            })
        }
        if (root is ViewGroup) {
            for (index in 0 until root.childCount) collectSurfaces(root.getChildAt(index))
        }
    }

    private fun voteAll() {
        for (view in surfaceViews) {
            vote(view.holder.surface)
        }
    }

    /**
     * Голос за частоту кадра: с Android 11 система переключает панель под него.
     * На более старых версиях остаётся только preferredDisplayModeId выше.
     */
    private fun vote(surface: Surface?) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        if (surface == null || !surface.isValid || targetRate <= 0f) return
        try {
            surface.setFrameRate(targetRate, Surface.FRAME_RATE_COMPATIBILITY_DEFAULT)
        } catch (_: Throwable) {
            // Отдельные прошивки не принимают голос — не повод падать.
        }
    }
}
