import Foundation

let reverseVideo = "\u{1B}[7m"
let resetStyle = "\u{1B}[0m"

/// `text` cut (with …) or padded with spaces to exactly `width` characters.
func fit(_ text: String, _ width: Int) -> String {
    guard width > 0 else { return "" }
    if text.count > width { return String(text.prefix(width - 1)) + "…" }
    return text + String(repeating: " ", count: width - text.count)
}

/// Like `fit`, but keeps the end: handy for long paths.
func fitKeepingEnd(_ text: String, _ width: Int) -> String {
    guard width > 0 else { return "" }
    if text.count > width { return "…" + String(text.suffix(width - 1)) }
    return fit(text, width)
}

func rightAligned(_ text: String, _ width: Int) -> String {
    String(repeating: " ", count: max(0, width - text.count)) + text
}

/// 1234567 → "1,234,567"
func grouped(_ number: Int) -> String {
    let digits = Array(String(number))
    var result = ""
    for (i, digit) in digits.enumerated() {
        if i > 0 && (digits.count - i) % 3 == 0 { result += "," }
        result.append(digit)
    }
    return result
}

/// "[#####     ]" with `width` cells between the brackets.
func bar(_ fraction: Double, _ width: Int) -> String {
    let filled = min(width, max(0, Int((fraction * Double(width)).rounded())))
    return "[" + String(repeating: "#", count: filled) + String(repeating: " ", count: width - filled) + "]"
}
