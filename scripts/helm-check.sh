#!/usr/bin/env sh
# Validate every Helm chart in the repo: `helm lint` + `helm template` render.
# Used by the lefthook pre-push hook (see lefthook.yml). Collects all failures
# and exits non-zero if any chart is broken.
#
# Values-file strategy (matches charts/CONVENTIONS.md):
#   - lint with values.minimal.yaml when present (the working example), else the
#     default values.yaml. Order-driven charts (ingress-gateway) intentionally
#     ship a default values.yaml without naming, so it would not lint - the
#     minimal example is the right input for them.
#   - template-render with values.minimal.yaml and values.full.yaml when present.
#     Charts that only ship a default values.yaml needing runtime config
#     (console) are lint-only.

fail=0

for chartyaml in */Chart.yaml; do
  chart=${chartyaml%/Chart.yaml}

  render_files=""
  [ -f "$chart/values.minimal.yaml" ] && render_files="$render_files values.minimal.yaml"
  [ -f "$chart/values.full.yaml" ] && render_files="$render_files values.full.yaml"

  # File used for linting: first render file, or the default values.yaml.
  lint_file=$(echo "$render_files" | awk '{print $1}')
  [ -z "$lint_file" ] && lint_file="values.yaml"

  echo ">> helm lint $chart -f $chart/$lint_file"
  if ! helm lint "$chart" -f "$chart/$lint_file"; then
    fail=1
  fi

  for f in $render_files; do
    echo ">> helm template $chart -f $chart/$f"
    if ! helm template release "$chart" -f "$chart/$f" >/dev/null; then
      fail=1
    fi
  done
done

if [ "$fail" -ne 0 ]; then
  echo "helm validation failed" >&2
  exit 1
fi

echo "all charts valid"
