#!/usr/bin/swift 

/**
 Compile the SDK into archives, and combine into an xcframework.

 Script-specific build arguments are expected to be in a format of:
    --argumentName value

 Supported script arguments:
    --destination [device, simulator] >> Specify to build only a single architecture

 Additional build arguments that are not prefixed with two dashes will be 
 appended onto the end of the internal xcodebuild commands. For example:

    ./compile_xcframework.swift DSH_KEEP_LOCAL_SERVER=YES

 will result in the following xcodebuild:

    xcodebuild archive \ 
       -project "some-project.xcodeproj" \
       -scheme "some-scheme" \
       ... 
       BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
       DSH_KEEP_LOCAL_SERVER=YES
*/

import Foundation 

print("Launching compile_xcframework.swift with launch arguments:")
print(CommandLine.arguments)

// ---------------------------------------------------
// Command Line Argument Helpers
// ---------------------------------------------------

extension CommandLine { 

    /// Extract script-related arguments from the script's inpus arguments.
    static var scriptArguments: [String: String] {
        parsedArguments.script
    }

    /// Extract build-related arguments from the script's input arguments.
    static var xcodebuildArguments: String {
        parsedArguments.xcodebuild.joined(separator: " ")
    }

    private static var parsedArguments: (script: [String: String], xcodebuild: [String]) { 
        let inputArguments: [String] = {
            var args = Self.arguments
            args.removeFirst(1)
            return args
        }()
        
        var scriptArguments: [String: String] = [:]
        var buildArguments: [String] = []
        var nextArgumentIsScriptArgValue = false

        for (index, argument) in inputArguments.enumerated() {
            if nextArgumentIsScriptArgValue {
                nextArgumentIsScriptArgValue = false
                scriptArguments[inputArguments[index-1]] = argument
            } else if argument.hasPrefix("--") {
                nextArgumentIsScriptArgValue = true
            } else {
                buildArguments.append(argument)
            }
        }

        return (script: scriptArguments, xcodebuild: buildArguments)
    }
}

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
let projectDir = "\(scriptDir)/MySDK"
let buildDir = "\(scriptDir)/Build-12"
let frameworkName = "MySDK"

// Define output archives

struct ArchiveDestination: Equatable {
    var buildDestinationParameter: Path
    var archiveFile: Path
    var shouldHaveBitcodeSymbols: Bool

    var path: Path {
        "\(buildDir)/\(archiveFile).xcarchive"
    }

    var frameworkPath: Path { 
        "\(path)/Products/Library/Frameworks/\(frameworkName).framework"
    }

    var bcSymbolMapsDirectory: Path { 
        "\(path)/BCSymbolMaps"
    }

    var dsymsDirectory: Path { 
        "\(path)/dSYMs"
    }

    var dsymPath: Path { 
        "\(path)/dSYMs/\(frameworkName).framework.dSYM"
    }

    func xcodebuildDebugSymbolsParameters() throws -> String { 
        var parameters = ""

        let findDsymsCommand = """
        find "\(dsymsDirectory)" -name "*.dSYM"
        """
        let findDsymsCommandShellResponse = try shell(command: findDsymsCommand) ?? ""
        let dSYMFiles = findDsymsCommandShellResponse.components(separatedBy: .newlines).filter { $0.isEmpty == false }
        // TODO: Update error thrown
        guard dSYMFiles.isEmpty == false else { throw SymbolMapError.noBcSymbolMapsFound }
        print("Found dSYMFiles files:".bold)
        print(dSYMFiles)

        for file in dSYMFiles { 
            parameters += " -debug-symbols '\(file)' \\\n"
        }

        let findSymbolMapsCommand = """
        find "\(bcSymbolMapsDirectory)" -name "*.bcsymbolmap" -type f
        """
        let symbolMapFilesShellResponse = (try? shell(command: findSymbolMapsCommand)) ?? ""
        let bcSymbolMapFiles = symbolMapFilesShellResponse.components(separatedBy: .newlines).filter { $0.isEmpty == false }

        let hasNecessaryBitcodeSymbols = shouldHaveBitcodeSymbols ? bcSymbolMapFiles.count > 0 : true 
        guard hasNecessaryBitcodeSymbols else { throw SymbolMapError.noBcSymbolMapsFound }
        print("Found BCSymbolMap files:".bold)
        print(bcSymbolMapFiles)

        for file in bcSymbolMapFiles { 
            parameters += " -debug-symbols '\(file)' \\\n"
        }

        return parameters
    }
}

let simulatorArchive = ArchiveDestination(
    buildDestinationParameter: "generic/platform=iOS Simulator",
    archiveFile: "SDK-iOS-Simulator",
    shouldHaveBitcodeSymbols: false
)

let deviceArchive = ArchiveDestination(
    buildDestinationParameter: "generic/platform=iOS",
    archiveFile: "SDK-iOS",
    shouldHaveBitcodeSymbols: true
)

let buildDestinations: [ArchiveDestination] = {
    if let deviceArgument = CommandLine.scriptArguments["--destination"] { 
        if deviceArgument == "simulator" { 
            return [simulatorArchive]
        } else if deviceArgument == "device" { 
            return [deviceArchive]
        }
    }
    return [
        deviceArchive,
        simulatorArchive
    ]
}()

// ---------------------------------------------------
// Archive compilation
// ---------------------------------------------------

struct BuildDefinition { 
    private let projectName = "MySDK.xcodeproj"
    private var projectPath: String { "\(projectDir)/\(projectName)" }
    private let scheme: String = "MySDK"
    private let buildConfig: String = "Release"
    private let destination: ArchiveDestination

    init(destination: ArchiveDestination) { 
        self.destination = destination
    }

    var shellCommand: String { 
        """
        xcodebuild archive \\
            -project "\(projectPath)" \\
            -scheme "\(scheme)" \\
            -configuration "\(buildConfig)" \\
            -destination "\(destination.buildDestinationParameter)" \\
            -derivedDataPath "\(buildDir)" \\
            -archivePath "\(destination.path)" \\
            SKIP_INSTALL=NO \\
            BUILD_LIBRARY_FOR_DISTRIBUTION=YES \\
            \(CommandLine.xcodebuildArguments)
        """
    }
}

// Build the archive for each destination
for destination in buildDestinations { 
    let build = BuildDefinition(destination: destination)
    try asyncShell(command: build.shellCommand)
}

// ---------------------------------------------------
// XCFramework
// ---------------------------------------------------

let xcOutputDir = buildDir
let xcframeworkOutputPath = "\(xcOutputDir)/\(frameworkName).xcframework"
try fileManager.deleteDirectory(at: xcframeworkOutputPath)

// Generate xcframework from all archives
var xcframeworkCommand = "xcodebuild -create-xcframework \\\n"
try buildDestinations.forEach {
    xcframeworkCommand += """
        -framework "\($0.frameworkPath)" \\
        \(try $0.xcodebuildDebugSymbolsParameters())
    """
}
xcframeworkCommand += """
    -output "\(xcframeworkOutputPath)"
"""

try asyncShell(command: xcframeworkCommand)

// ---------------------------------------------------
// BCSymbolMaps
// ---------------------------------------------------

enum SymbolMapError: Error {
    case noUUIDsFound
    case noBcSymbolMapsFound
}
