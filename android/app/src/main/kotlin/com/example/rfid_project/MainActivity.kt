package com.example.rfid_project // REPLACE WITH YOUR FLUTTER APP'S PACKAGE NAME

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel // For continuous tag streams
import android.util.Log
import com.rscja.deviceapi.RFIDWithUHFA4RS232
import com.rscja.deviceapi.entity.GPIStateEntity
import com.rscja.deviceapi.entity.AntennaState
import com.rscja.deviceapi.entity.UHFTAGInfo
import android.os.Handler
import android.os.Looper

// TODO: IMPORT YOUR CHAINWAY SDK CLASSES HERE
// Example:
// import com.rscja.deviceapi.RFIDWithUHF // This is a GUESS - Check SDK docs
// import com.rscja.deviceapi.entity.UHFTAGInfo // GUESS
// import com.rscja.deviceapi.exception.ConfigurationException // GUESS
// import android.os.AsyncTask // If SDK operations are blocking

class MainActivity : FlutterActivity() {
    private val CHANNEL = "rfid_channel"
    private var uhf: RFIDWithUHFA4RS232? = null
    private var lastTag: String? = null
    private val MOCK_MODE = false // Set to false for real hardware

    private val STATUS_EVENT_CHANNEL = "rfid_status_channel"
    private var statusEventSink: EventChannel.EventSink? = null
    private var mockStatusHandler: Handler? = null
    private var mockStatusRunnable: Runnable? = null

    // TODO: Instantiate your SDK's RFID Reader object
    // private var uhfReader: RFIDWithUHF? = null // Example: Replace RFIDWithUHF with actual class

