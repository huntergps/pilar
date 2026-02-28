package tech.galapagos.pilarprint

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothSocket
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.OutputStream
import java.util.UUID

class PilarPrintPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private var socket: BluetoothSocket? = null
    private var outputStream: OutputStream? = null
    private val SPP_UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "tech.galapagos.pilar/print_bt")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getPairedDevices" -> {
                val adapter = BluetoothAdapter.getDefaultAdapter()
                val devices = adapter?.bondedDevices?.map { device ->
                    mapOf("name" to device.name, "address" to device.address)
                } ?: emptyList()
                result.success(devices)
            }
            "connect" -> {
                val address = call.argument<String>("address")!!
                try {
                    val adapter = BluetoothAdapter.getDefaultAdapter()
                    val device = adapter.getRemoteDevice(address)
                    socket = device.createRfcommSocketToServiceRecord(SPP_UUID)
                    adapter.cancelDiscovery()
                    socket!!.connect()
                    outputStream = socket!!.outputStream
                    result.success(true)
                } catch (e: Exception) {
                    result.error("BT_CONNECT_ERROR", e.message, null)
                }
            }
            "send" -> {
                val data = call.argument<ByteArray>("data")!!
                try {
                    outputStream?.write(data)
                    outputStream?.flush()
                    result.success(true)
                } catch (e: Exception) {
                    result.error("BT_SEND_ERROR", e.message, null)
                }
            }
            "disconnect" -> {
                try {
                    outputStream?.close()
                    socket?.close()
                    outputStream = null
                    socket = null
                    result.success(true)
                } catch (e: Exception) {
                    result.error("BT_DISCONNECT_ERROR", e.message, null)
                }
            }
            else -> result.notImplemented()
        }
    }
}
