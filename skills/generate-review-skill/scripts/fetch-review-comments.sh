#!/usr/bin/env bash
# ABOUTME: Fetches human review comments from the current user's GitLab MRs.
# ABOUTME: Outputs a single JSON array to stdout for downstream analysis by the generate-review-skill.

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
DAYS="${1:-90}"
PARALLELISM="${2:-8}"
OUTPUT_FILE="${3:-}"
BOT_PATTERN="bot|service-|async-agent|gitlab|tfbuddy|dependabot|renovate|prjiracheck|droid"
NOISE_PATTERN="vercel\.com|(^|\n)\s*(Preview|Production) deployment:|(^|\n)\s*Inspect:\s*https://|(^|\n)\s*Build logs:\s*https://|(^|\n)\s*✅\s*Ready in"

# ---------------------------------------------------------------------------
# Preflight checks
# ---------------------------------------------------------------------------
for cmd in glab jq; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "ERROR: $cmd is required but not installed." >&2
    exit 1
  fi
done

api_get() {
  local endpoint="$1"
  local attempts=0
  local max_attempts=4
  local delay=1

  while (( attempts < max_attempts )); do
    if glab api "$endpoint" --paginate 2>/dev/null; then
      return 0
    fi

    attempts=$((attempts + 1))
    if (( attempts >= max_attempts )); then
      return 1
    fi

    sleep "$delay"
    delay=$((delay * 2))
  done

  return 1
}

# ---------------------------------------------------------------------------
# Resolve current user
# ---------------------------------------------------------------------------
echo "Resolving GitLab user..." >&2
USER_JSON=$(api_get "/user")
USER_ID=$(echo "$USER_JSON" | jq -r '.id')
USERNAME=$(echo "$USER_JSON" | jq -r '.username')

if [[ -z "$USER_ID" || "$USER_ID" == "null" ]]; then
  echo "ERROR: Could not resolve GitLab user. Run 'glab auth login' first." >&2
  exit 1
fi
echo "  User: $USERNAME (ID: $USER_ID)" >&2

# ---------------------------------------------------------------------------
# Fetch all merged MRs in the time window (single paginated call)
# ---------------------------------------------------------------------------
AFTER_DATE=$(date -v-"${DAYS}"d +%Y-%m-%dT00:00:00Z 2>/dev/null \
  || date -d "${DAYS} days ago" +%Y-%m-%dT00:00:00Z)

echo "Fetching merged MRs from the last ${DAYS} days..." >&2

MR_ENDPOINT="/merge_requests?author_id=${USER_ID}&created_after=${AFTER_DATE}&scope=all&per_page=100&state=merged"
MR_JSON=$(api_get "$MR_ENDPOINT")

# Extract MRs that have human comments, along with project metadata
MR_LIST=$(echo "$MR_JSON" | jq -c '[.[] | select(.user_notes_count > 0) | {
  project_id: .project_id,
  iid: .iid,
  title: .title,
  web_url: .web_url,
  user_notes_count: .user_notes_count,
  project_path: (.references.full | split("!")[0])
}]')

MR_COUNT=$(echo "$MR_LIST" | jq 'length')
TOTAL_NOTES=$(echo "$MR_LIST" | jq '[.[].user_notes_count] | add // 0')
PROJECT_COUNT=$(echo "$MR_LIST" | jq '[.[].project_path] | unique | length')

echo "  Found ${MR_COUNT} MRs with comments across ${PROJECT_COUNT} projects (~${TOTAL_NOTES} notes total)" >&2

if [[ "$MR_COUNT" -eq 0 ]]; then
  echo "[]"
  exit 0
fi

# ---------------------------------------------------------------------------
# Fetch discussions for each MR in parallel
# ---------------------------------------------------------------------------
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# Write the MR list as individual files so workers can read by index
echo "$MR_LIST" | jq -c '.[]' > "$TMPDIR/mrs.jsonl"
MR_LINE_COUNT=$(wc -l < "$TMPDIR/mrs.jsonl" | tr -d ' ')

