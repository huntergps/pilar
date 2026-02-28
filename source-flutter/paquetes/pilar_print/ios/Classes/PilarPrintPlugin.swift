import Flutter
import ExternalAccessory
import UIKit

public class PilarPrintPlugin: NSObject, FlutterPlugin, EAAccessoryDelegate, StreamDelegate {
    static let channelName = "tech.galapagos.pilar/print_bt"
    private static let zebraProtocol = "com.zebra.rawport"
    private var session: EASession?
    private var outputStream: OutputStream?
    private var connectResult: FlutterResult?
    private var sendResult: FlutterResult?
    private var pendingData: Data?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: registrar.messenger()
        )
        let instance = PilarPrintPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getPairedDevices":
            let manager = EAAccessoryManager.shared()
            let accessories = manager.connectedAccessories.filter {
                $0.protocolStrings.contains(PilarPrintPlugin.zebraProtocol)
            }
            let devices = accessories.map { acc -> [String: String] in
                ["name": acc.name, "address": acc.serialNumber]
            }
            result(devices)
        case "connect":
            guard let args = call.arguments as? [String: Any],
                  let serial = args["address"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing address", details: nil))
                return
            }
            let manager = EAAccessoryManager.shared()
            guard let accessory = manager.connectedAccessories.first(where: {
                $0.serialNumber == serial &&
                $0.protocolStrings.contains(PilarPrintPlugin.zebraProtocol)
            }) else {
                result(FlutterError(code: "NOT_FOUND", message: "Accessory not found", details: nil))
                return
            }
            session = EASession(accessory: accessory, forProtocol: PilarPrintPlugin.zebraProtocol)
            outputStream = session?.outputStream
            outputStream?.delegate = self
            outputStream?.schedule(in: .main, forMode: .default)
            outputStream?.open()
            connectResult = result
            result(true)
        case "send":
            guard let args = call.arguments as? [String: Any],
                  let data = args["data"] as? FlutterStandardTypedData else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing data", details: nil))
                return
            }
            sendResult = result
            pendingData = Data(data.data)
            writeData()
        case "disconnect":
            outputStream?.close()
            outputStream = nil
            session = nil
            result(true)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func writeData() {
        guard let data = pendingData, let stream = outputStream else { return }
        data.withUnsafeBytes { pointer in
            if let baseAddress = pointer.baseAddress?.assumingMemoryBound(to: UInt8.self) {
                stream.write(baseAddress, maxLength: data.count)
            }
        }
        sendResult?(true)
        sendResult = nil
        pendingData = nil
    }
}
