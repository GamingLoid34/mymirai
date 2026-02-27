package com.mymirai.my_mirai

import android.os.Build
import android.view.Window
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onResume() {
        super.onResume()
        requestHighestRefreshRateIfAvailable()
    }

    private fun requestHighestRefreshRateIfAvailable() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return

        val display = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            display
        } else {
            @Suppress("DEPRECATION")
            windowManager.defaultDisplay
        } ?: return

        val bestMode = display.supportedModes.maxByOrNull { it.refreshRate } ?: return

        val attrs = window.attributes
        attrs.preferredDisplayModeId = bestMode.modeId
        window.attributes = attrs

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.setFrameRate(
                bestMode.refreshRate,
                Window.FRAME_RATE_COMPATIBILITY_DEFAULT
            )
        }
    }
}
