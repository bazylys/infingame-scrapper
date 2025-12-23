#!/usr/bin/env bash
set -euo pipefail

# ===================== SETTINGS =====================
BASE_URL="https://data.infingame.com"
LOGIN_URL="$BASE_URL/index.php"
LIST_URL="$BASE_URL/my_files/index.php"   # ?page=N will be added automatically

# Credentials
USERNAME=''
PASSWORD=''

# aria2c parameters
CONTINUE=1      # 1 = enable resume (-c)
JOBS=8          # -j : number of files to download in parallel
SPLIT=16        # -s : number of connections per file
MAX_CONN=16     # -x : max connections per server

OUTDIR="downloads"
UA="Mozilla/5.0"

# ===================== CHECK REQUIRED BINARIES =====================
for bin in aria2c curl grep sed awk tr wc find sort uniq; do
  command -v "$bin" >/dev/null 2>&1 || { echo "Not found: $bin"; exit 1; }
done
mkdir -p "$OUTDIR"

COOKIE_JAR="$(mktemp -t psend.cookies.XXXX)"
URLS_FILE="$(mktemp -t psend.urls.XXXX.txt)"
TMP_IDS="$(mktemp -t psend.ids.XXXX.txt)"
trap 'rm -f "$COOKIE_JAR" "$URLS_FILE" "$TMP_IDS" 2>/dev/null || true' EXIT

# ===================== [1/5] GET LOGIN PAGE =====================
echo "[1/5] GET login page"
LOGIN_PAGE=$(curl -sSL -L --compressed -c "$COOKIE_JAR" -A "$UA" "$LOGIN_URL")
CSRF=$(printf "%s" "$LOGIN_PAGE" | grep -oE 'name="csrf_token" value="[^"]+' | sed 's/.*value="//' || true)
if [[ -z "${CSRF:-}" ]]; then
  mkdir -p debug_html && printf "%s" "$LOGIN_PAGE" > debug_html/login_fail.html
  echo "Could not retrieve csrf_token. See debug_html/login_fail.html"
  exit 1
fi

# ===================== [2/5] LOGIN =====================
echo "[2/5] POST login"
POST_RES=$(curl -sSL -L --compressed -b "$COOKIE_JAR" -c "$COOKIE_JAR" -A "$UA" -e "$LOGIN_URL" \
  --data-urlencode "csrf_token=$CSRF" \
  --data-urlencode "do=login" \
  --data-urlencode "username=$USERNAME" \
  --data-urlencode "password=$PASSWORD" \
  -X POST "$LOGIN_URL")
if ! grep -q $'\tPHPSESSID\t' "$COOKIE_JAR"; then
  mkdir -p debug_html && printf "%s" "$POST_RES" > debug_html/post_login_fail.html
  echo "Login failed (no PHPSESSID in cookies). See debug_html/post_login_fail.html"
  exit 1
fi

# ===================== [3/5] DETERMINE NUMBER OF PAGES =====================
echo "[3/5] GET first list page"
PAGE1=$(curl -sSL -L --compressed -b "$COOKIE_JAR" -A "$UA" "${LIST_URL}")
LAST_PAGE=$(
  printf "%s" "$PAGE1" | grep -oE 'data-page="last"[^>]*href="[^"]*page=[0-9]+' \
    | grep -oE 'page=[0-9]+' | sed 's/page=//' | sort -n | tail -n1 || true
)
if [[ -z "$LAST_PAGE" ]]; then
  LAST_PAGE=$(
    printf "%s" "$PAGE1" | grep -oE 'index\.php\?page=[0-9]+' \
      | sed 's/.*page=//' | sort -n | tail -n1 || echo "1"
  )
fi
[[ -z "$LAST_PAGE" ]] && LAST_PAGE=1
echo "Total pages detected: $LAST_PAGE"

# ===================== [4/5] COLLECT RECORDS (SAVE FINAL LINKS) =====================
echo "[4/5] Collecting records from all pages"
> "$TMP_IDS"
for PAGE in $(seq 1 "$LAST_PAGE"); do
  HTML=$(curl -sSL -L --compressed -b "$COOKIE_JAR" -A "$UA" "${LIST_URL}?page=${PAGE}")
  ids=$(
    printf "%s" "$HTML" \
    | grep -oE 'process\.php\?do=download(&amp;|&)id=[0-9]+' \
    | sed 's/&amp;/\&/g' \
    | sed -E 's/.*id=([0-9]+)/\1/' \
    | sed '/^$/d' | sort -u
  )
  cnt=$(printf "%s\n" "$ids" | sed '/^$/d' | wc -l | tr -d ' ')
  echo "  page ${PAGE}: records found = $cnt"
  if [[ "$cnt" -gt 0 ]]; then
    printf "%s\n" "$ids" >> "$TMP_IDS"
  fi
done

if [[ ! -s "$TMP_IDS" ]]; then
  mkdir -p debug_html && printf "%s" "$PAGE1" > debug_html/page1_noids.html
  echo "No files found. See debug_html/page1_noids.html"
  exit 0
fi

# Build final links list
sort -u "$TMP_IDS" | awk -v B="$BASE_URL/process.php?do=download&id=" '{print B $1}' > "$URLS_FILE"
TOTAL=$(wc -l < "$URLS_FILE" | tr -d ' ')
echo "Total records found: $TOTAL"
echo

# Print list of links
echo "Download links:"
nl -ba "$URLS_FILE" | awk -v total="$TOTAL" '{printf "  [%d/%d] %s\n", $1, total, $2}'
echo

# ===================== [5/5] DOWNLOAD =====================
echo "[5/5] Downloading with aria2c + progress counter"
ARIA_OPTS=( -x"$MAX_CONN" -s"$SPLIT" -j"$JOBS"
  --load-cookies="$COOKIE_JAR"
  --user-agent="$UA"
  --referer="${LIST_URL}?page=1"
  --auto-file-renaming=true
  --content-disposition-default-utf8=true
  --dir="$OUTDIR" -i "$URLS_FILE"
)
[[ "$CONTINUE" -eq 1 ]] && ARIA_OPTS=( -c "${ARIA_OPTS[@]}" )

aria2c "${ARIA_OPTS[@]}" >/dev/null 2>&1 &
PID=$!

LAST=-1
while kill -0 "$PID" 2>/dev/null; do
  DONE=$(find "$OUTDIR" -maxdepth 1 -type f ! -name "*.aria2" | wc -l | tr -d ' ')
  if [[ "$DONE" -ne "$LAST" ]]; then
    printf "\rDownloading: %d / %d" "$DONE" "$TOTAL"
    LAST="$DONE"
  fi
  sleep 1
done
wait "$PID" || true
DONE=$(find "$OUTDIR" -maxdepth 1 -type f ! -name "*.aria2" | wc -l | tr -d ' ')
printf "\rDownloading: %d / %d\n" "$DONE" "$TOTAL"

if find "$OUTDIR" -maxdepth 1 -type f -name "*.aria2" | grep -q .; then
  echo "There are unfinished *.aria2 files — restart the script to resume."
fi

echo "Done. Files saved in: $OUTDIR"
