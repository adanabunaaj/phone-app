# phone_capture

**phone_capture** is an iOS ARKit app that captures camera frames, depth map, camera pose, and GPS location using ARKit, CoreLocation, and SceneKit. It sends the collected data over TCP to an edge server and listens for UDP commands to trigger alerts (e.g., box full/empty).

## Features

- Captures color image and depth maps using ARKit
- Tracks device GPS location
- Records camera intrinsics and position/orientation matrix
- Saves data locally (image, depth, metadata)
- Sends captured data as Base64-encoded JSON over TCP
- Listens for UDP messages and displays alert based on received value
- Uses Network.framework for TCP and UDP communication

## Architecture

### On Capture:
1. Captures AR frame (color + depth)
2. Extracts camera intrinsics, position, orientation
3. Records current GPS coordinates
4. Saves files locally (`Documents/captures`)
5. Encodes everything into a JSON packet:
    <pre> { 
      "image": "<base64 jpg>",
      "depth": "<base64 raw depth>", 
      "meta": { "intrinsics": [[...],[...],[...]],
      "timestamp": ..., "location": {"lat": ..., "lon": ...},
      "camera_position": [...],
      "camera_orientation": [[...],[...],[...]] } 
     }  </pre>

6. Sends the JSON via TCP to a remote server

### UDP Listener:
- Listens on port `9999` for incoming messages
- Displays alert:
  - `"TRUE"` → Box is full
  - `"FALSE"` or anything else → Box is empty

## Setup

1. Open `phone_capture.xcodeproj` in Xcode
2. Ensure camera and location permissions are set in `Info.plist`:
    ```xml
    <key>NSCameraUsageDescription</key>
    <string>AR capture requires camera access.</string>
    <key>NSLocationWhenInUseUsageDescription</key>
    <string>Used to tag image capture with GPS location.</string>
    ```
3. Update the TCP host in:
    ```swift
    let tcpHost = "192.168.41.148" // ← Replace with server IP
    ```
4. Build and run the app on a physical device (ARKit and CoreLocation require hardware)

## Output Directory

Captured data is stored locally in:
```

<app sandbox>/Documents/captures/<timestamp>/
├── frame.jpg // captured RGB frame
├── depth.bin // raw depth data
└── meta.json // intrinsics, location, timestamp
  ```
## Requirements

- iOS 15.0+
- ARKit-compatible iPhone or iPad (We used iPhone 14 Pro)
- Xcode 13+
- Network access (TCP/UDP on LAN)





