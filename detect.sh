#!/usr/bin/env bash
# detect.sh - Environment detection for Mac/Linux
# Run with: bash detect.sh
# Output: ~/.preflight/env-config.json

set -uo pipefail

OUTPUT_DIR="$HOME/.preflight"
OUTPUT_FILE="$OUTPUT_DIR/env-config.json"
mkdir -p "$OUTPUT_DIR"

echo -e "\033[36mScanning environment...\033[0m"

# ─── SYSTEM ───────────────────────────────────────────────────────────────────

printf "  system..."
_OS="unknown"
_UNAME="$(uname -s 2>/dev/null)"
if [[ "$_UNAME" == "Darwin" ]]; then
    _OS="macOS $(sw_vers -productVersion 2>/dev/null || true)"
elif [[ -f /etc/os-release ]]; then
    _OS=$(. /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-unknown}")
elif [[ -f /etc/issue ]]; then
    _OS=$(head -1 /etc/issue 2>/dev/null | sed 's/\\[a-z]//g' | xargs)
fi
echo -e " \033[32mdone\033[0m"

# ─── HARDWARE ─────────────────────────────────────────────────────────────────

printf "  hardware..."
_CPU="unknown"
_RAM_GB=0
_DISK_TOTAL_GB=0
_DISK_USED_GB=0
_DISK_FREE_GB=0

if [[ "$_UNAME" == "Darwin" ]]; then
    _CPU=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "unknown")
    _RAM_BYTES=$(sysctl -n hw.memsize 2>/dev/null || echo 0)
    _RAM_GB=$(python3 -c "print(round($_RAM_BYTES/1073741824,2))" 2>/dev/null || echo 0)
else
    _CPU=$(grep -m1 "model name" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs || echo "unknown")
    _RAM_KB=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}' || echo 0)
    _RAM_GB=$(python3 -c "print(round(${_RAM_KB}/1048576,2))" 2>/dev/null || echo 0)
fi

if command -v df >/dev/null 2>&1; then
    _DF_LINE=$(df -k "$HOME" 2>/dev/null | tail -1)
    if [[ -n "$_DF_LINE" ]]; then
        _DT=$(echo "$_DF_LINE" | awk '{print $2}')
        _DU=$(echo "$_DF_LINE" | awk '{print $3}')
        _DF=$(echo "$_DF_LINE" | awk '{print $4}')
        _DISK_TOTAL_GB=$(python3 -c "print(round(${_DT:-0}/1048576,2))" 2>/dev/null || echo 0)
        _DISK_USED_GB=$(python3 -c "print(round(${_DU:-0}/1048576,2))" 2>/dev/null || echo 0)
        _DISK_FREE_GB=$(python3 -c "print(round(${_DF:-0}/1048576,2))" 2>/dev/null || echo 0)
    fi
fi
echo -e " \033[32mdone\033[0m"

# ─── SHELL ────────────────────────────────────────────────────────────────────

printf "  shell..."
_DEFAULT_SHELL="${SHELL:-unknown}"

