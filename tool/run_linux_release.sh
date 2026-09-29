#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
mode="${1-}"
[[ "$mode" == prepare || "$mode" == publish ]] || { echo 'expected prepare or publish' >&2; exit 2; }
source_ref="${GITHUB_REF:?workflow_dispatch branch ref required}"
dispatch_sha="${GITHUB_SHA:?dispatch SHA required}"
bump="${INPUT_BUMP:?bump required}"
retry_tag="${INPUT_RETRY_TAG:-}"
[[ "$source_ref" == refs/heads/* ]] || { echo 'dispatch must come from a branch' >&2; exit 2; }
branch="${source_ref#refs/heads/}"
git check-ref-format "$source_ref"
[[ "$dispatch_sha" =~ ^[0-9a-f]{40}$ ]] || { echo 'invalid dispatch SHA' >&2; exit 2; }
[[ "$bump" == major || "$bump" == minor || "$bump" == patch ]] || { echo 'invalid bump' >&2; exit 2; }
work_dir="${RUNNER_TEMP:?runner temp required}/hgc-release"
if [[ "$mode" == prepare ]]; then
  [[ "$(git rev-parse HEAD)" == "$dispatch_sha" ]] || { echo 'checkout does not match dispatch SHA' >&2; exit 1; }
  [[ -z "$(git status --porcelain --untracked-files=no)" ]] || { echo 'release checkout must be clean' >&2; exit 1; }
  [[ ! -e "$work_dir" ]] || { echo 'release work directory already exists' >&2; exit 1; }
  mkdir -p "$work_dir"
  git fetch --no-tags origin 'refs/heads/main:refs/remotes/origin/main'
  git fetch --tags origin
  git ls-remote --tags --refs origin | sed 's#.*refs/tags/##' > "$work_dir/tags"
  main_version="$(git show origin/main:pubspec.yaml | sed -nE 's/^version: ([^[:space:]]+).*/\1/p')"
  [[ -n "$main_version" ]] || { echo 'origin/main has no version' >&2; exit 1; }
else
  [[ -d "$work_dir/assets" && -f "$work_dir/SHA256SUMS" && -f "$work_dir/plan" && -f "$work_dir/source-sha" ]] || { echo 'prepared release is missing' >&2; exit 1; }
fi
current_version() { sed -nE 's/^version: ([^[:space:]]+).*/\1/p' pubspec.yaml; }
plan_version() {
  dart run tool/release_version.dart --pubspec-version "$(current_version)" --main-version "$main_version" --branch-ref "$source_ref" --bump "$bump" --tags-file "$work_dir/tags" --retry-tag "$retry_tag" > "$work_dir/plan"
  version="$(sed -n 's/^version=//p' "$work_dir/plan")"
  tag="$(sed -n 's/^tag=//p' "$work_dir/plan")"
  title="$(sed -n 's/^title=//p' "$work_dir/plan")"
  prerelease="$(sed -n 's/^prerelease=//p' "$work_dir/plan")"
  [[ -n "$version" && -n "$tag" ]] || { echo 'version planner returned no release' >&2; exit 1; }
}
set_temporary_version() {
  local wanted="$1"
  sed -i -E "s/^version: [^[:space:]]+/version: $wanted/" pubspec.yaml
  [[ "$(current_version)" == "$wanted" ]] || { echo 'pubspec version update failed' >&2; exit 1; }
}
check_main_fresh() {
  git fetch --no-tags origin 'refs/heads/main:refs/remotes/origin/main'
  [[ "$(git rev-parse origin/main)" == "$dispatch_sha" ]] || { echo 'main moved after dispatch; refusing stale release' >&2; exit 1; }
}
verify_retry_tag() {
  [[ "$(git cat-file -t "refs/tags/$tag")" == tag ]] || { echo 'retry requires an annotated tag' >&2; exit 1; }
  git for-each-ref --format='%(contents)' "refs/tags/$tag" > "$work_dir/tag-message"
  local recorded_ref recorded_source recorded_target recorded_version recorded_run_id recorded_run_attempt recorded_manifest
  grep -Fxq 'release-workflow: hotkey-grammar-corrector-linux-v1' "$work_dir/tag-message" || { echo 'foreign release tag' >&2; exit 1; }
  recorded_ref="$(sed -n 's/^source-ref: //p' "$work_dir/tag-message")"
  recorded_source="$(sed -n 's/^source-sha: //p' "$work_dir/tag-message")"
  recorded_target="$(sed -n 's/^target-sha: //p' "$work_dir/tag-message")"
  recorded_version="$(sed -n 's/^version: //p' "$work_dir/tag-message")"
  recorded_run_id="$(sed -n 's/^run-id: //p' "$work_dir/tag-message")"
  recorded_run_attempt="$(sed -n 's/^run-attempt: //p' "$work_dir/tag-message")"
  recorded_manifest="$(sed -n 's/^assets-sha256: //p' "$work_dir/tag-message")"
  [[ "$recorded_ref" == "$source_ref" && "$recorded_version" == "$version" && "$recorded_source" =~ ^[0-9a-f]{40}$ && "$recorded_target" =~ ^[0-9a-f]{40}$ ]] || { echo 'tag provenance mismatch' >&2; exit 1; }
  [[ "$recorded_run_id" =~ ^[0-9]+$ && "$recorded_run_attempt" =~ ^[0-9]+$ && "$recorded_manifest" =~ ^[0-9a-f]{64}$ ]] || { echo 'tag asset provenance missing' >&2; exit 1; }
  [[ "$(git rev-parse "refs/tags/$tag^{commit}")" == "$recorded_target" ]] || { echo 'tag target mismatch' >&2; exit 1; }
  if [[ "$branch" == main ]]; then
    [[ "$(git rev-parse "$recorded_target^")" == "$recorded_source" ]] || { echo 'stable source parent mismatch' >&2; exit 1; }
    git merge-base --is-ancestor "$recorded_target" origin/main || { echo 'stable tag is not on main' >&2; exit 1; }
    [[ "$(git show "$recorded_target:pubspec.yaml" | sed -nE 's/^version: ([^[:space:]]+).*/\1/p')" == "$version" ]] || { echo 'stable tag version mismatch' >&2; exit 1; }
  else
    [[ "$recorded_source" == "$recorded_target" ]] || { echo 'branch tag target mismatch' >&2; exit 1; }
    git fetch --no-tags origin "$source_ref:refs/remotes/origin/$branch"
    git merge-base --is-ancestor "$recorded_source" "refs/remotes/origin/$branch" || { echo 'branch tag source is unreachable' >&2; exit 1; }
  fi
  git checkout --detach "$recorded_target"
  if [[ "$prerelease" == true ]]; then set_temporary_version "$version"; fi
  source_sha="$recorded_source"
  gh run download "$recorded_run_id" --repo "${GITHUB_REPOSITORY:?}" --name "linux-release-$recorded_run_id-$recorded_run_attempt" --dir "$work_dir/recovered"
  [[ -d "$work_dir/recovered/assets" && -f "$work_dir/recovered/SHA256SUMS" ]] || { echo 'original verified packages are unavailable' >&2; exit 1; }
  mv "$work_dir/recovered/assets" "$work_dir/assets"
  mv "$work_dir/recovered/SHA256SUMS" "$work_dir/SHA256SUMS"
  [[ "$(sha256sum "$work_dir/SHA256SUMS" | cut -d ' ' -f 1)" == "$recorded_manifest" ]] || { echo 'stored asset manifest differs from tag' >&2; exit 1; }
}
run_gates() {
  flutter pub get
  dart analyze --fatal-infos
  tool/provision_sidecar.sh
  rm -f coverage/lcov.info
  flutter test --coverage --branch-coverage --exclude-tags=live test
  dart run tool/check_coverage.dart coverage/lcov.info
}
verify_assets() {
  (cd "$work_dir/assets" && sha256sum --check ../SHA256SUMS)
  chmod 755 "$work_dir/assets/hotkey_grammar_corrector-${version}-linux-x86_64.AppImage"
  tool/verify_linux_release.sh --version "$version" --output-dir "$work_dir/assets"
}
check_name_collision() {
  local collision
  gh api --paginate "repos/${GITHUB_REPOSITORY:?}/releases?per_page=100" > "$work_dir/release-list.json"
  collision="$(jq -sr --arg title "$title" --arg tag "$tag" 'add | any(.[]; .name == $title and .tag_name != $tag)' "$work_dir/release-list.json")"
  if [[ "$collision" == true ]]; then
    echo 'release title belongs to another tag' >&2
    exit 1
  fi
}
check_existing_sequence_tags() {
  [[ "$branch" != main ]] || return 0
  local existing
  for existing in $(git tag -l "${tag%.*}.*"); do
    [[ "$(git cat-file -t "refs/tags/$existing")" == tag ]] || { echo "foreign lightweight tag: $existing" >&2; exit 1; }
    git for-each-ref --format='%(contents)' "refs/tags/$existing" | grep -Fxq 'release-workflow: hotkey-grammar-corrector-linux-v1' || { echo "foreign sequence tag: $existing" >&2; exit 1; }
  done
}
publish_assets() {
  local remote_json="$work_dir/release.json" asset name remote_size remote_digest local_size local_digest
  check_name_collision
  if ! gh api "repos/${GITHUB_REPOSITORY:?}/releases/tags/$tag" > "$remote_json" 2> "$work_dir/gh-error"; then
    grep -q 'HTTP 404' "$work_dir/gh-error" || { cat "$work_dir/gh-error" >&2; exit 1; }
    if [[ "$prerelease" == true ]]; then
      gh release create "$tag" --verify-tag --draft --prerelease --latest=false --title "$title" --notes-from-tag
    else
      gh release create "$tag" --verify-tag --draft --title "$title" --notes-from-tag
    fi
    gh api "repos/$GITHUB_REPOSITORY/releases/tags/$tag" > "$remote_json"
  fi
  [[ "$(jq -r .name "$remote_json")" == "$title" && "$(jq -r .prerelease "$remote_json")" == "$prerelease" ]] || { echo 'conflicting GitHub release metadata' >&2; exit 1; }
  for asset in "$work_dir/assets"/*; do
    name="${asset##*/}"
    local_size="$(stat -c %s "$asset")"
    local_digest="sha256:$(sha256sum "$asset" | cut -d ' ' -f 1)"
    remote_size="$(jq -r --arg name "$name" '.assets[] | select(.name == $name) | .size' "$remote_json")"
    remote_digest="$(jq -r --arg name "$name" '.assets[] | select(.name == $name) | .digest' "$remote_json")"
    if [[ -n "$remote_size" ]]; then
      [[ "$remote_size" == "$local_size" && "$remote_digest" == "$local_digest" ]] || { echo "remote asset differs: $name" >&2; exit 1; }
    elif [[ "$(jq -r .draft "$remote_json")" == true ]]; then
      gh release upload "$tag" "$asset"
    else
      echo "published release is missing $name" >&2; exit 1
    fi
  done
  gh api "repos/$GITHUB_REPOSITORY/releases/tags/$tag" > "$remote_json"
  [[ "$(jq '.assets | length' "$remote_json")" == 4 ]] || { echo 'release has unexpected asset count' >&2; exit 1; }
  for asset in "$work_dir/assets"/*; do
    name="${asset##*/}"
    local_size="$(stat -c %s "$asset")"
    local_digest="sha256:$(sha256sum "$asset" | cut -d ' ' -f 1)"
    jq -e --arg name "$name" --argjson size "$local_size" --arg digest "$local_digest" '.assets | any(.[]; .name == $name and .size == $size and .digest == $digest)' "$remote_json" >/dev/null || { echo "uploaded asset differs: $name" >&2; exit 1; }
  done
  if [[ "$(jq -r .draft "$remote_json")" == true ]]; then
    gh release edit "$tag" --verify-tag --draft=false
  fi
}

