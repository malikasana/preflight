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

# ─── INSTALLED PROGRAMS ───────────────────────────────────────────────────────

printf "  installed_programs...\n"

_ver_cmd() { "$@" 2>&1 | head -1 2>/dev/null || true; }
_find_exe() { command -v "$1" 2>/dev/null || true; }
_probe() { local _pp; for _pp in "$@"; do [[ -f "$_pp" ]] && { echo "$_pp"; return 0; }; done; echo ""; }

# ── DATABASES ─────────────────────────────────────────────────────────────────
printf "    databases..."

_REDIS_EXE=$(_find_exe redis-server)
[[ -z "$_REDIS_EXE" ]] && _REDIS_EXE=$(_probe /usr/bin/redis-server /usr/local/bin/redis-server)
if [[ -n "$_REDIS_EXE" ]]; then
    _REDIS_INSTALLED=true
    _rv=$(_ver_cmd "$_REDIS_EXE" --version)
    _REDIS_VER=$(echo "$_rv" | grep -oE 'v=[0-9.]+' | sed 's/v=//' || echo "$_rv")
else
    _REDIS_INSTALLED=false; _REDIS_VER="not installed"; _REDIS_EXE="not found"
fi
_REDIS_CFG=$(_probe /etc/redis/redis.conf /usr/local/etc/redis.conf)
[[ -z "$_REDIS_CFG" ]] && _REDIS_CFG="not found"

_PSQL_EXE=$(_find_exe psql)
if [[ -n "$_PSQL_EXE" ]]; then
    _PG_INSTALLED=true
    _pv=$(_ver_cmd "$_PSQL_EXE" --version)
    _PG_VER=$(echo "$_pv" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1 || echo "$_pv")
else
    _PG_INSTALLED=false; _PG_VER="not installed"; _PSQL_EXE="not found"
fi
_PG_DATA="${PGDATA:-not configured}"

_MONGOD_EXE=$(_find_exe mongod)
if [[ -n "$_MONGOD_EXE" ]]; then
    _MONGO_INSTALLED=true
    _mv=$(_ver_cmd "$_MONGOD_EXE" --version)
    _MONGO_VER=$(echo "$_mv" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "$_mv")
else
    _MONGO_INSTALLED=false; _MONGO_VER="not installed"; _MONGOD_EXE="not found"
fi
_MONGO_DATA=$(_probe /data/db /var/lib/mongodb)
[[ -z "$_MONGO_DATA" ]] && _MONGO_DATA="not found"

_MYSQL_EXE=$(_find_exe mysql)
if [[ -n "$_MYSQL_EXE" ]]; then
    _MYSQL_INSTALLED=true
    _myv=$(_ver_cmd "$_MYSQL_EXE" --version)
    _MYSQL_VER=$(echo "$_myv" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "$_myv")
else
    _MYSQL_INSTALLED=false; _MYSQL_VER="not installed"; _MYSQL_EXE="not found"
fi
_MYSQL_CFG=$(_probe /etc/mysql/mysql.conf.d/mysqld.cnf /etc/mysql/my.cnf /usr/local/etc/my.cnf)
[[ -z "$_MYSQL_CFG" ]] && _MYSQL_CFG="not found"

_SQLITE_EXE=$(_find_exe sqlite3)
if [[ -n "$_SQLITE_EXE" ]]; then
    _SQLITE_INSTALLED=true
    _sv=$(_ver_cmd "$_SQLITE_EXE" --version)
    _SQLITE_VER=$(echo "$_sv" | awk '{print $1}')
else
    _SQLITE_INSTALLED=false; _SQLITE_VER="not installed"; _SQLITE_EXE="not found"
fi

echo -e " \033[32mdone\033[0m"

# ── WEB SERVERS ───────────────────────────────────────────────────────────────
printf "    web servers..."

_NGINX_EXE=$(_find_exe nginx)
if [[ -n "$_NGINX_EXE" ]]; then
    _NGINX_INSTALLED=true
    _nv=$(_ver_cmd "$_NGINX_EXE" -v)
    _NGINX_VER=$(echo "$_nv" | grep -oE 'nginx/[0-9.]+' | sed 's/nginx\///' || echo "$_nv")
