import Foundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers

func check(_ value: @autoclosure () -> Bool, _ message: String) {
    precondition(value(), message)
}
let code = "0123456789abcdef0123456789abcdef"
let payload = SharedInvite(code: code, expiresAt: .now).url.absoluteString
let image = SharedQRCode.image(for: payload)!
check(SharedQRCode.invitation(in: image) == code, "Generated invitation must survive QR decoding")
let png = NSMutableData()
let destination = CGImageDestinationCreateWithData(png, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, image, nil)
check(CGImageDestinationFinalize(destination), "PNG export")
check(SharedQRCode.invitation(in: png as Data) == code, "Image import must preserve invitation")
check(SharedQRCode.invitation(in: Data("not an image".utf8)) == nil, "Invalid images must be rejected")
let foreign = SharedQRCode.image(for: "https://example.com/\(code)")!
check(SharedQRCode.invitation(in: foreign) == nil, "Foreign QR links must be rejected")
let legacy = SharedQRCode.image(for: "com.monotask.ios://join?code=\(code)")!
check(SharedQRCode.invitation(in: legacy) == code, "Legacy invitations must scan")
print("Passed 6 QR generation, PNG import and invitation validation checks")
