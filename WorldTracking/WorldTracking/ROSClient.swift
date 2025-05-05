//
//  ROSClient.swift
//  WorldTracking
//
//  Created by Fatema on 4/11/25.
//

//noetic ros

import Foundation
import Network

func startRepeatingUDPSender() {
    Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
        //sendUDP(message: "Hello from UIKit!", host: "192.168.41.205", port: 5005)
    }
}


func sendUDP(message: String, host: String, port: UInt16) {
    let connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: .udp)

        connection.stateUpdateHandler = { newState in
            switch newState {
            case .ready:
                print("Connection ready")
                let data = message.data(using: .utf8)!
                connection.send(content: data, completion: .contentProcessed({ error in
                    if let error = error {
                        print("Send error: \(error)")
                    } else {
                        print("Message sent")
                        
                        // Now wait for a response
                        connection.receiveMessage { (data, context, isComplete, error) in
                            if let data = data, let message = String(data: data, encoding: .utf8) {
                                print("Received response: \(message)")
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
