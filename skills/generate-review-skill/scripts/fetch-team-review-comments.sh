#!/usr/bin/env bash
# ABOUTME: Fetches human review comments from team GitLab projects (not user-authored MRs).
# ABOUTME: Used when the current user lacks enough personal MR history to mine patterns from.

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
DAYS="${1:-90}"
PARALLELISM="${2:-8}"
OUTPUT_FILE="${3:-}"
# PROJECTS: comma-separated project paths, e.g. "org/team/repo1,org/team/repo2"
# Can be set as env var or discovered interactively
PROJECTS="${PROJECTS:-}"
BOT_PATTERN="bot|service-|async-agent|gitlab|tfbuddy|dependabot|renovate|prjiracheck|droid"
NOISE_PATTERN="vercel\.com|(^|\n)\s*(Preview|Production) deployment:|(^|\n)\s*Inspect:\s*https://|(^|\n)\s*Build logs:\s*https://|(^|\n)\s*✅\s*Ready in"

# ---------------------------------------------------------------------------
# Preflight checks
# ---------------------------------------------------------------------------
[[ "$DAYS" =~ ^[0-9]+$ ]] || { echo "ERROR: DAYS must be a positive integer" >&2; exit 1; }

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
# Resolve current user (to exclude their own comments from results)
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
# Discover project paths if not provided
# ---------------------------------------------------------------------------
if [[ -z "$PROJECTS" ]]; then
  # Try to detect from current git remote
  if git rev-parse --git-dir &>/dev/null; then
    REMOTE_URL=$(git remote get-url origin 2>/dev/null || true)
    if [[ -n "$REMOTE_URL" ]]; then
      # Extract path from git@gitlab.com:org/repo.git or https://gitlab.com/org/repo
      DETECTED=$(echo "$REMOTE_URL" \
        | sed 's|git@gitlab\.com:||' \
        | sed 's|https://gitlab\.com/||' \
        | sed 's|\.git$||')
      if [[ -n "$DETECTED" ]]; then
        echo "  Auto-detected project from git remote: $DETECTED" >&2
        PROJECTS="$DETECTED"
      fi
    fi
  fi
fi

if [[ -z "$PROJECTS" ]]; then
  echo "ERROR: No projects specified. Set PROJECTS env var:" >&2
  echo "  PROJECTS=\"org/team/repo1,org/team/repo2\" $0" >&2
  echo "  Or run from inside a git repo with a GitLab remote." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Fetch merged MRs from each project
# ---------------------------------------------------------------------------
AFTER_DATE=$(date -v-"${DAYS}"d +%Y-%m-%dT00:00:00Z 2>/dev/null \
  || date -d "${DAYS} days ago" +%Y-%m-%dT00:00:00Z)

TMPDIR_WORK=$(mktemp -d)
trap 'rm -rf "$TMPDIR_WORK"' EXIT

echo "Fetching merged MRs from projects: $PROJECTS" >&2
echo "  Looking back ${DAYS} days (since ${AFTER_DATE})" >&2

IFS=',' read -ra PROJECT_LIST <<< "$PROJECTS"

MR_LIST="[]"
for PROJECT_PATH in "${PROJECT_LIST[@]}"; do
  PROJECT_PATH=$(echo "$PROJECT_PATH" | tr -d ' ')
  # URL-encode the project path (replace / with %2F)
  PROJECT_ENCODED=$(printf '%s' "$PROJECT_PATH" | python3 -c "import sys, urllib.parse; print(urllib.parse.quote(sys.stdin.read(), safe=''))" 2>/dev/null \
    || printf '%s' "$PROJECT_PATH" | sed 's|/|%2F|g')

  echo "  Fetching MRs from $PROJECT_PATH..." >&2
  PROJECT_MRS=$(api_get "projects/${PROJECT_ENCODED}/merge_requests?state=merged&created_after=${AFTER_DATE}&per_page=100" || echo "[]")

  # Filter to MRs that have human comments, adding project context
  PROJECT_MR_LIST=$(echo "$PROJECT_MRS" | jq -c --arg project "$PROJECT_PATH" '
    [.[] | select(.user_notes_count > 0) | {
      project_id: .project_id,
      iid: .iid,
      title: .title,
      web_url: .web_url,
      user_notes_count: .user_notes_count,
      project_path: $project
    }]
  ')

  PROJECT_COUNT=$(echo "$PROJECT_MR_LIST" | jq 'length')
  echo "    Found $PROJECT_COUNT MRs with comments" >&2

  MR_LIST=$(echo "$MR_LIST $PROJECT_MR_LIST" | jq -s 'add | unique_by(.project_id, .iid)')
done

MR_COUNT=$(echo "$MR_LIST" | jq 'length')
TOTAL_NOTES=$(echo "$MR_LIST" | jq '[.[].user_notes_count] | add // 0')
echo "  Total: ${MR_COUNT} MRs with comments (~${TOTAL_NOTES} notes)" >&2

if [[ "$MR_COUNT" -eq 0 ]]; then
  echo "[]"
  exit 0
fi

# ---------------------------------------------------------------------------
# Fetch discussions for each MR in parallel
# ---------------------------------------------------------------------------
echo "$MR_LIST" | jq -c '.[]' > "$TMPDIR_WORK/mrs.jsonl"
MR_LINE_COUNT=$(wc -l < "$TMPDIR_WORK/mrs.jsonl" | tr -d ' ')

echo "Fetching discussions (parallelism: ${PARALLELISM})..." >&2

cat > "$TMPDIR_WORK/worker.sh" << 'WORKER_EOF'
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
chmod +x "$TMPDIR_WORK/worker.sh"

seq 1 "$MR_LINE_COUNT" | xargs -P "$PARALLELISM" -I {} \
  "$TMPDIR_WORK/worker.sh" {} "$TMPDIR_WORK/mrs.jsonl" "$USERNAME" "$BOT_PATTERN" "$NOISE_PATTERN" "$TMPDIR_WORK"

# ---------------------------------------------------------------------------
# Merge all results into a single JSON array
# ---------------------------------------------------------------------------
COMMENT_COUNT=0
if ls "$TMPDIR_WORK"/result_*.jsonl &>/dev/null; then
  RESULT=$(cat "$TMPDIR_WORK"/result_*.jsonl | jq -s 'unique_by(.author, .body, .file, .line, .mr_url)' 2>/dev/null || echo "[]")
  COMMENT_COUNT=$(echo "$RESULT" | jq 'length')
else
  RESULT="[]"
fi

echo "" >&2
echo "Done. Extracted ${COMMENT_COUNT} human review comments from team MRs." >&2

if [[ -n "$OUTPUT_FILE" ]]; then
  printf '%s\n' "$RESULT" > "$OUTPUT_FILE"
  echo "Wrote JSON output to $OUTPUT_FILE" >&2
fi

echo "$RESULT"