echo "Fetching discussions (parallelism: ${PARALLELISM})..." >&2

# Write a self-contained worker script to disk so xargs can invoke it cleanly
cat > "$TMPDIR/worker.sh" << 'WORKER_EOF'
#!/usr/bin/env bash
set -euo pipefail
LINE_NUM="$1"
MRS_FILE="$2"
USERNAME="$3"
BOT_PATTERN="$4"
NOISE_PATTERN="$5"
OUTDIR="$6"

api_get() {
  local endpoint="$1"
  local attempts=0
  local max_attempts=4
  local delay=1

  while (( attempts < max_attempts )); do
    if glab api "$endpoint" --paginate 2>/dev/null; then
      return 0
    fi

    attempts=$((attempts + 1))
    if (( attempts >= max_attempts )); then
      return 1
    fi

    sleep "$delay"
    delay=$((delay * 2))
  done

  return 1
}

mr_json=$(sed -n "${LINE_NUM}p" "$MRS_FILE")
project_id=$(echo "$mr_json" | jq -r '.project_id')
iid=$(echo "$mr_json" | jq -r '.iid')
title=$(echo "$mr_json" | jq -r '.title')
web_url=$(echo "$mr_json" | jq -r '.web_url')
project_path=$(echo "$mr_json" | jq -r '.project_path')

echo "  ${project_path}!${iid}: ${title}" >&2

discussions=$(api_get "projects/${project_id}/merge_requests/${iid}/discussions?per_page=100" || echo "[]")

echo "$discussions" | jq -c --arg username "$USERNAME" --arg bot_pattern "$BOT_PATTERN" --arg noise_pattern "$NOISE_PATTERN" \
  --arg mr_title "$title" --arg mr_url "$web_url" --arg project "$project_path" '
  [.[] | .notes[] | select(
    .system == false
    and .author.username != $username
    and (.author.username | test($bot_pattern; "i") | not)
    and (.body | test($noise_pattern; "i") | not)
    and (.body | test("^:\\w+:$") | not)
    and (.body | test("^(lgtm|approved|ship it|looks good|nice|thanks|:thumbsup:|:eyes:|:rocket:)$"; "i") | not)
  ) | {
    author: .author.username,
    body: .body,
    file: .position.new_path,
    line: .position.new_line,
    mr_title: $mr_title,
    mr_url: $mr_url,
    project: $project,
    created_at: .created_at
  }] | .[]
' > "$OUTDIR/result_${project_id}_${iid}.jsonl" 2>/dev/null || true
WORKER_EOF
chmod +x "$TMPDIR/worker.sh"

# Generate line numbers 1..N and run workers in parallel
seq 1 "$MR_LINE_COUNT" | xargs -P "$PARALLELISM" -I {} \
  "$TMPDIR/worker.sh" {} "$TMPDIR/mrs.jsonl" "$USERNAME" "$BOT_PATTERN" "$NOISE_PATTERN" "$TMPDIR"

# ---------------------------------------------------------------------------
# Merge all results into a single JSON array
# ---------------------------------------------------------------------------
COMMENT_COUNT=0
if ls "$TMPDIR"/result_*.jsonl &>/dev/null; then
  RESULT=$(cat "$TMPDIR"/result_*.jsonl | jq -s 'unique_by(.author, .body, .file, .line, .mr_url)' 2>/dev/null || echo "[]")
  COMMENT_COUNT=$(echo "$RESULT" | jq 'length')
else
  RESULT="[]"
fi

echo "" >&2
echo "Done. Extracted ${COMMENT_COUNT} human review comments." >&2

if [[ -n "$OUTPUT_FILE" ]]; then
  printf '%s\n' "$RESULT" > "$OUTPUT_FILE"
  echo "Wrote JSON output to $OUTPUT_FILE" >&2
fi

# Output the final JSON array to stdout
echo "$RESULT"
