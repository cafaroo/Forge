#!/usr/bin/env bash
set -euo pipefail

release=${1:?Usage: deploy-prod.sh prod-vYYYY.MM.DD.N}
if [[ ! "$release" =~ ^prod-v[0-9]{4}\.[0-9]{2}\.[0-9]{2}\.[0-9]+$ ]]; then
  echo "Expected a prod-vYYYY.MM.DD.N tag" >&2
  exit 2
fi

repo_dir=${FORGE_REPO_DIR:-/opt/forge-src}
env_file=${FORGE_ENV_FILE:-/etc/forge-prod/forge.env}
test -r "$env_file"
cd "$repo_dir"

git fetch --prune origin '+refs/heads/prod:refs/remotes/origin/prod'
git fetch --tags origin
commit=$(git rev-parse --verify "refs/tags/${release}^{commit}")
git merge-base --is-ancestor "$commit" origin/prod
if [[ -n $(git status --porcelain) ]]; then
  echo "Checkout has local changes; refusing release" >&2
  exit 1
fi
git checkout --detach "$commit"

compose=(docker compose --project-name forge-prod --env-file "$env_file" -f docker-compose.yml -f compose.prod.yml)
"${compose[@]}" config --quiet
for service in api worker web; do
  "${compose[@]}" build "$service"
done
"${compose[@]}" up -d --no-build --remove-orphans

stable_rounds=0
for attempt in $(seq 1 60); do
  api_id=$("${compose[@]}" ps -q api)
  worker_id=$("${compose[@]}" ps -q worker)
  if [[ -n "$api_id" && -n "$worker_id" ]] \
      && [[ $(docker inspect --format '{{.State.Health.Status}}' "$api_id") == healthy ]] \
      && [[ $(docker inspect --format '{{.State.Running}}' "$worker_id") == true ]] \
      && [[ $(docker inspect --format '{{.RestartCount}}' "$worker_id") == 0 ]] \
      && "${compose[@]}" exec -T web wget -q -O /dev/null http://127.0.0.1:3000/; then
    stable_rounds=$((stable_rounds + 1))
    if (( stable_rounds >= 6 )); then
      mkdir -p /var/lib/forge-prod
      printf '%s %s\n' "$release" "$commit" > /var/lib/forge-prod/release
      echo "Forge release $release is healthy ($commit)"
      exit 0
    fi
  else
    stable_rounds=0
  fi
  sleep 5
done

echo "Forge release $release did not become healthy" >&2
"${compose[@]}" ps >&2
exit 1
