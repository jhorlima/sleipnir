#!/usr/bin/env bash
# PostToolUse hook: validates the edited file. Exit 2 sends the errors back to Claude.
set -u

edited_file=$(jq -r '.tool_input.file_path // empty')

if [ -z "$edited_file" ] || [ ! -f "$edited_file" ]; then
  exit 0
fi

project_dir="${CLAUDE_PROJECT_DIR:-.}"
errors=""

case "$edited_file" in
  *.sh)
    if ! syntax_output=$(bash -n "$edited_file" 2>&1); then
      errors="$syntax_output"
    fi
    if command -v shellcheck >/dev/null; then
      if ! lint_output=$(shellcheck "$edited_file" 2>&1); then
        errors="$errors$lint_output"
      fi
    fi
    ;;
  */compose.yaml | */compose/*.yaml)
    if [ -f "$project_dir/compose.yaml" ]; then
      if ! compose_output=$(docker compose --project-directory "$project_dir" config -q 2>&1); then
        errors="$compose_output"
      fi
    fi
    ;;
esac

if [ -n "$errors" ]; then
  echo "Validation failed for $edited_file:" >&2
  echo "$errors" >&2
  exit 2
fi

exit 0
