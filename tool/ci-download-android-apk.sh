#!/usr/bin/env bash
set -euo pipefail

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required but not installed." >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required but not installed." >&2
  exit 1
fi

: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY must be set}"
: "${GITHUB_TOKEN:?GITHUB_TOKEN must be set}"
: "${SOURCE_WORKFLOW:?SOURCE_WORKFLOW must be set (e.g. build-android.yml)}"
: "${ARTIFACT_NAME:?ARTIFACT_NAME must be set (e.g. android-apk)}"

SOURCE_BRANCH="${SOURCE_BRANCH:-}"
BRANCH_LABEL="${SOURCE_BRANCH:-all branches}"
DOWNLOAD_DIR="${ARTIFACT_DOWNLOAD_DIR:-downloaded-artifact}"

API_ROOT="https://api.github.com"
RUNS_QUERY_PARAMS="status=success&per_page=1"
if [[ -n "$SOURCE_BRANCH" ]]; then
  ENCODED_BRANCH=$(jq -rn --arg v "$SOURCE_BRANCH" '$v|@uri')
  RUNS_QUERY_PARAMS+="&branch=${ENCODED_BRANCH}"
fi

runs_url="${API_ROOT}/repos/${GITHUB_REPOSITORY}/actions/workflows/${SOURCE_WORKFLOW}/runs?${RUNS_QUERY_PARAMS}"
runs_json=$(curl -fsSL -H "Authorization: Bearer ${GITHUB_TOKEN}" -H "Accept: application/vnd.github+json" "$runs_url")
if ! run_id=$(echo "$runs_json" | jq -er '.workflow_runs[0].id'); then
  echo "No successful workflow runs found for '${SOURCE_WORKFLOW}' on ${BRANCH_LABEL}." >&2
  exit 1
fi

artifacts_url="${API_ROOT}/repos/${GITHUB_REPOSITORY}/actions/runs/${run_id}/artifacts?per_page=100"
artifacts_json=$(curl -fsSL -H "Authorization: Bearer ${GITHUB_TOKEN}" -H "Accept: application/vnd.github+json" "$artifacts_url")
if ! artifact_json=$(echo "$artifacts_json" | jq -er --arg name "$ARTIFACT_NAME" '.artifacts | map(select(.name == $name and (.expired | not))) | .[0]'); then
  echo "Artifact '${ARTIFACT_NAME}' was not found in workflow run ${run_id}." >&2
  exit 1
fi
artifact_id=$(echo "$artifact_json" | jq -er '.id')
artifact_name=$(echo "$artifact_json" | jq -er '.name')

zip_path="${DOWNLOAD_DIR}.zip"
rm -rf "$DOWNLOAD_DIR"
rm -f "$zip_path"
mkdir -p "$DOWNLOAD_DIR"

download_url="${API_ROOT}/repos/${GITHUB_REPOSITORY}/actions/artifacts/${artifact_id}/zip"
curl -fsSL -H "Authorization: Bearer ${GITHUB_TOKEN}" -H "Accept: application/vnd.github+json" -o "$zip_path" -L "$download_url"

unzip -q "$zip_path" -d "$DOWNLOAD_DIR"
rm -f "$zip_path"

apk_path=$(find "$DOWNLOAD_DIR" -type f -name "*.apk" | head -n 1 || true)
if [[ -z "$apk_path" ]]; then
  echo "No APK file found in artifact '${artifact_name}'." >&2
  exit 1
fi

echo "Downloaded artifact '${artifact_name}' from run ${run_id}."
echo "APK available at: ${apk_path}"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "apk-path=${apk_path}"
    echo "workflow-run-id=${run_id}"
  } >> "${GITHUB_OUTPUT}"
fi
