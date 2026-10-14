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
#   - template-render with every values.<example>.yaml the chart ships
#     (values.minimal.yaml, values.full.yaml, values.direct.yaml and the like);
#     the default values.yaml itself is not rendered. Charts that only ship a
#     default values.yaml needing runtime config (console) are lint-only.

fail=0

for chartyaml in */Chart.yaml; do
  chart=${chartyaml%/Chart.yaml}

  # Populate nested file:// dependencies before Helm packages their parents.
  # Alphabetical chart order alone is insufficient for namespace -> subnet.
  if ! sh "$(dirname "$0")/helm-dependency-build.sh" "$chart"; then
    fail=1
    continue
  fi

  render_files=""
  [ -f "$chart/values.minimal.yaml" ] && render_files="$render_files values.minimal.yaml"
  [ -f "$chart/values.full.yaml" ] && render_files="$render_files values.full.yaml"
  for f in "$chart"/values.*.yaml; do
    [ -f "$f" ] || continue
    f=${f##*/}
    case " $render_files " in *" $f "*) ;; *) render_files="$render_files $f" ;; esac
  done

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
