#!/bin/bash

# Pulls vendor/tronbyt, detects applet directory/file changes against the
# pre-pull tree, and writes the corresponding INSERT / UPDATE / DELETE
# statements into a fresh controller migration. Does NOT run db:migrate.
#
# Status classification:
#   added   = applet directory present after pull, absent before
#   deleted = applet directory absent after pull, present before
#   updated = applet directory in both, but at least one file under
#             apps/<applet>/ changed between BEFORE_COMMIT and AFTER_COMMIT
#
# Output:
#   controller/src/lib/db/migrations/<seq>_<YYYY-MM-DD>_applets_update.sql
#
# Mirrors manifest parsing, hex-cast, and migration finalisation from
# bin/render-applets.sh so both scripts produce compatible SQL.

set -eu

VENDOR_RELATIVE_PATH="vendor/tronbyt"
VENDOR_APPS_PATH="$VENDOR_RELATIVE_PATH/apps"
VENDOR_APPS_GIT_PREFIX="apps"

CONTROLLER_DIR=""
MIGRATIONS_DIR=""
GENERATED_MIGRATION_FILE=""
MIGRATION_TEMP_DIR=""
MIGRATION_BACKUP_DIR=""

ADDED_APPLETS=()
UPDATED_APPLETS=()
DELETED_APPLETS=()

# Manifest detail vars populated by loadAppletDetails.
APPLET_NAME=""
APPLET_SUMMARY=""
APPLET_DESC=""
APPLET_AUTHOR=""
APPLET_PACKAGE_NAME=""
APPLET_FILE_NAME=""

# Map deleted applet directory name → its pre-pull manifest packageName.
DELETED_PACKAGE_NAMES_FILE=""

hex_value() {
  printf '%s' "$1" | xxd -p | tr -d '\n'
}

requireManifestField() {
  if [ "$2" = "null" ]; then
    echo "ERROR: missing field '$1' in $3" >&2
    exit 1
  fi
}

listAppletDirs() {
  local apps_dir="$1"
  if [ -d "$apps_dir" ]; then
    find "$apps_dir" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort
  fi
}

# Parse the current on-disk manifest and populate APPLET_* vars.
# Fallbacks for packageName and fileName match render-applets.sh.
loadAppletDetails() {
  local applet_dir="$SCRIPT_DIR/$VENDOR_APPS_PATH/$1"
  local manifest_file="$applet_dir/manifest.yaml"

  if [[ ! -f "$manifest_file" ]]; then
    echo "ERROR: Manifest file not found: $manifest_file" >&2
    exit 1
  fi

  IFS=$'\t' read -r APPLET_NAME APPLET_SUMMARY APPLET_DESC APPLET_AUTHOR APPLET_PACKAGE_NAME APPLET_FILE_NAME < <(
    yq -r '[.name, .summary, .desc, .author, .packageName, .fileName] | map(. // "null") | @tsv' "$manifest_file"
  )

  if [ "$APPLET_PACKAGE_NAME" = "null" ]; then
    APPLET_PACKAGE_NAME="$1"
  fi

  if [ "$APPLET_FILE_NAME" = "null" ]; then
    if [ -f "$applet_dir/$1.star" ]; then
      APPLET_FILE_NAME="$1.star"
    else
      local star_files star_count
      star_files=$(find "$applet_dir" -maxdepth 1 -type f -name '*.star')
      star_count=$(printf '%s\n' "$star_files" | grep -c .)
      if [ "$star_count" -eq 1 ]; then
        APPLET_FILE_NAME=$(basename "$star_files")
      else
        echo "ERROR: missing field 'fileName' in $manifest_file" >&2
        exit 1
      fi
    fi
  fi
}

