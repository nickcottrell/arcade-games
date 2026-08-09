# Security Red-Team Report

**Review date:** 2026-08-08  
**Scope:** current repository state; report-only review of game/PTY input, the ROM
manifest and composable-game boundary, browser DOM/message inputs, and remote code
loading. No product code was changed.

## Executive summary

The arcade must not be exposed to an untrusted network in its current form. An
unauthenticated, cross-origin Socket.IO client can start native Bash ROMs, and one
ROM turns player-supplied PTY text into a GNU `sed` program with the `e` flag
reachable. That is a direct route from a web-origin attacker to host command
execution. Independently, the manifest is an execution policy rather than merely
metadata: unchecked `file`/`active_path` paths select arbitrary local Bash files,
the scripts receive the server's environment and filesystem privileges, and
there is no sandbox.

The browser also executes mutable third-party JavaScript directly from CDNs.
Manifest values can inject JavaScript through the unquoted numeric fields in the
standalone player template. No current URL-parameter or inbound `postMessage`
DOM-XSS path was found, and the formerly tracked static browser bundle is absent
from the reviewed tree.

## Findings

| ID | Severity | Attack surface | Evidence / exploit sketch | Impact | Recommended fix |
|---|---|---|---|---|---|
| RT-01 | **Critical** | Untrusted PTY game input | `madlibs.sh` reads an entire attacker-controlled word and interpolates it into a double-quoted `sed` substitution. A word such as `id\|e;#` changes the generated program to `s\|{1}\|id\|e;#\|g`; GNU `sed` executes the replacement as a shell command and treats the intended suffix as a comment. The web server forwards arbitrary Socket.IO `game_input` bytes directly to the PTY. | Arbitrary commands as the arcade server account; access to its files, environment, localhost services, and credentials. | Do not use a generated `sed` program. Perform literal placeholder replacement in a language/API where the replacement is data (for example Python `str.replace` with arguments passed out of band). Add adversarial tests for delimiters, backslashes, newlines, `e`, ANSI bytes, and long input. Treat every ROM's text-input path as hostile. |
| RT-02 | **Critical** | Network-to-PTY boundary | Socket.IO accepts every origin, has no authentication/authorization, the app listens on `0.0.0.0`, and `game_start` launches a process. Browser input is written unfiltered to that process. A malicious website can therefore drive a visitor's locally reachable arcade, while any network peer that can reach port 3001 can allocate processes and interact with them. Dimensions are also unbounded before `struct.pack`/PTY allocation. | Makes RT-01 remotely reachable; cross-site request abuse; process/FD/thread exhaustion and malformed-size exceptions. | Bind loopback by default; require authenticated sessions and an unpredictable CSRF/origin-bound Socket.IO handshake; replace `*` CORS with an exact allowlist; rate-limit starts/input; cap sessions per user/IP; validate type and bounds for slug, input length, rows, and columns; cap process resources and lifetime. |
| RT-03 | **Critical** (if the manifest or promotion source is untrusted) | Dynamic manifest / composable-game contract | Web launch joins `ROMS_DIR` with `rom["file"]` without canonicalization or containment checking; absolute paths and `../` escape `roms/`. CLI launch likewise concatenates manifest-controlled `file` or `active_path`, then runs the result with Bash. “Validation” checks only a shebang, a source-text pattern, `SCRIPT_DIR`, and syntax—it is not a security boundary. The web child inherits `os.environ`, runs with the server's UID, and has no filesystem, network, syscall, or process sandbox. | A malicious manifest can select and execute an arbitrary readable Bash script; a composable/malicious game has full host privileges and trivially escapes the supposed game boundary. | Define a versioned, schema-validated manifest with strict slug/filename patterns and duplicate rejection. Resolve (`realpath`) and require files to remain beneath an immutable ROM root; reject symlinks and non-regular files; allowlist hashes/signatures. Never equate static lint with trust. Run games in a separate least-privilege container/user with a read-only filesystem, empty/minimal environment, no host network, seccomp/AppArmor, PID/memory/CPU/time limits, and an explicit narrow token API. |
| RT-04 | **High** (stored manifest XSS) | Manifest-to-browser rendering | In `player.html`, `rom.cols` and `rom.rows` are emitted directly as JavaScript expressions. A malicious value such as `80;alert(document.domain)//` executes when `/play/<slug>` loads. HTML autoescaping is not JavaScript serialization. Picker metadata is safer because it is placed in escaped attributes and later copied with `textContent`. | Script execution in the arcade origin; access to same-origin unauthenticated APIs and Socket.IO, enabling PTY control and host compromise through RT-01. | Validate manifest field types server-side and serialize every value crossing into JavaScript with Jinja `tojson` (including slug). Prefer an `application/json` data island. Add a restrictive nonce/hash CSP that blocks inline script. |
| RT-05 | **High** | Remote code fetch and execution | Both player pages load xterm and Socket.IO JavaScript from jsDelivr with floating package URLs and no Subresource Integrity. They also load a remote stylesheet. Compromise, account takeover, or mutable upstream content executes with arcade-origin privileges. There is no CSP visible in the app. | Supply-chain code execution in every arcade visitor's browser, followed by same-origin PTY/API access. | Vendor and review exact dependency artifacts, or pin immutable versions/content hashes and add `integrity` plus `crossorigin`. Serve dependencies locally. Deploy a restrictive CSP (`script-src 'self'` plus nonces/hashes; narrow `connect-src`; `object-src 'none'`; `base-uri 'none'`; `frame-ancestors`). |
| RT-06 | **Medium** | Remote theme data | A fixed remote API supplies arbitrary token values and `__css_rules__`; the result is inserted into a `<style>` element with `textContent`. This prevents HTML/script breakout but still installs attacker-controlled CSS capable of network requests, UI deception, and future browser/CSS side channels. | Tracking/data disclosure through CSS fetches and deceptive UI; increases remote supply-chain exposure. Direct JavaScript execution was not demonstrated through this sink. | Treat the response as structured color data, validate property names and values against strict allowlists, and discard `__css_rules__`. Prefer local generation. Restrict CSS destinations with CSP and do not allow remote `@import`/`url()` values. |