else
    _NGINX_INSTALLED=false; _NGINX_VER="not installed"; _NGINX_EXE="not found"
fi
_NGINX_CFG=$(_probe /etc/nginx/nginx.conf /usr/local/etc/nginx/nginx.conf)
[[ -z "$_NGINX_CFG" ]] && _NGINX_CFG="not found"

_HTTPD_EXE=$(_find_exe httpd)
[[ -z "$_HTTPD_EXE" ]] && _HTTPD_EXE=$(_find_exe apache2)
if [[ -n "$_HTTPD_EXE" ]]; then
    _APACHE_INSTALLED=true
    _av=$(_ver_cmd "$_HTTPD_EXE" -v)
    _APACHE_VER=$(echo "$_av" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "$_av")
else
    _APACHE_INSTALLED=false; _APACHE_VER="not installed"; _HTTPD_EXE="not found"
fi
_APACHE_CFG=$(_probe /etc/httpd/conf/httpd.conf /etc/apache2/apache2.conf /usr/local/etc/httpd/httpd.conf)
[[ -z "$_APACHE_CFG" ]] && _APACHE_CFG="not found"

echo -e " \033[32mdone\033[0m"

# ── LANGUAGES ─────────────────────────────────────────────────────────────────
printf "    languages..."

_RUSTC_EXE=$(_find_exe rustc)
if [[ -n "$_RUSTC_EXE" ]]; then
    _RUST_INSTALLED=true
    _rv=$(_ver_cmd "$_RUSTC_EXE" --version)
    _RUST_VER=$(echo "$_rv" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "$_rv")
else
    _RUST_INSTALLED=false; _RUST_VER="not installed"; _RUSTC_EXE="not found"
fi
_CARGO_EXE=$(_find_exe cargo); [[ -z "$_CARGO_EXE" ]] && _CARGO_EXE="not found"

_GO_EXE=$(_find_exe go)
if [[ -n "$_GO_EXE" ]]; then
    _GO_INSTALLED=true
    _gv=$(_ver_cmd "$_GO_EXE" version)
    _GO_VER=$(echo "$_gv" | grep -oE 'go[0-9]+\.[0-9]+\.[0-9]+' | sed 's/go//' | head -1 || echo "$_gv")
else
    _GO_INSTALLED=false; _GO_VER="not installed"; _GO_EXE="not found"
fi
_GOPATH="${GOPATH:-$HOME/go}"

_RUBY_EXE=$(_find_exe ruby)
if [[ -n "$_RUBY_EXE" ]]; then
    _RUBY_INSTALLED=true
    _rbv=$(_ver_cmd "$_RUBY_EXE" --version)
    _RUBY_VER=$(echo "$_rbv" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+p?[0-9]*' | head -1 || echo "$_rbv")
else
    _RUBY_INSTALLED=false; _RUBY_VER="not installed"; _RUBY_EXE="not found"
fi

echo -e " \033[32mdone\033[0m"

# ── AI & ML ───────────────────────────────────────────────────────────────────
printf "    ai_ml..."

_OLLAMA_EXE=$(_find_exe ollama)
if [[ -n "$_OLLAMA_EXE" ]]; then
    _OLLAMA_INSTALLED=true
    _OLLAMA_VER=$(_ver_cmd "$_OLLAMA_EXE" --version)
    _OLLAMA_MODELS_JSON="[]"
    if _ml=$(timeout 5 "$_OLLAMA_EXE" list 2>/dev/null | tail -n +2); then
        _OLLAMA_MODELS_JSON=$(echo "$_ml" | awk '{print $1}' | grep -v '^$' | \
            python3 -c "import sys,json; print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))" 2>/dev/null || echo "[]")
    fi
else
    _OLLAMA_INSTALLED=false; _OLLAMA_VER="not installed"; _OLLAMA_EXE="not found"; _OLLAMA_MODELS_JSON="[]"
fi

_NVCC_EXE=$(_find_exe nvcc)
if [[ -n "$_NVCC_EXE" ]]; then
    _CUDA_INSTALLED=true
    _cv=$(_ver_cmd "$_NVCC_EXE" --version)
    _CUDA_VER=$(echo "$_cv" | grep -oE 'release [0-9.]+' | sed 's/release //' || echo "$_cv")
else
    _CUDA_INSTALLED=false; _CUDA_VER="not installed"; _NVCC_EXE="not found"
fi
_GPU_INFO="no NVIDIA GPU detected"
command -v nvidia-smi >/dev/null 2>&1 && \
    _GPU_INFO=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 || echo "no NVIDIA GPU detected")

