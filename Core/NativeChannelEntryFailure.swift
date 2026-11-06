import Foundation

public enum NativeSpaceAdmissionFailure: Error { case unavailable, invalid, notSent, unknown, rejected(Int) }
