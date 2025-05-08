package com.example.metflix

import android.content.SharedPreferences
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.view.View
import androidx.annotation.OptIn
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.edit
import androidx.media3.common.*
import androidx.media3.common.util.UnstableApi
import androidx.media3.common.util.Util
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import androidx.media3.ui.PlayerView

@UnstableApi
class DrmPlayerActivity : AppCompatActivity() {

    private lateinit var player       : ExoPlayer
    private lateinit var playerView   : PlayerView
    private lateinit var trackSelector: DefaultTrackSelector
    private lateinit var prefs        : SharedPreferences

    // ──────────────────────────────────────────────────────────────────────────────
    //  LIFECYCLE
    // ──────────────────────────────────────────────────────────────────────────────
    @OptIn(UnstableApi::class)
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Immersive full-screen.
        window.decorView.systemUiVisibility = (
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or
                        View.SYSTEM_UI_FLAG_FULLSCREEN or
                        View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                )

        playerView = PlayerView(this).apply {
            // Media3 “Styled” controls are enabled by default.
            // Show buttons we need:
            setShowFastForwardButton(true)
            setShowRewindButton(true)
            setShowSubtitleButton(true)
//            setShowTrackSelectionButton(true)   // quality / audio tracks
//            setShowPlaybackSpeedButton(true)
        }
        setContentView(playerView)

        prefs = getSharedPreferences("metflix_resume", MODE_PRIVATE)

        val videoUrl   = intent.getStringExtra("url")        ?: return
        val licenseUrl = intent.getStringExtra("licenseUrl") ?: return
        val contentId  = intent.getStringExtra("id")         ?: videoUrl // fallback

        // Subtitle (optional) — replace with real URL if you have one
        val subtitleConfig = MediaItem.SubtitleConfiguration.Builder(
            Uri.parse("https://storage.googleapis.com/shaka-demo-assets/angel-one/subtitles/eng.vtt")
        )
            .setMimeType(MimeTypes.TEXT_VTT)
            .setLanguage("en")
            .setSelectionFlags(C.SELECTION_FLAG_DEFAULT)
            .build()

        // Build MediaItem with Widevine DRM + subtitles
        val mediaItem = MediaItem.Builder()
            .setUri(Uri.parse(videoUrl))
            .setMimeType(MimeTypes.APPLICATION_MPD)   // DASH mpd
            .setDrmConfiguration(
                MediaItem.DrmConfiguration.Builder(Util.getDrmUuid("widevine")!!)
                    .setLicenseUri(licenseUrl)
                    .setMultiSession(true)
                    .build()
            )
            .setSubtitleConfigurations(listOf(subtitleConfig))
            .build()

        // Track selector lets us switch quality/audio
        trackSelector = DefaultTrackSelector(this).apply {
            setParameters(buildUponParameters().setPreferredAudioLanguage("en"))
        }

        // Build the player
        player = ExoPlayer.Builder(this)
            .setTrackSelector(trackSelector)
            .build()
            .also { exo ->
                playerView.player = exo
                exo.setMediaItem(mediaItem)
                exo.prepare()

                // Seek to saved position (if any)
                val startPositionMs = prefs.getLong(contentId, 0L)
                if (startPositionMs > 0) exo.seekTo(startPositionMs)

                exo.playWhenReady = true
            }

        // Save playback position periodically
        player.addListener(object : Player.Listener {
            override fun onIsPlayingChanged(isPlaying: Boolean) {
                if (!isPlaying) saveResumePosition(contentId)
            }
            override fun onPlaybackStateChanged(state: Int) {
                if (state == Player.STATE_ENDED) prefs.edit { remove(contentId) }
            }
        })
    }

    // Persist position
    private fun saveResumePosition(id: String) {
        val pos = player.currentPosition
        prefs.edit { putLong(id, pos) }
    }

    override fun onStop() {
        super.onStop()
        saveResumePosition(intent.getStringExtra("id") ?: intent.getStringExtra("url")!!)
        player.release()
    }
}
