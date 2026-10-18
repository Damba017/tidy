"""Drive tidy's TUI in a pseudo-terminal and print what's on screen. Dev tool only.

usage: python3 -I scripts/drive_tui.py COLS ROWS STEP... -- COMMAND ARGS...
steps: wait:SECONDS | snap | up down left right enter esc bs end home tab btab | text:STRING | key:CHAR

`snap` prints the current screen; the cursor row (reverse video) is marked ">> ". At the end it
reports the exit status, how long tidy took to exit, and whether the terminal was restored.
Only ever drive tidy with --dry-run or on fixtures in /tmp/tidy-test, and answer "n" to questions.
"""
import fcntl, os, pty, re, select, struct, sys, termios, time

KEYS = {"up": b"\x1b[A", "down": b"\x1b[B", "right": b"\x1b[C", "left": b"\x1b[D",
        "enter": b"\r", "esc": b"\x1b", "bs": b"\x7f", "end": b"\x1b[F", "home": b"\x1b[H", "tab": b"\t", "btab": b"\x1b[Z"}
ANSI = re.compile(rb"\x1b\[[0-9;?]*[A-Za-z]")
ENTER_ALT, LEAVE_ALT = b"\x1b[?1049h", b"\x1b[?1049l"

split = sys.argv.index("--")
cols, rows = int(sys.argv[1]), int(sys.argv[2])
steps, command = sys.argv[3:split], sys.argv[split + 1:]

pid, fd = pty.fork()
if pid == 0:
    fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
    os.environ["TERM"] = "xterm-256color"
    os.execv(command[0], command)

out = b""
def pump(seconds):
    global out
    end = time.time() + seconds
    while time.time() < end:
        ready, _, _ = select.select([fd], [], [], 0.05)
        if ready:
            try:
                data = os.read(fd, 1 << 16)
            except OSError:
                return
            if not data:
                return
            out += data

def screen():
    alt = out.rfind(ENTER_ALT) > out.rfind(LEAVE_ALT)
    if alt:
        frame = out[out.rfind(b"\x1b[H") + 3:]
    else:
        frame = out[out.rfind(LEAVE_ALT) + len(LEAVE_ALT):] if LEAVE_ALT in out else out
    frame = frame.replace(b"\x1b[7m", b">> ")  # mark the cursor row (reverse video)
    text = ANSI.sub(b"", frame).decode("utf-8", "replace").replace("\r\n", "\n").replace("\r", "")
    return ("[alt screen]\n" if alt else "[normal screen]\n") + "\n".join(l.rstrip() for l in text.split("\n"))

pump(0.5)
for step in steps:
    if step.startswith("wait:"):
        pump(float(step[5:]))
    elif step == "snap":
        print("=" * cols)
        print(screen())
    elif step.startswith("text:"):
        os.write(fd, step[5:].encode())
        pump(0.4)
    elif step.startswith("key:"):
        os.write(fd, step[4:].encode())
        pump(0.4)
    else:
        os.write(fd, KEYS[step])
        pump(0.4)
last_key = time.time()
left_alt_at = None
done, status = 0, 0
while time.time() - last_key < 5 and done == 0:
    pump(0.02)
    if left_alt_at is None and out.rfind(LEAVE_ALT) > out.rfind(ENTER_ALT):
        left_alt_at = time.time() - last_key
    try:
        done, status = os.waitpid(pid, os.WNOHANG)
    except ChildProcessError:
        done, status = pid, 0
if done:
    print("timing: left alt screen %.2fs and exited %.2fs after the last step"
          % (left_alt_at if left_alt_at is not None else -1, time.time() - last_key))
print("=" * cols)
if done == 0:
    print("STILL RUNNING - sampling, then killing it")
    import subprocess
    report = subprocess.run(["/usr/bin/sample", str(pid), "1"], capture_output=True, text=True).stdout
    graph = report[report.find("Call graph"):report.find("Total number")]
    print("\n".join(graph.splitlines()[:60]))
    os.kill(pid, 9)
else:
    print("exit status:", os.waitstatus_to_exitcode(status) if hasattr(os, "waitstatus_to_exitcode") else status)
print("terminal restored (left alt screen + cursor shown):", out.rfind(LEAVE_ALT) > out.rfind(ENTER_ALT) and b"\x1b[?25h" in out)
