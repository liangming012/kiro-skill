#!/usr/bin/env bash
# ps-export.sh
# macOS 入口：打开 PSD/PSB，调用 ps-export.jsx 导出 PNG。
# 参数与 ps-export.ps1 一致。Windows 请继续使用 ps-export.ps1。
#
# 示例：
#   bash ps-export.sh "/path/to/1.psb"
#   bash ps-export.sh "/path/to/1.psb" -Hide "Header/watermark","Footer/old"
#   bash ps-export.sh "/path/to/1.psb" -Show "Header/new logo"
#   bash ps-export.sh "/path/to/1.psb" -Export "Header/banner","Content/icon"
#   bash ps-export.sh "/path/to/1.psb" -Hide "Header/watermark" -Export "Header/banner"

set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "ps-export.sh is for macOS. On Windows run ps-export.ps1." >&2
    exit 1
fi

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
JSX_PATH="$SCRIPT_DIR/ps-export.jsx"

usage() {
    cat <<'EOF'
Usage:
  ps-export.sh <PSD/PSB> [-Hide paths] [-Show paths] [-Export paths]

Options match ps-export.ps1. Multiple layer paths are comma-separated.
EOF
}

trim() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
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

csv_to_json_array() {
    local csv="$1"
    local json="[" first=1 item esc rest
    rest="$csv"
    if [[ -z "$csv" ]]; then
        printf '%s' "[]"
        return
    fi
    while [[ -n "$rest" ]]; do
        item="${rest%%,*}"
        if [[ "$rest" == *,* ]]; then
            rest="${rest#*,}"
        else
            rest=""
        fi
        item=$(trim "$item")
        [[ -z "$item" ]] && continue
        esc=$(js_escape "$item")
        if [[ $first -eq 1 ]]; then
            json="${json}\"${esc}\""
            first=0
        else
            json="${json},\"${esc}\""
        fi
    done
    printf '%s' "${json}]"
}