echo -e " \033[32mdone\033[0m"

# ── DEV TOOLS ─────────────────────────────────────────────────────────────────
printf "    dev_tools..."

if [[ "$_UNAME" == "Darwin" ]]; then
    _STUDIO_PATH=$(_probe "/Applications/Android Studio.app/Contents/MacOS/studio" \
        "$HOME/Applications/Android Studio.app/Contents/MacOS/studio")
    if [[ -n "$_STUDIO_PATH" ]]; then
        _STUDIO_INSTALLED=true
        _STUDIO_VER=$(defaults read "/Applications/Android Studio.app/Contents/Info.plist" \
            CFBundleShortVersionString 2>/dev/null || echo "installed")
    else
        _STUDIO_INSTALLED=false; _STUDIO_VER="not installed"; _STUDIO_PATH="not found"
    fi
    _PYCHARM_PATH=$(_probe "/Applications/PyCharm.app/Contents/MacOS/pycharm" \
        "/Applications/PyCharm CE.app/Contents/MacOS/pycharm" \
        "$HOME/Applications/PyCharm.app/Contents/MacOS/pycharm")
    if [[ -n "$_PYCHARM_PATH" ]]; then
        _PYCHARM_INSTALLED=true
        _PYCHARM_VER=$(defaults read "${_PYCHARM_PATH%%/Contents/*}/Contents/Info.plist" \
            CFBundleShortVersionString 2>/dev/null || echo "installed")
    else
        _PYCHARM_INSTALLED=false; _PYCHARM_VER="not installed"; _PYCHARM_PATH="not found"
    fi
    _POSTMAN_PATH=$(_probe "/Applications/Postman.app/Contents/MacOS/Postman" \
        "$HOME/Applications/Postman.app/Contents/MacOS/Postman")
    if [[ -n "$_POSTMAN_PATH" ]]; then
        _POSTMAN_INSTALLED=true
        _POSTMAN_VER=$(defaults read "${_POSTMAN_PATH%%/Contents/*}/Contents/Info.plist" \
            CFBundleShortVersionString 2>/dev/null || echo "installed")
    else
        _POSTMAN_INSTALLED=false; _POSTMAN_VER="not installed"; _POSTMAN_PATH="not found"
    fi
    _TABLEPLUS_PATH=$(_probe "/Applications/TablePlus.app/Contents/MacOS/TablePlus" \
        "$HOME/Applications/TablePlus.app/Contents/MacOS/TablePlus")
    if [[ -n "$_TABLEPLUS_PATH" ]]; then
        _TABLEPLUS_INSTALLED=true
        _TABLEPLUS_VER=$(defaults read "${_TABLEPLUS_PATH%%/Contents/*}/Contents/Info.plist" \
            CFBundleShortVersionString 2>/dev/null || echo "installed")
    else
        _TABLEPLUS_INSTALLED=false; _TABLEPLUS_VER="not installed"; _TABLEPLUS_PATH="not found"
    fi
