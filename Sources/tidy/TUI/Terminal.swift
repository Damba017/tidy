import Foundation

enum Key: Equatable {
    case up, down, left, right, pageUp, pageDown, home, end
    case enter, backspace, escape, interrupt
    case char(Character)

    /// The bytes of one read() as a key. Unknown escape sequences are ignored.
    static func parse(_ bytes: [UInt8]) -> Key? {
        guard let first = bytes.first else { return nil }
        switch first {
        case 3: return .interrupt  // Ctrl-C (ISIG is off in raw mode)
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
            default: return nil
            }
        default:
            return String(decoding: bytes, as: UTF8.self).first.map(Key.char)
        }
    }
}

/// Raw mode on the alternate screen. Always restored: by `stop()`, at exit, and on fatal signals.
enum Terminal {
    nonisolated(unsafe) private static var original = termios()
    nonisolated(unsafe) private static var active = false
    nonisolated(unsafe) private static var handlersInstalled = false
    nonisolated(unsafe) static var resized = false

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

    /// Waits up to 0.1 s for a key.
    static func readKey() -> Key? {
        var bytes = [UInt8](repeating: 0, count: 32)
        let count = read(STDIN_FILENO, &bytes, bytes.count)
        return count > 0 ? Key.parse(Array(bytes[..<count])) : nil
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
