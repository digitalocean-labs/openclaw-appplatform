#!/bin/bash
# Shared environment utilities for s6-overlay scripts

ENV_BASE="${ENV_BASE:-/run/s6/container_environment}"

# Auto-detect and persist all prefixed env vars (PREFIX_*)
# Creates a directory for each unique prefix found in environment
# Usage: persist_env_all_prefixes
persist_env_all_prefixes() {
  local prefixes
  prefixes=$(env | grep -oE '^[A-Z][A-Z0-9]*_' | sort -u)
  for prefix in $prefixes; do
    persist_env_prefix "$prefix"
  done
}

# Persist environment variables matching a prefix to s6 container environment
# Creates a prefix-specific subdirectory and writes to base for with-contenv
# Usage: persist_env_prefix "TS_" "RESTIC_" "MYAPP_"
persist_env_prefix() {
  local prefix
  for prefix in "$@"; do
    local prefix_dir="$ENV_BASE/$prefix"
    mkdir -p "$prefix_dir"

    while IFS='=' read -r var value; do
      # Write to prefix folder for selective loading via s6-envdir
      echo "$value" > "$prefix_dir/$var" || {
        echo "[persist-env] Warning: Failed to write $var to $prefix_dir" >&2
        continue
      }
      # Also write to base for with-contenv compatibility
      echo "$value" > "$ENV_BASE/$var"
    done < <(env | grep -E "^$prefix")
  done
}

# Persist single environment variables to a specific directory
# Usage: persist_env_var <directory> "VAR1" "VAR2=default" ...
persist_env_var() {
  local dir="$1"
  shift
  local target_dir="$ENV_BASE/$dir"
  mkdir -p "$target_dir"

  local arg var default value
  for arg in "$@"; do
    if [[ "$arg" == *=* ]]; then
      var="${arg%%=*}"
      default="${arg#*=}"
    else
      var="$arg"
      default=""
    fi

    value="${!var:-$default}"
    if [[ -n "$value" ]]; then
      echo "$value" > "$target_dir/$var" || {
        echo "[persist-env] Warning: Failed to write $var to $target_dir" >&2
        continue
      }
      # Also write to base for with-contenv compatibility
      echo "$value" > "$ENV_BASE/$var"
    fi
  done
}

# Write env var to all existing prefix directories and base
# Usage: persist_env_global "VAR1" "VAR2=default" ...
persist_env_global() {
  for prefix_dir in "$ENV_BASE"/*/; do
    [[ -d "$prefix_dir" ]] || continue
    local prefix
    prefix=$(basename "$prefix_dir")
    persist_env_var "$prefix" "$@"
  done
}

# Load environment variables from prefix directories
# Usage: source_env_prefix "TS_" "RESTIC_"
source_env_prefix() {
  local prefix
  for prefix in "$@"; do
    local prefix_dir="$ENV_BASE/$prefix"
    if [[ -d "$prefix_dir" ]]; then
      for file in "$prefix_dir"/*; do
        [[ -f "$file" ]] || continue
        local var
        var=$(basename "$file")
        export "$var"="$(cat "$file")"
      done
    fi
  done
}

# Exec command with only prefix env vars (clears ambient env)
# Usage: with_env_prefix [--user USER] PREFIX_ -- command args...
# When --user is specified, runs command in user's login shell
with_env_prefix() {
  local run_user=""

  # Check for --user option
  if [[ "$1" == "--user" ]]; then
    run_user="$2"
    shift 2
  fi

  local prefix="$1"
  shift
  [[ "$1" == "--" ]] && shift

  if [[ -n "$run_user" ]]; then
    # Use runuser for proper login shell, source env vars and user's bashrc inside the shell
    exec runuser -l "$run_user" -c "source /etc/s6-overlay/lib/env-utils.sh && [[ -f ~/.bashrc ]] && source ~/.bashrc; source_env_prefix $prefix && $*" 2>&1
  else
    exec env -i PATH="$PATH" /command/s6-envdir "$ENV_BASE/$prefix" "$@" 2>&1
  fi
}

# Apply permissions from YAML config file
# Usage: apply_permissions [config_file]
# Default config: /etc/digitalocean/permissions.yaml
apply_permissions() {
  local config="${1:-/etc/digitalocean/permissions.yaml}"

  if [[ ! -f "$config" ]]; then
    echo "[permissions] Config not found: $config" >&2
    return 1
  fi

  local count
  count=$(yq '.permissions | length' "$config")

  for i in $(seq 0 $((count - 1))); do
    local path mode user group
    path=$(yq -r ".permissions[$i].path" "$config")
    mode=$(yq -r ".permissions[$i].mode // \"\"" "$config")
    user=$(yq -r ".permissions[$i].user // \"\"" "$config")
    group=$(yq -r ".permissions[$i].group // \"\"" "$config")
    # yq returns "null" for missing fields with -r
    [[ "$mode" == "null" ]] && mode=""
    [[ "$user" == "null" ]] && user=""
    [[ "$group" == "null" ]] && group=""

    # Skip if base path doesn't exist
    local base_path="${path%%\**}"
    base_path="${base_path%%/\*}"
    if [[ ! -e "$base_path" ]]; then
      echo "[permissions] Warning: path does not exist: $path" >&2
      continue
    fi

    # Check if glob pattern matches anything
    local matched=false
    case "$path" in
      *\*)
        # shellcheck disable=SC2086
        for _ in $path; do matched=true; break; done
        if [[ "$matched" == "false" ]]; then
          echo "[permissions] Warning: pattern matched no files: $path" >&2
          continue
        fi
        ;;
    esac

    # Apply mode
    if [[ -n "$mode" ]]; then
      case "$path" in
        *\*) chmod "$mode" $path 2>/dev/null || true ;;
        *) chmod "$mode" "$path" 2>/dev/null || true ;;
      esac
    fi

    # Apply ownership
    if [[ -n "$user" || -n "$group" ]]; then
      local owner="${user}:${group}"
      owner="${owner#:}"  # Remove leading : if no user
      owner="${owner%:}"  # Remove trailing : if no group
      if [[ -n "$owner" ]]; then
        case "$path" in
          *\*) chown "$owner" $path 2>/dev/null || true ;;
          *) chown "$owner" "$path" 2>/dev/null || true ;;
        esac
      fi
    fi
  done
}
