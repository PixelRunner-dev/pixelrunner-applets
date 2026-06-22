#!/bin/bash

set -eu

DATABASE_FILE="../db.sqlite"
WEBP_LOCATION="./public"
VENDOR_APPS_PATH="vendor/tronbyt/apps"
CONTRIB_APPS_PATH="src/contrib"
CONTROLLER_DIR=""
MIGRATIONS_DIR=""
GENERATED_MIGRATION_FILE=""
MIGRATION_TEMP_DIR=""
MIGRATION_BACKUP_DIR=""
NEW_APPLET_COUNT=0

# Emit applet directory paths (relative to SCRIPT_DIR) from every configured
# source root. Dirs without a manifest.yaml are silently skipped.
# ponytail: contrib dirs without manifest (e.g. clock/) are dropped here instead of erroring downstream.
getAvailableApplets() {
  local root abs dir
  for root in "$VENDOR_APPS_PATH" "$CONTRIB_APPS_PATH"; do
    abs="$SCRIPT_DIR/$root"
    [ -d "$abs" ] || continue
    while IFS= read -r dir; do
      [ -f "$dir/manifest.yaml" ] || continue
      printf '%s\n' "${dir#$SCRIPT_DIR/}"
    done < <(find "$abs" -mindepth 1 -maxdepth 1 -type d)
  done
}

appletExistsInDb() {
  local count
  count=$(sqlite3 "$DATABASE_FILE" "select count(*) from applets where package_name = CAST(X'$(hex_value "$1")' AS TEXT);")
  [ "$count" -gt 0 ]
}

renderAppletImage() {
  local packageName="$1"
  local fileName="$2"
  local sourceRel="$3"

  if [ -z "$packageName" ] || [ -z "$fileName" ] || [ -z "$sourceRel" ]; then
    echo "ERROR: Incorrect manifest analysis: [$packageName] [$fileName] [$sourceRel]"
    exit 1
  fi

  local image=$(node ./bin/pixlet.mjs render -o "$WEBP_LOCATION/$packageName.webp" -w 64 -t 32 -z 5 --locale en --format webp "$SCRIPT_DIR/$sourceRel/$fileName")
  echo "$image"
}

# Exit with an error when a required manifest field is missing (literal "null").
requireManifestField() {
  if [ "$2" = "null" ]; then
    echo "ERROR: missing field '$1' in $3" >&2
    exit 1
  fi
}

# Parse an applet manifest in a single yq pass and populate detail variables.
# Sets: APPLET_NAME, APPLET_SUMMARY, APPLET_DESC, APPLET_AUTHOR,
#       APPLET_PACKAGE_NAME, APPLET_FILE_NAME.
# Missing fields are reported as the literal "null"; packageName and fileName
# get their derived fallbacks applied here (they are always needed for rendering).
loadAppletDetails() {
  local applet_rel="$1"
  local applet_dir="$SCRIPT_DIR/$applet_rel"
  local applet_name
  applet_name=$(basename "$applet_rel")
  local manifest_file="$applet_dir/manifest.yaml"

  if [[ ! -f "$manifest_file" ]]; then
    echo "ERROR: Manifest file not found: $manifest_file" >&2
    exit 1
  fi

  # Single fork+yq pass extracts every consumed field as a TSV row.
  IFS=$'\t' read -r APPLET_NAME APPLET_SUMMARY APPLET_DESC APPLET_AUTHOR APPLET_PACKAGE_NAME APPLET_FILE_NAME < <(
    yq -r '[.name, .summary, .desc, .author, .packageName, .fileName] | map(. // "null") | @tsv' "$manifest_file"
  )

  # packageName fallback: the applet directory name.
  if [ "$APPLET_PACKAGE_NAME" = "null" ]; then
    APPLET_PACKAGE_NAME="$applet_name"
  fi

  # fileName fallback: <applet>.star, otherwise a unique *.star in the directory.
  if [ "$APPLET_FILE_NAME" = "null" ]; then
    if [ -f "$applet_dir/$applet_name.star" ]; then
      APPLET_FILE_NAME="$applet_name.star"
    else
      local star_files star_count
      star_files=$(find "$applet_dir" -maxdepth 1 -type f -name '*.star')
      star_count=$(printf '%s\n' "$star_files" | grep -c .)
      if [ "$star_count" -eq 1 ]; then
        APPLET_FILE_NAME=$(basename "$star_files")
      else
        echo "ERROR: missing field 'fileName' in $manifest_file; no $applet_name.star and could not pick a unique *.star in $applet_dir (found $star_count)" >&2
        exit 1
      fi
    fi
  fi
}

