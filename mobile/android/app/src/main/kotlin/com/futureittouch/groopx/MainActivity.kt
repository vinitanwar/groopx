package com.futureittouch.groopx

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.MediaRecorder
import android.os.Build
import android.os.Bundle
import android.provider.ContactsContract
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val voiceChannel = "com.futureittouch.groopx/voice_recorder"
    private val contactsChannel = "com.futureittouch.groopx/contacts"
    private val playbackChannelName = "com.futureittouch.groopx/audio_player"
    private val screenSecurityChannel = "com.futureittouch.groopx/screen_security"
    private lateinit var playbackChannel: MethodChannel
    private var recorder: MediaRecorder? = null
    private var recordingFile: File? = null
    private var mediaPlayer: MediaPlayer? = null
    private var playingUrl: String? = null
    private var playbackSpeed = 1.0f

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannels()
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val messages = NotificationChannel("groopx_messages", "Messages", NotificationManager.IMPORTANCE_HIGH).apply {
            description = "New GroopX messages and shared media"
            enableVibration(true)
        }
        val callSound = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE).build()
        val calls = NotificationChannel("groopx_calls", "Calls", NotificationManager.IMPORTANCE_HIGH).apply {
            description = "Incoming GroopX audio and video calls"
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 500, 250, 500, 250, 500)
            setSound(Settings.System.DEFAULT_RINGTONE_URI, callSound)
        }
        val reminders = NotificationChannel("groopx_reminders", "Reminders", NotificationManager.IMPORTANCE_HIGH).apply {
            description = "GroopX reminder and meeting alerts"
            enableVibration(true)
        }
        val updates = NotificationChannel("groopx_updates", "Updates", NotificationManager.IMPORTANCE_DEFAULT).apply {
            description = "GroopX account and service updates"
        }
        manager.createNotificationChannels(listOf(messages, calls, reminders, updates))
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, voiceChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> startRecording(result)
                "stop" -> stopRecording(result, delete = false)
                "cancel" -> stopRecording(result, delete = true)
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, contactsChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "getPhoneNumbers" -> loadPhoneNumbers(result)
                "getContacts" -> loadContacts(result)
                "openContactEditor" -> openContactEditor(call.arguments, result)
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, screenSecurityChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "setSecure" -> {
                    if (call.arguments as? Boolean == true) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        playbackChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, playbackChannelName)
        playbackChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "play" -> playAudio(call.arguments as? String, result)
                "pause" -> { mediaPlayer?.pause(); result.success(null) }
                "resume" -> { mediaPlayer?.start(); result.success(null) }
                "seek" -> { mediaPlayer?.seekTo((call.arguments as? Int) ?: 0); result.success(null) }
                "position" -> result.success(mediaPlayer?.currentPosition ?: 0)
                "setSpeed" -> setPlaybackSpeed(call.arguments, result)
                "stop" -> { releasePlayer(); result.success(null) }
                else -> result.notImplemented()
            }
        }
    }

    private fun loadPhoneNumbers(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && checkSelfPermission(Manifest.permission.READ_CONTACTS) != PackageManager.PERMISSION_GRANTED) {
            result.error("contacts_permission_denied", "Contacts permission is required", null)
            return
        }
        Thread {
            try {
                val unique = LinkedHashSet<String>()
                val projection = arrayOf(ContactsContract.CommonDataKinds.Phone.NUMBER)
                contentResolver.query(
                    ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
                    projection,
                    null,
                    null,
                    null
                )?.use { cursor ->
                    val numberIndex = cursor.getColumnIndex(ContactsContract.CommonDataKinds.Phone.NUMBER)
                    while (cursor.moveToNext() && unique.size < 500) {
                        if (numberIndex < 0) break
                        val number = cursor.getString(numberIndex)?.trim().orEmpty()
                        val digits = number.filter { it in '0'..'9' }
                        if (digits.length in 7..15) unique.add(digits)
                    }
                }
                runOnUiThread { result.success(unique.toList()) }
            } catch (failure: Exception) {
                runOnUiThread { result.error("contacts_read_failed", failure.message ?: "Phone contacts could not be read", null) }
            }
        }.start()
    }

    private fun loadContacts(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && checkSelfPermission(Manifest.permission.READ_CONTACTS) != PackageManager.PERMISSION_GRANTED) {
            result.error("contacts_permission_denied", "Contacts permission is required", null)
            return
        }
        Thread {
            try {
                val unique = LinkedHashMap<String, Map<String, String>>()
                val projection = arrayOf(
                    ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME_PRIMARY,
                    ContactsContract.CommonDataKinds.Phone.NUMBER
                )
                contentResolver.query(
                    ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
                    projection,
                    null,
                    null,
                    "${ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME_PRIMARY} COLLATE LOCALIZED ASC"
                )?.use { cursor ->
                    val nameIndex = cursor.getColumnIndex(ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME_PRIMARY)
                    val numberIndex = cursor.getColumnIndex(ContactsContract.CommonDataKinds.Phone.NUMBER)
                    while (cursor.moveToNext() && unique.size < 500) {
                        if (numberIndex < 0) break
                        val number = cursor.getString(numberIndex)?.trim().orEmpty()
                        val digits = number.filter { it in '0'..'9' }
                        if (digits.length !in 7..15 || unique.containsKey(digits)) continue
                        val displayName = if (nameIndex >= 0) cursor.getString(nameIndex)?.trim().orEmpty() else ""
                        unique[digits] = mapOf(
                            "name" to displayName.ifBlank { number },
                            "phone" to number
                        )
                    }
                }
                runOnUiThread { result.success(unique.values.toList()) }
            } catch (failure: Exception) {
                runOnUiThread { result.error("contacts_read_failed", failure.message ?: "Phone contacts could not be read", null) }
            }
        }.start()
    }

    private fun openContactEditor(arguments: Any?, result: MethodChannel.Result) {
        val values = arguments as? Map<*, *>
        val name = values?.get("name")?.toString()?.trim().orEmpty()
        val phone = values?.get("phone")?.toString()?.trim().orEmpty()
        if (name.isBlank() || phone.isBlank()) {
            result.error("invalid_contact", "Contact name and phone are required", null)
            return
        }
        try {
            val intent = Intent(ContactsContract.Intents.Insert.ACTION).apply {
                type = ContactsContract.RawContacts.CONTENT_TYPE
                putExtra(ContactsContract.Intents.Insert.NAME, name)
                putExtra(ContactsContract.Intents.Insert.PHONE, phone)
                putExtra(ContactsContract.Intents.Insert.PHONE_TYPE, ContactsContract.CommonDataKinds.Phone.TYPE_MOBILE)
            }
            startActivity(intent)
            result.success(true)
        } catch (failure: Exception) {
            result.error("contact_editor_failed", failure.message ?: "Contact editor could not be opened", null)
        }
    }

    @Suppress("DEPRECATION")
    private fun playAudio(url: String?, result: MethodChannel.Result) {
        if (url.isNullOrBlank()) {
            result.error("invalid_url", "Audio URL is unavailable", null)
            return
        }
        releasePlayer()
        var replied = false
        try {
            playingUrl = url
            mediaPlayer = MediaPlayer().apply {
                setAudioStreamType(AudioManager.STREAM_MUSIC)
                setDataSource(url)
                setOnPreparedListener {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        try {
                            it.playbackParams = it.playbackParams.setSpeed(playbackSpeed)
                        } catch (_: Exception) {
                            playbackSpeed = 1.0f
                            playbackChannel.invokeMethod("playbackSpeedChanged", playbackSpeed.toDouble())
                        }
                    }
                    it.start()
                    replied = true
                    result.success(it.duration)
                }
                setOnCompletionListener {
                    playbackChannel.invokeMethod("playbackCompleted", playingUrl)
                    releasePlayer()
                }
                setOnErrorListener { _, what, extra ->
                    if (!replied) {
                        replied = true
                        result.error("playback_failed", "Audio playback failed ($what/$extra)", null)
                    } else {
                        playbackChannel.invokeMethod("playbackError", playingUrl)
                    }
                    releasePlayer()
                    true
                }
                prepareAsync()
            }
        } catch (failure: Exception) {
            releasePlayer()
            if (!replied) result.error("playback_failed", failure.message ?: "Audio could not play", null)
        }
    }

    private fun setPlaybackSpeed(arguments: Any?, result: MethodChannel.Result) {
        val requested = (arguments as? Number)?.toFloat()
        val supported = listOf(1.0f, 1.5f, 2.0f)
        val next = requested?.let { value -> supported.firstOrNull { kotlin.math.abs(it - value) < 0.01f } }
        if (next == null) {
            result.error("invalid_speed", "Playback speed must be 1x, 1.5x, or 2x", null)
            return
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M && next != 1.0f) {
            result.error("speed_unsupported", "Playback speed requires Android 6 or newer", null)
            return
        }
        val player = mediaPlayer
        if (player != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                val wasPlaying = player.isPlaying
                player.playbackParams = player.playbackParams.setSpeed(next)
                if (!wasPlaying) player.pause()
            } catch (failure: Exception) {
                result.error("speed_failed", failure.message ?: "Playback speed could not be changed", null)
                return
            }
        }
        playbackSpeed = next
        result.success(playbackSpeed.toDouble())
    }

    private fun releasePlayer() {
        try { mediaPlayer?.stop() } catch (_: Exception) {}
        try { mediaPlayer?.release() } catch (_: Exception) {}
        mediaPlayer = null
        playingUrl = null
    }

    @Suppress("DEPRECATION")
    private fun startRecording(result: MethodChannel.Result) {
        if (recorder != null) {
            result.error("already_recording", "A voice recording is already active", null)
            return
        }
        try {
            if (mediaPlayer != null) {
                playbackChannel.invokeMethod("playbackCompleted", playingUrl)
                releasePlayer()
            }
            val file = File(cacheDir, "voice-${System.currentTimeMillis()}.m4a")
            recordingFile = file
            val next = MediaRecorder().apply {
                setAudioSource(MediaRecorder.AudioSource.MIC)
                setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                setAudioEncodingBitRate(128000)
                setAudioSamplingRate(44100)
                setOutputFile(file.absolutePath)
                prepare()
                start()
            }
            recorder = next
            result.success(file.absolutePath)
        } catch (failure: Exception) {
            releaseRecorder()
            recordingFile?.delete()
            recordingFile = null
            result.error("recording_failed", failure.message ?: "Recording could not start", null)
        }
    }

    private fun stopRecording(result: MethodChannel.Result, delete: Boolean) {
        val active = recorder
        val file = recordingFile
        if (active == null || file == null) {
            result.success(null)
            return
        }
        try {
            active.stop()
            releaseRecorder()
            recordingFile = null
            if (delete) {
                file.delete()
                result.success(null)
            } else {
                result.success(file.absolutePath)
            }
        } catch (failure: RuntimeException) {
            releaseRecorder()
            recordingFile = null
            file.delete()
            result.error("recording_too_short", "Voice note was too short", null)
        }
    }

    private fun releaseRecorder() {
        try { recorder?.release() } catch (_: Exception) {}
        recorder = null
    }

    override fun onDestroy() {
        recorder?.let {
            try { it.stop() } catch (_: Exception) {}
        }
        releaseRecorder()
        recordingFile?.delete()
        recordingFile = null
        releasePlayer()
        super.onDestroy()
    }
}
