// Runs a Core ML classifier over photographs the way the app does, through Vision with the centre crop, and
// prints every probability as one line of JSON per photograph.
//
//     swift tools/vision_predict.swift model.mlpackage photo1.jpg photo2.jpg
//
// The pipeline resizes with Pillow and the phone with Vision. The two do not sample alike, and this tool is how
// the difference is measured on the Mac instead of guessed. Vision on the Mac and on the phone share their code.

import CoreML
import Foundation
import Vision

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    FileHandle.standardError.write(Data("usage: swift tools/vision_predict.swift model.mlpackage photo.jpg ...\n".utf8))
    exit(2)
}

do {
    let source = URL(fileURLWithPath: arguments[1])
    let compiled = source.pathExtension == "mlmodelc" ? source : try MLModel.compileModel(at: source)
    let configuration = MLModelConfiguration()
    configuration.computeUnits = .cpuOnly          // the same arithmetic on every Mac, so that two runs agree
    let model = try VNCoreMLModel(for: MLModel(contentsOf: compiled, configuration: configuration))
    for path in arguments.dropFirst(2) {
        let request = VNCoreMLRequest(model: model)
        request.imageCropAndScaleOption = .centerCrop
        try VNImageRequestHandler(url: URL(fileURLWithPath: path), orientation: .up).perform([request])
        guard let observations = request.results as? [VNClassificationObservation] else {
            FileHandle.standardError.write(Data("no classification for \(path)\n".utf8))
            exit(1)
        }
        var probabilities: [String: Double] = [:]
        for observation in observations { probabilities[observation.identifier] = Double(observation.confidence) }
        let line = try JSONSerialization.data(withJSONObject: ["file": URL(fileURLWithPath: path).lastPathComponent, "probabilities": probabilities], options: [.sortedKeys])
        print(String(decoding: line, as: UTF8.self))
    }
} catch {
    FileHandle.standardError.write(Data("vision_predict failed, \(error)\n".utf8))
    exit(1)
}
