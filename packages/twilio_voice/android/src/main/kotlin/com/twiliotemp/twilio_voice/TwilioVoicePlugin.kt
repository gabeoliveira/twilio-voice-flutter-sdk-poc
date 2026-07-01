package com.twiliotemp.twilio_voice

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.twilio.voice.Call
import com.twilio.voice.CallException
import com.twilio.voice.ConnectOptions
import com.twilio.voice.Voice
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry

/**
 * Android side of the Twilio Voice Flutter wrapper.
 *
 * Outbound-only. The [Call.Listener] is the natural place to also handle incoming
 * calls later (via Voice.handleMessage from an FCM service) without changing the
 * Dart-facing channel contract.
 */
class TwilioVoicePlugin :
    FlutterPlugin,
    MethodCallHandler,
    ActivityAware,
    EventChannel.StreamHandler,
    PluginRegistry.RequestPermissionsResultListener {

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var appContext: Context? = null
    private var activity: Activity? = null
    private var events: EventChannel.EventSink? = null

    private var activeCall: Call? = null
    private var micPermissionResult: Result? = null

    private companion object {
        const val MIC_PERMISSION_REQUEST = 0xB001
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        methodChannel = MethodChannel(binding.binaryMessenger, "twilio_voice")
        methodChannel.setMethodCallHandler(this)
        eventChannel = EventChannel(binding.binaryMessenger, "twilio_voice/events")
        eventChannel.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        appContext = null
    }

    // --- EventChannel ---
    override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
        events = sink
    }

    override fun onCancel(arguments: Any?) {
        events = null
    }

    private fun emit(state: String, message: String? = null, callSid: String? = null) {
        activity?.runOnUiThread {
            events?.success(
                mapOf("state" to state, "message" to message, "callSid" to callSid)
            )
        }
    }

    // --- MethodChannel ---
    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "requestMicPermission" -> requestMicPermission(result)
            "connect" -> connect(call, result)
            "disconnect" -> {
                activeCall?.disconnect()
                result.success(null)
            }
            "setMuted" -> {
                activeCall?.mute(call.argument<Boolean>("muted") ?: false)
                result.success(null)
            }
            "setSpeaker" -> {
                val on = call.argument<Boolean>("on") ?: false
                val am = appContext?.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
                am?.isSpeakerphoneOn = on
                result.success(null)
            }
            "sendDigits" -> {
                activeCall?.sendDigits(call.argument<String>("digits") ?: "")
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun connect(call: MethodCall, result: Result) {
        val ctx = appContext
        if (ctx == null) {
            result.error("NO_CONTEXT", "Plugin not attached", null)
            return
        }
        val token = call.argument<String>("accessToken")
        val to = call.argument<String>("to") ?: ""
        if (token.isNullOrEmpty()) {
            result.error("NO_TOKEN", "accessToken is required", null)
            return
        }

        val options = ConnectOptions.Builder(token)
            // Forwarded to the TwiML App as call parameters; <Dial> uses `To`.
            .params(mapOf("To" to to))
            .build()

        emit("connecting")
        activeCall = Voice.connect(ctx, options, callListener)
        result.success(null)
    }

    private val callListener = object : Call.Listener {
        override fun onConnectFailure(call: Call, error: CallException) {
            activeCall = null
            emit("error", error.message, call.sid)
        }

        override fun onRinging(call: Call) = emit("ringing", callSid = call.sid)

        override fun onConnected(call: Call) {
            activeCall = call
            emit("connected", callSid = call.sid)
        }

        override fun onReconnecting(call: Call, error: CallException) =
            emit("reconnecting", error.message, call.sid)

        override fun onReconnected(call: Call) = emit("connected", callSid = call.sid)

        override fun onDisconnected(call: Call, error: CallException?) {
            activeCall = null
            emit("disconnected", error?.message, call.sid)
        }
    }

    // --- Mic permission ---
    private fun requestMicPermission(result: Result) {
        val ctx = appContext ?: return result.success(false)
        val granted = ContextCompat.checkSelfPermission(ctx, Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED
        if (granted) {
            result.success(true)
            return
        }
        val act = activity
        if (act == null) {
            result.success(false)
            return
        }
        micPermissionResult = result
        ActivityCompat.requestPermissions(
            act, arrayOf(Manifest.permission.RECORD_AUDIO), MIC_PERMISSION_REQUEST
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int, permissions: Array<out String>, grantResults: IntArray
    ): Boolean {
        if (requestCode != MIC_PERMISSION_REQUEST) return false
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        micPermissionResult?.success(granted)
        micPermissionResult = null
        return true
    }

    // --- ActivityAware ---
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() { activity = null }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addRequestPermissionsResultListener(this)
    }
    override fun onDetachedFromActivity() { activity = null }
}