# Look up the pre-pull packageName for an applet whose directory is now
# gone. Reads the manifest from the BEFORE_COMMIT tree.
lookupDeletedPackageName() {
  local applet="$1"
  local manifest_path="${VENDOR_APPS_GIT_PREFIX}/${applet}/manifest.yaml"
  local raw

  raw=$(git -C "$VENDOR_DIR" show "${BEFORE_COMMIT}:${manifest_path}" 2>/dev/null || true)
  if [ -z "$raw" ]; then
    # No manifest in the pre-pull tree either — fall back to directory name.
    printf '%s' "$applet"
    return
  fi

  local pkg
  pkg=$(printf '%s' "$raw" | yq -r '.packageName // "null"')
  if [ "$pkg" = "null" ] || [ -z "$pkg" ]; then
    pkg="$applet"
  fi
  printf '%s' "$pkg"
}

prepareMigrationFile() {
  local migrationName="$1"

  CONTROLLER_DIR="$SCRIPT_DIR/../controller"
  MIGRATIONS_DIR="$CONTROLLER_DIR/src/lib/db/migrations"

  if [ ! -d "$CONTROLLER_DIR" ]; then
    echo "ERROR: Controller directory not found: $CONTROLLER_DIR" >&2
    exit 1
  fi
  if [ ! -d "$MIGRATIONS_DIR" ]; then
    echo "ERROR: Migrations directory not found: $MIGRATIONS_DIR" >&2
    exit 1
  fi

  MIGRATION_TEMP_DIR=$(mktemp -d)
  MIGRATION_BACKUP_DIR="$MIGRATION_TEMP_DIR/migrations"
  cp -R "$MIGRATIONS_DIR" "$MIGRATION_BACKUP_DIR"

  echo "Generate migration $migrationName"
  (cd "$CONTROLLER_DIR" && npm run db:generate -- --custom --name="$migrationName")

  GENERATED_MIGRATION_FILE=$(find "$MIGRATIONS_DIR" -maxdepth 1 -type f -name "*_${migrationName}.sql" | sort | tail -n 1)
  if [ -z "$GENERATED_MIGRATION_FILE" ]; then
    echo "ERROR: Generated migration file not found for $migrationName" >&2
    exit 1
  fi
}

restoreMigrationBackup() {
  if [ -n "$MIGRATION_BACKUP_DIR" ] && [ -d "$MIGRATION_BACKUP_DIR" ]; then
    rm -rf "$MIGRATIONS_DIR"
    cp -R "$MIGRATION_BACKUP_DIR" "$MIGRATIONS_DIR"
  fi
}

cleanupTemp() {
  if [ -n "$MIGRATION_TEMP_DIR" ] && [ -d "$MIGRATION_TEMP_DIR" ]; then
    rm -rf "$MIGRATION_TEMP_DIR"
  fi
  if [ -n "$DELETED_PACKAGE_NAMES_FILE" ] && [ -f "$DELETED_PACKAGE_NAMES_FILE" ]; then
    rm -f "$DELETED_PACKAGE_NAMES_FILE"
  fi
}

emitInsertSection() {
  if [ "${#ADDED_APPLETS[@]}" -eq 0 ]; then return; fi

  printf "\n-- ADDED APPLETS\nINSERT INTO applets (\`name\`, \`summary\`, \`desc\`, \`author\`, \`is_official_applet\`, \`file_name\`, \`package_name\`)\nVALUES\n" \
    >> "$GENERATED_MIGRATION_FILE"

  local first=true
  local applet manifest_file
  for applet in "${ADDED_APPLETS[@]}"; do
    loadAppletDetails "$applet"
    manifest_file="$SCRIPT_DIR/$VENDOR_APPS_PATH/$applet/manifest.yaml"
    requireManifestField 'name' "$APPLET_NAME" "$manifest_file"
    requireManifestField 'summary' "$APPLET_SUMMARY" "$manifest_file"
    requireManifestField 'desc' "$APPLET_DESC" "$manifest_file"
    requireManifestField 'author' "$APPLET_AUTHOR" "$manifest_file"

    if [ "$first" = true ]; then
      first=false
    else
      printf ",\n" >> "$GENERATED_MIGRATION_FILE"
    fi

    printf "  (CAST(X'%s' AS TEXT), CAST(X'%s' AS TEXT), CAST(X'%s' AS TEXT), CAST(X'%s' AS TEXT), 0, CAST(X'%s' AS TEXT), CAST(X'%s' AS TEXT))" \
      "$(hex_value "$APPLET_NAME")" \
      "$(hex_value "$APPLET_SUMMARY")" \
      "$(hex_value "$APPLET_DESC")" \
      "$(hex_value "$APPLET_AUTHOR")" \
      "$(hex_value "$APPLET_FILE_NAME")" \
      "$(hex_value "$APPLET_PACKAGE_NAME")" \
      >> "$GENERATED_MIGRATION_FILE"
  done

  printf ";\n" >> "$GENERATED_MIGRATION_FILE"
}

