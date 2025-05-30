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
    
    var listener: NWListener?

    //Properties
    let locationManager = CLLocationManager()
    var currentLocation: CLLocation?
    private var tcpConnection: NWConnection?

    // TCP server config
    let tcpHost =  "192.168.41.148"//"192.168.41.178"//"10.31.128.25" //"192.168.41.163"//"10.31.128.25"    // Replace with computer IP adress
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
        
        //UDP Listener
        startUDPListener(on: 9999)
    }
    
    //UDP Listener
    func startUDPListener(on port: UInt16) {
            do {
                let params = NWParameters.udp
                listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
                
                listener?.newConnectionHandler = { connection in
                    connection.start(queue: .main)
                    self.receive(on: connection)
                }
                
                listener?.start(queue: .main)
                print("Listening on UDP port \(port)")
            } catch {
                print("Failed to create listener: \(error)")
            }
        }

        func receive(on connection: NWConnection) {
            connection.receiveMessage { (data, context, isComplete, error) in
                if let data = data, !data.isEmpty {
                    let message = String(decoding: data, as: UTF8.self)
                    print("Received data: \(message)")
                    if message == "TRUE" {
                        let alert = UIAlertController(title: "Box is full", message: nil, preferredStyle: .alert)
                        alert.addAction(.init(title: "OK", style: .default))
                        self.present(alert, animated: true)
                    } else {
                        let alert = UIAlertController(title: "Box is empty", message: nil, preferredStyle: .alert)
                        alert.addAction(.init(title: "OK", style: .default))
                        self.present(alert, animated: true)
                    }
                }
                if error == nil {
                    self.receive(on: connection) // Keep receiving
                } else {
                    print("Error receiving data: \(String(describing: error))")
                }
            }
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
        
        let cameraTransform = frame.camera.transform
        
        //Extract Camera position (x,y,z)
        let cameraPosition = [
            cameraTransform.columns.3.x,
            cameraTransform.columns.3.y,
            cameraTransform.columns.3.z
        ]
        
        // Extract orientation as 3x3 rotation matrix
        let cameraOrientation = [
            [cameraTransform.columns.0.x, cameraTransform.columns.0.y, cameraTransform.columns.0.z],
            [cameraTransform.columns.1.x, cameraTransform.columns.1.y, cameraTransform.columns.1.z],
            [cameraTransform.columns.2.x, cameraTransform.columns.2.y, cameraTransform.columns.2.z]
        ]
        
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
            "location": ["lat": lat ?? 0, "lon": lon ?? 0],
            "camera_position": cameraPosition,
            "camera_orientation": cameraOrientation
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
            print("Preparing to connect to \(tcpHost):\(tcpPort)…")
            sendWithNetworkFramework(data: packet,
                                     host: tcpHost,
                                     port: tcpPort)
            
            // send udp message here
            
            //sendUDP(message: "RADAR STARTING DATA CAPTURE NOW", host: tcpHost, port: 5006)
            
        } catch {
            print("Failed to serialize JSON:", error)
        }
    }

    //Network.framework Sender using TCP connection
    func sendWithNetworkFramework(data: Data, host: String, port: UInt16) {
        var success = false
        let nwHost = NWEndpoint.Host(host)
        let nwPort = NWEndpoint.Port(rawValue: port)!
        let connection = NWConnection(host: nwHost, port: nwPort, using: .tcp)
        self.tcpConnection = connection
        print("NWConnection created: \(connection)")

        connection.stateUpdateHandler = { state in
            switch state {
            case .setup:
                print("Setup complete.")
            case .waiting(let error):
                print("Waiting (backoff):", error)
            case .preparing:
                print("Preparing connection…")
            case .ready:
                print("Connection ready—sending \(data.count) bytes.")
                connection.send(content: data, completion: .contentProcessed { error in
                    if let e = error {
                        print("❌ Network send error:", e)
                    } else {
                        print("✅ Sent \(data.count) bytes to \(host):\(port)")
                    }
                    //connection.cancel()
                })
                
                /*connection.receiveMessage { (data, context, isComplete, error) in
                                            if let data = data, let message = String(data: data, encoding: .utf8) {
                                                print("Received response: \(message)")
                                                if message == "TRUE" {
                                                    success = true
                                                    let alert = UIAlertController(title: "Box is full", message: nil, preferredStyle: .alert)
                                                    alert.addAction(.init(title: "OK", style: .default))
                                                    self.present(alert, animated: true)
                                                } else {
                                                    success = false
                                                    let alert = UIAlertController(title: "Box is empty", message: nil, preferredStyle: .alert)
                                                    alert.addAction(.init(title: "OK", style: .default))
                                                    self.present(alert, animated: true)
                                                }
                                            } else if let error = error {
                                                print("Receive error: \(error)")
                                            } else {
                                                print("No data received")
                                            }
                                            connection.cancel()
                                        }*/

            case .failed(let error):
                print("❌ Connection failed:", error)
                connection.cancel()

            case .cancelled:
                print("Connection cancelled.")
            default:
                break
            }
        }

        connection.start(queue: .global(qos: .utility))
    }
    
    
    
    func sendUDP(message: String, host: String, port: UInt16) {
        let connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: .udp)
            connection.stateUpdateHandler = { newState in
                switch newState {
                case .ready:
                    print("Connection ready UDP")
                    let data = message.data(using: .utf8)!
                    connection.send(content: data, completion: .contentProcessed({ error in
                        if let error = error {
                            print("Send error: \(error)")
                        } else {
                            print("Message sent UDP")
                            // Now wait for a response
                            connection.receiveMessage { (data, context, isComplete, error) in
                                if let data = data, let message = String(data: data, encoding: .utf8) {
                                    print("Received response: \(message)")
                                    if message == "TRUE" {
                                        let alert = UIAlertController(title: "Box is full", message: nil, preferredStyle: .alert)
                                        alert.addAction(.init(title: "OK", style: .default))
                                        self.present(alert, animated: true)
                                    } else {
                                        let alert = UIAlertController(title: "Box is empty", message: nil, preferredStyle: .alert)
                                        alert.addAction(.init(title: "OK", style: .default))
                                        self.present(alert, animated: true)
                                    }
                                } else if let error = error {
                                    print("Receive error: \(error)")
                                } else {
                                    print("No data received")
                                }
                                connection.cancel()
                            }
                        }
                    }))
                case .failed(let error):
                    print("Connection failed: \(error)")
                default:
                    break
                }
            }

            connection.start(queue: .global())
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


