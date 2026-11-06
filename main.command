#!/bin/zsh
set -euo pipefail

APP_TITLE="YouTube Downloader"

# Make Homebrew binaries visible when launched by double-click
if [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -x /usr/local/bin/brew ]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi

# ---------- Dependency checks ----------
if ! command -v yt-dlp >/dev/null 2>&1; then
  osascript -e "display dialog \"yt-dlp is not installed.\n\nInstall with:\n\nbrew install yt-dlp\" buttons {\"OK\"} with title \"$APP_TITLE\""
  exit 1
fi

if ! command -v ffmpeg >/dev/null 2>&1; then
  osascript -e "display dialog \"ffmpeg is not installed.\n\nInstall with:\n\nbrew install ffmpeg\" buttons {\"OK\"} with title \"$APP_TITLE\""
  exit 1
fi

# ---------- 1) Ask for URL ----------
URL=$(osascript <<'APPLESCRIPT'
set r to display dialog "Enter YouTube URL:" default answer "" with title "YouTube Downloader"
set u to text returned of r
if u is "" then error number -128
return u
APPLESCRIPT
) || exit 0

URL=$(echo "$URL" | tr -d '[:space:]')

# ---------- 2) Mode ----------
MODE=$(osascript <<'APPLESCRIPT'
set r to display dialog "Choose download type:" buttons {"Cancel","Audio Only (M4A)","Video + Audio (MP4)"} default button "Video + Audio (MP4)" with title "YouTube Downloader"
if button returned of r is "Cancel" then error number -128
return button returned of r
APPLESCRIPT
) || exit 0

# ---------- 3) Output folder ----------
OUTDIR=$(osascript <<'APPLESCRIPT'
set f to choose folder with prompt "Choose output folder:" default location (path to desktop folder)
return POSIX path of f
APPLESCRIPT
) || exit 0

cd "$OUTDIR" || exit 1

COMMON_OPTS=(
  --no-playlist
  --restrict-filenames
  --newline
  --remote-components ejs:github
)

COOKIES_OPTS=()

# Helper: ask for Chrome profile name (Profile 9 etc.)
ask_chrome_profile () {
  osascript <<'APPLESCRIPT'
set choices to {"Profile 9","Profile 12","Profile 20","Profile 21","Guest Profile"}
set r to choose from list choices with prompt "This video appears age-restricted.\nSelect the Chrome profile where you are logged into YouTube:" default items {"Profile 9"} with title "YouTube Downloader"
if r is false then error number -128
return item 1 of r
APPLESCRIPT
}

# ---------- 4) Detect age restriction / auth need ----------
TMP=$(mktemp)

# First try unauthenticated (fast path)
if ! yt-dlp "${COMMON_OPTS[@]}" -F "$URL" >"$TMP" 2>&1; then
  if grep -qiE "age-restricted|confirm your age|sign in|account age-verification|Sorry, this content is age-restricted" "$TMP"; then

    # Your real case: Chrome + a numbered profile
    PROFILE=$(ask_chrome_profile) || { rm -f "$TMP"; exit 0; }
    COOKIES_OPTS=(--cookies-from-browser "chrome:${PROFILE}")

    # Verify cookies actually unlock formats
    if ! yt-dlp "${COMMON_OPTS[@]}" "${COOKIES_OPTS[@]}" -F "$URL" >/dev/null 2>&1; then
      osascript -e "display dialog \"Login failed (cookies not accepted).\n\n1) Open YouTube in Chrome (${PROFILE})\n2) Confirm you are logged in and age-verified\n3) Retry\" buttons {\"OK\"} with title \"$APP_TITLE\""
      rm -f "$TMP"
      exit 1
    fi

  else
    osascript -e "display dialog \"Unable to access this video.\n\n$(tail -n 3 "$TMP" | sed 's/"/\\"/g')\" buttons {\"OK\"} with title \"$APP_TITLE\""
    rm -f "$TMP"
    exit 1
  fi
fi

rm -f "$TMP"

# ---------- 5) Download ----------
if [[ "$MODE" == "Video + Audio (MP4)" ]]; then
  yt-dlp "${COMMON_OPTS[@]}" "${COOKIES_OPTS[@]}" \
    -f "bv*[ext=mp4]+ba[ext=m4a]/b[ext=mp4]/bv*+ba/best" \
    --remux-video mp4 \
    --merge-output-format mp4 \
    -o "%(title)s.%(ext)s" \
    "$URL"
else
  yt-dlp "${COMMON_OPTS[@]}" "${COOKIES_OPTS[@]}" \
    -f "ba[ext=m4a]/ba/best" \
    --extract-audio \
    --audio-format m4a \
    --audio-quality 0 \
    -o "%(title)s.%(ext)s" \
    "$URL"
fi

osascript -e "display dialog \"Download complete.\" buttons {\"OK\"} with title \"$APP_TITLE\""