else
    # Linux paths
    _STUDIO_PATH=$(_probe "$HOME/android-studio/bin/studio.sh" /opt/android-studio/bin/studio.sh)
    if [[ -n "$_STUDIO_PATH" ]]; then
        _STUDIO_INSTALLED=true; _STUDIO_VER="installed"
    else
        _STUDIO_INSTALLED=false; _STUDIO_VER="not installed"; _STUDIO_PATH="not found"
    fi
    _PYCHARM_PATH=$(find /opt /usr/local "$HOME/.local/share/JetBrains/Toolbox/apps" \
        -maxdepth 4 -name "pycharm.sh" 2>/dev/null | sort | tail -1 || true)
    if [[ -n "$_PYCHARM_PATH" ]]; then
        _PYCHARM_INSTALLED=true; _PYCHARM_VER="installed"
    else
        _PYCHARM_INSTALLED=false; _PYCHARM_VER="not installed"; _PYCHARM_PATH="not found"
    fi
    _POSTMAN_PATH=$(_probe "$HOME/.local/share/Postman/Postman" /opt/Postman/Postman /usr/bin/postman)
    if [[ -n "$_POSTMAN_PATH" ]]; then
        _POSTMAN_INSTALLED=true; _POSTMAN_VER="installed"
    else
        _POSTMAN_INSTALLED=false; _POSTMAN_VER="not installed"; _POSTMAN_PATH="not found"
    fi
    _TABLEPLUS_PATH=$(_probe /opt/TablePlus/TablePlus)
    if [[ -n "$_TABLEPLUS_PATH" ]]; then
        _TABLEPLUS_INSTALLED=true; _TABLEPLUS_VER="installed"
    else
        _TABLEPLUS_INSTALLED=false; _TABLEPLUS_VER="not installed"; _TABLEPLUS_PATH="not found"
    fi
fi

_PYCHARM_INTERP=$(python3 -c "import sys; print(sys.executable)" 2>/dev/null || echo "not detected")
_SDK_ROOT="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
_SDKMANAGER_PATH=$(_probe "$_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" "$_SDK_ROOT/tools/bin/sdkmanager")
[[ -z "$_SDKMANAGER_PATH" ]] && _SDKMANAGER_PATH="not found"

echo -e " \033[32mdone\033[0m"

# ── CLOUD TOOLS ───────────────────────────────────────────────────────────────
printf "    cloud..."

_AWS_EXE=$(_find_exe aws)
if [[ -n "$_AWS_EXE" ]]; then
    _AWS_INSTALLED=true
    _av=$(_ver_cmd "$_AWS_EXE" --version)
    _AWS_VER=$(echo "$_av" | grep -oE 'aws-cli/[0-9.]+' | sed 's/aws-cli\///' || echo "$_av")
    _AWS_REGION=$(aws configure get region 2>/dev/null || echo "not configured")
else
    _AWS_INSTALLED=false; _AWS_VER="not installed"; _AWS_EXE="not found"; _AWS_REGION="not configured"
fi

_GCLOUD_EXE=$(_find_exe gcloud)
if [[ -n "$_GCLOUD_EXE" ]]; then
    _GCLOUD_INSTALLED=true
    _gv=$(_ver_cmd "$_GCLOUD_EXE" version)
    _GCLOUD_VER=$(echo "$_gv" | grep -oE 'Google Cloud SDK [0-9.]+' | sed 's/Google Cloud SDK //' || echo "$_gv")
else
    _GCLOUD_INSTALLED=false; _GCLOUD_VER="not installed"; _GCLOUD_EXE="not found"
fi

_AZ_EXE=$(_find_exe az)
if [[ -n "$_AZ_EXE" ]]; then
    _AZ_INSTALLED=true
    _azv=$(_ver_cmd "$_AZ_EXE" --version)
    _AZ_VER=$(echo "$_azv" | grep -oE 'azure-cli[[:space:]]+[0-9.]+' | grep -oE '[0-9.]+$' || echo "$_azv")
else
    _AZ_INSTALLED=false; _AZ_VER="not installed"; _AZ_EXE="not found"
fi

echo -e " \033[32mdone\033[0m"

# ── PREFLIGHT.JSON SCAN ───────────────────────────────────────────────────────
printf "  preflight.json scan..."
_PREFLIGHT_DISCOVERED_JSON=$(python3 - << 'PFEOF'
import json, os
from datetime import datetime, timezone

discovered, seen = [], set()
ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S+00:00")

dirs = [d.strip() for d in os.environ.get("PATH", "").split(":") if d.strip()]
for root in ["/usr/local", "/opt", "/opt/homebrew", os.path.expanduser("~")]:
    if os.path.isdir(root):
        try:
            dirs += [os.path.join(root, s) for s in os.listdir(root)]
        except:
            pass

for d in dirs:
    pf = os.path.join(d, "preflight.json")
    if pf in seen or not os.path.isfile(pf):
        continue
    seen.add(pf)
    try:
        data = json.load(open(pf, encoding="utf-8"))
        if data.get("name"):
            discovered.append({
                "name": str(data["name"]),
                "version": str(data.get("version", "unknown")),
                "added_at": ts,
                "description": str(data.get("description", f"registered via preflight.json at {pf}")),
                "source": pf,
            })
    except:
        pass
print(json.dumps(discovered))
PFEOF
)
_PF_COUNT=$(echo "$_PREFLIGHT_DISCOVERED_JSON" | \
    python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo 0)
