#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

repo="$(git remote get-url origin | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##')"
current_sha="$(git rev-parse HEAD)"

steam_payload="$(curl -fsSL "https://api.steamcmd.net/v1/info/2089300")"
current_steam_buildid="$(printf '%s' "${steam_payload}" | grep -Eo '"public"[[:space:]]*:[[:space:]]*\{[[:space:]]*"buildid"[[:space:]]*:[[:space:]]*"[0-9]+"' | head -n1 | grep -Eo '[0-9]+' || true)"

release_json="$(curl -fsSL "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null || true)"
meta_url="$(printf '%s' "${release_json}" | grep -Eo '"browser_download_url"[[:space:]]*:[[:space:]]*"[^"]*release-meta.json"' | head -n1 | sed -E 's/.*"browser_download_url"[[:space:]]*:[[:space:]]*"([^"]*)"/\1/' || true)"

if [[ -z "${meta_url}" ]]; then
  should_run="true"
  reason="no_release_meta"

  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    {
      echo "should_run=${should_run}"
      echo "reason=${reason}"
      echo "current_steam_buildid=${current_steam_buildid}"
      echo "current_sha=${current_sha}"
      echo "last_source_sha="
      echo "last_steam_buildid="
    } >> "${GITHUB_OUTPUT}"
  fi

  echo "repo=${repo}"
  echo "current_sha=${current_sha}"
  echo "current_steam_buildid=${current_steam_buildid}"
  echo "last_source_sha=<none>"
  echo "last_steam_buildid=<none>"
  echo "should_run=${should_run} (reason: ${reason})"
  exit 0
fi

meta_json="$(curl -fsSL "${meta_url}")"
last_source_sha="$(printf '%s' "${meta_json}" | grep -Eo '"source_sha"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n1 | sed -E 's/.*"source_sha"[[:space:]]*:[[:space:]]*"([^"]*)"/\1/' || true)"
last_steam_buildid="$(printf '%s' "${meta_json}" | grep -Eo '"steam_buildid"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n1 | sed -E 's/.*"steam_buildid"[[:space:]]*:[[:space:]]*"([^"]*)"/\1/' || true)"

should_run=false
reason="unchanged"

if [[ "${current_sha}" != "${last_source_sha}" ]]; then
  should_run=true
  reason="source_sha_changed"
fi

if [[ "${current_steam_buildid}" != "${last_steam_buildid}" ]]; then
  should_run=true
  if [[ "${reason}" == "unchanged" ]]; then
    reason="steam_buildid_changed"
  else
    reason="source_and_steam_changed"
  fi
fi

echo "repo=${repo}"
echo "current_sha=${current_sha}"
echo "current_steam_buildid=${current_steam_buildid}"
echo "last_source_sha=${last_source_sha}"
echo "last_steam_buildid=${last_steam_buildid}"
echo "should_run=${should_run} (reason: ${reason})"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "should_run=${should_run}"
    echo "reason=${reason}"
    echo "current_steam_buildid=${current_steam_buildid}"
    echo "current_sha=${current_sha}"
    echo "last_source_sha=${last_source_sha}"
    echo "last_steam_buildid=${last_steam_buildid}"
  } >> "${GITHUB_OUTPUT}"
fi
