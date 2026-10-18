import Foundation

enum Key: Equatable {
    case up, down, left, right, pageUp, pageDown, home, end
    case enter, backspace, escape, interrupt, tab, backTab
    case char(Character)

    /// The bytes of one key as a key. Unknown escape sequences are ignored.
    static func parse(_ bytes: [UInt8]) -> Key? {
        guard let first = bytes.first else { return nil }
        switch first {
        case 3: return .interrupt  // Ctrl-C (ISIG is off in raw mode)
        case 9: return .tab
        case 13, 10: return .enter
        case 127, 8: return .backspace
        case 27:
            if bytes.count == 1 { return .escape }
            guard bytes.count >= 3, bytes[1] == UInt8(ascii: "[") || bytes[1] == UInt8(ascii: "O") else { return nil }
            switch bytes[2] {
            case UInt8(ascii: "A"): return .up
            case UInt8(ascii: "B"): return .down
            case UInt8(ascii: "C"): return .right
            case UInt8(ascii: "D"): return .left
            case UInt8(ascii: "H"), UInt8(ascii: "1"), UInt8(ascii: "7"): return .home
            case UInt8(ascii: "F"), UInt8(ascii: "4"), UInt8(ascii: "8"): return .end
            case UInt8(ascii: "5"): return .pageUp
            case UInt8(ascii: "6"): return .pageDown
            case UInt8(ascii: "Z"): return .backTab  // ⇧Tab
            default: return nil
            }
        default:
            return String(decoding: bytes, as: UTF8.self).first.map(Key.char)
        }
    }

    /// Every key in one read(): fast typing and pasting deliver several at once.
    static func parseAll(_ bytes: [UInt8]) -> [Key] {
        var keys: [Key] = []
        var start = 0
        while start < bytes.count {
            let end = start + length(of: bytes, at: start)
            if let key = parse(Array(bytes[start..<end])) { keys.append(key) }
            start = end
        }
        return keys
    }

    /// Bytes taken by the key at `start`: an escape sequence, one UTF-8 character, or one byte.
    private static func length(of bytes: [UInt8], at start: Int) -> Int {
        let first = bytes[start]
        let left = bytes.count - start
        if first == 27 {
            guard left > 2, bytes[start + 1] == UInt8(ascii: "[") || bytes[start + 1] == UInt8(ascii: "O") else { return 1 }
            // ESC [ or ESC O, then parameter bytes (0-9 ; etc.), then one final byte.
            var end = start + 2
            while end < bytes.count && (0x30...0x3F).contains(bytes[end]) { end += 1 }
            return min(bytes.count, end + 1) - start
        }
        if first >= 0xF0 { return min(4, left) }
        if first >= 0xE0 { return min(3, left) }
        if first >= 0xC0 { return min(2, left) }
        return 1
    }
}

/// Raw mode on the alternate screen. Always restored: by `stop()`, at exit, and on fatal signals.
enum Terminal {
    nonisolated(unsafe) private static var original = termios()
    nonisolated(unsafe) private static var active = false
    nonisolated(unsafe) private static var handlersInstalled = false
    nonisolated(unsafe) static var resized = false
    nonisolated(unsafe) private static var pending: [Key] = []

    static func start() {
        guard !active else { return }
        installHandlers()
        tcgetattr(STDIN_FILENO, &original)
        var raw = original
        raw.c_lflag &= ~tcflag_t(ECHO | ICANON | ISIG | IEXTEN)
        raw.c_iflag &= ~tcflag_t(IXON | ICRNL)
        withUnsafeMutableBytes(of: &raw.c_cc) { cc in
            cc[Int(VMIN)] = 0
            cc[Int(VTIME)] = 1  // read() waits at most 0.1 s
        }
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)
        writeStatic("\u{1B}[?1049h\u{1B}[?25l")  // alternate screen, hide cursor
        active = true
    }

    /// Safe to call from a signal handler: only write() and tcsetattr().
    static func stop() {
        guard active else { return }
        active = false
        writeStatic("\u{1B}[?25h\u{1B}[?1049l")  // show cursor, back to the normal screen
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &original)
    }

    static func size() -> (rows: Int, cols: Int) {
        var size = winsize()
        if ioctl(STDOUT_FILENO, TIOCGWINSZ, &size) == 0, size.ws_row > 0, size.ws_col > 0 {
            return (Int(size.ws_row), Int(size.ws_col))
        }
        return (24, 80)
    }

    /// The next key, waiting up to 0.1 s when none are queued.
    static func readKey() -> Key? {
        if pending.isEmpty {
            var bytes = [UInt8](repeating: 0, count: 256)
            let count = read(STDIN_FILENO, &bytes, bytes.count)
            if count > 0 { pending = Key.parseAll(Array(bytes[..<count])) }
        }
        return pending.isEmpty ? nil : pending.removeFirst()
    }

    /// Blocks until a key is pressed. Nil means the window was resized and needs a redraw.
    static func waitForKey() -> Key? {
        while true {
            if resized {
                resized = false
                return nil
            }
            if let key = readKey() { return key }
        }
    }

    /// Redraws the whole screen in one write, so it doesn't flicker.
    static func draw(_ lines: [String]) {
        var text = "\u{1B}[H" + lines.map { $0 + "\u{1B}[K" }.joined(separator: "\r\n") + "\u{1B}[J"
        text.withUTF8 { bytes in
            var offset = 0
            while offset < bytes.count {
                let written = write(STDOUT_FILENO, bytes.baseAddress! + offset, bytes.count - offset)
                if written <= 0 { break }
                offset += written
            }
        }
    }

    private static func writeStatic(_ text: StaticString) {
        _ = write(STDOUT_FILENO, text.utf8Start, text.utf8CodeUnitCount)
    }

    private static func installHandlers() {
        guard !handlersInstalled else { return }
        handlersInstalled = true
        atexit { Terminal.stop() }
        for sig in [SIGINT, SIGTERM, SIGHUP, SIGQUIT, SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGTRAP, SIGFPE] {
            signal(sig) { sig in
                Terminal.stop()
                signal(sig, SIG_DFL)
                raise(sig)
            }
        }
        signal(SIGWINCH) { _ in Terminal.resized = true }
    }
}
