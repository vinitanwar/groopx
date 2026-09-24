package com.futureittouch.groopx

import android.media.MediaRecorder
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val voiceChannel = "com.futureittouch.groopx/voice_recorder"
    private var recorder: MediaRecorder? = null
    private var recordingFile: File? = null

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
    }

    @Suppress("DEPRECATION")
    private fun startRecording(result: MethodChannel.Result) {
        if (recorder != null) {
            result.error("already_recording", "A voice recording is already active", null)
            return
        }
        try {
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
        super.onDestroy()
    }
}
