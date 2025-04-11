//
//  ROSClient.swift
//  WorldTracking
//
//  Created by Fatema on 4/11/25.
//

//noetic ros

import Foundation
import Starscream

class ROSClient: WebSocketDelegate {
    func didReceive(event: Starscream.WebSocketEvent, client: any Starscream.WebSocketClient) {
        <#code#>
    }
    
    var socket: WebSocket!

    init() {
        var request = URLRequest(url: URL(string: "ws://<ROS_IP>:9090")!)
        socket = WebSocket(request: request)
        socket.delegate = self
        socket.connect()
    }

    func sendMessage(topic: String, data: [String: Any]) {
        let message: [String: Any] = [
            "op": "publish",
            "topic": topic,
            "msg": data
        ]

        if let jsonData = try? JSONSerialization.data(withJSONObject: message) {
            socket.write(data: jsonData)
        }
    }

    func didReceive(event: WebSocketEvent, client: WebSocket) {
        switch event {
        case .connected(_):
            print("Connected to ROS bridge!")
        case .disconnected(let reason, let code):
            print("Disconnected: \(reason) with code: \(code)")
        case .text(let string):
            print("Received text: \(string)")
        case .binary(let data):
            print("Received binary: \(data.count) bytes")
        default:
            break
        }
    }
}
