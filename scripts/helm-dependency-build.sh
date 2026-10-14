#!/usr/bin/env sh
# Build local Helm dependencies from the leaves up before packaging the parent.
# Usage: sh scripts/helm-dependency-build.sh <chart-directory>
# Repository URLs in Chart.yaml use the repo's one-line repository: convention.

set -eu

build_chart() (
  chart_dir=$(cd "$1" && pwd)
  ancestry=$2
  case "$ancestry" in
    *"|$chart_dir|"*)
      echo "Local Helm dependency cycle: $chart_dir" >&2
      exit 1
      ;;
  esac
  ancestry="$ancestry|$chart_dir|"

  if [ ! -f "$chart_dir/Chart.yaml" ]; then
    echo "Missing Chart.yaml: $chart_dir" >&2
    exit 1
  fi

  # Helm packages file:// dependencies as they are; it does not recursively
  # populate their charts/ directories. Each child must be built first.
  repositories=$(awk '
    $1 == "repository:" {
      value = $2
      gsub(/["\047\r]/, "", value)
      if (value ~ /^file:\/\//) {
        sub(/^file:\/\//, "", value)
        if (!seen[value]++) print value
      }
    }
  ' "$chart_dir/Chart.yaml")

  while IFS= read -r repository; do
    [ -n "$repository" ] || continue
    case "$repository" in
      /*) child_dir=$repository ;;
      *) child_dir="$chart_dir/$repository" ;;
    esac
    build_chart "$child_dir" "$ancestry" || exit 1
  done <<EOF
$repositories
EOF

  if grep -q '^dependencies:' "$chart_dir/Chart.yaml"; then
    echo ">> helm dependency build $chart_dir"
    helm dependency build "$chart_dir" --skip-refresh
  fi
)

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <chart-directory>" >&2
  exit 2
fi
build_chart "$1" ""