_SSH_HAS_KEYS="false"
_SSH_KEYS_JSON="[]"
_SSH_DIR="$HOME/.ssh"
if [[ -d "$_SSH_DIR" ]]; then
    _KEYS_ARR=()
    while IFS= read -r -d '' f; do
        _KEYS_ARR+=("$f")
    done < <(find "$_SSH_DIR" -maxdepth 1 -type f \( -name "id_*" ! -name "*.pub" -o -name "*.pem" \) -print0 2>/dev/null || true)
    if [[ -f "$_SSH_DIR/config" ]]; then
        while IFS= read -r line; do
            if [[ "$line" =~ ^[[:space:]]*IdentityFile[[:space:]]+(.+)$ ]]; then
                _kp="${BASH_REMATCH[1]}"
                _kp="${_kp/#\~/$HOME}"
                [[ -f "$_kp" ]] && _KEYS_ARR+=("$_kp")
            fi
        done < "$_SSH_DIR/config"
    fi
    if [[ ${#_KEYS_ARR[@]} -gt 0 ]]; then
        _SSH_HAS_KEYS="true"
        _SSH_KEYS_JSON=$(printf '%s\n' "${_KEYS_ARR[@]}" | \
            python3 -c "import sys,json; print(json.dumps([l.rstrip() for l in sys.stdin]))" 2>/dev/null || echo "[]")
    fi
fi

_PATH_JSON=$(echo "$PATH" | tr ':' '\n' | awk '!seen[$0]++' | \
    python3 -c "import sys,json; print(json.dumps([l.rstrip() for l in sys.stdin if l.strip()]))" 2>/dev/null || echo "[]")
echo -e " \033[32mdone\033[0m"

# ─── RUNTIMES ─────────────────────────────────────────────────────────────────

printf "  runtimes..."
_NODE_VER=$(node --version 2>/dev/null | sed 's/^v//' || echo "not found")
_NPM_VER=$(npm --version 2>/dev/null || echo "not found")
_YARN_VER=$(yarn --version 2>/dev/null || echo "not found")
_PNPM_VER=$(pnpm --version 2>/dev/null || echo "not found")

_PYTHON_VER="not found"
for _pcmd in python3 python; do
    _pv=$($_pcmd --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
    if [[ -n "$_pv" ]]; then _PYTHON_VER="$_pv"; break; fi
done

_GIT_VER=$(git --version 2>/dev/null | sed 's/git version //' || echo "not found")
_GIT_USER=$(git config --global user.name 2>/dev/null || echo "not configured")
_GIT_EMAIL=$(git config --global user.email 2>/dev/null || echo "not configured")
_GIT_BRANCH=$(git config --global init.defaultBranch 2>/dev/null || echo "not configured")

_DOCKER_VER=$(docker --version 2>/dev/null | sed 's/Docker version //;s/,.*//' || echo "not found")

_GLOBAL_NPM_JSON="[]"
if command -v npm >/dev/null 2>&1; then
    _GLOBAL_NPM_JSON=$(npm list -g --depth=0 --json 2>/dev/null | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin).get('dependencies', {})
    print(json.dumps([f'{k}@{v.get(\"version\",\"?\")}' for k, v in d.items()]))
except:
    print('[]')
" 2>/dev/null || echo "[]")
fi

_PYTHON_PKGS_JSON="[]"
for _pip in pip3 pip; do
    if command -v "$_pip" >/dev/null 2>&1; then
        _PYTHON_PKGS_JSON=$($_pip list --format=json 2>/dev/null | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(json.dumps([f'{x[\"name\"]}=={x[\"version\"]}' for x in d]))
except:
    print('[]')
" 2>/dev/null || echo "[]")
        break
    fi
done
echo -e " \033[32mdone\033[0m"

# ─── EDITORS ──────────────────────────────────────────────────────────────────

printf "  editors (VS Code extensions may take a moment)..."
_VSCODE_VER=$(code --version 2>/dev/null | head -1 || echo "not found")
_VSCODE_EXT_JSON="[]"
if [[ "$_VSCODE_VER" != "not found" ]] && command -v code >/dev/null 2>&1; then
    _VSCODE_EXT_JSON=$(code --list-extensions --show-versions 2>/dev/null | python3 -c "
import sys, json
print(json.dumps([l.strip() for l in sys.stdin if '.' in l.strip()]))
" 2>/dev/null || echo "[]")
fi
echo -e " \033[32mdone\033[0m"

# ─── MOBILE DEV ───────────────────────────────────────────────────────────────

printf "  mobile_dev..."
_FLUTTER_VER="not found"
_FLUTTER_RAW=$(flutter --version 2>/dev/null | head -1 || true)
if [[ "$_FLUTTER_RAW" =~ Flutter[[:space:]]+([0-9]+\.[0-9]+\.[0-9]+) ]]; then
    _FLUTTER_VER="${BASH_REMATCH[1]}"
fi

_DART_VER="not found"
_DART_RAW=$(dart --version 2>&1 | head -1 || true)
if [[ "$_DART_RAW" =~ ([0-9]+\.[0-9]+\.[0-9]+) ]]; then
    _DART_VER="${BASH_REMATCH[1]}"
fi

_ANDROID_HOME="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
if [[ -z "$_ANDROID_HOME" ]]; then
    for _p in "$HOME/Library/Android/sdk" "$HOME/Android/Sdk" "/opt/android-sdk"; do
        [[ -f "$_p/platform-tools/adb" ]] && { _ANDROID_HOME="$_p"; break; }
    done
fi
_ANDROID_SDK_PATH="${_ANDROID_HOME:-not set}"
_ANDROID_SDK_VER="not found"
if [[ -n "${_ANDROID_HOME:-}" && -d "$_ANDROID_HOME/build-tools" ]]; then
    _ANDROID_SDK_VER=$(ls -1 "$_ANDROID_HOME/build-tools" 2>/dev/null | sort -V | tail -1 || echo "not found")
fi
echo -e " \033[32mdone\033[0m"

# ─── NETWORK ──────────────────────────────────────────────────────────────────

printf "  network & browsers..."
_NETWORK_TYPE="unknown"
if [[ "$_UNAME" == "Darwin" ]]; then
    _IFACE=$(route -n get default 2>/dev/null | awk '/interface:/{print $2}' | head -1 || true)
    [[ -n "$_IFACE" ]] && _NETWORK_TYPE="$_IFACE"
elif command -v ip >/dev/null 2>&1; then
    _IFACE=$(ip route 2>/dev/null | awk '/^default/{print $5}' | head -1 || true)
    [[ -n "$_IFACE" ]] && _NETWORK_TYPE="$_IFACE"
fi

_CHROME_VER="not found"
_FIREFOX_VER="not found"
_SAFARI_VER="not found"
if [[ "$_UNAME" == "Darwin" ]]; then
    if [[ -f "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" ]]; then
        _CHROME_VER=$("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --version 2>/dev/null \
            | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "not found")
    fi
    if [[ -f "/Applications/Firefox.app/Contents/MacOS/firefox" ]]; then
        _FIREFOX_VER=$("/Applications/Firefox.app/Contents/MacOS/firefox" --version 2>/dev/null \
            | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1 || echo "not found")
    fi
    if [[ -f "/Applications/Safari.app/Contents/Info.plist" ]]; then
        _SAFARI_VER=$(defaults read "/Applications/Safari.app/Contents/Info.plist" \
            CFBundleShortVersionString 2>/dev/null || echo "not found")
    fi
else
    _CHROME_VER=$(google-chrome --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1 || \
                  chromium-browser --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1 || \
                  echo "not found")
    _FIREFOX_VER=$(firefox --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1 || echo "not found")
fi

_cdn_ms() {
    local _url="$1"
    local _t0 _t1
    _t0=$(python3 -c "import time; print(int(time.time()*1000))" 2>/dev/null || echo 0)
    if curl -s -o /dev/null --max-time 8 --head "$_url" 2>/dev/null; then
        _t1=$(python3 -c "import time; print(int(time.time()*1000))" 2>/dev/null || echo 0)
        echo "$((_t1 - _t0)) ms"
    else
        echo "timeout/error"
    fi
}
_CDN_CDNJS=$(   _cdn_ms "https://cdnjs.cloudflare.com/ajax/libs/jquery/3.6.0/jquery.min.js")
_CDN_JSDELIVR=$(_cdn_ms "https://cdn.jsdelivr.net/npm/jquery@3.6.0/dist/jquery.min.js")
_CDN_UNPKG=$(   _cdn_ms "https://unpkg.com/jquery@3.6.0/dist/jquery.min.js")
_CDN_SKYPACK=$( _cdn_ms "https://cdn.skypack.dev/lodash@4.17.21")
echo -e " \033[32mdone\033[0m"

# ─── WRITE JSON ───────────────────────────────────────────────────────────────

printf "  writing JSON..."

export _OUT_FILE="$OUTPUT_FILE"
export _OS _CPU _RAM_GB _DISK_TOTAL_GB _DISK_USED_GB _DISK_FREE_GB
export _DEFAULT_SHELL _SSH_HAS_KEYS _SSH_KEYS_JSON _PATH_JSON
export _NODE_VER _NPM_VER _YARN_VER _PNPM_VER _PYTHON_VER
export _PYTHON_PKGS_JSON _GLOBAL_NPM_JSON
export _GIT_VER _GIT_USER _GIT_EMAIL _GIT_BRANCH _DOCKER_VER
export _VSCODE_VER _VSCODE_EXT_JSON
export _FLUTTER_VER _DART_VER _ANDROID_SDK_PATH _ANDROID_SDK_VER
export _NETWORK_TYPE _CHROME_VER _FIREFOX_VER _SAFARI_VER
export _CDN_CDNJS _CDN_JSDELIVR _CDN_UNPKG _CDN_SKYPACK
export _TIMESTAMP
_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%S+00:00" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%S+00:00")

python3 - << 'PYEOF'
import json, os

e = os.environ.get

def num(k, default=0.0):
    try:    return float(e(k, str(default)))
    except: return default

def jlist(k):
    try:    return json.loads(e(k, "[]"))
    except: return []

config = {
    "config_version": "1.1",
    "generated_at":   e("_TIMESTAMP"),
    "system":  {"os": e("_OS")},
    "hardware": {
        "cpu":    e("_CPU"),
        "ram_GB": num("_RAM_GB"),
        "disk_home": {
            "total_GB": num("_DISK_TOTAL_GB"),
            "used_GB":  num("_DISK_USED_GB"),
            "free_GB":  num("_DISK_FREE_GB"),
        },
    },
    "shell": {
        "default_shell":    e("_DEFAULT_SHELL"),
        "ssh_keys_present": e("_SSH_HAS_KEYS") == "true",
        "ssh_key_files":    jlist("_SSH_KEYS_JSON"),
        "path_entries":     jlist("_PATH_JSON"),
    },
    "runtimes": {
        "node":   e("_NODE_VER"),
        "npm":    e("_NPM_VER"),
        "yarn":   e("_YARN_VER"),
        "pnpm":   e("_PNPM_VER"),
        "python": e("_PYTHON_VER"),
        "python_packages":  jlist("_PYTHON_PKGS_JSON"),
        "git": {
            "version":        e("_GIT_VER"),
            "username":       e("_GIT_USER"),
            "email":          e("_GIT_EMAIL"),
            "default_branch": e("_GIT_BRANCH"),
        },
        "docker":              e("_DOCKER_VER"),
        "global_npm_packages": jlist("_GLOBAL_NPM_JSON"),
    },
    "editors": {
        "vscode": {
            "version":    e("_VSCODE_VER"),
            "extensions": jlist("_VSCODE_EXT_JSON"),
        }
    },
    "mobile_dev": {
        "flutter": e("_FLUTTER_VER"),
        "dart":    e("_DART_VER"),
        "android_sdk": {
            "path":    e("_ANDROID_SDK_PATH"),
            "version": e("_ANDROID_SDK_VER"),
        },
    },
    "network": {
        "type": e("_NETWORK_TYPE"),
        "browsers": {
            "chrome":  e("_CHROME_VER"),
            "firefox": e("_FIREFOX_VER"),
            "safari":  e("_SAFARI_VER"),
        },
        "cdn_latency_ms": {
            "cdnjs":    e("_CDN_CDNJS"),
            "jsdelivr": e("_CDN_JSDELIVR"),
            "unpkg":    e("_CDN_UNPKG"),
            "skypack":  e("_CDN_SKYPACK"),
        },
    },
    "extensions_schema": {
        "name":        "string - tool or package name",
        "version":     "string - semver or tag",
        "added_at":    "string - ISO 8601 timestamp",
        "description": "string - what this extension does",
    },
    "extensions": [],
}

out_path = e("_OUT_FILE")
os.makedirs(os.path.dirname(out_path), exist_ok=True)
with open(out_path, "w", encoding="utf-8") as f:
    json.dump(config, f, indent=4)
PYEOF

echo -e " \033[32mdone\033[0m"
echo ""
echo -e "\033[32mWritten to: $OUTPUT_FILE\033[0m"