emitUpdateSection() {
  if [ "${#UPDATED_APPLETS[@]}" -eq 0 ]; then return; fi

  printf "\n-- UPDATED APPLETS\n" >> "$GENERATED_MIGRATION_FILE"

  local applet manifest_file
  for applet in "${UPDATED_APPLETS[@]}"; do
    loadAppletDetails "$applet"
    manifest_file="$SCRIPT_DIR/$VENDOR_APPS_PATH/$applet/manifest.yaml"
    requireManifestField 'name' "$APPLET_NAME" "$manifest_file"
    requireManifestField 'summary' "$APPLET_SUMMARY" "$manifest_file"
    requireManifestField 'desc' "$APPLET_DESC" "$manifest_file"
    requireManifestField 'author' "$APPLET_AUTHOR" "$manifest_file"

    printf "UPDATE applets SET \`name\` = CAST(X'%s' AS TEXT), \`summary\` = CAST(X'%s' AS TEXT), \`desc\` = CAST(X'%s' AS TEXT), \`author\` = CAST(X'%s' AS TEXT), \`file_name\` = CAST(X'%s' AS TEXT) WHERE \`package_name\` = CAST(X'%s' AS TEXT);\n" \
      "$(hex_value "$APPLET_NAME")" \
      "$(hex_value "$APPLET_SUMMARY")" \
      "$(hex_value "$APPLET_DESC")" \
      "$(hex_value "$APPLET_AUTHOR")" \
      "$(hex_value "$APPLET_FILE_NAME")" \
      "$(hex_value "$APPLET_PACKAGE_NAME")" \
      >> "$GENERATED_MIGRATION_FILE"
  done
}

emitDeleteSection() {
  if [ "${#DELETED_APPLETS[@]}" -eq 0 ]; then return; fi

  printf "\n-- DELETED APPLETS\n" >> "$GENERATED_MIGRATION_FILE"

  local applet pkg
  for applet in "${DELETED_APPLETS[@]}"; do
    pkg=$(lookupDeletedPackageName "$applet")
    printf "DELETE FROM applets WHERE \`package_name\` = CAST(X'%s' AS TEXT);\n" \
      "$(hex_value "$pkg")" \
      >> "$GENERATED_MIGRATION_FILE"
  done
}