echo -e " \033[32mdone ($_PF_COUNT found)\033[0m"

export _REDIS_INSTALLED _REDIS_VER _REDIS_EXE _REDIS_CFG
export _PG_INSTALLED _PG_VER _PSQL_EXE _PG_DATA
export _MONGO_INSTALLED _MONGO_VER _MONGOD_EXE _MONGO_DATA
export _MYSQL_INSTALLED _MYSQL_VER _MYSQL_EXE _MYSQL_CFG
export _SQLITE_INSTALLED _SQLITE_VER _SQLITE_EXE
export _NGINX_INSTALLED _NGINX_VER _NGINX_EXE _NGINX_CFG
export _APACHE_INSTALLED _APACHE_VER _HTTPD_EXE _APACHE_CFG
export _RUST_INSTALLED _RUST_VER _RUSTC_EXE _CARGO_EXE
export _GO_INSTALLED _GO_VER _GO_EXE _GOPATH
export _RUBY_INSTALLED _RUBY_VER _RUBY_EXE
export _OLLAMA_INSTALLED _OLLAMA_VER _OLLAMA_EXE _OLLAMA_MODELS_JSON
export _CUDA_INSTALLED _CUDA_VER _NVCC_EXE _GPU_INFO
export _STUDIO_INSTALLED _STUDIO_VER _STUDIO_PATH _SDKMANAGER_PATH
export _PYCHARM_INSTALLED _PYCHARM_VER _PYCHARM_PATH _PYCHARM_INTERP
export _POSTMAN_INSTALLED _POSTMAN_VER _POSTMAN_PATH
export _TABLEPLUS_INSTALLED _TABLEPLUS_VER _TABLEPLUS_PATH
export _AWS_INSTALLED _AWS_VER _AWS_EXE _AWS_REGION
export _GCLOUD_INSTALLED _GCLOUD_VER _GCLOUD_EXE
export _AZ_INSTALLED _AZ_VER _AZ_EXE
export _PREFLIGHT_DISCOVERED_JSON

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

def b(k): return e(k, "false") == "true"

# Preserve existing manual extensions; merge with preflight.json discoveries
_existing_ext = []
_out = e("_OUT_FILE", "")
if _out and os.path.isfile(_out):
    try:
        with open(_out, encoding="utf-8") as _f:
            _prev = json.load(_f)
        _existing_ext = _prev.get("extensions", [])
    except:
        pass
_discovered = jlist("_PREFLIGHT_DISCOVERED_JSON")
_discovered_names = {x.get("name") for x in _discovered}
_merged_ext = _discovered + [x for x in _existing_ext if x.get("name") not in _discovered_names]

