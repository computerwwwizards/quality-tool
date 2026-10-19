#!/usr/bin/env bash
set -euo pipefail

METRICS=(
  ncloc
  sqale_index
  sqale_debt_ratio
  sqale_rating
  code_smells
  bugs
  vulnerabilities
  security_hotspots
  coverage
  duplicated_lines_density
  alert_status
)

SONARQUBE_IMAGE="${SONARQUBE_IMAGE:-sonarqube:9.9.8-community}"
SCANNER_IMAGE="${SCANNER_IMAGE:-sonarsource/sonar-scanner-cli:11.3.1.1910_7.1.0}"
SONAR_PORT="${SONAR_PORT:-9000}"
SONAR_ADMIN_USER="${SONAR_ADMIN_USER:-admin}"
SONAR_URL="http://127.0.0.1:${SONAR_PORT}"
WAIT_SECONDS="${QUALITY_WAIT_SECONDS:-300}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOKEN_DIR="$ROOT/.quality"
if [[ -z "${SONAR_ADMIN_PASSWORD:-}" && -r "$TOKEN_DIR/admin.password" ]]; then
  SONAR_ADMIN_PASSWORD="$(<"$TOKEN_DIR/admin.password")"
fi
SONAR_ADMIN_PASSWORD="${SONAR_ADMIN_PASSWORD:-admin}"
NETWORK=quality-net
CONTAINER=quality-sonarqube
SCANNER_CACHE=quality-scanner-cache
VOLUMES=(quality-sonarqube-data quality-sonarqube-extensions quality-sonarqube-logs "$SCANNER_CACHE")

die() { echo "quality: $*" >&2; exit 1; }

usage() {
  cat >&2 <<EOF
usage: $(basename "$0") <command>
  up                           start SonarQube on 127.0.0.1:$SONAR_PORT and wait until UP
  token <project-key>          create the project and a fresh analysis token
  reference <file> <project-key>
                               apply the reference quality profiles and gate to the project
  scan <repo-path> <project-key> [-Dsonar.key=value ...]
                               run the scanner on the repo (read-only) and wait for processing
  export <project-key> [out]   write metrics CSV (default reports/<key>.csv)
  down [--purge]               remove the container (--purge: volumes and network too)
EOF
  exit 2
}

api() {
  local method=$1 endpoint=$2
  shift 2
  curl -fsS -u "$SONAR_ADMIN_USER:$SONAR_ADMIN_PASSWORD" -X "$method" "$SONAR_URL/api/$endpoint" "$@" \
    || die "request failed: $method api/$endpoint"
}

container_state() {
  # docker 29 prints a blank line on stdout for a missing object, so ignore its output on failure.
  local s
  s="$(docker container inspect -f '{{.State.Status}}' "$CONTAINER" 2>/dev/null)" || s=missing
  echo "$s"
}

cmd_up() {
  docker network inspect "$NETWORK" >/dev/null 2>&1 || docker network create "$NETWORK" >/dev/null
  local v
  for v in "${VOLUMES[@]}"; do
    docker volume inspect "$v" >/dev/null 2>&1 || docker volume create "$v" >/dev/null
  done

  local state
  state="$(container_state)"
  if [[ "$state" != missing ]]; then
    local image
    image="$(docker inspect -f '{{.Config.Image}}' "$CONTAINER")"
    [[ "$image" == "$SONARQUBE_IMAGE" ]] \
      || die "$CONTAINER runs $image, not $SONARQUBE_IMAGE. Run '$0 down --purge' first, which deletes the analyses."
  fi

  case "$state" in
    missing)
      # Bootstrap checks off so a default vm.max_map_count (65530) works without sudo.
      # Telemetry off so the server sends no usage statistics to SonarSource.
      docker run -d --name "$CONTAINER" --network "$NETWORK" \
        -p "127.0.0.1:${SONAR_PORT}:9000" \
        -e SONAR_ES_BOOTSTRAP_CHECKS_DISABLE=true \
        -e SONAR_TELEMETRY_ENABLE=false \
        -v quality-sonarqube-data:/opt/sonarqube/data \
        -v quality-sonarqube-extensions:/opt/sonarqube/extensions \
        -v quality-sonarqube-logs:/opt/sonarqube/logs \
        "$SONARQUBE_IMAGE" >/dev/null
      ;;
    running) ;;
    *) docker start "$CONTAINER" >/dev/null ;;
  esac

  local deadline=$((SECONDS + WAIT_SECONDS)) status=""
  while ((SECONDS < deadline)); do
    status="$(curl -fsS "$SONAR_URL/api/system/status" 2>/dev/null | jq -r '.status' 2>/dev/null || true)"
    [[ "$status" == UP ]] && { echo "SonarQube is UP at $SONAR_URL"; return; }
    [[ "$(container_state)" == running ]] || break
    sleep 3
  done
  docker logs --tail 30 "$CONTAINER" >&2 || true
  die "SonarQube not UP after ${WAIT_SECONDS}s (last status: ${status:-unreachable}, container: $(container_state))"
}

