# Environment Rules for Claude Code
# Generated from env-config.json — D:\AI Projects\preflight

## Shell & Execution
- Platform: Windows 10 Pro (Build 19045). Always use PowerShell syntax, not bash.
- Run scripts with: `powershell -ExecutionPolicy Bypass -File script.ps1`
- Execution policy is RemoteSigned — unsigned local scripts need `-ExecutionPolicy Bypass`.
- Default shell is Git Bash (`C:\Program Files\Git\bin\bash.exe`) but prefer PowerShell for system tasks.
- Path separator is `\`. Always double-quote paths containing spaces.
- No `&&` in PowerShell 5.1 — chain with `;` or `if ($?) { }`.

## Package Manager
- Use **npm only**. yarn and pnpm are not installed.
- npm 11.12.1 / Node 24.15.0. Global packages: `claude-code`, `firebase-tools`, `vercel`.
- Do not suggest yarn or pnpm without confirming installation first.

## CDN
- Prefer **jsdelivr** (`cdn.jsdelivr.net`) — lowest consistent latency on this machine.
- Avoid skypack (`cdn.skypack.dev`) — slowest (900 ms+). Avoid unpkg when latency matters.

## Detected Versions
- Node 24.15.0 / npm 11.12.1
- Python 3.14.3 — bare install, only `pip==25.3`. No numpy/requests/etc. Install before use.
- Git 2.53.0.windows.2 — user: malikasana, email: malikasana2810@gmail.com, branch: main
- Docker 29.2.1 (uses WSL2 backend)
- VS Code 1.121.0 with 12 extensions (Flutter, Dart, Python, Remote SSH, Containers)
- Flutter 3.41.5 / Dart 3.11.3
- Android SDK 36.1.0 at `D:\Sdk`
- Java OpenJDK 21.0.9 (JetBrains Runtime) at `D:\Android Studio\jbr`

## Environment Variables (all permanently set at user level)
- `JAVA_HOME`    = `D:\Android Studio\jbr`
- `ANDROID_HOME` = `D:\Sdk`
- `FLUTTER_HOME` = `D:\flutter`
- `PYTHON_PATH`  = `C:\Users\sawar\AppData\Local\Python\bin`
- New env vars require a fresh terminal session to take effect.

## Flutter & Android Setup
- Flutter is on PATH via `D:\flutter\bin`. FLUTTER_HOME is now set.
- Android SDK: `D:\Sdk` — platform-tools, build-tools 36.1.0, NDK, emulator present.
- `adb.exe` at `D:\Sdk\platform-tools\adb.exe`.
- JAVA_HOME points to Android Studio JBR — sdkmanager and Gradle should work.
- Prefer physical device or `flutter run -d chrome` — i7-6700HQ emulator performance is limited.

## SSH
- Key exists at `D:\id_ed25519` (ed25519). Public key at `D:\id_ed25519.pub`.
- Configured in `~/.ssh/config` for 5 remote servers (root, custom ports).
- Warning: config uses `D:id_ed25519` (missing `\`) — functionally works but is non-standard.
- Git operations use HTTPS (SSH key is for server access, not GitHub).

## WSL
- WSL2 installed. Ubuntu is the default distro (stopped). docker-desktop also registered (stopped).
- Start Ubuntu with: `wsl` or `wsl -d Ubuntu`.

## Windows Gotchas
- Environment variables set via `[Environment]::SetEnvironmentVariable` apply only to new sessions.
- Firefox is not installed. Available browsers: Chrome 148, Edge 148.
- `D:\` drive: 281 GB total, ~128 GB free. Check space before large SDK/emulator downloads.
- No proxy — direct connection via Intel AC 8260 Wi-Fi.
- PyCharm 2025.3.3 is installed (also bundles JBR 21.0.10 if Java path changes).
- ffmpeg is on PATH: `D:\ffmpeg-...-essentials_build\bin`.
- Ollama is installed at `C:\Users\sawar\AppData\Local\Programs\Ollama`.

## Hardware
- CPU: Intel i7-6700HQ @ 2.60 GHz. RAM: 15.88 GB.
- All performance-heavy tasks (emulator, Docker builds) will be slow — plan accordingly.
