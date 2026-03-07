#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="${WORK_DIR:-${ROOT_DIR}/.build}"
DIST_DIR="${DIST_DIR:-${ROOT_DIR}/dist}"

STEAMCMD_DIR="${STEAMCMD_DIR:-${WORK_DIR}/steamcmd}"
GAME_DIR="${GAME_DIR:-${WORK_DIR}/icarus_server}"
EXTRACT_DIR="${EXTRACT_DIR:-${WORK_DIR}/extracted}"
MOD_STAGING_DIR="${MOD_STAGING_DIR:-${WORK_DIR}/mod_staging}"

GAME_APP_ID="${GAME_APP_ID:-2089300}"
STEAM_PLATFORM="${STEAM_PLATFORM:-}"

PAK_GLOB="${PAK_GLOB:-*.pak}"
PAK_INPUT="${PAK_INPUT:-}"
PAK_TARGET_FILE="${PAK_TARGET_FILE:-D_ProcessorRecipes.json}"
PAK_STRIP_PREFIX="${PAK_STRIP_PREFIX:-auto}"

MOD_NAME="${MOD_NAME:-icarus_qol}"
MOD_VERSION="${MOD_VERSION:-$(date +%Y.%m.%d-%H%M)}"
OUTPUT_PAK="${OUTPUT_PAK:-${DIST_DIR}/${MOD_NAME}.pak}"
RELEASE_VERSION_FILE="${RELEASE_VERSION_FILE:-${DIST_DIR}/release-version.txt}"
BUILD_UPDATED_FILE="${BUILD_UPDATED_FILE:-${DIST_DIR}/build-updated.flag}"
PACK_VERSION="${PACK_VERSION:-V11}"
PACK_MOUNT_POINT="${PACK_MOUNT_POINT:-../../../Icarus/Content/data/}"
PACK_PATH_HASH_SEED="${PACK_PATH_HASH_SEED:-115277563}"

