#!/usr/bin/env bash
# Validate that all patterns listed in README.md exist as files
set -e

MISSING=0
while IFS= read -r line; do
  file=$(echo "$line" | grep -oP 'patterns/\S+\.md' | head -1)
  [ -z "$file" ] && continue
  if [ ! -f "$file" ]; then
    echo "MISSING: $file"
    MISSING=$((MISSING + 1))
  else
    echo "  OK: $file"
  fi
done < README.md

if [ $MISSING -gt 0 ]; then
  echo ""
  echo "ERROR: $MISSING pattern file(s) missing."
  exit 1
fi

echo ""
echo "All patterns present ($(ls patterns/*.md | wc -l | tr -d ' ') files)."