_ip = {
    "redis":          {"installed": b("_REDIS_INSTALLED"),   "version": e("_REDIS_VER",   "not installed"), "path": e("_REDIS_EXE",   "not found"), "port": 6379,  "config_file": e("_REDIS_CFG",   "not found")},
    "postgresql":     {"installed": b("_PG_INSTALLED"),      "version": e("_PG_VER",      "not installed"), "path": e("_PSQL_EXE",    "not found"), "port": 5432,  "data_dir":    e("_PG_DATA",     "not configured")},
    "mongodb":        {"installed": b("_MONGO_INSTALLED"),   "version": e("_MONGO_VER",   "not installed"), "path": e("_MONGOD_EXE",  "not found"), "port": 27017, "data_dir":    e("_MONGO_DATA",  "not found")},
    "mysql":          {"installed": b("_MYSQL_INSTALLED"),   "version": e("_MYSQL_VER",   "not installed"), "path": e("_MYSQL_EXE",   "not found"), "port": 3306,  "config_file": e("_MYSQL_CFG",   "not found")},
    "sqlite":         {"installed": b("_SQLITE_INSTALLED"),  "version": e("_SQLITE_VER",  "not installed"), "path": e("_SQLITE_EXE",  "not found")},
    "nginx":          {"installed": b("_NGINX_INSTALLED"),   "version": e("_NGINX_VER",   "not installed"), "path": e("_NGINX_EXE",   "not found"), "port": 80,    "config_file": e("_NGINX_CFG",   "not found")},
    "apache":         {"installed": b("_APACHE_INSTALLED"),  "version": e("_APACHE_VER",  "not installed"), "path": e("_HTTPD_EXE",   "not found"), "port": 80,    "config_file": e("_APACHE_CFG",  "not found")},
    "rust":           {"installed": b("_RUST_INSTALLED"),    "version": e("_RUST_VER",    "not installed"), "rustc_path": e("_RUSTC_EXE", "not found"), "cargo_path": e("_CARGO_EXE", "not found")},
    "go":             {"installed": b("_GO_INSTALLED"),      "version": e("_GO_VER",      "not installed"), "path": e("_GO_EXE",      "not found"), "GOPATH": e("_GOPATH", "not configured")},
    "ruby":           {"installed": b("_RUBY_INSTALLED"),    "version": e("_RUBY_VER",    "not installed"), "path": e("_RUBY_EXE",    "not found")},
    "ollama":         {"installed": b("_OLLAMA_INSTALLED"),  "version": e("_OLLAMA_VER",  "not installed"), "path": e("_OLLAMA_EXE",  "not found"), "port": 11434, "models": jlist("_OLLAMA_MODELS_JSON")},
    "cuda":           {"installed": b("_CUDA_INSTALLED"),    "version": e("_CUDA_VER",    "not installed"), "nvcc_path": e("_NVCC_EXE", "not found"), "gpu": e("_GPU_INFO", "no NVIDIA GPU detected")},
    "android_studio": {"installed": b("_STUDIO_INSTALLED"),  "version": e("_STUDIO_VER",  "not installed"), "path": e("_STUDIO_PATH",  "not found"), "sdkmanager_path": e("_SDKMANAGER_PATH", "not found")},
    "pycharm":        {"installed": b("_PYCHARM_INSTALLED"), "version": e("_PYCHARM_VER", "not installed"), "path": e("_PYCHARM_PATH", "not found"), "default_interpreter": e("_PYCHARM_INTERP", "not detected")},
    "postman":        {"installed": b("_POSTMAN_INSTALLED"), "version": e("_POSTMAN_VER", "not installed"), "path": e("_POSTMAN_PATH", "not found")},
    "tableplus":      {"installed": b("_TABLEPLUS_INSTALLED"),"version": e("_TABLEPLUS_VER","not installed"),"path": e("_TABLEPLUS_PATH","not found")},
    "aws_cli":        {"installed": b("_AWS_INSTALLED"),     "version": e("_AWS_VER",     "not installed"), "path": e("_AWS_EXE",     "not found"), "configured_region": e("_AWS_REGION", "not configured")},
    "gcloud":         {"installed": b("_GCLOUD_INSTALLED"),  "version": e("_GCLOUD_VER",  "not installed"), "path": e("_GCLOUD_EXE",  "not found")},
    "azure_cli":      {"installed": b("_AZ_INSTALLED"),      "version": e("_AZ_VER",      "not installed"), "path": e("_AZ_EXE",      "not found")},
}

config = {
    "config_version": "1.3",
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
    "installed_programs": _ip,
    "extensions_schema": {
        "name":        "string - tool or package name",
        "version":     "string - semver or tag",
        "added_at":    "string - ISO 8601 timestamp",
        "description": "string - what this extension does",
    },
    "extensions": _merged_ext,
}

out_path = e("_OUT_FILE")
os.makedirs(os.path.dirname(out_path), exist_ok=True)
with open(out_path, "w", encoding="utf-8") as f:
    json.dump(config, f, indent=4)
PYEOF

echo -e " \033[32mdone\033[0m"
echo ""
echo -e "\033[32mWritten to: $OUTPUT_FILE\033[0m"
