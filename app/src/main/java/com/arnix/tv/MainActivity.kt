package com.arnix.tv

import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.Typeface
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.style.ForegroundColorSpan
import android.text.style.StyleSpan
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Xml
import android.view.Gravity
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ProgressBar
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
import org.xmlpull.v1.XmlPullParser
import java.io.BufferedInputStream
import java.util.zip.GZIPInputStream
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

class MainActivity : AppCompatActivity() {
    private data class Channel(
        val name: String,
        val url: String,
        val id: String,
        val logo: String,
        val group: String
    )
    private data class Programme(val title: String, val start: Long, val stop: Long)

    private var player: ExoPlayer? = null
    private lateinit var playerView: PlayerView
    private lateinit var infoBar: LinearLayout
    private lateinit var hint: TextView
    private lateinit var logoView: ImageView
    private lateinit var logoFallback: TextView
    private lateinit var channelNameView: TextView
    private lateinit var channelMetaView: TextView
    private lateinit var nowView: TextView
    private lateinit var nextView: TextView
    private lateinit var progress: ProgressBar
    private val handler = Handler(Looper.getMainLooper())
    private var overlayVisible = false
    private var touchDownX = 0f
    private var touchDownY = 0f
    private var channels: List<Channel> = emptyList()
    private var currentChannelIndex = -1
    private var currentProgramme: Programme? = null
    private val epgCache = ConcurrentHashMap<String, List<Programme>>()

