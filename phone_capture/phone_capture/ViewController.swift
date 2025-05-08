//
//  ViewController.swift
//  phone_capture
//
//  Created by Adan Abu Naaj on 4/17/25.
//

import UIKit
import ARKit
import SceneKit
import CoreLocation
import Network

class ViewController: UIViewController, ARSessionDelegate, CLLocationManagerDelegate {
    //IBOutlets
    @IBOutlet weak var arView: ARSCNView!

    //Properties
    let locationManager = CLLocationManager()
    var currentLocation: CLLocation?

    // TCP server config
    let tcpHost = "10.31.128.25"    // Replace with computer IP adress
    let tcpPort: UInt16 = 5005

    override func viewDidLoad() {
        super.viewDidLoad()

        // ARKit setup
        arView.session.delegate = self
        let config = ARWorldTrackingConfiguration()
        config.frameSemantics.insert(.sceneDepth)
        arView.session.run(config)

        // Location setup
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }

    //Capture Action
    @IBAction func capturePressed(_ sender: UIButton) {
        //Pop up an alert when image is captured
        let alert = UIAlertController(title: "Image Captured ✅", message: nil, preferredStyle: .alert)
        alert.addAction(.init(title: "OK", style: .default))
        present(alert, animated: true)

        guard let frame = arView.session.currentFrame else { return }

        // 1️⃣ Color image
        let buffer = frame.capturedImage
        let ci = CIImage(cvPixelBuffer: buffer)
        let uiImage = UIImage(ciImage: ci)

        // 2️⃣ Depth map
        guard let sceneDepth = frame.sceneDepth else { return }
        let depthMap = sceneDepth.depthMap

        // 3️⃣ Intrinsics & timestamp
        let intrinsics = frame.camera.intrinsics
        let timestamp = frame.timestamp

        // 4️⃣ Location
        let lat = currentLocation?.coordinate.latitude
        let lon = currentLocation?.coordinate.longitude

        // 5️⃣ Temporarly save locally
        saveCaptureLocally(image: uiImage,
                           depthMap: depthMap,
                           intrinsics: intrinsics,
                           timestamp: timestamp,
                           location: (lat, lon))

        // 6️⃣ Encode to Base64
        guard let jpegData = uiImage.jpegData(compressionQuality: 0.8) else { return }
        let imgB64 = jpegData.base64EncodedString()

        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        let depthSize = CVPixelBufferGetDataSize(depthMap)
        let depthBase = CVPixelBufferGetBaseAddress(depthMap)!
        let depthData = Data(bytes: depthBase, count: depthSize)
        CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)
        let depthB64 = depthData.base64EncodedString()

        // 7️⃣ Metadata
        let meta: [String: Any] = [
            "intrinsics": [
                [intrinsics[0,0], intrinsics[0,1], intrinsics[0,2]],
                [intrinsics[1,0], intrinsics[1,1], intrinsics[1,2]],
                [intrinsics[2,0], intrinsics[2,1], intrinsics[2,2]]
            ],
            "timestamp": timestamp,
            "location": ["lat": lat ?? 0, "lon": lon ?? 0]
        ]

        // 8️⃣ Build JSON packet
        do {
            var packet = try JSONSerialization.data(withJSONObject: [
                "image": imgB64,
                "depth": depthB64,
                "meta": meta
            ])
            packet.append(0x0A)  // newline

            // 9️⃣ Send via Network.framework
            sendWithNetworkFramework(data: packet,
                                     host: tcpHost,
                                     port: tcpPort)
        } catch {
            print("Failed to serialize JSON:", error)
        }
    }

    //Network.framework Sender using TCP connection
    func sendWithNetworkFramework(data: Data, host: String, port: UInt16) {
        let nwHost = NWEndpoint.Host(host)
        let nwPort = NWEndpoint.Port(rawValue: port)!
        let connection = NWConnection(host: nwHost, port: nwPort, using: .tcp)

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                connection.send(content: data, completion: .contentProcessed { error in
                    if let e = error {
                        print("❌ Network send error:", e)
                    } else {
                        print("✅ Sent \(data.count) bytes to \(host):\(port)")
                    }
                    connection.cancel()
                })

            case .failed(let error):
                print("❌ Connection failed:", error)
                connection.cancel()

            default:
                break
            }
        }

        connection.start(queue: .global(qos: .utility))
    }

    // Local Saving Helper Function
    func capturesDirectoryURL() -> URL {
        let fm = FileManager.default
        let docs = try! fm.url(for: .documentDirectory,
                               in: .userDomainMask,
                               appropriateFor: nil,
                               create: true)
        let dir = docs.appendingPathComponent("captures", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try! fm.createDirectory(at: dir,
                                     withIntermediateDirectories: true,
                                     attributes: nil)
        }
        return dir
    }

    func saveCaptureLocally(image: UIImage,
                            depthMap: CVPixelBuffer,
                            intrinsics: simd_float3x3,
                            timestamp: TimeInterval,
                            location: (Double?, Double?)) {
        let base = capturesDirectoryURL()
        let name = String(format: "%.3f", timestamp)
        let folder = base.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder,
                                                 withIntermediateDirectories: true,
                                                 attributes: nil)
        // Save image
        if let jpg = image.jpegData(compressionQuality: 0.8) {
            let url = folder.appendingPathComponent("frame.jpg")
            try? jpg.write(to: url)
            print("Saved image to", url.path)
        }
        
        // Save depth map
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        let len = CVPixelBufferGetDataSize(depthMap)
        let addr = CVPixelBufferGetBaseAddress(depthMap)!
        let data = Data(bytes: addr, count: len)
        CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)
        let depthURL = folder.appendingPathComponent("depth.bin")
        try? data.write(to: depthURL)
        print("Saved depth to", depthURL.path)
        
        // Save metadata
        let meta: [String: Any] = [
            "intrinsics": [
                [intrinsics[0,0], intrinsics[0,1], intrinsics[0,2]],
                [intrinsics[1,0], intrinsics[1,1], intrinsics[1,2]],
                [intrinsics[2,0], intrinsics[2,1], intrinsics[2,2]]
            ],
            "timestamp": timestamp,
            "location": ["lat": location.0 ?? 0, "lon": location.1 ?? 0]
        ]
        let metaURL = folder.appendingPathComponent("meta.json")
        if let json = try? JSONSerialization.data(withJSONObject: meta, options: [.prettyPrinted]) {
            try? json.write(to: metaURL)
            print("Saved metadata to", metaURL.path)
        }
    }

    //CLLocationManagerDelegate
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        currentLocation = locations.last
    }
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        // handle permission changes
    }
}


