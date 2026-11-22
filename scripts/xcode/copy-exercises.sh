#!/bin/sh
# Copies the app's exercise templates and their demos into the bundle (specs/02
# "Repo yerleşimi": exercises/ is copied at build time; exercises/source/ never
# enters the app). The files come from scripts/xcode/exercises.xcfilelist (the
# build sandbox only lets the script read declared inputs); a SoloEngine test
# keeps the list in sync with exercises/*.json and exercises/demos/*.json.
set -eu
dest="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/exercises"
rm -rf "$dest"
mkdir -p "$dest/demos"
while IFS= read -r f; do
  [ -n "$f" ] || continue
  case "$f" in
    */exercises/demos/*) cp "$f" "$dest/demos/" ;;
    *) cp "$f" "$dest/" ;;
  esac
done < "${SCRIPT_INPUT_FILE_LIST_0}"
