#!/usr/bin/env bash
# list-layers.sh
# macOS 入口：读取 PSD/PSB 图层结构，写出 UTF-8 无 BOM 的 JSON。
# 参数与 list-layers.ps1 一致。Windows 请继续使用 list-layers.ps1。
#
# 示例：
#   bash list-layers.sh "/path/to/1.psb"
#
# 输出：
#   与源文件同目录，文件名为 "源文件名_layers.json"

set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "list-layers.sh is for macOS. On Windows run list-layers.ps1." >&2
    exit 1
fi

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
JSX_PATH="$SCRIPT_DIR/list-layers.jsx"

usage() {
    cat <<'EOF'
Usage:
  list-layers.sh <PSD/PSB>
EOF
}

js_escape() {
    local s=$1
    local out="" i c len
    len=${#s}
    i=0
    while [[ $i -lt $len ]]; do
        c=${s:i:1}
        case "$c" in
            \\) out="${out}\\\\" ;;
            '"') out="${out}\\\"" ;;
            $'\n') out="${out}\\n" ;;
            $'\r') out="${out}\\r" ;;
            $'\t') out="${out}\\t" ;;
            *) out="${out}${c}" ;;
        esac
        i=$((i + 1))
    done
    printf '%s' "$out"
}

abs_path() {
    local p="$1"
    local dir base
    if [[ "$p" != /* ]]; then
        p="$PWD/$p"
    fi
    dir=$(cd "$(dirname "$p")" && pwd)
    base=$(basename "$p")
    printf '%s/%s' "$dir" "$base"
}

strip_utf8_bom() {
    local f="$1" hex
    hex=$(head -c 3 "$f" | od -An -tx1 | tr -d ' \n')
    if [[ "$hex" == "efbbbf" ]]; then
        tail -c +4 "$f" > "$f.nobom"
        mv "$f.nobom" "$f"
    fi
}

detect_photoshop() {
    local names app
    names=$(osascript <<"EOF" 2>/dev/null || true
tell application "System Events"
    set psNames to name of every process whose name starts with "Adobe Photoshop"
end tell
set text item delimiters to linefeed
if (count of psNames) is 0 then
    return ""
end if
return psNames as text
EOF
)
    names=$(printf '%s' "$names" | tr -d '\r')
    names_compact=$(printf '%s' "$names" | tr -d '[:space:]')
    if [[ -n "$names_compact" ]]; then
        PS_MODE=name
        PS_TARGET=$(printf '%s\n' "$names" | head -n 1)
        return 0
    fi

    if mdfind 'kMDItemCFBundleIdentifier == "com.adobe.Photoshop"' 2>/dev/null | head -n 1 | grep -q .; then
        PS_MODE=id
        PS_TARGET="com.adobe.Photoshop"
        return 0
    fi

    app=$(find /Applications "$HOME/Applications" /Volumes/*/Applications -maxdepth 3 -name 'Adobe Photoshop*.app' -print 2>/dev/null | sort | tail -n 1 || true)
    if [[ -n "$app" ]]; then
        PS_MODE=name
        PS_TARGET=$(basename "$app" .app)
        return 0
    fi
    return 1
}

# 执行期间自动关掉 Photoshop 报错弹窗，避免 do javascript 停在「确定」上。
start_error_dialog_dismisser() {
    local proc_prefix="$1"
    DISMISS_FLAG=$(mktemp "${TMPDIR:-/tmp}/ps-dismiss.XXXXXX")
    osascript - "$proc_prefix" "$DISMISS_FLAG" >/dev/null 2>&1 <<'EOF' &
on run argv
    set procPrefix to item 1 of argv
    set flagPath to item 2 of argv
    repeat
        try
            do shell script "test -f " & quoted form of flagPath
        on error
            exit repeat
        end try
        try
            tell application "System Events"
                set psProcs to every process whose name starts with procPrefix
                repeat with psProc in psProcs
                    tell psProc
                        repeat with w in windows
                            set wname to ""
                            try
                                set wname to name of w as text
                            end try
                            if wname contains ".psb" or wname contains ".psd" or wname contains ".PSB" or wname contains ".PSD" then
                                try
                                    repeat with s in sheets of w
                                        my click_ok(s)
                                    end repeat
                                end try
                            else
                                my click_ok(w)
                                try
                                    repeat with s in sheets of w
                                        my click_ok(s)
                                    end repeat
                                end try
                            end if
                        end repeat
                    end tell
                end repeat
            end tell
        end try
        delay 0.25
    end repeat
end run

on click_ok(uiElem)
    tell application "System Events"
        tell uiElem
            set labels to {"确定", "OK", "好"}
            repeat with labelName in labels
                try
                    if exists button labelName then
                        click button labelName
                        return true
                    end if
                end try
            end repeat
        end tell
    end tell
    return false
end click_ok
EOF
    DISMISS_PID=$!
}

stop_error_dialog_dismisser() {
    if [[ -n "${DISMISS_FLAG:-}" ]]; then
        rm -f "$DISMISS_FLAG"
        DISMISS_FLAG=""
    fi
    if [[ -n "${DISMISS_PID:-}" ]]; then
        kill "$DISMISS_PID" 2>/dev/null || true
        wait "$DISMISS_PID" 2>/dev/null || true
        DISMISS_PID=""
    fi
}

run_photoshop_jsx() {
    local mode="$1" target="$2" jsx="$3"
    local err_file out_file rc
    err_file=$(mktemp)
    out_file=$(mktemp)
    rc=0
    # using terms from 让动态应用名也能编译 do javascript。
    # tell application id 变量本身不会带上 Photoshop 术语表。
    osascript - "$target" "$mode" "$jsx" >"$out_file" 2>"$err_file" <<'EOF' || rc=$?
on run argv
    set appTarget to item 1 of argv
    set targetMode to item 2 of argv
    set jsxPath to item 3 of argv
    set jsCode to read (POSIX file jsxPath) as «class utf8»
    using terms from application id "com.adobe.Photoshop"
        with timeout of 7200 seconds
            if targetMode is "id" then
                tell application id appTarget
                    set r to do javascript jsCode
                    return r
                end tell
            else
                tell application appTarget
                    set r to do javascript jsCode
                    return r
                end tell
            end if
        end timeout
    end using terms from
end run
EOF
    PHOTOSHOP_STDERR=$(cat "$err_file" "$out_file" 2>/dev/null || true)
    rm -f "$err_file" "$out_file"
    return "$rc"
}

if [[ $# -eq 0 ]]; then
    usage >&2
    exit 1
fi
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    usage
    exit 0
fi

if [[ $# -ne 1 ]]; then
    echo "Unexpected argument: $2" >&2
    usage >&2
    exit 1
fi

PSD_PATH="$1"

if [[ ! -f "$PSD_PATH" ]]; then
    echo "File not found: $PSD_PATH" >&2
    exit 1
fi

ext=$(printf '%s' "${PSD_PATH##*.}" | tr '[:upper:]' '[:lower:]')
if [[ "$ext" != "psd" && "$ext" != "psb" ]]; then
    echo "Unsupported file format: .$ext (only .psd and .psb are supported)" >&2
    exit 1
fi

if [[ ! -f "$JSX_PATH" ]]; then
    echo "list-layers.jsx not found, make sure it is in the same folder as this script" >&2
    exit 1
fi

PSD_PATH=$(abs_path "$PSD_PATH")
JSX_PATH=$(abs_path "$JSX_PATH")

psd_dir=$(dirname "$PSD_PATH")
psd_base=$(basename "$PSD_PATH")
psd_name="${psd_base%.*}"
json_path="$psd_dir/${psd_name}_layers.json"

result_file=$(mktemp "${TMPDIR:-/tmp}/list-layers-result.XXXXXX")
runner_file=$(mktemp "${TMPDIR:-/tmp}/list-layers-runner.XXXXXX.jsx")
cleanup() {
    stop_error_dialog_dismisser
    rm -f "$result_file" "$runner_file"
}
trap cleanup EXIT

{
    printf 'var file = new File("%s");\n' "$(js_escape "$PSD_PATH")"
    cat <<'EOF'
var __prevDialogs = app.displayDialogs;
app.displayDialogs = DialogModes.NO;
try {
    try {
        var opts = new PhotoshopOpenOptions();
        opts.preserveLayers = true;
        app.open(file, opts);
    } catch (e) {
        var desc = new ActionDescriptor();
        desc.putPath(charIDToTypeID("null"), file);
        desc.putBoolean(stringIDToTypeID("preserveLayers"), true);
        app.executeAction(charIDToTypeID("Opn "), desc, DialogModes.NO);
    }
} catch (eOpen) {
    app.displayDialogs = __prevDialogs;
    throw eOpen;
}
app.displayDialogs = __prevDialogs;
EOF
    printf 'var __layersJson = $.evalFile(new File("%s"));\n' "$(js_escape "$JSX_PATH")"
    printf 'var resultOut = new File("%s");\n' "$(js_escape "$result_file")"
    cat <<'EOF'
resultOut.encoding = "UTF-8";
resultOut.lineFeed = "Unix";
resultOut.open("w");
resultOut.write(__layersJson == null ? "" : String(__layersJson));
resultOut.close();
"OK";
EOF
} > "$runner_file"

echo "Connecting to Photoshop..."
if ! detect_photoshop; then
    echo "Cannot connect to Photoshop. Make sure it is installed and has been launched at least once." >&2
    exit 1
fi

echo "Opening (preserve layers): $PSD_PATH"
echo "Reading layers..."

dismiss_prefix="Adobe Photoshop"
if [[ "$PS_MODE" == "name" ]]; then
    dismiss_prefix="$PS_TARGET"
fi
start_error_dialog_dismisser "$dismiss_prefix"
set +e
run_photoshop_jsx "$PS_MODE" "$PS_TARGET" "$runner_file"
ps_rc=$?
set -e
stop_error_dialog_dismisser

if [[ $ps_rc -ne 0 ]]; then
    echo "Failed to read layers: ${PHOTOSHOP_STDERR:-unknown error}" >&2
    if printf '%s' "$PHOTOSHOP_STDERR" | grep -Eq '1743|不允许|not authorized|not permitted'; then
        echo "Allow this terminal to control Photoshop in System Settings > Privacy & Security > Automation." >&2
    fi
    exit 1
fi

if [[ ! -f "$result_file" ]]; then
    echo "No result returned from Photoshop. The file may be corrupted or empty." >&2
    exit 1
fi
strip_utf8_bom "$result_file"
result=$(cat "$result_file" || true)

if [[ "$result" == *'"error"'* ]]; then
    echo ""
    echo "ERROR: Photoshop returned an error:"
    echo "$result"
    exit 1
fi

result_compact=$(printf '%s' "$result" | tr -d '[:space:]')
if [[ -z "$result_compact" ]]; then
    echo "No result returned from Photoshop. The file may be corrupted or empty." >&2
    exit 1
fi

printf '%s' "$result" > "$json_path"

file_size=$(wc -c < "$json_path" | tr -d ' ')
file_size_kb=$(awk -v n="$file_size" 'BEGIN { printf "%.1f", n / 1024 }')
echo ""
echo "Done! JSON saved to: $json_path ($file_size_kb KB)"
echo ""
echo "Tip: Use the 'path' field in JSON as layer path for ps-export.sh:"
echo "  bash \"$SCRIPT_DIR/../ps-export/ps-export.sh\" \"$PSD_PATH\" -Export \"path/to/layer\""