## Attack-chain proof points

1. An attacker connects to the unauthenticated Socket.IO endpoint, emits
   `game_start` for `madlibs`, then supplies the required prompt input.
2. The server starts `bash arcade/roms/madlibs.sh` and writes attacker bytes to
   its PTY without interpreting them. This direct write is not itself argument
   injection.
3. The game later embeds the word inside a `sed` program. Supplying `id|e;#` for
   a `{1}` replacement causes GNU `sed`'s `e` flag to execute `id`.
4. The Bash process is not isolated and inherited the web server environment, so
   execution occurs in the host security context.

The minimal primitive can be verified independently without launching the web
application:

```sh
word='id|e;#'
echo '{1}' | sed "s|{1}|$word|g"
```

On GNU `sed`, its output is the result of the `id` command. This proof should be
run only in a disposable test environment; no exploit was added to the codebase.

## Clean / negative areas

- **No shell-string execution in the Python launcher:** `subprocess.Popen` uses an
  argument array and does not set `shell=True`. Slug text is matched against a
  manifest entry, rather than appended to a shell command. The unsafe boundary is
  which script the manifest selects and what that script does with PTY data.
- **No direct shell injection in token/TTS helpers found:** reviewed calls quote
  values into argv arrays or use `curl --data-urlencode`; no `eval`, `bash -c`, or
  `sh -c` sink was found in the current ROM path.
- **Picker manifest display is not an identified DOM-XSS sink:** Jinja escapes
  data attributes and client code assigns title/description through
  `textContent`. Clearing the terminal with `innerHTML = ""` contains no attacker
  data.
- **Terminal output is passed to xterm, not assigned to HTML:** no application
  code writes game output to `innerHTML`. Terminal escape-sequence handling still
  depends on the security of the externally loaded xterm version.
- **No inbound `postMessage` handler exists in this repository:** outbound messages
  use a fixed target origin rather than `*`. Consequently no local message-to-DOM
  XSS path was found. The receiving localhost application is outside this review
  and must independently validate `event.origin`, `event.source`, message schema,
  and all rendered fields.
- **No URL-parameter-to-DOM flow was found in the game templates:** the only
  `URLSearchParams` usage constructs a request from remote theme data, not the
  browser location. Flask route slugs are used for an exact manifest lookup.
- **No fetched game payload is executed:** game code is loaded from local files.
  The Ollama request is localhost JSON inference, and remote theme responses are
  installed as CSS rather than evaluated as JavaScript. RT-05 remains a real
  remote JavaScript execution path for UI dependencies.
- **No static browser game bundle is present in the current tree:** the Git history
  states that `public/` was moved to a separate repository. Static-bundle XSS in
  that separate artifact is therefore not assessable here and should be reviewed
  in its new repository before deployment.

## Remediation order

1. Disable network access to the web arcade; fix RT-01 and add a regression test.
2. Authenticate and constrain Socket.IO, then isolate every game process (RT-02
   and RT-03). Treat isolation as mandatory even after individual ROM fixes.
3. Enforce the manifest schema/containment/signature boundary and use JSON-safe
   browser serialization (RT-03 and RT-04).
4. Vendor dependencies and deploy CSP; constrain or remove remote theme CSS
   (RT-05 and RT-06).
5. Red-team the separately deployed static bundle and the receiving cue-vox
   `postMessage` implementation as distinct scopes.

## Review limitations

This was source review plus a minimal local sink proof, not a deployed
penetration test. External cue-vox/cue-sheet templates discovered at runtime,
the repository that now owns `public/`, remote CDN/API contents, browser-specific
xterm escape handling, and production proxy/authentication configuration were not
available in this repository and are not certified clean.