finalizeMigrationFile() {
  if [ -z "$GENERATED_MIGRATION_FILE" ]; then return; fi

  local total=$(( ${#ADDED_APPLETS[@]} + ${#UPDATED_APPLETS[@]} + ${#DELETED_APPLETS[@]} ))

  if [ "$total" -eq 0 ]; then
    restoreMigrationBackup
    echo "No applet changes; reverted generated migration."
    return
  fi

  echo "Migration written: $GENERATED_MIGRATION_FILE"
  echo "  added:   ${#ADDED_APPLETS[@]}"
  echo "  updated: ${#UPDATED_APPLETS[@]}"
  echo "  deleted: ${#DELETED_APPLETS[@]}"
  echo "Run \`npm run db:migrate\` from controller/ when ready."
}

################################################################################

if ! command -v git &> /dev/null; then
  echo "Error: install 'git' as this is a required dependency."
  exit 1
fi
if ! command -v yq &> /dev/null; then
  echo "Error: install 'yq' as this is a required dependency."
  exit 1
fi
if ! command -v xxd &> /dev/null; then
  echo "Error: install 'xxd' as this is a required dependency."
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR_DIR="$SCRIPT_DIR/$VENDOR_RELATIVE_PATH"
APPS_DIR="$SCRIPT_DIR/$VENDOR_APPS_PATH"

trap cleanupTemp EXIT

# vendor/tronbyt is a git submodule, so .git is a file (gitlink) pointing
# to the parent repo's modules directory rather than a real .git/ folder.
if [ ! -e "$VENDOR_DIR/.git" ]; then
  echo "ERROR: Vendor directory is not a git checkout: $VENDOR_DIR" >&2
  exit 1
fi

echo "Snapshot vendor state at HEAD"
BEFORE_COMMIT=$(git -C "$VENDOR_DIR" rev-parse HEAD)
BEFORE_APPLETS=$(listAppletDirs "$APPS_DIR")

echo "git submodule update --remote $VENDOR_RELATIVE_PATH"
# Use the parent repo's submodule machinery: it fetches origin and
# checks out the configured remote tip, which works regardless of the
# submodule's detached-HEAD state.
PULL_OUTPUT=$(git -C "$SCRIPT_DIR" submodule update --remote -- "$VENDOR_RELATIVE_PATH" 2>&1)
printf '%s\n' "$PULL_OUTPUT"

AFTER_COMMIT=$(git -C "$VENDOR_DIR" rev-parse HEAD)

if [ "$BEFORE_COMMIT" = "$AFTER_COMMIT" ]; then
  echo "Already up to date. Nothing to do."
  exit 0
fi
AFTER_APPLETS=$(listAppletDirs "$APPS_DIR")

# Classify applets — Bash 3.2 compatible (no mapfile).
while IFS= read -r line; do
  [ -n "$line" ] && ADDED_APPLETS+=("$line")
done < <(comm -13 <(printf '%s\n' "$BEFORE_APPLETS") <(printf '%s\n' "$AFTER_APPLETS"))

while IFS= read -r line; do
  [ -n "$line" ] && DELETED_APPLETS+=("$line")
done < <(comm -23 <(printf '%s\n' "$BEFORE_APPLETS") <(printf '%s\n' "$AFTER_APPLETS"))

COMMON_APPLETS=$(comm -12 <(printf '%s\n' "$BEFORE_APPLETS") <(printf '%s\n' "$AFTER_APPLETS"))

if [ "$BEFORE_COMMIT" != "$AFTER_COMMIT" ]; then
  CHANGED_FILES=$(git -C "$VENDOR_DIR" diff --name-only "$BEFORE_COMMIT" "$AFTER_COMMIT")
else
  CHANGED_FILES=""
fi

while IFS= read -r applet; do
  [ -z "$applet" ] && continue
  if printf '%s\n' "$CHANGED_FILES" | grep -qE "^${VENDOR_APPS_GIT_PREFIX}/${applet}(/|$)"; then
    UPDATED_APPLETS+=("$applet")
  fi
done <<< "$COMMON_APPLETS"

echo "Detected:"
echo "  added:   ${#ADDED_APPLETS[@]}"
echo "  updated: ${#UPDATED_APPLETS[@]}"
echo "  deleted: ${#DELETED_APPLETS[@]}"

if [ "${#ADDED_APPLETS[@]}" -eq 0 ] && [ "${#UPDATED_APPLETS[@]}" -eq 0 ] && [ "${#DELETED_APPLETS[@]}" -eq 0 ]; then
  echo "No applet directory or file changes after pull."
  exit 0
fi

MIGRATION_NAME="$(date +%F)_applets_update"
prepareMigrationFile "$MIGRATION_NAME"

emitInsertSection
emitUpdateSection
emitDeleteSection
finalizeMigrationFile

echo "Done."