require_admin() {
  api GET authentication/validate | jq -e '.valid' >/dev/null \
    || die "SonarQube rejected the password of '$SONAR_ADMIN_USER'. If you changed it in the web interface, write it to .quality/admin.password or export SONAR_ADMIN_PASSWORD."
}

token_file() { echo "$TOKEN_DIR/$1.token"; }

cmd_token() {
  require_admin
  local key=$1 name="quality-$1"
  if [[ "$(api GET projects/search -G --data-urlencode "projects=$key" | jq '.components | length')" == 0 ]]; then
    api POST projects/create --data-urlencode "project=$key" --data-urlencode "name=$key" >/dev/null
    echo "created project $key"
  fi

  # A token value cannot be read back, so an existing one is useless here: replace it.
  if api GET user_tokens/search -G --data-urlencode "login=$SONAR_ADMIN_USER" \
      | jq -e --arg n "$name" 'any(.userTokens[]; .name == $n)' >/dev/null; then
    api POST user_tokens/revoke --data-urlencode "name=$name" >/dev/null
  fi
  local token
  token="$(api POST user_tokens/generate --data-urlencode "name=$name" \
    --data-urlencode type=PROJECT_ANALYSIS_TOKEN --data-urlencode "projectKey=$key" | jq -r '.token')"

  mkdir -p "$TOKEN_DIR"
  local file tmp
  file="$(token_file "$key")"
  tmp="$(mktemp "$TOKEN_DIR/.token.XXXXXX")"
  chmod 600 "$tmp"
  printf '%s\n' "$token" >"$tmp"
  mv "$tmp" "$file"
  echo "token written to $file"
}

cmd_reference() {
  require_admin
  local file=$1 key=$2
  jq -e '.gate.name and (.profiles | length > 0)' "$file" >/dev/null 2>&1 || die "not a reference file: $file"
  [[ "$(api GET projects/search -G --data-urlencode "projects=$key" | jq '.components | length')" != 0 ]] \
    || die "no project $key. Run '$0 token $key' first."

  local lang name expected parent actual
  # parent comes last: read collapses consecutive tabs, so an empty field must not sit in the middle.
  while IFS=$'\t' read -r lang name expected parent; do
    if ! api GET qualityprofiles/search -G --data-urlencode "language=$lang" \
        | jq -e --arg n "$name" 'any(.profiles[]; .name == $n)' >/dev/null; then
      [[ -n "$parent" ]] || die "profile $name ($lang) has no parent in $file and does not exist on the local server"
      api POST qualityprofiles/create --data-urlencode "language=$lang" --data-urlencode "name=$name" >/dev/null
    fi
    if [[ -n "$parent" ]]; then
      api POST qualityprofiles/change_parent --data-urlencode "language=$lang" \
        --data-urlencode "qualityProfile=$name" --data-urlencode "parentQualityProfile=$parent"
    fi
    api POST qualityprofiles/add_project --data-urlencode "language=$lang" \
      --data-urlencode "qualityProfile=$name" --data-urlencode "project=$key"
    actual="$(api GET qualityprofiles/search -G --data-urlencode "language=$lang" \
      | jq -r --arg n "$name" '.profiles[] | select(.name == $n) | .activeRuleCount')"
    [[ "$actual" == "$expected" ]] \
      || echo "quality: warning: $name has $actual active rules, the reference has $expected" >&2
    echo "profile $name ($lang): $actual rules${parent:+, parent $parent}"
  done < <(jq -r '.profiles[] | [.language, .name, .activeRules, .parent // ""] | @tsv' "$file")

  local gate id
  gate="$(jq -r '.gate.name' "$file")"
  if ! api GET qualitygates/list | jq -e --arg n "$gate" 'any(.qualitygates[]; .name == $n)' >/dev/null; then
    api POST qualitygates/create --data-urlencode "name=$gate" >/dev/null
  fi
  # Replace every condition so the local gate converges to the file, whatever it held before.
  for id in $(api GET qualitygates/show -G --data-urlencode "name=$gate" | jq -r '.conditions[]?.id'); do
    api POST qualitygates/delete_condition --data-urlencode "id=$id"
  done
  local metric op error
  while IFS=$'\t' read -r metric op error; do
    api POST qualitygates/create_condition --data-urlencode "gateName=$gate" --data-urlencode "metric=$metric" \
      --data-urlencode "op=$op" --data-urlencode "error=$error" >/dev/null
  done < <(jq -r '.gate.conditions[] | [.metric, .op, .error] | @tsv' "$file")
  api POST qualitygates/select --data-urlencode "gateName=$gate" --data-urlencode "projectKey=$key"
  echo "gate $gate: $(jq '.gate.conditions | length' "$file") conditions"
}

