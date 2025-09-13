package com.example.locked_in

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.EventChannel

class MainActivity: FlutterActivity() {
    private val SCREEN_CHANNEL = "screen_events"
    private var eventSink: EventChannel.EventSink? = null

    private val screenReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when(intent?.action) {
                Intent.ACTION_SCREEN_OFF -> eventSink?.success("locked")
                Intent.ACTION_SCREEN_ON -> eventSink?.success("unlocked")
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: io.flutter.embedding.engine.FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, SCREEN_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    val filter = IntentFilter().apply {
                        addAction(Intent.ACTION_SCREEN_OFF)
                        addAction(Intent.ACTION_SCREEN_ON)
                    }
                    registerReceiver(screenReceiver, filter)
                }

                override fun onCancel(arguments: Any?) {
                    unregisterReceiver(screenReceiver)
                    eventSink = null
                }
            }
        )
    }
}
