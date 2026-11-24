#!/bin/sh
# Copies the app's exercise templates, demos and workouts into the bundle (specs/02
# "Repo yerleşimi": exercises/ is copied at build time; exercises/source/ never
# enters the app). The build sandbox lets the script read only declared inputs
# and write only declared outputs, so both are listed file by file:
# scripts/xcode/exercises.xcfilelist (inputs) and exercises-out.xcfilelist
# (outputs, the same names in the bundle). A SoloEngine test keeps both in sync
# with exercises/*.json, exercises/demos/*.json, exercises/demos/steps/*.json and
# exercises/workouts/*.json, exercises/reflex/*.json and exercises/energy/*.json.
set -eu
dest="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/exercises"
mkdir -p "$dest/demos/steps" "$dest/workouts" "$dest/reflex" "$dest/energy"
while IFS= read -r f; do
  [ -n "$f" ] || continue
  case "$f" in
    */exercises/demos/steps/*) cp "$f" "$dest/demos/steps/" ;;
    */exercises/demos/*) cp "$f" "$dest/demos/" ;;
    */exercises/workouts/*) cp "$f" "$dest/workouts/" ;;
    */exercises/reflex/*) cp "$f" "$dest/reflex/" ;;
    */exercises/energy/*) cp "$f" "$dest/energy/" ;;
    *) cp "$f" "$dest/" ;;
  esac
done < "${SCRIPT_INPUT_FILE_LIST_0}"
