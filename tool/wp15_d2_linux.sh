#!/usr/bin/env bash
# Run inside WSL2/Linux with the Linux Flutter 3.32.8 SDK.
# Default invocation is blocked (2); acceptance always needs an explicit opt-in.
set -euo pipefail
if [[ ${1:-} != --run || -z ${2:-} ]]; then
  echo 'Usage: wp15_d2_linux.sh --run /path/to/linux/flutter [system|iana-TZ]' >&2
  exit 2
fi
flutter=$2
zone_mode=${3:-system}
source_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
log_root="$source_root/build/wp15-d2"
mkdir -p -- "$log_root"
# Windows-created worktree gitfiles contain a drive-letter gitdir. Resolve it
# for WSL without rewriting the checkout or shared Git metadata.
git_args=(-C "$source_root")
if [[ -f "$source_root/.git" ]]; then
  git_dir=$(sed -n 's/^gitdir: //p' "$source_root/.git" | tr -d '\r')
  if [[ $git_dir =~ ^[A-Za-z]: ]]; then
    git_dir=$(wslpath -u "$git_dir")
    git_args=(--git-dir="$git_dir" --work-tree="$source_root")
  fi
fi
revision=$(git "${git_args[@]}" rev-parse HEAD)
dirty=$(git "${git_args[@]}" status --porcelain --untracked-files=normal)
version=$("$flutter" --version --machine)
if ! python3 -c 'import json,sys; assert json.load(sys.stdin)["frameworkVersion"] == "3.32.8"' <<< "$version"; then
  echo 'Flutter 3.32.8 is required.' >&2
  exit 2
fi
if [[ $(uname -s) != Linux ]] || ! command -v Xvfb >/dev/null; then
  echo 'Linux + Xvfb required; no device means blocked, not passed.' >&2
  exit 2
fi
scratch=$(mktemp -d /tmp/wp15-d2-XXXXXXXX)
owned_pid=''
cleanup() {
  if [[ -n $owned_pid ]] && kill -0 "$owned_pid" 2>/dev/null; then
    kill -TERM -- "-$owned_pid" 2>/dev/null || true
    wait "$owned_pid" 2>/dev/null || true
  fi
  case $scratch in /tmp/wp15-d2-????????) rm -rf -- "$scratch";; *) echo 'Refused unexpected cleanup root' >&2;; esac
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir -p "$scratch/source" "$scratch/data" "$scratch/config" "$scratch/cache"
# Linux-generated plugin files never overwrite the Windows checkout's cache.
# Copy includes unstaged D2 changes, but excludes all generated state/user data.
tar -C "$source_root" --exclude=.git --exclude=.dart_tool --exclude=build \
  --exclude=.flutter-plugins --exclude=.flutter-plugins-dependencies \
  --exclude=android/local.properties --exclude=android/.gradle --exclude=android/app/build --exclude=linux/flutter/ephemeral \
  --exclude=windows/flutter/ephemeral --exclude=.codebuddy -cf - . |
  tar -C "$scratch/source" -xf -
export XDG_DATA_HOME="$scratch/data" XDG_CONFIG_HOME="$scratch/config" XDG_CACHE_HOME="$scratch/cache"
if [[ $zone_mode == system ]]; then
  unset TZ
  if [[ -s /etc/timezone ]]; then
    expected=$(head -n1 /etc/timezone | tr -d '\r\n')
  else
    expected=$(readlink /etc/localtime)
    expected=${expected#*zoneinfo/}
  fi
else
  export TZ=$zone_mode
  expected=${TZ#:}
  expected=${expected#*zoneinfo/}
fi
log_tag=${zone_mode//\//_}
log="$log_root/linux-$log_tag.log"
cd "$scratch/source"
# Optional read-only seed from another platform's exact package source cache.
# This stays inside scratch and avoids resolving newer versions from a mirror.
if [[ -n ${WP15_D2_PUB_CACHE_SEED:-} ]]; then
  if [[ -f $WP15_D2_PUB_CACHE_SEED ]]; then
    mkdir -p "$scratch/pub-cache"
    tar -C "$scratch/pub-cache" -xf "$WP15_D2_PUB_CACHE_SEED"
  else
  python3 - "$scratch/source/pubspec.lock" "$WP15_D2_PUB_CACHE_SEED" "$scratch/pub-cache" <<'PY'
import pathlib,re,shutil,sys
lock,seed,dest=map(pathlib.Path,sys.argv[1:])
for name,body in re.findall(r'^  (\w+):\n(.*?)(?=^  \w+:|\Z)',lock.read_text(),re.M|re.S):
    if 'source: hosted' not in body: continue
    version=re.search(r'^    version: "([^"]+)"',body,re.M).group(1)
    host=re.search(r'url: "https://([^"]+)"',body).group(1)
    package=f'{name}-{version}'
    shutil.copytree(seed/'hosted'/host/package,dest/'hosted'/host/package)
    for sub,file in [('hosted-hashes',package+'.sha256'),('hosted', '.cache/'+name+'-versions.json')]:
        src=seed/sub/host/file
        if src.exists():
            target=dest/sub/host/file
            target.parent.mkdir(parents=True,exist_ok=True)
            shutil.copy2(src,target)
PY
  fi
  export PUB_CACHE="$scratch/pub-cache"
  unset PUB_HOSTED_URL
fi
"$flutter" pub get --offline --enforce-lockfile
# Even when a caller supplies its own cache/mirror, enforce exact locked versions.
python3 - "$source_root/pubspec.lock" "$scratch/source/pubspec.lock" <<'PY'
import pathlib,re,sys
def versions(path):
    return {name:re.search(r'^    version: "([^"]+)"',body,re.M).group(1)
            for name,body in re.findall(r'^  (\w+):\n(.*?)(?=^  \w+:|\Z)',pathlib.Path(path).read_text(),re.M|re.S)
            if re.search(r'^    version:',body,re.M)}
assert versions(sys.argv[1]) == versions(sys.argv[2]), 'Dependency versions changed'
PY
# This is a normal app Debug build from main.dart, not a channel-only probe.
"$flutter" build linux --debug --no-pub > "$log_root/linux-normal-debug.log" 2>&1
set +e
# timeout owns the child process group, including the app/Xvfb on interruption.
setsid timeout --kill-after=10s 900s xvfb-run -a -s '-screen 0 1280x900x24' \
  "$flutter" drive --no-pub -d linux --driver=test/wp15_d2_device_driver.dart \
  --target=test/wp15_d2_device_test.dart --dart-define=WP15_D2_DEVICE=true \
  "--dart-define=WP15_D2_EXPECTED_ZONE=$expected" \
  "--dart-define=WP15_D2_COMMIT=$revision" > "$log" 2>&1 &
owned_pid=$!
wait "$owned_pid"
code=$?
owned_pid=''
set -e
cat "$log"
if [[ $code == 0 ]] && ! grep -q 'WP15_D2_RESULT' "$log"; then code=1; fi
python3 - "$log_root/linux-$log_tag-result.json" "$revision" "$dirty" "$expected" "$code" <<'PY'
import json,sys
path,revision,dirty,zone,code=sys.argv[1:]
with open(path,'w') as f:
    json.dump(dict(revision=revision,dirty=bool(dirty),iana=zone,exitCode=int(code),
                   platform='linux',display='Xvfb',systemTimezoneModified=False),f,indent=2)
PY
printf 'WP15_D2_LINUX_EXIT=%s mode=%s\n' "$code" "$zone_mode"
exit "$code"