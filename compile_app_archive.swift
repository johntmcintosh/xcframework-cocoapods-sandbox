#!/usr/bin/swift 

import Foundation 

// ---------------------------------------------------
// FileManager Helpers
// ---------------------------------------------------

extension FileManager {

    func directoryExists(at path: Path) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory:&isDirectory)
        return exists && isDirectory.boolValue
    }
    
    func deleteDirectory(at path: Path) throws {
        print("Deleting directory: \(path)".bold)
        guard directoryExists(at: path) else { return }
        try removeItem(atPath: path)
    }
    
    func prepareOutputDirectory(at path: Path) throws {
        try deleteDirectory(at: path)
        
        print("Creating output directory: \(path)".bold)
        try createDirectory(atPath: path, withIntermediateDirectories: true, attributes: nil)
    }

    func copyFile(atPath: String, toDirectory: String, allowOverwrite: Bool) throws {
        if directoryExists(at: toDirectory) == false { 
            try createDirectory(atPath: toDirectory, withIntermediateDirectories: true, attributes: nil)
        }

        let fileName = (atPath as NSString).lastPathComponent
        let destinationPath = (toDirectory as NSString).appendingPathComponent(fileName)

        if allowOverwrite {
            try? removeItem(atPath: destinationPath)
        }
        
        print("Copying item from \(atPath) to \(destinationPath)".bold)
        try copyItem(atPath: atPath, toPath: destinationPath)
    }
}

// ---------------------------------------------------
// String Helpers
// ---------------------------------------------------

extension String {
    var bold: String { 
        "\u{001B}[1m\(self)\u{001B}[22m"
    }

    var isNotEmpty: Bool { !isEmpty }
}

// ---------------------------------------------------
// Shell Helpers
// ---------------------------------------------------

enum ShellError: Error {
    case badTerminationStatus(code: Int, output: String?)
}

func asyncShell(command: String) throws {
    print("Executing command:\n\(command)".bold)
    
    let task = Process()
    task.launchPath = "/bin/bash"
    task.arguments = ["-c", command]

    let group = DispatchGroup()
    group.enter()
    
    task.terminationHandler = { process in
        group.leave()
    }
    
    task.launch()
    group.wait()
    
    print("Command terminated with status: \(task.terminationStatus)")
    if task.terminationStatus != 0 {
        throw ShellError.badTerminationStatus(code: Int(task.terminationStatus), output: nil)
    }
}

@discardableResult
func shell(command: String) throws -> String? {
    print("Executing command:\n\(command)".bold)

    let task = Process()
    task.launchPath = "/bin/bash"
    task.arguments = ["-c", command]

    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe

    task.launch()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8)

    task.waitUntilExit()
    if task.terminationStatus == 0 {
        return output
    } else {
        throw ShellError.badTerminationStatus(code: Int(task.terminationStatus), output: output)
    }
}

// ---------------------------------------------------
// Script execution
// ---------------------------------------------------

typealias Path = String
let fileManager = FileManager()

// Setup constants
let scriptDir: Path = fileManager.currentDirectoryPath
let projectDir = "\(scriptDir)/MyApp"
let buildDir = "\(scriptDir)/Build-App"
let appName = "MyApp"
let workspacePath = "\(projectDir)/\(appName).xcworkspace"
let archivePath = "\(buildDir)/\(appName).xcarchive"

// Build the archive
let buildCommand = """
    xcodebuild archive \\
        -workspace "\(workspacePath)" \\
        -scheme "\(appName)" \\
        -configuration "Release" \\
        -derivedDataPath "\(buildDir)" \\
        -archivePath "\(archivePath)"
    """

try asyncShell(command: buildCommand)

// Ensure that there are the expected number of BCSymbolMap files
print("Evaluating BCSymbolMaps...")
let archiveSymbolMapsPath = "\(archivePath)/BCSymbolMaps"
let expectedSymbolMapCount = 3
let foundSymbolMaps = try shell(command: "ls -1 '\(archiveSymbolMapsPath)'")!
print("Found BCSymbolMaps:\n\(foundSymbolMaps)")

// Ensure that there are the expected number of dSYMs
print("Evaluating dSYMs...")
let archiveDsymPath = "\(archivePath)/dSYMs"
let expectedDsymCount = 3
let foundDsyms = try shell(command: "ls -1 '\(archiveDsymPath)'")!
print("Found dSYMs:\n\(foundDsyms)")

// Results
let foundSymbolMapCount = foundSymbolMaps.trimmingCharacters(in: .whitespaces).components(separatedBy: .newlines).count - 1
if foundSymbolMapCount == expectedSymbolMapCount { 
    print("✅ Found the expected \(expectedSymbolMapCount) BCSymbolMap files".bold)
} else { 
    print("⛔️ Expected \(expectedSymbolMapCount) BCSymbolMap files, but found \(foundSymbolMapCount)".bold)
}

let foundDsymCount = foundDsyms.trimmingCharacters(in: .whitespaces).components(separatedBy: .newlines).count - 1
if foundDsymCount == expectedDsymCount { 
    print("✅ Found the expected \(expectedDsymCount) dSYMs".bold)
} else { 
    print("⛔️ Expected \(expectedDsymCount) dSYMs, but found \(foundDsymCount)".bold)
}
