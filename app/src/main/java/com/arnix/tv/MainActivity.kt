package com.arnix.tv

import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView

class MainActivity : AppCompatActivity() {
    private var player: ExoPlayer? = null
    private lateinit var playerView: PlayerView
    private lateinit var infoBar: LinearLayout
    private lateinit var hint: TextView
    private val handler = Handler(Looper.getMainLooper())
    private var overlayVisible = false
    private val defaultStreamUrl = "http://cdntv.online/hls/9n3hebsjat/playlist.m3u8"
    private val hideOverlay = Runnable { showInfoBar(false) }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        enterImmersiveMode()

        val root = FrameLayout(this).apply { setBackgroundColor(0xFF000000.toInt()) }
        playerView = PlayerView(this).apply {
            useController = false
            resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
            setShutterBackgroundColor(android.graphics.Color.BLACK)
            setBackgroundColor(android.graphics.Color.BLACK)
        }
        root.addView(playerView, FrameLayout.LayoutParams(-1, -1))

        hint = TextView(this).apply {
            text = "ARNIX TV\nПодключение к трансляции…"
            setTextColor(0xFFB8C2CC.toInt())
            textSize = 17f
            gravity = Gravity.CENTER
            setLineSpacing(6f, 1f)
        }
        root.addView(hint, FrameLayout.LayoutParams(-1, -1))

        infoBar = buildInfoBar()
        val infoParams = FrameLayout.LayoutParams(-1, dp(112), Gravity.BOTTOM)
        infoParams.setMargins(dp(20), 0, dp(20), dp(22))
        root.addView(infoBar, infoParams)
        infoBar.visibility = View.GONE
        root.setOnClickListener { toggleInfoBar() }
        playerView.setOnClickListener { toggleInfoBar() }
        setContentView(root)

        try {
            val exoPlayer = ExoPlayer.Builder(this).build()
            player = exoPlayer
            playerView.player = exoPlayer
            exoPlayer.addListener(object : Player.Listener {
                override fun onPlaybackStateChanged(playbackState: Int) {
                    if (playbackState == Player.STATE_BUFFERING) {
                        hint.text = "ARNIX TV\nПодключение к трансляции…"
                        hint.visibility = View.VISIBLE
                    } else if (playbackState == Player.STATE_READY) {
                        hint.visibility = View.GONE
                    }
                }

                override fun onPlayerError(error: PlaybackException) {
                    hint.text = "Не удалось запустить трансляцию\nПроверьте интернет или адрес потока\nКод: ${error.errorCodeName}"
                    hint.visibility = View.VISIBLE
                }
            })
            playChannel(defaultStreamUrl)
        } catch (error: Exception) {
            hint.text = "Ошибка запуска плеера\n${error.javaClass.simpleName}: ${error.message ?: "без подробностей"}"
            hint.visibility = View.VISIBLE
        }
    }

    private fun buildInfoBar(): LinearLayout {
        val bar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(22), dp(14), dp(22), dp(14))
            setBackgroundColor(0xE820252D.toInt())
            elevation = dp(12).toFloat()
        }
        val logo = TextView(this).apply {
            text = "TV"
            textSize = 21f
            setTextColor(0xFFFFFFFF.toInt())
            gravity = Gravity.CENTER
            setBackgroundColor(0xFF168BDB.toInt())
            typeface = android.graphics.Typeface.DEFAULT_BOLD
        }
        bar.addView(logo, LinearLayout.LayoutParams(dp(58), dp(58)))
        val textColumn = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(16), 0, 0, 0)
        }
        val channel = TextView(this).apply {
            text = "ARNIX TV • Прямой эфир"
            textSize = 19f
            setTextColor(0xFFFFFFFF.toInt())
            typeface = android.graphics.Typeface.DEFAULT_BOLD
        }
        val programme = TextView(this).apply {
            text = "Трансляция по умолчанию"
            textSize = 14f
            setTextColor(0xFFCAD2DC.toInt())
            setPadding(0, dp(7), 0, 0)
        }
        textColumn.addView(channel)
        textColumn.addView(programme)
        bar.addView(textColumn, LinearLayout.LayoutParams(0, -2, 1f))
        val live = TextView(this).apply {
            text = "● LIVE"
            textSize = 13f
            setTextColor(0xFFFF6666.toInt())
            typeface = android.graphics.Typeface.DEFAULT_BOLD
        }
        bar.addView(live)
        return bar
    }

    private fun playChannel(url: String) {
        hint.text = "ARNIX TV\nПодключение к трансляции…"
        hint.visibility = View.VISIBLE
        player?.setMediaItem(MediaItem.fromUri(url))
        player?.prepare()
        player?.playWhenReady = true
        showInfoBar(true)
    }

    private fun toggleInfoBar() = showInfoBar(!overlayVisible)
    private fun showInfoBar(show: Boolean) {
        overlayVisible = show
        infoBar.visibility = if (show) View.VISIBLE else View.GONE
        handler.removeCallbacks(hideOverlay)
        if (show) handler.postDelayed(hideOverlay, 7000)
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        when (keyCode) {
            KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER,
            KeyEvent.KEYCODE_DPAD_DOWN, KeyEvent.KEYCODE_MENU -> {
                toggleInfoBar()
                return true
            }
            KeyEvent.KEYCODE_BACK -> if (overlayVisible) {
                showInfoBar(false)
                return true
            }
        }
        return super.onKeyDown(keyCode, event)
    }

    private fun enterImmersiveMode() {
        WindowCompat.setDecorFitsSystemWindows(window, false)
        WindowInsetsControllerCompat(window, window.decorView).let { controller ->
            controller.hide(WindowInsetsCompat.Type.systemBars())
            controller.systemBarsBehavior =
                WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        }
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    override fun onStop() {
        player?.pause()
        super.onStop()
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        playerView.player = null
        player?.release()
        player = null
        super.onDestroy()
    }
}
