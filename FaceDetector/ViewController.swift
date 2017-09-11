//
//  ViewController.swift
//  FaceDetector
//
//  Created by Louis Franco on 6/11/17.
//  Copyright © 2017 Lou Franco. All rights reserved.
//

import UIKit
import Vision
import AVFoundation

class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {

    @IBOutlet var imageView: UIImageView?
    @IBOutlet var face: UIView?

    var captureSession = AVCaptureSession();
    var sessionOutput = AVCaptureVideoDataOutput()

    private let cameraPosition = AVCaptureDevice.Position.front

    private let sessionQueue = DispatchQueue(label: "avcapture sessionQueue")
    private var hasCameraPermission: Bool = false
    private let context = CIContext()

    var requests: [VNDetectFaceRectanglesRequest] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        self.face?.isHidden = true

        getCameraPermission()
        setupVision()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        sessionQueue.async { [weak self] in
            self?.configureSession()
            self?.captureSession.startRunning()
        }
    }

    func getCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            self.hasCameraPermission = true
            break
        case .notDetermined:
            sessionQueue.suspend()
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                self?.hasCameraPermission = granted
                self?.sessionQueue.resume()
            }
        case .denied, .restricted:
            break
        }
    }

    private func configureSession() {
        let deviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [ .builtInTelephotoCamera, .builtInWideAngleCamera], mediaType: .video, position: self.cameraPosition)
        for device in (deviceDiscoverySession.devices) {
            do {
                let input = try AVCaptureDeviceInput(device: device)
                if (captureSession.canAddInput(input)) {
                    captureSession.addInput(input);
                    sessionOutput.setSampleBufferDelegate(self, queue: self.sessionQueue)

                    if (captureSession.canAddOutput(sessionOutput)){
                        captureSession.addOutput(sessionOutput);
                        guard let connection = sessionOutput.connection(with: .video) else { return }
                        guard connection.isVideoOrientationSupported else { return }
                        guard connection.isVideoMirroringSupported else { return }
                        connection.videoOrientation = .portrait
                        connection.isVideoMirrored = (self.cameraPosition == .front)
                    }
                    break
                }
            }
            catch {

            }
        }
    }

    private func imageFromSampleBuffer(imageBuffer: CVImageBuffer) -> UIImage? {

        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    // MARK: AVCaptureVideoDataOutputSampleBufferDelegate

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection:  AVCaptureConnection) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Draw the image on the screen
        guard let uiImage = imageFromSampleBuffer(imageBuffer: imageBuffer) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.imageView?.image = uiImage
        }

        // Make the Face Detection Request
        var requestOptions: [VNImageOption: Any] = [:]
        if let cameraIntrinsicData = CMGetAttachment(sampleBuffer, kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix, nil) {
            requestOptions = [.cameraIntrinsics: cameraIntrinsicData]
        }

        // The orientation should be determined from the phone position, but assume portrait for now
        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer:imageBuffer, orientation: .up, options: requestOptions)

        do {
            try imageRequestHandler.perform(self.requests)
        } catch {
            print (error)
        }
    }

    // MARK: Face Detection code

    func setupVision() {
        let faceDetectionRequest = VNDetectFaceRectanglesRequest(completionHandler: self.handleFaces)
        self.requests = [faceDetectionRequest];
    }

    func drawFaceBox(frame: CGRect) {
        self.face?.frame = frame
        self.face?.isHidden = false
    }

    func hideFaceBox() {
        self.face?.isHidden = true
    }

    func handleFaces(request: VNRequest, error: Error?) {
        DispatchQueue.main.async {
            self.hideFaceBox()
            guard let result = (request.results as? [VNFaceObservation])?.first else { return }
            let bb = result.boundingBox
            if let imgFrame = self.imageView?.frame {
                // Bounding Box is a 0..<1.0 normlized to the size of the input image and
                // the origin is at the bottom left of the image (so Y needs to be flipped)
                let faceSize = CGSize(width: bb.width * imgFrame.width, height: bb.height * imgFrame.height)
                self.drawFaceBox(frame:
                    CGRect(x: imgFrame.origin.x + bb.origin.x * imgFrame.width,
                           y: imgFrame.origin.y + imgFrame.height - (bb.origin.y * imgFrame.height) - faceSize.height,
                           width: faceSize.width,
                           height: faceSize.height)
                )
            }
        }
    }

}

