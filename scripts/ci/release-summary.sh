#!/usr/bin/env bash
# What a release would deploy: everything since the last prod-* tag, grouped
# by how carefully it needs reviewing. Markdown on stdout.
#   scripts/ci/release-summary.sh [ref]     (default HEAD; make release-diff)
# In GitHub Actions it also writes has_migrations, first_release and base to
# $GITHUB_OUTPUT. See docs/release-process.md.
set -euo pipefail

ref=${1:-HEAD}
values=deploy/k8s/overlays/prod/values/values.env
base=$(git describe --tags --match 'prod-*' --abbrev=0 "$ref" 2>/dev/null || true)
if [[ -n $base ]]; then
  from=$base
  range="$base..$ref"
else
  from=$(git hash-object -t tree /dev/null) # empty tree: everything is new
  range=$ref
fi

changes=$(git diff --name-status --no-renames "$from" "$ref")
files() {  # files <grep -E pattern>: "STATUS<tab>path" lines under these paths
  grep -E $'^[A-Z]\t('"$1"')' <<< "$changes" || true
}
list() {  # list <title> <lines>
  [[ -z $2 ]] && return
  echo "#### $1"
  echo
  sed -E $'s/^A\t/- added: `/; s/^M\t/- changed: `/; s/^D\t/- deleted: `/; s/$/`/' <<< "$2"
  echo
}

workflows=$(files '\.github/|scripts/ci/')
migrations=$(files 'db/migrations/')
infra=$(files 'infra/')
values_change=$(files "$values")
k8s=$(grep -vF "$values" <<< "$(files 'deploy/')" || true)
services=$(files 'services/')
frontend=$(files 'frontend/')
other=$(grep -vE $'^[A-Z]\t(\\.github/|scripts/ci/|db/migrations/|infra/|deploy/|services/|frontend/)' <<< "$changes" || true)

has_migrations=false
grep -qE $'^[AM]\t' <<< "$migrations" && has_migrations=true

echo "## Release review: ${ref} since ${base:-the beginning (first release)}"
echo
echo "Read every ⚠ section before approving. Checklist: docs/release-process.md"
echo
echo "### Commits"
echo
echo '```'
git log --oneline --no-decorate -n 60 "$range"
echo '```'
echo

if [[ -n $workflows ]]; then
  list "⚠ Workflows and CI scripts: these run with production credentials; read every line" "$workflows"
fi

if [[ -n $migrations ]]; then
  list "⚠ Database migrations: irreversible; a backup is taken before they run" "$migrations"
  if grep -qE $'^[MD]\t' <<< "$migrations"; then
    echo "> ⚠ **An existing migration was changed or deleted.** Applied migrations never run again, so this edit has no effect in production. Add a new migration instead."
    echo
  fi
  while IFS=$'\t' read -r status path; do
    [[ $status == A || $status == M ]] || continue
    echo "<details><summary><code>$path</code></summary>"
    echo
    echo '```sql'
    git show "$ref:$path" | head -n 200
    echo '```'
    echo "</details>"
    echo
  done <<< "$migrations"
fi

list "⚠ Infrastructure: compare with the Terraform plan job" "$infra"

if [[ -n $values_change ]]; then
  echo "#### ⚠ Production values (\`values.env\`)"
  echo
  echo '```diff'
  git diff "$from" "$ref" -- "$values" | sed -n '/^@@/,$p'
  echo '```'
  echo
fi

list "Kubernetes manifests" "$k8s"
list "Services" "$services"
list "Frontend" "$frontend"
list "Other" "$other"

if [[ -n ${GITHUB_OUTPUT:-} ]]; then
  {
    echo "has_migrations=$has_migrations"
    echo "first_release=$([[ -z $base ]] && echo true || echo false)"
    echo "base=$base"
  } >> "$GITHUB_OUTPUT"
fi