if [[ "$mode" == prepare ]]; then
  plan_version
  if [[ -n "$retry_tag" ]]; then
    verify_retry_tag
  else
    source_sha="$dispatch_sha"
    check_existing_sequence_tags
    if [[ "$branch" == main ]]; then check_main_fresh; fi
    set_temporary_version "$version"
  fi
  printf '%s\n' "$source_sha" > "$work_dir/source-sha"
  SOURCE_DATE_EPOCH="$(git show -s --format=%ct "$source_sha")"
  export SOURCE_DATE_EPOCH
  run_gates
  if [[ -z "$retry_tag" ]]; then
    mkdir "$work_dir/assets"
    tool/package_linux_release.sh --version "$version" --output-dir "$work_dir/assets"
    (cd "$work_dir/assets" && sha256sum ./* > ../SHA256SUMS)
  fi
  verify_assets
  exit 0
fi

version="$(sed -n 's/^version=//p' "$work_dir/plan")"
tag="$(sed -n 's/^tag=//p' "$work_dir/plan")"
title="$(sed -n 's/^title=//p' "$work_dir/plan")"
prerelease="$(sed -n 's/^prerelease=//p' "$work_dir/plan")"
source_sha="$(cat "$work_dir/source-sha")"
[[ "$source_sha" =~ ^[0-9a-f]{40}$ && "$tag" == "v$version" && ( "$prerelease" == true || "$prerelease" == false ) ]] || { echo 'invalid prepared release' >&2; exit 1; }
verify_assets
if [[ -z "$retry_tag" ]]; then
  [[ "$(git rev-parse HEAD)" == "$dispatch_sha" ]] || { echo 'checkout moved before publish' >&2; exit 1; }
  if [[ "$branch" == main ]]; then
    check_main_fresh
    git config user.name 'github-actions[bot]'
    git config user.email '41898282+github-actions[bot]@users.noreply.github.com'
    git add pubspec.yaml
    git commit -m "chore(release): $version"
  fi
  target_sha="$(git rev-parse HEAD)"
  manifest_sha="$(sha256sum "$work_dir/SHA256SUMS" | cut -d ' ' -f 1)"
  git tag -a "$tag" -m "release-workflow: hotkey-grammar-corrector-linux-v1
source-ref: $source_ref
source-sha: $source_sha
target-sha: $target_sha
version: $version
run-id: ${GITHUB_RUN_ID:?}
run-attempt: ${GITHUB_RUN_ATTEMPT:?}
assets-sha256: $manifest_sha"
  if [[ "$branch" == main ]]; then
    git push --atomic origin HEAD:refs/heads/main "refs/tags/$tag"
  else
    git push origin "refs/tags/$tag"
  fi
else
  [[ "$retry_tag" == "$tag" ]] || { echo 'retry tag changed between steps' >&2; exit 1; }
  [[ -f "$work_dir/tag-message" ]] || { echo 'retry tag was not verified' >&2; exit 1; }
fi
remote_tag_sha="$(git ls-remote --tags --refs origin "refs/tags/$tag" | cut -f 1)"
[[ -n "$remote_tag_sha" && "$remote_tag_sha" == "$(git rev-parse "refs/tags/$tag")" ]] || { echo 'remote tag differs from verified local tag' >&2; exit 1; }
publish_assets