append_csv() {
    local current="$1" extra="$2"
    if [[ -z "$current" ]]; then
        printf '%s' "$extra"
    else
        printf '%s,%s' "$current" "$extra"
    fi
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

# Photoshop 的「命令不可用」之类报错会弹出模态框，do javascript 会一直停在那里。
# 执行期间只点报错框上的「确定 / OK」，点完后脚本收到异常并继续。
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

PSD_PATH=""
HIDE_CSV=""
SHOW_CSV=""
EXPORT_CSV=""

if [[ $# -eq 0 ]]; then
    usage >&2
    exit 1
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        -Hide|--hide|-Show|--show|-Export|--export)
            if [[ $# -lt 2 ]]; then
                echo "Missing value for $1" >&2
                exit 1
            fi
            case "$1" in
                -Hide|--hide) HIDE_CSV=$(append_csv "$HIDE_CSV" "$2") ;;
                -Show|--show) SHOW_CSV=$(append_csv "$SHOW_CSV" "$2") ;;
                -Export|--export) EXPORT_CSV=$(append_csv "$EXPORT_CSV" "$2") ;;
            esac
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            if [[ $# -gt 0 && -z "$PSD_PATH" ]]; then
                PSD_PATH="$1"
                shift
            fi
            if [[ $# -gt 0 ]]; then
                echo "Unexpected argument: $1" >&2
                exit 1
            fi
            ;;
        -*)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
        *)
            if [[ -n "$PSD_PATH" ]]; then
                echo "Unexpected argument: $1" >&2
                exit 1
            fi
            PSD_PATH="$1"
            shift
            ;;
    esac
done

if [[ -z "$PSD_PATH" ]]; then
    echo "File not found: (missing PSD/PSB path)" >&2
    usage >&2
    exit 1
fi

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
    echo "ps-export.jsx not found, make sure it is in the same folder as this script" >&2
    exit 1
fi

PSD_PATH=$(abs_path "$PSD_PATH")
JSX_PATH=$(abs_path "$JSX_PATH")

args_json="{\"hide\":$(csv_to_json_array "$HIDE_CSV"),\"show\":$(csv_to_json_array "$SHOW_CSV"),\"export\":$(csv_to_json_array "$EXPORT_CSV")}"
args_file=$(mktemp "${TMPDIR:-/tmp}/ps-export-args.XXXXXX")
result_file=$(mktemp "${TMPDIR:-/tmp}/ps-export-result.XXXXXX")
runner_file=$(mktemp "${TMPDIR:-/tmp}/ps-export-runner.XXXXXX.jsx")
cleanup() {
    stop_error_dialog_dismisser
    rm -f "$args_file" "$result_file" "$runner_file"
}
trap cleanup EXIT

printf '%s' "$args_json" > "$args_file"

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
    printf 'var argsFile = new File("%s");\n' "$(js_escape "$args_file")"
    cat <<'EOF'
argsFile.open("r");
argsFile.encoding = "UTF-8";
var __args = argsFile.read();
argsFile.close();
EOF
    printf 'var __psExportResult = $.evalFile(new File("%s"));\n' "$(js_escape "$JSX_PATH")"
    printf 'var resultOut = new File("%s");\n' "$(js_escape "$result_file")"
    cat <<'EOF'
resultOut.encoding = "UTF-8";
resultOut.lineFeed = "Unix";
resultOut.open("w");
resultOut.write(__psExportResult == null ? "" : String(__psExportResult));
resultOut.close();
"OK";
EOF
} > "$runner_file"

echo "Args JSON: $args_json"
if [[ -n "$HIDE_CSV" ]]; then
    echo "Hide layers: $(printf '%s' "$HIDE_CSV" | sed 's/,/, /g')"
fi
if [[ -n "$SHOW_CSV" ]]; then
    echo "Show layers: $(printf '%s' "$SHOW_CSV" | sed 's/,/, /g')"
fi
if [[ -n "$EXPORT_CSV" ]]; then
    echo "Export layers: $(printf '%s' "$EXPORT_CSV" | sed 's/,/, /g')"
else
    echo "Export mode: full page"
fi

echo "Connecting to Photoshop..."
if ! detect_photoshop; then
    echo "Cannot connect to Photoshop. Make sure it is installed." >&2
    exit 1
fi

echo "Opening (preserve layers): $PSD_PATH"
echo "Exporting PNG..."

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
    echo "Photoshop script execution failed: ${PHOTOSHOP_STDERR:-unknown error}" >&2
    if printf '%s' "$PHOTOSHOP_STDERR" | grep -Eq '1743|不允许|not authorized|not permitted'; then
        echo "Allow this terminal to control Photoshop in System Settings > Privacy & Security > Automation." >&2
    fi
    exit 1
fi

if [[ ! -f "$result_file" ]]; then
    echo "No result returned from Photoshop. Export may have failed." >&2
    exit 1
fi
strip_utf8_bom "$result_file"
result=$(cat "$result_file" || true)

result_compact=$(printf '%s' "$result" | tr -d '[:space:]')
if [[ -z "$result_compact" ]]; then
    echo "No result returned from Photoshop. Export may have failed." >&2
    exit 1
fi

if [[ "$result" == ERROR:* ]]; then
    echo ""
    echo "$result"
    echo ""
    echo "Tip: Use list-layers.sh to get the correct layer paths:"
    echo "  bash \"$SCRIPT_DIR/../list-layers/list-layers.sh\" \"$PSD_PATH\""
else
    exported=""
    warns=""
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" == WARNING:* ]]; then
            warns="${warns}${line}"$'\n'
        elif [[ -n "$(printf '%s' "$line" | tr -d '[:space:]')" ]]; then
            exported="${exported}${line}"$'\n'
        fi
    done <<< "$result"
    if [[ -n "$exported" ]]; then
        echo "Done! Exported to:"
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            echo "  $line"
        done <<< "$exported"
    fi
    if [[ -n "$warns" ]]; then
        echo ""
        printf '%s' "$warns"
        echo ""
        echo "Tip: Use list-layers.sh to check layer paths:"
        echo "  bash \"$SCRIPT_DIR/../list-layers/list-layers.sh\" \"$PSD_PATH\""
    fi
fi
