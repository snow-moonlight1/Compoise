#!/usr/bin/env bash
# Explicit opt-in benchmark; fixed SDK, read-only old assets, own ext4 outputs.
set -euo pipefail
root=/home/ubuntu/wp17q1-private
source=/mnt/d/Dev_project/martix-wp17-q1
flutter=/home/ubuntu/develop/flutter/bin/flutter
mkdir -p "$root/logs"
run() {
  local label=$1
  shift
  local code=0
  "$@" > "$root/logs/$label.log" 2>&1 || code=$?
  printf '%s\n' "$code" > "$root/logs/$label.exit"
  echo "$label=$code"
  return "$code"
}
case "${1:?setup/build-before/build-after/run-before/run-after}" in
  setup)
    test ! -e "$root/repo-before/pubspec.yaml"
    mkdir -p "$root/repo-before" "$root/repo-after"
    # Windows worktree .git has a Windows absolute pointer. Read the shared
    # object database explicitly; this command never mutates the main checkout.
    git --git-dir=/mnt/d/Dev_project/martix/.git archive 3ac0b6d9192a0495f1db1f636d9b8726b03179c4 | tar -xf - -C "$root/repo-before"
    if [ ! -e "$root/pub-cache" ]; then cp -a /home/ubuntu/wp17i6-private/pub-cache "$root/pub-cache"; fi
    ;;
  build-before|build-after)
    mode=${1#build-}
    repo="$root/repo-$mode"
    if [ "$mode" = after ]; then
      rsync -a --exclude=.git --exclude=.dart_tool --exclude=build --exclude=.gradle --exclude=.cxx --exclude=local.properties "$source/" "$repo/"
    else
      cp "$source/tool/wp17_q1_benchmark.dart" "$repo/tool/"
      cp "$source/native/ocr/tools/q1_cases.json" "$repo/native/ocr/tools/"
    fi
    cd "$repo"
    export PUB_CACHE="$root/pub-cache"
    unset WP17_OCR_NCNN_DIR WP17_OCR_STB_DIR
    run "flutter-pub-$mode" "$flutter" pub get --offline
    git --git-dir=/mnt/d/Dev_project/martix/.git show 3ac0b6d9192a0495f1db1f636d9b8726b03179c4:pubspec.lock > "$root/lock-baseline"
    # I6's copied offline cache lacks hosted-hashes. Pub removes just those
    # descriptions; verify every other byte/version and restore the exact lock.
    cmp <(sed -e 's/\r$//' -e '/      sha256:/d' pubspec.lock) <(sed '/      sha256:/d' "$root/lock-baseline")
    cp "$root/lock-baseline" pubspec.lock
    cmp pubspec.lock "$root/lock-baseline"
    run "flutter-build-$mode" "$flutter" build linux --release --no-pub --target=tool/wp17_q1_benchmark.dart
    ;;
  run-before|run-after)
    mode=${1#run-}
    label=$mode
    unset MALLOC_ARENA_MAX
    if [ "${2:-}" = arena2 ]; then
      # Diagnostic ablation only; not a product setting or portable fix.
      export MALLOC_ARENA_MAX=2
      label="$mode-arena2"
    elif [ -n "${2:-}" ]; then exit 2; fi
    repo="$root/repo-$mode"
    session=$(mktemp -d "$root/xdg-q1-XXXXXX")
    case "$(realpath "$session")" in "$root"/xdg-q1-*) ;; *) exit 2 ;; esac
    trap 'rm -rf -- "$session"' EXIT
    export XDG_DATA_HOME="$session/data" XDG_CONFIG_HOME="$session/config" XDG_CACHE_HOME="$session/cache"
    mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
    export GDK_BACKEND=x11 LIBGL_ALWAYS_SOFTWARE=1
    export WP17_Q1_REPO="$repo" WP17_Q1_REPORT="$root/flutter-$label.json"
    export WP17_Q1_LIBRARY="$root/native-linux-$mode/libmatrixflow_ocr.so"
    export WP17_Q1_ASSETS=/home/ubuntu/wp17i6-private/official-deploy
    if [ -e "$root/fixtures/labels.json" ]; then export WP17_Q1_FIXTURES="$root/fixtures"; fi
    run "flutter-run-$label" timeout 600 xvfb-run -a dbus-run-session -- "$repo/build/linux/x64/release/bundle/matrixflow_native"
    ;;
  profile)
    for mode in before after; do
      runtime="$source/native/ocr/ocr_runtime.cpp"
      if [ "$mode" = before ]; then runtime="$root/repo-before/native/ocr/ocr_runtime.cpp"; fi
      run "profile-generate-$mode" python3 "$source/native/ocr/tools/q1_profile.py" --source "$runtime" --out "$root/profile-src-$mode"
      run "profile-configure-$mode" cmake -S "$root/profile-src-$mode" -B "$root/profile-linux-$mode" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_COMPILER=clang++ -Dncnn_DIR=/home/ubuntu/wp17i4-ncnn-linux/install/lib/cmake/ncnn -DWP17_STB_DIR=/home/ubuntu/wp17i5-private/assets/third_party
      run "profile-build-$mode" cmake --build "$root/profile-linux-$mode" --parallel 4
      run "profile-run-$mode" python3 "$source/native/ocr/tools/q1_benchmark.py" --worker single --library "$root/profile-linux-$mode/libmatrixflow_ocr.so" --assets /home/ubuntu/wp17i6-private/official-deploy --build Release --report "$root/profile-$mode.json"
    done
    ;;
  dart-profile)
    for mode in before after; do
      repo="$root/trace-$mode"
      run "dart-profile-generate-$mode" python3 "$source/native/ocr/tools/q1_dart_profile.py" --repo "$root/repo-$mode" --out "$repo"
      cd "$repo"
      export PUB_CACHE="$root/pub-cache"
      unset WP17_OCR_NCNN_DIR WP17_OCR_STB_DIR MALLOC_ARENA_MAX
      run "dart-profile-pub-$mode" "$flutter" pub get --offline
      cmp <(sed -e 's/\r$//' -e '/      sha256:/d' pubspec.lock) <(sed '/      sha256:/d' "$root/lock-baseline")
      cp "$root/lock-baseline" pubspec.lock
      run "dart-profile-build-$mode" "$flutter" build linux --release --no-pub --target=tool/wp17_q1_benchmark.dart
      session=$(mktemp -d "$root/xdg-q1-XXXXXX")
      case "$(realpath "$session")" in "$root"/xdg-q1-*) ;; *) exit 2 ;; esac
      trap 'rm -rf -- "$session"' EXIT
      export XDG_DATA_HOME="$session/data" XDG_CONFIG_HOME="$session/config" XDG_CACHE_HOME="$session/cache"
      mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
      export GDK_BACKEND=x11 LIBGL_ALWAYS_SOFTWARE=1
      export WP17_Q1_REPO="$repo" WP17_Q1_REPORT="$root/flutter-trace-$mode.json" WP17_Q1_BATCHES=1
      export WP17_Q1_LIBRARY="$root/native-linux-$mode/libmatrixflow_ocr.so"
      export WP17_Q1_ASSETS=/home/ubuntu/wp17i6-private/official-deploy
      unset WP17_Q1_FIXTURES
      run "dart-profile-run-$mode" timeout 300 xvfb-run -a dbus-run-session -- "$repo/build/linux/x64/release/bundle/matrixflow_native"
      rm -rf -- "$session"
      trap - EXIT
    done
    ;;
  quality)
    run quality-linux env PYTHONDONTWRITEBYTECODE=1 /home/ubuntu/wp17i5-tools/bin/python "$source/native/ocr/tools/q1_quality.py" score --out "$root/fixtures" --library "$root/native-linux-after/libmatrixflow_ocr.so" --baseline-library "$root/native-linux-before/libmatrixflow_ocr.so" --assets /home/ubuntu/wp17i6-private/official-deploy --flutter-report "$root/flutter-after.json"
    ;;
  limits)
    run limits-native-linux python3 "$source/native/ocr/tools/q1_limits.py" --library "$root/native-linux-after/libmatrixflow_ocr.so" --assets /home/ubuntu/wp17i6-private/official-deploy --out "$root/limits-linux"
    run limits-build bash "$source/native/ocr/tools/q1_linux.sh" build-after
    session=$(mktemp -d "$root/xdg-q1-XXXXXX")
    case "$(realpath "$session")" in "$root"/xdg-q1-*) ;; *) exit 2 ;; esac
    trap 'rm -rf -- "$session"' EXIT
    export XDG_DATA_HOME="$session/data" XDG_CONFIG_HOME="$session/config" XDG_CACHE_HOME="$session/cache"
    mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
    export GDK_BACKEND=x11 LIBGL_ALWAYS_SOFTWARE=1
    export WP17_Q1_REPO="$root/repo-after" WP17_Q1_REPORT="$root/flutter-limits-after.json"
    export WP17_Q1_LIBRARY="$root/native-linux-after/libmatrixflow_ocr.so"
    export WP17_Q1_ASSETS=/home/ubuntu/wp17i6-private/official-deploy
    export WP17_Q1_ONLY_LIMITS=true WP17_Q1_LIMITS="$root/limits-linux"
    unset WP17_Q1_FIXTURES MALLOC_ARENA_MAX
    run limits-flutter timeout 300 xvfb-run -a dbus-run-session -- "$root/repo-after/build/linux/x64/release/bundle/matrixflow_native"
    ;;
  *) exit 2 ;;
esac