    private val playlistUrl = "http://cdntv.online/high/9n3hebsjat/mpeg.m3u"
    private var epgUrl: String? = null
    private val fallbackEpgUrl: String? = "https://iptvx.one/epg/epg_lite.xml.gz"
    private val epgExecutor = Executors.newSingleThreadExecutor()
    private val warmExecutor = Executors.newFixedThreadPool(2)
    private val warmedStreams = ConcurrentHashMap<String, Long>()
    @Volatile private var epgLoading = false
    @Volatile private var epgLoaded = false
    private val hideOverlay = Runnable { showInfoBar(false) }
    private val progressTicker = object : Runnable {
        override fun run() {
            refreshCurrentEpg()
            updateProgress()
            handler.postDelayed(this, 15000)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        enterImmersiveMode()

        val root = FrameLayout(this).apply { setBackgroundColor(Color.BLACK) }
        playerView = PlayerView(this).apply {
            useController = false
            resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
            setShutterBackgroundColor(Color.BLACK)
            setBackgroundColor(Color.BLACK)
        }
        root.addView(playerView, FrameLayout.LayoutParams(-1, -1))

        hint = TextView(this).apply {
            text = "ARNIX TV\nЗагрузка списка каналов…"
            setTextColor(0xFFB8C2CC.toInt())
            textSize = 17f
            gravity = Gravity.CENTER
            setLineSpacing(6f, 1f)
        }
        root.addView(hint, FrameLayout.LayoutParams(-1, -1))

        infoBar = buildInfoBar()
        val infoParams = FrameLayout.LayoutParams(-1, -2, Gravity.BOTTOM)
        infoParams.setMargins(dp(18), 0, dp(18), dp(22))
        root.addView(infoBar, infoParams)
        infoBar.visibility = View.GONE

        val gestureListener = View.OnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    touchDownX = event.x
                    touchDownY = event.y
                    true
                }
                MotionEvent.ACTION_UP -> {
                    val dx = event.x - touchDownX
                    val dy = event.y - touchDownY
                    if (kotlin.math.abs(dy) > dp(65) && kotlin.math.abs(dy) > kotlin.math.abs(dx) * 1.25f) {
                        if (dy < 0) changeChannel(1) else changeChannel(-1)
                    } else if (kotlin.math.abs(dx) < dp(35) && kotlin.math.abs(dy) < dp(35)) {
                        toggleInfoBar()
                    }
                    true
                }
                MotionEvent.ACTION_CANCEL -> true
                else -> true
            }
        }
        root.setOnTouchListener(gestureListener)
        playerView.setOnTouchListener(gestureListener)
        setContentView(root)

        try {
            val exoPlayer = ExoPlayer.Builder(this).build()
            player = exoPlayer
            playerView.player = exoPlayer
            exoPlayer.addListener(object : Player.Listener {
                override fun onPlaybackStateChanged(playbackState: Int) {
                    if (playbackState == Player.STATE_BUFFERING) {
                        hint.visibility = View.GONE
                    } else if (playbackState == Player.STATE_READY) {
                        hint.visibility = View.GONE
                    }
                }
                override fun onPlayerError(error: PlaybackException) {
                    hint.text = "Не удалось запустить канал\nКод: ${error.errorCodeName}"
                    hint.visibility = View.VISIBLE
                }
            })
            loadPlaylist()
        } catch (error: Exception) {
            hint.text = "Ошибка запуска плеера\n${error.javaClass.simpleName}: ${error.message ?: "без подробностей"}"
            hint.visibility = View.VISIBLE
        }
        handler.post(progressTicker)
    }

    private fun buildInfoBar(): LinearLayout {
        val panel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(18), dp(14), dp(18), dp(14))
            background = GradientDrawable().apply {
                setColor(0xB8172533.toInt())
                cornerRadius = dp(20).toFloat()
                setStroke(dp(1), 0xB8FFFFFF.toInt())
            }
            elevation = dp(8).toFloat()
        }

        val top = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        val logoFrame = FrameLayout(this).apply {
            background = GradientDrawable().apply {
                setColor(0xFF263342.toInt())
                cornerRadius = dp(12).toFloat()
            }
        }
        logoView = ImageView(this).apply { scaleType = ImageView.ScaleType.FIT_CENTER }
        logoFrame.addView(logoView, FrameLayout.LayoutParams(-1, -1))
        logoFallback = TextView(this).apply {
            text = "TV"
            textSize = 20f
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            typeface = Typeface.DEFAULT_BOLD
        }
        logoFrame.addView(logoFallback, FrameLayout.LayoutParams(-1, -1))
        top.addView(logoFrame, LinearLayout.LayoutParams(dp(62), dp(62)))

        val titles = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(14), 0, dp(8), 0)
        }
        channelNameView = TextView(this).apply {
            text = "ARNIX TV"
            textSize = 19f
            maxLines = 1
            ellipsize = android.text.TextUtils.TruncateAt.END
            setTextColor(Color.WHITE)
            typeface = Typeface.DEFAULT_BOLD
        }
        channelMetaView = TextView(this).apply {
            text = "Канал 0 • Прямой эфир"
            textSize = 12f
            setTextColor(0xFFB8C5D4.toInt())
            setPadding(0, dp(4), 0, 0)
        }
        titles.addView(channelNameView)
        titles.addView(channelMetaView)
        top.addView(titles, LinearLayout.LayoutParams(0, -2, 1f))

        val accent = View(this).apply {
            background = GradientDrawable().apply {
                setColor(0xFF55B7FF.toInt())
                cornerRadius = dp(3).toFloat()
            }
        }
        top.addView(accent, LinearLayout.LayoutParams(dp(4), dp(34)))
        panel.addView(top)

        val separator = View(this).apply { setBackgroundColor(0x44FFFFFF) }
        val sepParams = LinearLayout.LayoutParams(-1, dp(1))
        sepParams.topMargin = dp(12)
        sepParams.bottomMargin = dp(9)
        panel.addView(separator, sepParams)

        nowView = epgLine("СЕЙЧАС", "Загрузка программы…")
        panel.addView(nowView)
        nextView = epgLine("ДАЛЕЕ", "Нет данных программы")
        val nextParams = LinearLayout.LayoutParams(-1, -2)
        nextParams.topMargin = dp(7)
        panel.addView(nextView, nextParams)

        progress = ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal).apply {
            max = 1000
            progress = 0
            progressTintList = android.content.res.ColorStateList.valueOf(0xFF45A5FF.toInt())
            progressBackgroundTintList = android.content.res.ColorStateList.valueOf(0x55FFFFFF)
        }
        val progressParams = LinearLayout.LayoutParams(-1, dp(3))
        progressParams.topMargin = dp(11)
        panel.addView(progress, progressParams)
        return panel
    }

    private fun epgLine(label: String, initial: String): TextView {
        return TextView(this).apply {
            text = "$label   $initial"
            textSize = 13f
            maxLines = 2
            ellipsize = android.text.TextUtils.TruncateAt.END
            setLineSpacing(dp(3).toFloat(), 1.0f)
            setTextColor(0xFFE5EBF2.toInt())
            setPadding(0, dp(2), 0, dp(2))
        }
    }

    private fun loadPlaylist() {
        hint.text = "ARNIX TV\nЗагрузка списка каналов…"
        Thread {
            var connection: HttpURLConnection? = null
            try {
                connection = (URL(playlistUrl).openConnection() as HttpURLConnection).apply {
                    connectTimeout = 15000
                    readTimeout = 25000
                    setRequestProperty("User-Agent", "ARNIX-TV/0.3")
                }
                val body = connection.inputStream.bufferedReader(Charsets.UTF_8).use { it.readText() }
                val header = body.lineSequence().firstOrNull { it.startsWith("#EXTM3U", true) }.orEmpty()
                epgUrl = Regex("""(?:url-tvg|x-tvg-url)="([^"]+)"""", RegexOption.IGNORE_CASE).find(header)?.groupValues?.getOrNull(1)
                val parsed = parseM3u(body, playlistUrl)
                runOnUiThread {
                    if (isFinishing || isDestroyed) return@runOnUiThread
                    channels = parsed
                    if (channels.isEmpty()) {
                        hint.text = "В плейлисте нет доступных HTTP/HTTPS-каналов"
                        hint.visibility = View.VISIBLE
                    } else {
                        playChannel(0)
                    }
                }
            } catch (error: Exception) {
                runOnUiThread {
                    if (isFinishing || isDestroyed) return@runOnUiThread
                    hint.text = "Ошибка загрузки списка\n${error.message ?: "проверьте интернет"}"
                    hint.visibility = View.VISIBLE
                }
            } finally {
                connection?.disconnect()
            }
        }.start()
    }

    private fun parseM3u(content: String, baseUrl: String): List<Channel> {
        val result = mutableListOf<Channel>()
        var pending: Channel? = null
        content.lineSequence().forEach { raw ->
            val line = raw.trim()
            if (line.startsWith("#EXTINF", true)) {
                val name = line.substringAfterLast(',').trim().ifBlank { "Телеканал" }
                fun attr(key: String): String {
                    val match = Regex("""$key="([^"]*)"""", RegexOption.IGNORE_CASE).find(line)
                    return match?.groupValues?.getOrNull(1).orEmpty()
                }
                pending = Channel(name, "", attr("tvg-id"), attr("tvg-logo"), attr("group-title"))
            } else if (line.isNotBlank() && !line.startsWith("#") && pending != null) {
                val url = try { URL(URL(baseUrl), line).toString() } catch (_: Exception) { line }
                if (url.startsWith("http://", true) || url.startsWith("https://", true) || url.startsWith("udp://", true)) {
                    result.add(pending!!.copy(url = url))
                }
                pending = null
            }
        }
        return result
    }

    private fun playChannel(index: Int) {
        if (channels.isEmpty()) return
        currentChannelIndex = ((index % channels.size) + channels.size) % channels.size
        val channel = channels[currentChannelIndex]
        channelNameView.text = channel.name
        channelMetaView.text = "Канал ${currentChannelIndex + 1} из ${channels.size}" +
            if (channel.group.isNotBlank()) " • ${channel.group}" else ""
        nowView.text = "СЕЙЧАС   Загрузка программы…"
        nextView.text = "ДАЛЕЕ   Загрузка программы…"
        currentProgramme = null
        progress.progress = 0
        loadLogo(channel)
        showInfoBar(true)
        loadEpgFor(channel)
        if (channel.url.startsWith("udp://", true)) {
            player?.stop()
            hint.text = "Канал есть в плейлисте, но использует UDP multicast.\\nДля просмотра нужна сеть провайдера с поддержкой multicast."
            hint.visibility = View.VISIBLE
        } else {
            hint.visibility = View.GONE
            player?.setMediaItem(MediaItem.fromUri(channel.url))
            player?.prepare()
            player?.playWhenReady = true
        }
        preloadAdjacentChannels()
    }

    // Прогреваем только следующий HLS-поток, не скачивая обычные HTTP-видео.
    private fun preloadAdjacentChannels() {
        if (channels.isEmpty() || currentChannelIndex !in channels.indices) return
        val url = channels[(currentChannelIndex + 1) % channels.size].url
        if (!url.startsWith("http://", true) && !url.startsWith("https://", true)) return
        if (System.currentTimeMillis() - (warmedStreams[url] ?: 0L) < 120_000L) return
        warmExecutor.execute { warmStream(url) }
    }

    private fun warmStream(streamUrl: String) {
        if (!streamUrl.contains(".m3u8", true)) return
        var connection: HttpURLConnection? = null
        try {
            connection = (URL(streamUrl).openConnection() as HttpURLConnection).apply {
                connectTimeout = 2500
                readTimeout = 2500
                instanceFollowRedirects = true
                setRequestProperty("Range", "bytes=0-2047")
                setRequestProperty("User-Agent", "ARNIX-TV/0.6")
            }
            val reader = connection.inputStream.bufferedReader(Charsets.UTF_8)
            var segment: String? = null
            for (i in 0 until 40) {
                val line = reader.readLine() ?: break
                val value = line.trim()
                if (value.isNotEmpty() && !value.startsWith("#")) { segment = value; break }
            }
            reader.close()
            if (segment != null) {
                val segmentUrl = URL(URL(streamUrl), segment).toString()
                var seg: HttpURLConnection? = null
                try {
                    seg = (URL(segmentUrl).openConnection() as HttpURLConnection).apply {
                        connectTimeout = 2500
                        readTimeout = 2500
                        instanceFollowRedirects = true
                        setRequestProperty("Range", "bytes=0-2047")
                        setRequestProperty("User-Agent", "ARNIX-TV/0.6")
                    }
                    seg.inputStream.use { it.readNBytes(2048) }
                    warmedStreams[streamUrl] = System.currentTimeMillis()
                } finally { seg?.disconnect() }
            }
        } catch (_: Exception) {
        } finally { connection?.disconnect() }
    }

    private fun changeChannel(step: Int) {
        if (channels.isEmpty()) return
        playChannel(currentChannelIndex + step)
    }

    private fun loadLogo(channel: Channel) {
        logoView.setImageDrawable(null)
        logoFallback.visibility = View.VISIBLE
        if (channel.logo.isBlank()) return
        Thread {
            var connection: HttpURLConnection? = null
            try {
                connection = (URL(channel.logo).openConnection() as HttpURLConnection).apply {
                    connectTimeout = 8000
                    readTimeout = 8000
                    instanceFollowRedirects = true
                    setRequestProperty("User-Agent", "ARNIX-TV/0.3")
                }
                val bitmap = connection.inputStream.use { BitmapFactory.decodeStream(it) }
                runOnUiThread {
                    if (!isFinishing && !isDestroyed && currentChannelIndex >= 0 &&
                        channels[currentChannelIndex].logo == channel.logo && bitmap != null) {
                        logoView.setImageBitmap(bitmap)
                        logoFallback.visibility = View.GONE
                    }
                }
            } catch (_: Exception) {
            } finally {
                connection?.disconnect()
            }
        }.start()
    }

    private fun normalizeChannelName(value: String): String =
        value.lowercase(Locale.ROOT).replace(Regex("[^\\p{L}\\p{N}]"), "")

    private fun loadEpgFor(channel: Channel) {
        val key = channel.id.ifBlank { normalizeChannelName(channel.name) }
        epgCache[key]?.let { displayEpg(channel, it); return }
        if (epgLoaded) {
            nowView.text = "СЕЙЧАС   Нет программы для канала"
            nextView.text = "ДАЛЕЕ   Нет данных"
            return
        }
        nowView.text = "СЕЙЧАС   Загружается ТВ-программа…"
        nextView.text = "ДАЛЕЕ   Данные появятся после загрузки"
        if (epgLoading) return
        val source = epgUrl?.takeIf { it.isNotBlank() } ?: fallbackEpgUrl ?: return
        epgLoading = true
        epgExecutor.execute {
            var connection: HttpURLConnection? = null
            try {
                connection = (URL(source).openConnection() as HttpURLConnection).apply {
                    connectTimeout = 12000
                    readTimeout = 30000
                    instanceFollowRedirects = true
                    setRequestProperty("User-Agent", "ARNIX-TV/0.6")
                    setRequestProperty("Accept-Encoding", "gzip")
                }
                val raw = BufferedInputStream(connection.inputStream, 64 * 1024)
                raw.mark(2)
                val b1 = raw.read()
                val b2 = raw.read()
                raw.reset()
                val gzip = source.substringBefore('?').endsWith(".gz", true) ||
                    connection.contentEncoding?.contains("gzip", true) == true || (b1 == 0x1f && b2 == 0x8b)
                val input = if (gzip) GZIPInputStream(raw, 64 * 1024) else raw
                val all = parseEpgAll(input)
                all.forEach { (id, programmes) -> epgCache[id] = programmes }
                runOnUiThread {
                    channels.forEach { item ->
                        val itemKey = item.id.ifBlank { normalizeChannelName(item.name) }
                        val matched = all["name:" + normalizeChannelName(item.name)]
                        if (matched != null) epgCache[itemKey] = matched
                    }
                    epgLoaded = true
                    epgLoading = false
                    if (currentChannelIndex in channels.indices) {
                        val current = channels[currentChannelIndex]
                        epgCache[current.id.ifBlank { normalizeChannelName(current.name) }]
                            ?.let { displayEpg(current, it) }
                    }
                }
            } catch (_: Exception) {
                epgLoading = false
                runOnUiThread {
                    if (!isFinishing && !isDestroyed) {
                        nowView.text = "СЕЙЧАС   EPG временно недоступен"
                        nextView.text = "ДАЛЕЕ   Повторите позже"
                    }
                }
            } finally { connection?.disconnect() }
        }
    }

    private fun parseEpgAll(input: java.io.InputStream): Map<String, List<Programme>> {
        val parser = Xml.newPullParser()
        parser.setFeature(XmlPullParser.FEATURE_PROCESS_NAMESPACES, false)
        parser.setInput(input, "UTF-8")
        val names = mutableMapOf<String, MutableSet<String>>()
        val data = mutableMapOf<String, MutableList<Programme>>()
        var channelId = ""
        var readingName = false
        var programmeChannel = ""
        var start = 0L
        var stop = 0L
        var title = ""
        var event = parser.eventType
        while (event != XmlPullParser.END_DOCUMENT) {
            when {
                event == XmlPullParser.START_TAG && parser.name == "channel" ->
                    channelId = parser.getAttributeValue(null, "id").orEmpty()
                event == XmlPullParser.START_TAG && parser.name == "display-name" && channelId.isNotBlank() ->
                    readingName = true
                event == XmlPullParser.START_TAG && parser.name == "programme" -> {
                    programmeChannel = parser.getAttributeValue(null, "channel").orEmpty()
                    start = parseXmltvTime(parser.getAttributeValue(null, "start").orEmpty())
                    stop = parseXmltvTime(parser.getAttributeValue(null, "stop").orEmpty())
                    title = ""
                }
                event == XmlPullParser.START_TAG && parser.name == "title" ->
                    title = parser.nextText().trim()
                event == XmlPullParser.TEXT && readingName && channelId.isNotBlank() -> {
                    val n = normalizeChannelName(parser.text)
                    if (n.isNotBlank()) names.getOrPut(channelId) { mutableSetOf() }.add(n)
                }
                event == XmlPullParser.END_TAG && parser.name == "display-name" -> readingName = false
                event == XmlPullParser.END_TAG && parser.name == "channel" -> channelId = ""
                event == XmlPullParser.END_TAG && parser.name == "programme" -> {
                    if (programmeChannel.isNotBlank() && title.isNotBlank() && stop > start)
                        data.getOrPut(programmeChannel) { mutableListOf() }.add(Programme(title, start, stop))
                    programmeChannel = ""
                }
            }
            event = parser.next()
        }
        val output = mutableMapOf<String, List<Programme>>()
        data.forEach { (id, list) -> output[id] = list.sortedBy { it.start } }
        names.forEach { (id, channelNames) ->
            val list = output[id] ?: return@forEach
            channelNames.forEach { output["name:" + it] = list }
        }
        return output
    }

    private fun displayEpg(channel: Channel, programmes: List<Programme>) {
        if (isFinishing || isDestroyed || currentChannelIndex !in channels.indices ||
            channels[currentChannelIndex].url != channel.url) return
        val now = System.currentTimeMillis()
        currentProgramme = programmes.firstOrNull { now >= it.start && now < it.stop }
        val next = programmes.firstOrNull { it.start > now }
        val current = currentProgramme
        nowView.text = if (current != null) {
            styledEpgLine("СЕЙЧАС", current.title,
                "${formatClock(current.start)}–${formatClock(current.stop)}  •  ${formatDuration(current.stop - current.start)}")
        } else {
            styledEpgLine("СЕЙЧАС", "Нет текущей программы", "Телепрограмма обновляется")
        }
        nextView.text = if (next != null) {
            val until = ((next.start - now).coerceAtLeast(0L) / 60_000L)
            styledEpgLine("ДАЛЕЕ", next.title,
                "${formatClock(next.start)}–${formatClock(next.stop)}  •  ${formatDuration(next.stop - next.start)}  •  через ${until} мин")
        } else {
            styledEpgLine("ДАЛЕЕ", "Нет следующей программы", "Расписание пока недоступно")
        }
        updateProgress()
    }

    private fun styledEpgLine(label: String, title: String, details: String): CharSequence {
        val result = SpannableStringBuilder()
        result.append(label).append("  ")
        result.setSpan(ForegroundColorSpan(0xFF65C0FF.toInt()), 0, label.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        result.setSpan(StyleSpan(Typeface.BOLD), 0, label.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        result.append(title).append("\n")
        val detailStart = result.length
        result.append(details)
        result.setSpan(ForegroundColorSpan(0xFFB9C9D9.toInt()), detailStart, result.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        return result
    }

    private fun formatClock(timestamp: Long): String =
        SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date(timestamp))

    private fun formatDuration(milliseconds: Long): String {
        val minutes = (milliseconds / 60_000L).coerceAtLeast(1L)
        val hours = minutes / 60L
        val rest = minutes % 60L
        return if (hours > 0) "${hours} ч ${rest} мин" else "${minutes} мин"
    }

    private fun refreshCurrentEpg() {
        if (currentChannelIndex !in channels.indices) return
        val channel = channels[currentChannelIndex]
        val key = channel.id.ifBlank { normalizeChannelName(channel.name) }
        epgCache[key]?.let { displayEpg(channel, it) }
    }

    private fun parseEpg(input: java.io.InputStream, target: Channel): List<Programme> {
        val parser = Xml.newPullParser()
        parser.setFeature(XmlPullParser.FEATURE_PROCESS_NAMESPACES, false)
        parser.setInput(input, "UTF-8")
        val found = mutableListOf<Programme>()
        val targetName = normalizeChannelName(target.name)
        val matchedIds = mutableSetOf<String>()
        if (target.id.isNotBlank()) matchedIds.add(target.id)
        var readingChannel = ""
        var readingDisplayName = false
        var programmeChannel = ""
        var start = 0L
        var stop = 0L
        var title = ""
        var event = parser.eventType
        while (event != XmlPullParser.END_DOCUMENT) {
            if (event == XmlPullParser.START_TAG && parser.name == "channel") {
                readingChannel = parser.getAttributeValue(null, "id").orEmpty()
            } else if (event == XmlPullParser.START_TAG && parser.name == "display-name" && readingChannel.isNotBlank()) {
                readingDisplayName = true
            } else if (event == XmlPullParser.START_TAG && parser.name == "programme") {
                programmeChannel = parser.getAttributeValue(null, "channel").orEmpty()
                start = parseXmltvTime(parser.getAttributeValue(null, "start").orEmpty())
                stop = parseXmltvTime(parser.getAttributeValue(null, "stop").orEmpty())
                title = ""
            } else if (event == XmlPullParser.START_TAG && parser.name == "title" &&
                matchedIds.contains(programmeChannel)) {
                title = parser.nextText().trim()
            } else if (event == XmlPullParser.END_TAG && parser.name == "programme") {
                if (matchedIds.contains(programmeChannel) && title.isNotBlank() && stop > start) {
                    found.add(Programme(title, start, stop))
                }
                programmeChannel = ""
            } else if (event == XmlPullParser.END_TAG && parser.name == "channel") {
                readingChannel = ""
            } else if (event == XmlPullParser.END_TAG && parser.name == "display-name") {
                readingDisplayName = false
            } else if (event == XmlPullParser.TEXT && readingDisplayName &&
                normalizeChannelName(parser.text) == targetName && readingChannel.isNotBlank()) {
                matchedIds.add(readingChannel)
            }
            event = parser.next()
        }
        return found.sortedBy { it.start }
    }

    private fun parseXmltvTime(raw: String): Long {
        return try {
            val value = raw.trim()
            val hasOffset = value.length >= 5 && (value[value.length - 5] == '+' || value[value.length - 5] == '-') && value.takeLast(4).all { it.isDigit() }
            val normalized = if (hasOffset) value else "$value +0000"
            val format = SimpleDateFormat("yyyyMMddHHmmss Z", Locale.US).apply {
                timeZone = TimeZone.getTimeZone("UTC")
                isLenient = true
            }
            format.parse(normalized)?.time ?: 0L
        } catch (_: Exception) { 0L }
    }

    private fun updateProgress() {
        val programme = currentProgramme ?: run { progress.progress = 0; return }
        val duration = (programme.stop - programme.start).coerceAtLeast(1L)
        val elapsed = (System.currentTimeMillis() - programme.start).coerceIn(0L, duration)
        progress.progress = ((elapsed * 1000L) / duration).toInt()
    }

    private fun toggleInfoBar() = showInfoBar(!overlayVisible)
    private fun showInfoBar(show: Boolean) {
        overlayVisible = show
        infoBar.visibility = if (show) View.VISIBLE else View.GONE
        handler.removeCallbacks(hideOverlay)
        if (show) handler.postDelayed(hideOverlay, 9000)
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        when (keyCode) {
            KeyEvent.KEYCODE_DPAD_UP -> { changeChannel(-1); return true }
            KeyEvent.KEYCODE_DPAD_DOWN -> { changeChannel(1); return true }
            KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER, KeyEvent.KEYCODE_MENU -> {
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
        epgExecutor.shutdownNow()
        warmExecutor.shutdownNow()
        playerView.player = null
        player?.release()
        player = null
        super.onDestroy()
    }
}
