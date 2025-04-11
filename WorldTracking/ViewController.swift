//
//  ViewController.swift
//  WorldTracking
//
//  Created by Maisy Lam on 3/2/25.

import UIKit
import ARKit
//import Kronos

class ViewController: UIViewController, ARSessionDelegate {

    var sceneView: ARSCNView!
    var logButton: UIButton!
    var positionLabel: UILabel!
    var timestampLabel: UILabel! // New label for timestamp
    var isLogging = false
//    var locationData: [(position: simd_float4x4, timestamp: String)] = []
    var locationData: [(position: simd_float4x4, timestamp: Double)] = []

    // Initial EST timestamp and mach start time
    var initialESTTimestamp: Date?
    var initialMachTime: UInt64 = 0
    
    // Cached timebase info
    var timebaseInfo = mach_timebase_info_data_t()

    
    func getTimeInNanoseconds(machTime: UInt64) -> UInt64 {
        // Ensure timebase info is valid
        if timebaseInfo.denom == 0 {
            print("Error: Timebase denominator is zero")
            return 0
        }
        return machTime * UInt64(timebaseInfo.numer) / UInt64(timebaseInfo.denom)
    }
    
    
    let dateFormatter: DateFormatter = {
           let formatter = DateFormatter()
           formatter.dateStyle = .medium
           formatter.timeStyle = .long
           formatter.timeZone = TimeZone(abbreviation: "EST") // Set time zone to EST
           return formatter
       }()

    override func viewDidLoad() {
        super.viewDidLoad()
        // Retrieve the timebase info once at the start
        let result = mach_timebase_info(&timebaseInfo)
        if result != KERN_SUCCESS {
            print("Error: Failed to retrieve mach timebase info.")
        }

        setupARView()
        setupUI()
    }



    func setupARView() {
        sceneView = ARSCNView(frame: view.frame)
        sceneView.session.delegate = self
        sceneView.automaticallyUpdatesLighting = true
        view.addSubview(sceneView)

        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity
        sceneView.session.run(configuration)
    }

