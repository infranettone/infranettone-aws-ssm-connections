#!/usr/bin/env bash

list_shell_scripts() {
  if command -v rg >/dev/null 2>&1; then
    rg --files -g "*.sh"
    return 0
  fi

  find . -type f -name "*.sh" | sed 's|^\./||'
}

run_shell_syntax_check() {
  local script=""
  local status=0
  local -a scripts=()

  mapfile -t scripts < <(list_shell_scripts)
  [[ "${#scripts[@]}" -gt 0 ]] || die "No shell scripts found to validate."

  for script in "${scripts[@]}"; do
    if ! bash -n "$script"; then
      status=1
    fi
  done

  [[ "$status" -eq 0 ]] || die "Bash syntax validation failed."
}

run_shellcheck() {
  local -a scripts=()

  if ! command -v shellcheck >/dev/null 2>&1; then
    warn "shellcheck is not installed. Skipping shellcheck step."
    return 0
  fi

  mapfile -t scripts < <(list_shell_scripts)
  [[ "${#scripts[@]}" -gt 0 ]] || die "No shell scripts found to lint."

  shellcheck "${scripts[@]}"
}

run_local_quality() {
  info "Running bash syntax checks..."
  run_shell_syntax_check

  info "Running shellcheck..."
  run_shellcheck

  info "Quality checks passed."
}
