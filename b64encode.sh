#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 \"string to encode\""
  exit 1
fi

# Join all args into one string (preserves spaces)
INPUT="$*"

# Encode without trailing newline
printf '%s' "${INPUT}" | base64