    func setupUI() {
        // Logging button
        logButton = UIButton(type: .system)
        logButton.setTitle("Start Logging", for: .normal)
        logButton.backgroundColor = .systemBlue
        logButton.setTitleColor(.white, for: .normal)
        logButton.layer.cornerRadius = 10
        logButton.frame = CGRect(x: 20, y: 50, width: 150, height: 50)
        logButton.addTarget(self, action: #selector(toggleLogging), for: .touchUpInside)
        view.addSubview(logButton)

        // XYZ Position Label
        positionLabel = UILabel()
        positionLabel.text = "X: 0.0 Y: 0.0 Z: 0.0"
        positionLabel.textAlignment = .center
        positionLabel.textColor = .white
        positionLabel.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        positionLabel.layer.cornerRadius = 8
        positionLabel.layer.masksToBounds = true
        positionLabel.frame = CGRect(x: 20, y: 120, width: 300, height: 60)
        view.addSubview(positionLabel)

        // Timestamp Label
       timestampLabel = UILabel()
       timestampLabel.text = "Timestamp: N/A"
       timestampLabel.textAlignment = .center
       timestampLabel.textColor = .white
       timestampLabel.backgroundColor = UIColor.black.withAlphaComponent(0.5)
       timestampLabel.layer.cornerRadius = 8
       timestampLabel.layer.masksToBounds = true
       timestampLabel.frame = CGRect(x: 20, y: 200, width: 300, height: 60)
       view.addSubview(timestampLabel)

    }

    @objc func toggleLogging() {
        isLogging.toggle()
        logButton.setTitle(isLogging ? "Stop Logging" : "Start Logging", for: .normal)
        logButton.backgroundColor = isLogging ? .systemRed : .systemBlue

        if !isLogging {
            saveLocationData()
        }
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let position = frame.camera.transform.columns.3
        let quaternion = simd_quatf(frame.camera.transform)
        
        DispatchQueue.main.async {
            self.positionLabel.text = String(format: "X: %.2f Y: %.2f Z: %.2f\nqx: %.2f qy: %.2f qz: %.2f qw: %.2f",
                                             position.x, position.y, position.z,
                                             quaternion.vector.x, quaternion.vector.y, quaternion.vector.z, quaternion.vector.w)
        }
        
        if isLogging {
            let timestamp = Date()
            let nanosecondTimestamp = timestamp.timeIntervalSince1970 * 1_000_000_000
            print("nanosecondTimestamp: \(nanosecondTimestamp)")

            // Step 1: Convert to seconds
            let timestampInSeconds = nanosecondTimestamp / 1_000_000_000

            // Step 2: Create Date object from seconds
            let date = Date(timeIntervalSince1970: timestampInSeconds)

            // Step 3: Format to EST time
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSS"
            formatter.timeZone = TimeZone(identifier: "America/New_York")
            let formattedDate = formatter.string(from: date)

            print("Formatted EST Time: \(formattedDate)")
            
            locationData.append((position: frame.camera.transform, timestamp: nanosecondTimestamp))
                
            
            print("Logged Position: \(position.x), \(position.y), \(position.z)")
            print("Quaternion: (\(quaternion.vector.x), \(quaternion.vector.y), \(quaternion.vector.z), \(quaternion.vector.w))")
            
//            // Update the timestamp label on the main thread
//            DispatchQueue.main.async {
//                self.timestampLabel.text = "Timestamp: \(estTimestamp)"

        }
    }
        

    

    func saveLocationData() {
        guard !locationData.isEmpty else { return }

        var output = "Timestamp, X, Y, Z, QX, QY, QZ, QW\n"
        for data in locationData {
            let position = data.position.columns.3
            let quaternion = simd_quatf(data.position)
            output += "\(data.timestamp), \(position.x), \(position.y), \(position.z), \(quaternion.vector.x), \(quaternion.vector.y), \(quaternion.vector.z), \(quaternion.vector.w)\n"
        }

        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("ARLocationData.csv")

        do {
            try output.write(to: fileURL, atomically: true, encoding: .utf8)
            print("✅ Saved location data to: \(fileURL)")

            let activityVC = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
            DispatchQueue.main.async {
                self.present(activityVC, animated: true, completion: nil)
            }
        } catch {
            print("❌ Error saving data: \(error)")
        }

        locationData.removeAll()
    }



    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isLogging {
            saveLocationData()
        }
        sceneView.session.pause()
    }
}


//

//let initialEstTime = Date()
//let formatter = DateFormatter()
//formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSS"  // up to microseconds
//formatter.timeZone = TimeZone(identifier: "America/New_York")
//let formattedDate = formatter.string(from: initialEstTime)
//print("Formatted EST Time with precision: \(formattedDate)")
//  

//
//if initialESTTimestamp == nil {
//    let initialEstTime = Date()
//    let formattedDate = formatter.string(from: initialEstTime)
//    print("Formatted EST Time with precision: \(formattedDate)")
//    
//    initialESTTimestamp = initialEstTime
//    initialMachTime = mach_absolute_time() // Capture the initial mach time
//}
//
//// Get the current mach time and calculate the elapsed time in nanoseconds
//let currentMachTime = mach_absolute_time()
//let elapsedTimeInNanoSeconds = getTimeInNanoseconds(machTime: (currentMachTime - initialMachTime))
//
//// add formattedDate + elapsedTimeInNanoSeconds
//if let initialEstTime = initialESTTimestamp {
//    let elapsedTimeInSeconds = Double(elapsedTimeInNanoSeconds) / 1_000_000_000
//    
//    let updatedTime = initialEstTime.addingTimeInterval(elapsedTimeInSeconds)
//    
//    let updatedFormattedDate = formatter.string(from: updatedTime)
//    print("Updated EST Time with elapsed nanoseconds: \(updatedFormattedDate) + \(elapsedTimeInNanoSeconds)ns")
//}
