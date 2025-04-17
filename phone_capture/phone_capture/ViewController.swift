//
//  ViewController.swift
//  phone_capture
//
//  Created by Adan Abu Naaj on 4/17/25.
//

import UIKit
import ARKit
import SceneKit //for ARSCNView
import CoreLocation

class ViewController: UIViewController, ARSessionDelegate {
    func capturesDirectoryURL() -> URL {
        let fm = FileManager.default
        let docs = try! fm.url(for: .documentDirectory,
                                 in: .userDomainMask,
                                 appropriateFor: nil,
                                 create: true)
        let captures = docs.appendingPathComponent("captures", isDirectory: true)
        
        if !fm.fileExists(atPath: captures.path) {
            try! fm.createDirectory(at: captures,
                                    withIntermediateDirectories: true,
                                    attributes: nil)
          }
          return captures
    }
    
    func saveCaptureLocally(image: UIImage,
                            depthMap: CVPixelBuffer,
                            intrinsics: simd_float3x3,
                            timestamp: TimeInterval,
                            location: (Double?, Double?)) {
        let folder = capturesDirectoryURL()
        
        // Create a unique subfolder per capture (e.g. timestamp)
          let name = String(format: "%.3f", timestamp)
          let captureFolder = folder.appendingPathComponent(name, isDirectory: true)
          try? FileManager.default.createDirectory(at: captureFolder,
                                                   withIntermediateDirectories: true,
                                                   attributes: nil)
        
        //Save image as JPEG
          if let jpg = image.jpegData(compressionQuality: 0.8) {
            let imgURL = captureFolder.appendingPathComponent("frame.jpg")
            try? jpg.write(to: imgURL)
            print("Saved image to", imgURL.path)
          }
        
        //  Save depth map raw bytes
          CVPixelBufferLockBaseAddress(depthMap, .readOnly)
          let length = CVPixelBufferGetDataSize(depthMap)
          let base   = CVPixelBufferGetBaseAddress(depthMap)!
          let depthData = Data(bytes: base, count: length)
          CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)
          
          let depthURL = captureFolder.appendingPathComponent("depth.bin")
          try? depthData.write(to: depthURL)
          print("Saved depth to", depthURL.path)
        
        
        //Save metadata JSON
          let meta: [String:Any] = [
            "intrinsics": [
              [intrinsics[0,0], intrinsics[0,1], intrinsics[0,2]],
              [intrinsics[1,0], intrinsics[1,1], intrinsics[1,2]],
              [intrinsics[2,0], intrinsics[2,1], intrinsics[2,2]]
            ],
            "timestamp": timestamp,
            "location": ["lat": location.0 ?? 0, "lon": location.1 ?? 0]
          ]
          let metaURL = captureFolder.appendingPathComponent("meta.json")
          let json = try! JSONSerialization.data(withJSONObject: meta, options: [.prettyPrinted])
          try? json.write(to: metaURL)
          print("Saved metadata to", metaURL.path)
        }
          
    
    
//    func sendToServer(image: UIImage,
//                        depthMap: CVPixelBuffer,
//                        intrinsics: simd_float3x3,
//                        timestamp: TimeInterval,
//                        location: (Double?, Double?)) {
//        
//        let url = URL(string: "https://<YOUR‑SERVER‑URL>/upload")!
//        var req = URLRequest(url: url)
//        req.httpMethod = "POST"
//        let boundary = "Boundary-\(UUID().uuidString)"
//        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
//
//        var data = Data()
//
//        // — Image part
//        data.append("--\(boundary)\r\n".data(using: .utf8)!)
//        data.append("Content-Disposition: form-data; name=\"image\"; filename=\"frame.jpg\"\r\n".data(using: .utf8)!)
//        data.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
//        data.append(image.jpegData(compressionQuality: 0.8)!)
//        data.append("\r\n".data(using: .utf8)!)
//
//        // — Depth map part (raw floats)
//        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
//        let length = CVPixelBufferGetDataSize(depthMap)
//        let base = CVPixelBufferGetBaseAddress(depthMap)!
//        data.append("--\(boundary)\r\n".data(using: .utf8)!)
//        data.append("Content-Disposition: form-data; name=\"depth\"; filename=\"depth.bin\"\r\n".data(using: .utf8)!)
//        data.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
//        data.append(Data(bytes: base, count: length))
//        data.append("\r\n".data(using: .utf8)!)
//        CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)
//
//        // — Metadata JSON
//        let meta: [String:Any] = [
//          "intrinsics": [
//            [intrinsics[0,0], intrinsics[0,1], intrinsics[0,2]],
//            [intrinsics[1,0], intrinsics[1,1], intrinsics[1,2]],
//            [intrinsics[2,0], intrinsics[2,1], intrinsics[2,2]]
//          ],
//          "timestamp": timestamp,
//          "location": ["lat": location.0 ?? 0, "lon": location.1 ?? 0]
//        ]
//        let jsonMeta = try! JSONSerialization.data(withJSONObject: meta)
//        data.append("--\(boundary)\r\n".data(using: .utf8)!)
//        data.append("Content-Disposition: form-data; name=\"meta\"\r\n\r\n".data(using: .utf8)!)
//        data.append(jsonMeta)
//        data.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
//
//        // — Send it off
//        URLSession.shared.uploadTask(with: req, from: data) { respData, resp, err in
//          if let err = err {
//            print("Upload error:", err)
//          } else {
//            print("Upload successful")
//          }
//        }.resume()
//      }
    
    @IBOutlet weak var arView: ARSCNView! //Connect this in interface builder
    let locationManager = CLLocationManager() //to get GPS
    var currentLocation: CLLocation?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        
        //set up AR
        arView.session.delegate = self
        let config = ARWorldTrackingConfiguration()
        config.frameSemantics.insert(.sceneDepth) //enable LiDAR depth
        arView.session.run(config)
        
        //set up Location
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        
    }
    
    //Capture Action
    @IBAction func capturePressed(_ sender: UIButton){
        let alert = UIAlertController(title: "🔥 Fired", message: nil, preferredStyle: .alert)
          alert.addAction(.init(title: "OK", style: .default))
          present(alert, animated: true)
        print("capturePressed!")
        guard let frame = arView.session.currentFrame else {return}
        
        //1. Color Image:
        let buffer = frame.capturedImage
        let ci = CIImage(cvPixelBuffer: buffer)
        let ui = UIImage(ciImage: ci)
        
        //2.Depth
        guard let depthData = frame.sceneDepth else {return}
        let depthMap = depthData.depthMap
        
        //3.Intrinsics & timestamp
        let intrinsics = frame.camera.intrinsics
        let ts = frame.timestamp
        
        //4.Location
        let lat = currentLocation?.coordinate.latitude
        let lon = currentLocation?.coordinate.longitude
        
        // 5. Send off (implement sendToServer as earlier)
//            sendToServer(image: ui,
//                         depthMap: depthMap,
//                         intrinsics: intrinsics,
//                         timestamp: ts,
//                         location: (lat, lon))
        saveCaptureLocally(image: ui,
                           depthMap: depthMap,
                           intrinsics: intrinsics,
                           timestamp: ts,
                           location: (lat, lon))
            
        
    }


}

//CLLocationManagerDelegate

extension ViewController: CLLocationManagerDelegate {
  func locationManager(_ mgr: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
    currentLocation = locs.last
  }
  
  func locationManager(_ mgr: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
    // handle user granting/denying location
  }
}