checkWebpDirectory() {
  if [ ! -d "$WEBP_LOCATION" ]; then
    mkdir -p "$WEBP_LOCATION"
  fi
}

hex_value() {
  printf '%s' "$1" | xxd -p | tr -d '\n'
}

hasFlag() {
  local flag="$1"
  shift

  for arg in "$@"; do
    if [ "$arg" == "$flag" ]; then
      return 0
    fi
  done

  return 1
}

cleanupTemp() {
  if [ -n "$MIGRATION_TEMP_DIR" ] && [ -d "$MIGRATION_TEMP_DIR" ]; then
    rm -rf "$MIGRATION_TEMP_DIR"
  fi
}

prepareMigrationFile() {
  local migrationName="new_applets_$(date +%F)"

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

appendAppletToMigration() {
  local name="$1" summary="$2" desc="$3" author="$4" fileName="$5" packageName="$6"

  if [ "$NEW_APPLET_COUNT" -eq 0 ]; then
    printf "\nINSERT INTO applets (\`name\`, \`summary\`, \`desc\`, \`author\`, \`is_official_applet\`, \`file_name\`, \`package_name\`)\nVALUES\n" >> "$GENERATED_MIGRATION_FILE"
  else
    printf ",\n" >> "$GENERATED_MIGRATION_FILE"
  fi

  printf "  (CAST(X'%s' AS TEXT), CAST(X'%s' AS TEXT), CAST(X'%s' AS TEXT), CAST(X'%s' AS TEXT), 0, CAST(X'%s' AS TEXT), CAST(X'%s' AS TEXT))" \
    "$(hex_value "$name")" "$(hex_value "$summary")" "$(hex_value "$desc")" "$(hex_value "$author")" "$(hex_value "$fileName")" "$(hex_value "$packageName")" >> "$GENERATED_MIGRATION_FILE"
  NEW_APPLET_COUNT=$((NEW_APPLET_COUNT + 1))
}

restoreMigrationBackup() {
  if [ -n "$MIGRATION_BACKUP_DIR" ] && [ -d "$MIGRATION_BACKUP_DIR" ]; then
    rm -rf "$MIGRATIONS_DIR"
    cp -R "$MIGRATION_BACKUP_DIR" "$MIGRATIONS_DIR"
  fi
}

finalizeMigrationFile() {
  if [ -z "$GENERATED_MIGRATION_FILE" ]; then
    return
  fi

  if [ "$NEW_APPLET_COUNT" -eq 0 ]; then
    restoreMigrationBackup
    echo "No new applets found; removed generated migration."
    return
  fi

  printf ";\n" >> "$GENERATED_MIGRATION_FILE"
  echo "Added $NEW_APPLET_COUNT new applet(s) to $GENERATED_MIGRATION_FILE"
}

################################################################################

if ! command -v yq &> /dev/null; then
  echo "Error: install 'yq' as this is a required dependency."
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKIP_DB=false

trap cleanupTemp EXIT

if hasFlag "--skip-db" "$@"; then
  SKIP_DB=true
else
  prepareMigrationFile
fi

checkWebpDirectory
applets=$(getAvailableApplets)
while IFS= read -r applet_rel; do
  [ -z "$applet_rel" ] && continue
  echo "Render $applet_rel"
  loadAppletDetails "$applet_rel"
  renderAppletImage "$APPLET_PACKAGE_NAME" "$APPLET_FILE_NAME" "$applet_rel"

  if [ "$SKIP_DB" == "true" ]; then
    echo "-skipping database tasks-"
    continue
  fi

  if appletExistsInDb "$APPLET_PACKAGE_NAME"; then continue; fi

  echo "(new applet) - appending record to migration"

  manifest_file="$SCRIPT_DIR/$applet_rel/manifest.yaml"
  requireManifestField 'name' "$APPLET_NAME" "$manifest_file"
  requireManifestField 'summary' "$APPLET_SUMMARY" "$manifest_file"
  requireManifestField 'desc' "$APPLET_DESC" "$manifest_file"
  requireManifestField 'author' "$APPLET_AUTHOR" "$manifest_file"

  appendAppletToMigration "$APPLET_NAME" "$APPLET_SUMMARY" "$APPLET_DESC" "$APPLET_AUTHOR" "$APPLET_FILE_NAME" "$APPLET_PACKAGE_NAME"

  echo
done <<< "$applets"

finalizeMigrationFile
