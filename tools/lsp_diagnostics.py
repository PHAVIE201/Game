#!/usr/bin/env python3
"""Prints GDScript errors/warnings exactly as the Godot editor reports them.

Starts the (headless) editor with its language server, opens every .gd file
and collects the published diagnostics.

Usage: python3 tools/lsp_diagnostics.py <path-to-godot-binary> <project-dir>
"""
import json, socket, sys, time, os, glob, subprocess

GODOT = sys.argv[1]
PROJ = sys.argv[2]
PORT = 6011

proc = subprocess.Popen([GODOT, "--headless", "--editor", "--path", PROJ, "--lsp-port", str(PORT)],
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
sock = None
for i in range(120):
    try:
        sock = socket.create_connection(("127.0.0.1", PORT), timeout=2)
        break
    except OSError:
        time.sleep(1)
if sock is None:
    print("no lsp"); proc.kill(); sys.exit(1)
sock.settimeout(1.0)
buf = b""
msg_id = 0

def send(method, params, is_request=True):
    global msg_id
    msg = {"jsonrpc": "2.0", "method": method, "params": params}
    if is_request:
        msg_id += 1
        msg["id"] = msg_id
    data = json.dumps(msg).encode()
    sock.sendall(b"Content-Length: %d\r\n\r\n" % len(data) + data)

def read_all(timeout):
    global buf
    out = []
    end = time.time() + timeout
    while time.time() < end:
        try:
            chunk = sock.recv(65536)
            if not chunk:
                break
            buf += chunk
        except socket.timeout:
            pass
        while b"\r\n\r\n" in buf:
            head, rest = buf.split(b"\r\n\r\n", 1)
            length = int([l for l in head.decode().split("\r\n") if l.lower().startswith("content-length")][0].split(":")[1])
            if len(rest) < length:
                break
            body, buf = rest[:length], rest[length:]
            out.append(json.loads(body))
    return out

root_uri = "file://" + os.path.abspath(PROJ)
send("initialize", {"processId": None, "rootUri": root_uri, "capabilities": {}})
read_all(3)
send("initialized", {}, False)
files = sorted(glob.glob(os.path.join(PROJ, "scripts", "**", "*.gd"), recursive=True) + glob.glob(os.path.join(PROJ, "tools", "*.gd")))
diags = {}
for f in files:
    uri = "file://" + os.path.abspath(f)
    send("textDocument/didOpen", {"textDocument": {"uri": uri, "languageId": "gdscript", "version": 1, "text": open(f).read()}}, False)
    for m in read_all(0.6):
        if m.get("method") == "textDocument/publishDiagnostics":
            diags[m["params"]["uri"]] = m["params"]["diagnostics"]
for m in read_all(3):
    if m.get("method") == "textDocument/publishDiagnostics":
        diags[m["params"]["uri"]] = m["params"]["diagnostics"]
total = 0
for uri, ds in sorted(diags.items()):
    for d in ds:
        total += 1
        sev = {1: "ERROR", 2: "WARN", 3: "INFO", 4: "HINT"}.get(d.get("severity"), "?")
        print("%s %s:%d  %s" % (sev, uri.replace(root_uri + "/", ""), d["range"]["start"]["line"] + 1, d["message"]))
print("files=%d diagnostics=%d" % (len(files), total))
proc.kill()
sys.exit(1 if total else 0)
