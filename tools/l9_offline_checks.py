#!/usr/bin/env python3
from pathlib import Path
import argparse, re, shutil, subprocess, os, tempfile
parser=argparse.ArgumentParser(description='Focused Linux L9 offline regression; no backend, APNs, CI or account access.')
parser.add_argument('--swift',default=shutil.which('swift'))
parser.add_argument('--work-dir',type=Path)
parser.add_argument('--base',help='Compare new regressions with these three production files at an existing local commit')
parser.add_argument('--filter')
args=parser.parse_args()
if not args.swift:
    parser.error('Supply --swift pointing to an installed Linux Swift toolchain')
repo=Path(__file__).resolve().parents[1]
out=args.work_dir or Path(tempfile.mkdtemp(prefix='l9-offline-'))
changed={'NativeFriendFlow','NativePushAttemptRead','NativeWebhookHTTPService'}
if args.base:
    args.base=subprocess.check_output(['git','rev-parse','--verify',args.base+'^{commit}'],cwd=repo,text=True).strip()
print('L9 focused source test; Linux adapters do not verify Apple Combine/CryptoKit, UI, signing, backend or normal-entry wiring.',flush=True)
for d in ['Sources/QuestifyCore','Sources/CryptoKit','Sources/Combine','Tests/QuestifyCoreTests']:
    (out/d).mkdir(parents=True,exist_ok=True)
(out/'Package.swift').write_text('''// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "L9Offline", products: [.library(name: "QuestifyCore", targets: ["QuestifyCore"])], targets: [
.target(name: "CryptoKit", linkerSettings: [.linkedLibrary("crypto")]), .target(name: "Combine"),
.target(name: "QuestifyCore", dependencies: ["CryptoKit", "Combine"]),
.testTarget(name: "QuestifyCoreTests", dependencies: ["QuestifyCore"])])
''')
# Linux-only test adapters: actual SHA256 from the installed OpenSSL, plus a
# publication wrapper. Neither reimplements the business methods under test.
(out/'Sources/CryptoKit/Compat.swift').write_text('''import Foundation
@_silgen_name("SHA256") private func opensslSHA256(_ data: UnsafeRawPointer?, _ size: Int, _ result: UnsafeMutablePointer<UInt8>) -> UnsafeMutablePointer<UInt8>?
public enum SHA256 {
 public static func hash(data: Data) -> [UInt8] {
  var result = [UInt8](repeating: 0, count: 32)
  data.withUnsafeBytes { bytes in _ = opensslSHA256(bytes.baseAddress, bytes.count, &result) }
  return result
 }
}
''')
(out/'Sources/Combine/Compat.swift').write_text('''public protocol ObservableObject: AnyObject {}
@propertyWrapper public struct Published<Value> {
 public var wrappedValue: Value
 public init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
}
''')
whole=['APIConfiguration','AuthRequestBuilder','AppPreferences','NativeFriendContracts','NativeFriendMetadataContracts','NativeFriendIntentJournal','NativeFriendFlow','NativeFriendService','NativeNotificationPermissionState','NativePushAttemptRead','NativeWebhookContracts','NativeWebhookScopeProvider','NativeWebhookRuntimeRoute','NativeWebhookHTTPService','NativeWebhookPendingJournal','NativeWebhookPresentation','NativeWebhookCoordinator']
for name in whole:
    source=subprocess.check_output(['git','show',args.base+':Core/'+name+'.swift'],cwd=repo) if args.base and name in changed else (repo/f'Core/{name}.swift').read_bytes()
    (out/f'Sources/QuestifyCore/{name}.swift').write_bytes(source)
# Copy exact top-level shared declarations; exclude unrelated app graphs.
def decl(file,marker):
    source=(repo/f'Core/{file}.swift').read_text()
    start=source.index(marker)
    first=source.index('{',start)
    if '\n' not in source[start:first+1] and source.find('}',first)<source.find('\n',first):
        end=source.index('}',first)+1
    else:
        end=source.index('\n}',first)+2
    return source[start:end]+'\n'
parts=[('AuthService','public protocol HTTPTransport'),('RegionalConfiguration','public enum RegionalMarket'),('PlayExperienceContracts','public struct PlayExperienceSession'),('PlayExperienceContracts','extension PlayExperienceSession'),('RuntimeDependencyConfiguration','public struct RuntimeDependencyContext'),('OperationAdapterSafety','public struct OperationEndpointApproval'),('OperationAdapterSafety','public struct OperationPendingRecord'),('OperationAdapterSafety','@MainActor public protocol OperationPendingJournal'),('OperationAdapterSafety','@MainActor public protocol OperationPendingListing'),('ProjectEditLocalStore','@MainActor public protocol ProjectEditDataStorage'),('SquareContracts','public enum SquareContentGeneration')]
(out/'Sources/QuestifyCore/SharedDeclarations.swift').write_text('import Foundation\nimport FoundationNetworking\n'+''.join(decl(*p) for p in parts))
tests=['NativeFriendOriginalReplayBoundaryTests','NativeFriendIndependentRecoveryTests','NativeWebhookContractsTests','NativeWebhookRestoredBoundaryTests','NativeWebhookResponseBoundaryTests','NativePushAttemptReadBoundaryTests','NativeNotificationPermissionLifecycleTests']
for name in tests:
    source=(repo/f'Tests/CoreTests/{name}.swift').read_text()
    # Linux XCTest cannot discover synchronous @MainActor methods. Only add async
    # to the temporary test signature; preserve every assertion and production byte.
    source=re.sub(r'(func test\w+\(\))(?! async)',r'\1 async',source)
    (out/f'Tests/QuestifyCoreTests/{name}.swift').write_text(source)
(out/'Tests/QuestifyCoreTests/LinuxDigestAdapterTests.swift').write_text('''import Foundation
import XCTest
import CryptoKit
final class LinuxDigestAdapterTests: XCTestCase {
 func testStandardSHA256Vectors() {
  XCTAssertEqual(SHA256.hash(data: Data()).map { String(format: "%02x", $0) }.joined(), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
  XCTAssertEqual(SHA256.hash(data: Data("abc".utf8)).map { String(format: "%02x", $0) }.joined(), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
 }
}
''')
env=os.environ.copy()
env.setdefault('XDG_CACHE_HOME',str(out/'cache'))
env.setdefault('CLANG_MODULE_CACHE_PATH',str(out/'clang-cache'))
command=[args.swift,'test','--package-path',str(out),'-j','4']
if args.filter:
    command += ['--filter',args.filter]
raise SystemExit(subprocess.run(command,cwd=repo,env=env).returncode)