    // private var tagEventSink: EventChannel.EventSink? = null // For EventChannel

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        uhf = RFIDWithUHFA4RS232.getInstance()

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            try {
                if (MOCK_MODE) {
                    when (call.method) {
                        "initializeReader" -> {
                            Log.d("RFIDNative", "MOCK: initializeReader always returns true")
                            result.success(true)
                        }
                        "readTag", "readSingleTag" -> {
                            Log.d("RFIDNative", "MOCK: Returning fake tag")
                            result.success("FAKE_TAG_${(1000..9999).random()}")
                        }
                        "writeTag" -> {
                            Log.d("RFIDNative", "MOCK: Pretending to write tag")
                            result.success(true)
                        }
                        "setAntennaConfiguration" -> {
                            Log.d("RFIDNative", "MOCK: Pretending to set antenna")
                            result.success(true)
                        }
                        "readGpioValues" -> {
                            Log.d("RFIDNative", "MOCK: Returning fake GPIO states")
                            val gpioMap = mapOf("gpio1" to true, "gpio2" to false)
                            result.success(gpioMap)
                        }
                        "setRfPower" -> {
                            Log.d("RFIDNative", "MOCK: Pretending to set RF power")
                            result.success(true)
                        }
                        "releaseReader" -> {
                            Log.d("RFIDNative", "MOCK: releaseReader called")
                            result.success(true)
                        }
                        "writeTagData" -> {
                            Log.d("RFIDNative", "MOCK: Pretending to write tag data")
                            result.success(true)
                        }
                        "output1On" -> { uhf?.output1On(); result.success(true) }
                        "output1Off" -> { uhf?.output1Off(); result.success(true) }
                        "output2On" -> { uhf?.output2On(); result.success(true) }
                        "output2Off" -> { uhf?.output2Off(); result.success(true) }
                        "startReading" -> {
                            Log.d("RFIDNative", "MOCK: startReading called")
                            startMockStatus()
                            result.success(true)
                        }
                        "stopReading" -> {
                            Log.d("RFIDNative", "MOCK: stopReading called")
                            stopMockStatus()
                            result.success(true)
                        }
                        else -> result.notImplemented()
                    }
                    return@setMethodCallHandler
                }
                when (call.method) {
                    "initializeReader" -> {
                        try {
                            Log.d("RFIDNative", "Attempting to initialize reader...")
                        val success = uhf?.init(this) ?: false
                            Log.d("RFIDNative", "Reader init result: $success")
                        result.success(success)
                        } catch (e: Exception) {
                            Log.e("RFIDNative", "Exception during init", e)
                            result.success(false)
                        }
                    }
                    "readTag" -> {
                        val tagInfo: UHFTAGInfo? = uhf?.inventorySingleTag()
                        result.success(tagInfo?.epc ?: "")
                    }
                    "readSingleTag" -> {
                        val tagInfo: UHFTAGInfo? = uhf?.inventorySingleTag()
                        result.success(tagInfo?.epc ?: "")
                    }
                    "writeTag" -> {
                        val currentEpc = call.argument<String>("currentEpc") ?: ""
                        val newEpc = call.argument<String>("tagId") ?: ""
                        val success = uhf?.writeDataToEpc(currentEpc, newEpc) ?: false
                        result.success(success)
                    }
                    "setAntennaConfiguration" -> {
                        val antennaNum = call.argument<Int>("antenna") ?: 1
                        val antList = uhf?.getANT() ?: mutableListOf()
                        antList.forEach { ant ->
                            Log.d("AntennaState", "Fields: " + ant.javaClass.declaredFields.joinToString { it.name })
                            Log.d("AntennaState", "Methods: " + ant.javaClass.methods.joinToString { it.name })
                        }
                        result.success(true)
                    }
                    "readGpioValues" -> {
                        val gpiStates = uhf?.inputStatus() ?: listOf()
                        gpiStates.forEach { gpi ->
                            Log.d("GPIStateEntity", "Fields: " + gpi.javaClass.declaredFields.joinToString { it.name })
                            Log.d("GPIStateEntity", "Methods: " + gpi.javaClass.methods.joinToString { it.name })
                        }
                        result.success(mapOf<String, Boolean>())
                    }
                    "setRfPower" -> {
                        val antennaNum = call.argument<Int>("antenna") ?: 1
                        val enabled = call.argument<Boolean>("enabled") ?: true
                        // You may need to map antennaNum to AntennaEnum if required
                        val power = if (enabled) 30 else 0 // Example: 30dBm on, 0dBm off
                        val enumName = "ANT$antennaNum"
                        val antennaEnum = com.rscja.deviceapi.enums.AntennaEnum.valueOf(enumName)
                        try {
                            Log.d("AntennaEnum", "Available values: " + com.rscja.deviceapi.enums.AntennaEnum.values().joinToString { it.name })
                            val success = uhf?.setAntennaPower(antennaEnum, power) ?: false
                            result.success(success)
                        } catch (e: Exception) {
                            Log.e("AntennaEnum", "Invalid enum name for antenna: $antennaNum", e)
                            result.success(false)
                        }
                    }
                    "releaseReader" -> {
                        uhf?.free()
                        result.success(true)
                    }
                    "writeTagData" -> {
                        val currentEpc = call.argument<String>("currentEpc") ?: ""
                        val newEpc = call.argument<String>("newEpc") ?: ""
                        val success = uhf?.writeDataToEpc(currentEpc, newEpc) ?: false
                        result.success(success)
                    }
                    "output1On" -> { uhf?.output1On(); result.success(true) }
                    "output1Off" -> { uhf?.output1Off(); result.success(true) }
                    "output2On" -> { uhf?.output2On(); result.success(true) }
                    "output2Off" -> { uhf?.output2Off(); result.success(true) }
                    "startReading" -> {
                        try {
                            Log.d("RFIDNative", "Starting real RFID reading")
                            // Replace with your SDK's method to start reading
                            val started = uhf?.startInventoryTag() ?: false
                            result.success(started)
                        } catch (e: Exception) {
                            Log.e("RFIDNative", "Error starting RFID reading", e)
                            result.success(false)
                        }
                    }
                    "stopReading" -> {
                        try {
                            val stopped = uhf?.stopInventory() ?: false
                            result.success(stopped)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("NATIVE_EXCEPTION", "Native exception: ${e.message}", null)
            }
        }

        // --- Event Channel Setup (Optional - for continuous tag reads) ---
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, STATUS_EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    statusEventSink = events
                    if (MOCK_MODE) startMockStatus()
                }
                override fun onCancel(arguments: Any?) {
                    statusEventSink = null
                    if (MOCK_MODE) stopMockStatus()
                }
            })
    }

    private fun startMockStatus() {
        if (mockStatusHandler != null) return // already running
        mockStatusHandler = Handler(Looper.getMainLooper())
        // Immediately send all active
        statusEventSink?.success(mapOf(
            "input" to true,
            "output" to true,
            "antenna" to true
        ))
        var toggle = false
        mockStatusRunnable = object : Runnable {
            override fun run() {
                // Continue toggling or keep active as you wish
                val status = mapOf(
                    "input" to toggle,
                    "output" to !toggle,
                    "antenna" to toggle
                )
                statusEventSink?.success(status)
                toggle = !toggle
                mockStatusHandler?.postDelayed(this, 1000)
            }
        }
        mockStatusHandler?.postDelayed(mockStatusRunnable!!, 1000) // Start after 1s
    }

    private fun stopMockStatus() {
        mockStatusHandler?.removeCallbacks(mockStatusRunnable!!)
        mockStatusHandler = null
        mockStatusRunnable = null
    }

    fun sendStatusToFlutter(input: Boolean, output: Boolean, antenna: Boolean) {
        val status = mapOf(
            "input" to input,
            "output" to output,
            "antenna" to antenna
        )
        statusEventSink?.success(status)
    }

    // It's good practice to ensure resources are freed if the FlutterEngine is detached
    // or activity is destroyed, though the 'releaseReader' method call from Dart's dispose
    // should typically handle it for this app structure.
    override fun onDestroy() {
        uhf?.free()
        super.onDestroy()
    }

    override fun onPause() {
        super.onPause()
        // BAD: Do not stop reading here!
        // uhf?.stopInventory()
    }
}