log() {
  printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

resolve_strip_prefixes() {
  if [[ "${PAK_STRIP_PREFIX}" == "auto" ]]; then
    printf '%s\n' '../../../' 'C:/' ''
    return
  fi

  printf '%s\n' "${PAK_STRIP_PREFIX}"
}

list_pak_entries() {
  local pak_path="$1"
  local strip_prefix="$2"

  repak list -s "${strip_prefix}" "${pak_path}"
}

unpack_pak_with_prefix() {
  local pak_path="$1"
  local out_dir="$2"
  local strip_prefix="$3"

  repak unpack -f -s "${strip_prefix}" -o "${out_dir}" "${pak_path}"
}

install_steamcmd() {
  mkdir -p "${STEAMCMD_DIR}"
  if [[ -x "${STEAMCMD_DIR}/steamcmd.sh" ]]; then
    return
  fi

  log "Downloading steamcmd"
  curl -fsSL "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" -o "${STEAMCMD_DIR}/steamcmd_linux.tar.gz"
  tar -xzf "${STEAMCMD_DIR}/steamcmd_linux.tar.gz" -C "${STEAMCMD_DIR}"
}

update_game_server() {
  local force_platform_cmd=()
  mkdir -p "${GAME_DIR}"

  if [[ -n "${STEAM_PLATFORM}" ]]; then
    force_platform_cmd=("+@sSteamCmdForcePlatformType" "${STEAM_PLATFORM}")
    log "Forcing SteamCMD platform: ${STEAM_PLATFORM}"
  fi

  log "Updating app ${GAME_APP_ID} through anonymous steamcmd login"
  "${STEAMCMD_DIR}/steamcmd.sh" \
    "${force_platform_cmd[@]}" \
    +force_install_dir "${GAME_DIR}" \
    +login anonymous \
    +app_update "${GAME_APP_ID}" validate \
    +quit
}

detect_release_version() {
  local manifest_path="${GAME_DIR}/steamapps/appmanifest_${GAME_APP_ID}.acf"
  local build_id=""

  if [[ -f "${manifest_path}" ]]; then
    build_id="$(grep -m1 '"buildid"' "${manifest_path}" | awk -F'"' '{print $4}' || true)"
  fi

  if [[ -n "${build_id}" ]]; then
    mkdir -p "$(dirname "${RELEASE_VERSION_FILE}")"
    printf '%s\n' "${build_id}" > "${RELEASE_VERSION_FILE}"
    log "Detected Steam release version: ${build_id}"
  else
    log "Steam release version not found in appmanifest"
  fi
}

find_input_pak() {
  if [[ -n "${PAK_INPUT}" ]]; then
    if [[ -f "${PAK_INPUT}" ]]; then
      echo "${PAK_INPUT}"
      return
    fi
    echo "PAK_INPUT was provided but does not exist: ${PAK_INPUT}" >&2
    exit 1
  fi

  local candidates
  candidates="$(find "${GAME_DIR}" -type f -name "${PAK_GLOB}" -printf '%s\t%p\n' | sort -nr || true)"

  if [[ -z "${candidates}" ]]; then
    echo "No pak matched '${PAK_GLOB}' under ${GAME_DIR}" >&2
    exit 1
  fi

  while IFS=$'\t' read -r _size candidate_path; do
    if [[ -z "${candidate_path:-}" ]]; then
      continue
    fi

    while IFS= read -r strip_prefix; do
      if list_pak_entries "${candidate_path}" "${strip_prefix}" 2>/dev/null | grep -q "${PAK_TARGET_FILE}"; then
        echo "${candidate_path}"
        return
      fi
    done < <(resolve_strip_prefixes)
  done <<< "${candidates}"

  local found
  found="$(printf '%s\n' "${candidates}" | head -n 1 | cut -f2- || true)"
  if [[ -z "${found}" ]]; then
    echo "No pak matched '${PAK_GLOB}' under ${GAME_DIR}" >&2
    exit 1
  fi

  printf 'No pak contained %s; falling back to largest pak match\n' "${PAK_TARGET_FILE}" >&2

  echo "${found}"
}

unpack_pak() {
  local input_pak="$1"
  rm -rf "${EXTRACT_DIR}"
  mkdir -p "${EXTRACT_DIR}"

  log "Unpacking pak"

  while IFS= read -r strip_prefix; do
    if unpack_pak_with_prefix "${input_pak}" "${EXTRACT_DIR}" "${strip_prefix}" >/dev/null 2>&1; then
      log "Unpack succeeded using strip prefix: ${strip_prefix:-<empty>}"
      return
    fi
  done < <(resolve_strip_prefixes)

  echo "Failed to unpack ${input_pak} with configured strip-prefix strategy." >&2
  echo "Set PAK_STRIP_PREFIX explicitly (e.g. '../../../' or 'C:/') and retry." >&2
  exit 1
}

discover_source_data_root() {
  local marker
  marker="$(find "${EXTRACT_DIR}" -type f -name "D_ProcessorRecipes.json" | head -n 1 || true)"
  if [[ -z "${marker}" ]]; then
    echo "Could not find D_ProcessorRecipes.json in extracted pak." >&2
    echo "Set PAK_INPUT/PAK_GLOB to the correct source pak and retry." >&2
    exit 1
  fi

  dirname "$(dirname "${marker}")"
}

run_modifiers() {
  local source_data_root="$1"

  rm -rf "${MOD_STAGING_DIR}"
  mkdir -p "${MOD_STAGING_DIR}"

  log "Running modifiers.js"
  (
    cd "${ROOT_DIR}"
    SOURCE_DATA_ROOT="${source_data_root}" \
    OUTPUT_DATA_ROOT="${MOD_STAGING_DIR}" \
    node modifiers.js
  )
}

has_mod_changes() {
  local source_data_root="$1"
  local output_data_root="${MOD_STAGING_DIR}"
  local found_any=0

  while IFS= read -r generated_file; do
    found_any=1
    local relative_path="${generated_file#${output_data_root}/}"
    local source_file="${source_data_root}/${relative_path}"

    if [[ ! -f "${source_file}" ]]; then
      return 0
    fi

    if ! cmp -s "${source_file}" "${generated_file}"; then
      return 0
    fi
  done < <(find "${output_data_root}" -type f -name '*.json' | sort)

  if [[ "${found_any}" -eq 0 ]]; then
    echo "No generated JSON files were found under ${output_data_root}." >&2
    exit 1
  fi

  return 1
}

pack_mod() {
  mkdir -p "${DIST_DIR}"
  local temp_output_pak="${OUTPUT_PAK}.tmp"

  log "Packing mod pak"
  repak pack \
    --version "${PACK_VERSION}" \
    --mount-point "${PACK_MOUNT_POINT}" \
    --path-hash-seed "${PACK_PATH_HASH_SEED}" \
    "${MOD_STAGING_DIR}" \
    "${temp_output_pak}"

  if [[ -f "${OUTPUT_PAK}" ]] && cmp -s "${OUTPUT_PAK}" "${temp_output_pak}"; then
    rm -f "${temp_output_pak}" "${BUILD_UPDATED_FILE}"
    return 1
  fi

  mv -f "${temp_output_pak}" "${OUTPUT_PAK}"

  (cd "${DIST_DIR}" && sha256sum "$(basename "${OUTPUT_PAK}")" > "$(basename "${OUTPUT_PAK}").sha256")
  printf 'updated\n' > "${BUILD_UPDATED_FILE}"
  return 0
}

main() {
  require_cmd curl
  require_cmd tar
  require_cmd find
  require_cmd node
  require_cmd repak

  mkdir -p "${WORK_DIR}" "${DIST_DIR}"
  rm -f "${BUILD_UPDATED_FILE}"

  install_steamcmd
  update_game_server
  detect_release_version

  local input_pak
  input_pak="$(find_input_pak)"
  log "Using input pak: ${input_pak}"

  unpack_pak "${input_pak}"

  local source_data_root
  source_data_root="$(discover_source_data_root)"
  log "Detected source data root: ${source_data_root}"

  run_modifiers "${source_data_root}"

  if ! has_mod_changes "${source_data_root}"; then
    log "No data changes detected; exiting without repacking or updating artifacts"
    exit 0
  fi

  if ! pack_mod; then
    log "No binary pak changes detected; exiting without updating artifacts"
    exit 0
  fi

  log "Build completed"
  log "Output pak: ${OUTPUT_PAK}"
  log "Checksum: ${OUTPUT_PAK}.sha256"
}

main "$@"
