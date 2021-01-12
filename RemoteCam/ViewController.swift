//
//  ViewController.swift
//  RemoteCam
//
//  Created by jino on 2021/01/12.
//

import UIKit
import ARKit
import Network

class ViewController: UIViewController {

    @IBOutlet weak var colorImageView: UIImageView!
    @IBOutlet weak var depthImageView: UIImageView!
    
    private let session = ARSession()
    private var sampleFrame: ARFrame { session.currentFrame! }
    
    private var listener = try! NWListener(using: .tcp, on:12345)
    private var nwConnection: NWConnection!
    private var connectionQueue = DispatchQueue(label: "connectionQueue")
    private var networkQueue = DispatchQueue(label: "networkQueue")
        
    private var colorImage : UIImage!
    private var depthImage : UIImage!
    private var depthData : CVPixelBuffer!
    
    // It'll works like EOF
    let tailData = "__TAIL_TAIL_TAIL__".data(using: .utf8)
    
    
    
    override func viewDidLoad() {
        super.viewDidLoad()

        session.delegate = self
    
        listener.newConnectionHandler = {
            connection in
            self.nwConnection = connection
            
            print("Connected!:", self.nwConnection.endpoint)
            
            self.nwConnection.start(queue: self.connectionQueue)
            print("connection started")
            
            func readData(){
                self.nwConnection.receive(minimumIncompleteLength: 1, maximumLength: 1024){
                    data, context, isComplete, error in
                    guard error == nil, let data = data else {
                        print("close connection")
                        return self.nwConnection.cancel()
                    }
                    let receivedString = String(decoding: data, as: UTF8.self)
                    print("Received:", receivedString)
                    
                    var imgData : Data?
                    if(receivedString == "rgb"){
                        imgData = self.colorImage.pngData()
                        
                    }
                    else if(receivedString == "depth"){
                        
                        CVPixelBufferLockBaseAddress(self.depthData, CVPixelBufferLockFlags(rawValue: 0))
                    
                        var byteBuffer = unsafeBitCast(CVPixelBufferGetBaseAddress(self.depthData), to: UnsafeMutablePointer<Float32>.self)
                        var depthArray = [Float32](repeating: -1, count: 256*192)
                        
                        for row in 0...191{
                            for col in 0...255{
                                depthArray[row*256 + col] = byteBuffer.pointee
                                byteBuffer = byteBuffer.successor()
                            }
                        }
                        CVPixelBufferUnlockBaseAddress(self.depthData, CVPixelBufferLockFlags(rawValue: 0))
                    
                        imgData = Data(bytes: &depthArray, count: depthArray.count * MemoryLayout<Float32>.stride)
                    }
                    else if(receivedString == "dummy"){
                        imgData = "DUMMY DATA".data(using: .utf8)
                    }
                    
                    var sendData = Data()
                    sendData.append(imgData!)
                    sendData.append(self.tailData!)
                    
                    print(sendData)
                    self.nwConnection.send(content : sendData, completion : .idempotent)
                }
            }
            while(true){
                readData()
                usleep(1000000) // 1sec, some delay is needed
                if(self.nwConnection.state == NWConnection.State.cancelled){
                    return;
                }
            }
        }
        
        listener.start(queue: DispatchQueue(label: "NWListener queue"))
        
        let configuration = ARWorldTrackingConfiguration()
        configuration.frameSemantics = .sceneDepth
        
        session.run(configuration)
        
    }
}

extension ViewController: ARSessionDelegate{
    
    func session(_ session: ARSession, didUpdate frame: ARFrame){
        
        let colorImage = UIImage(ciImage: CIImage(cvPixelBuffer: frame.capturedImage))
        colorImageView.image = colorImage
        self.colorImage = colorImage.resize(to: CGSize(width: 640, height: 480))
//        width :  1920
//        height :  1440
        
        // format : kCVPixelFormatType_DepthFloat32
        // width  : 256
        // height : 192
        let depthData = frame.sceneDepth?.depthMap
        if(depthData != nil){
            let depthImage = UIImage(ciImage: CIImage(cvPixelBuffer: depthData!))
            
            depthImageView.image = depthImage
            self.depthImage = depthImage
            self.depthData = depthData
        }
    }
}

// https://stackoverflow.com/a/55906075
extension UIImage {

    /// Resize image from given size.
    ///
    /// - Parameter newSize: Size of the image output.
    /// - Parameter resizeFramework: Technique for image resizing: UIKit / CoreImage / CoreGraphics / ImageIO / Accelerate.
    /// - Returns: Resized image.
    public func resize(to newSize: CGSize) -> UIImage? {
        return resizeWithUIKit(to: newSize)
//        return resizeWithCoreImage(to: newSize)
    }

    // MARK: - UIKit

    /// Resize image from given size.
    ///
    /// - Parameter newSize: Size of the image output.
    /// - Returns: Resized image.
    private func resizeWithUIKit(to newSize: CGSize) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(newSize, true, 1.0)
        self.draw(in: CGRect(origin: .zero, size: newSize))
        defer { UIGraphicsEndImageContext() }
        return UIGraphicsGetImageFromCurrentImageContext()
    }
}