cmd_scan() {
  local repo key=$2
  repo="$(cd "$1" && pwd)" || die "not a directory: $1"
  shift 2
  local prop
  for prop in "$@"; do
    [[ "$prop" == -D*=* ]] || die "extra scan arguments must look like -Dsonar.key=value, got: $prop"
  done
  local file
  file="$(token_file "$key")"
  [[ -r "$file" ]] || die "missing $file. Run '$0 token $key' first."

  # The work dir lives here, not in the analyzed repo, so the repo can be mounted read-only.
  local work="$TOKEN_DIR/work/$key"
  local report="$work/report-task.txt"
  mkdir -p "$work"
  rm -f "$report"
  # Same absolute path inside the container so absolute LCOV SF: paths resolve.
  # sonar.host.url goes on the command line because it outranks a sonar.host.url in the
  # repo's sonar-project.properties, which may point at a remote server.
  # The token goes through the environment, not argv, so `ps` does not show it.
  SONAR_TOKEN="$(<"$file")" docker run --rm --network "$NETWORK" --user "$(id -u):$(id -g)" \
    -e SONAR_TOKEN \
    -e SCANNER_WORKDIR_PATH="$work" \
    -v "$SCANNER_CACHE:/opt/sonar-scanner/.sonar" \
    -v "$repo:$repo:ro" -v "$work:$work" -w "$repo" \
    "$SCANNER_IMAGE" "-Dsonar.host.url=http://$CONTAINER:9000" "-Dsonar.projectKey=$key" "$@"

  [[ -r "$report" ]] || die "scanner did not write $report"
  local task
  task="$(sed -n 's/^ceTaskId=//p' "$report")"
  [[ -n "$task" ]] || die "no ceTaskId in $report"

  local deadline=$((SECONDS + WAIT_SECONDS)) status=""
  while ((SECONDS < deadline)); do
    status="$(api GET "ce/task?id=$task" | jq -r '.task.status')"
    case "$status" in
      SUCCESS) echo "analysis $task processed"; return ;;
      FAILED | CANCELED) die "analysis task $task ended $status" ;;
    esac
    sleep 2
  done
  die "analysis task $task still $status after ${WAIT_SECONDS}s"
}

cmd_export() {
  require_admin
  local key=$1 out=${2:-$ROOT/reports/$1.csv}
  local registry
  registry="$(printf '%s\n' "${METRICS[@]}" | jq -R . | jq -sc .)"

  local known keys skipped
  known="$(api GET "metrics/search?ps=500" | jq -c '[.metrics[].key]')"
  keys="$(jq -nc --argjson r "$registry" --argjson k "$known" '[$r[] | select(IN($k[]))]')"
  skipped="$(jq -nr --argjson r "$registry" --argjson k "$keys" '$r - $k | join(" ")')"
  [[ -z "$skipped" ]] || echo "quality: warning: server lacks metrics, skipped: $skipped" >&2

  local measures date
  measures="$(api GET "measures/component" -G --data-urlencode "component=$key" \
    --data-urlencode "metricKeys=$(jq -r 'join(",")' <<<"$keys")" --data-urlencode additionalFields=metrics)"
  date="$(api GET "project_analyses/search" -G --data-urlencode "project=$key" --data-urlencode ps=1 \
    | jq -r '.analyses[0].date // ""')"

  mkdir -p "$(dirname "$out")"
  local tmp
  tmp="$(mktemp "$(dirname "$out")/.export.XXXXXX")"
  jq -r --arg project "$key" --arg date "$date" --argjson keys "$keys" '
    (.metrics | map({key: .key, value: .}) | from_entries) as $meta
    | (.component.measures | map({key: .metric, value: .value}) | from_entries) as $values
    | ["project_key", "analysis_date", "metric_key", "metric_name", "metric_type", "value"],
      ($keys[] | [$project, $date, ., $meta[.].name, $meta[.].type, ($values[.] // "")])
    | @csv' <<<"$measures" >"$tmp"
  mv "$tmp" "$out"
  echo "wrote $out"
}

cmd_down() {
  docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
  if [[ "${1:-}" == --purge ]]; then
    local v
    for v in "${VOLUMES[@]}"; do
      if docker volume inspect "$v" >/dev/null 2>&1; then docker volume rm "$v" >/dev/null; fi
    done
    if docker network inspect "$NETWORK" >/dev/null 2>&1; then docker network rm "$NETWORK" >/dev/null; fi
  fi
  echo "down${1:+ $1}"
}

for dep in docker curl jq; do
  command -v "$dep" >/dev/null || die "missing dependency: $dep"
done

case "${1:-} $#" in
  "up 1") cmd_up ;;
  "token 2") cmd_token "$2" ;;
  "reference 3") cmd_reference "$2" "$3" ;;
  scan\ *) (($# >= 3)) || usage; cmd_scan "${@:2}" ;;
  "export 2" | "export 3") cmd_export "${@:2}" ;;
  "down 1") cmd_down ;;
  "down 2") [[ "$2" == --purge ]] || usage; cmd_down --purge ;;
  *) usage ;;
esac
