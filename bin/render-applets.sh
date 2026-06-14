#!/bin/bash

set -eu

DATABASE_FILE="../db.sqlite"
WEBP_LOCATION="./public"
CONTROLLER_DIR=""
MIGRATIONS_DIR=""
GENERATED_MIGRATION_FILE=""
MIGRATION_TEMP_DIR=""
MIGRATION_BACKUP_DIR=""
NEW_APPLET_COUNT=0

getAvailableApplets() {
  local applets=$(find "$SCRIPT_DIR/$VENDOR_APPS_PATH" -mindepth 1 -maxdepth 1 -type d -exec basename {} \;)
  echo "$applets"
}

appletExistsInDb() {
  local count
  count=$(sqlite3 "$DATABASE_FILE" "select count(*) from applets where package_name = CAST(X'$(hex_value "$1")' AS TEXT);")
  [ "$count" -gt 0 ]
}

renderAppletImage() {
  local packageName=$(getAppletDetails "$1" 'packageName')
  local fileName=$(getAppletDetails "$1" 'fileName')

  if [ -z "$packageName" ] || [ -z "$fileName" ]; then
    echo "ERROR: Incorrect manifest analysis: [$packageName] [$fileName]"
    exit 1
  fi

  local image=$(node ./bin/pixlet.mjs render -o "$WEBP_LOCATION/$packageName.webp" -w 64 -t 32 -z 5 --locale en --format webp "$SCRIPT_DIR/$VENDOR_APPS_PATH/$packageName/$fileName")
  echo "$image"
}

getAppletDetails() {
  local applet_dir="$SCRIPT_DIR/$VENDOR_APPS_PATH/$1"
  local manifest_file="$applet_dir/manifest.yaml"

  if [[ ! -f "$manifest_file" ]]; then
    echo "ERROR: Manifest file not found: $manifest_file" >&2
    exit 1
  fi

  local manifest=$(cat "$manifest_file" | yq -r ".$2")
  if [ "$manifest" = "null" ]; then
    case "$2" in
      packageName)
        echo "$1"
        return 0
        ;;
      fileName)
        if [ -f "$applet_dir/$1.star" ]; then
          echo "$1.star"
          return 0
        fi
        local star_files star_count
        star_files=$(find "$applet_dir" -maxdepth 1 -type f -name '*.star')
        star_count=$(printf '%s\n' "$star_files" | grep -c .)
        if [ "$star_count" -eq 1 ]; then
          basename "$star_files"
          return 0
        fi
        echo "ERROR: missing field 'fileName' in $manifest_file; no $1.star and could not pick a unique *.star in $applet_dir (found $star_count)" >&2
        exit 1
        ;;
      *)
        echo "ERROR: missing field '$2' in $manifest_file" >&2
        exit 1
        ;;
    esac
  fi
  echo "$manifest"
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
# VENDOR_APPS_PATH="vendor/tidbyt/apps"
VENDOR_APPS_PATH="vendor/tronbyt/apps"
SKIP_DB=false

trap cleanupTemp EXIT

if hasFlag "--skip-db" "$@"; then
  SKIP_DB=true
else
  prepareMigrationFile
fi

checkWebpDirectory
applets=$(getAvailableApplets)
while IFS= read -r applet; do
  echo "Render $applet"
  renderAppletImage "$applet"

  if [ "$SKIP_DB" == "true" ]; then
    echo "-skipping database tasks-"
    continue
  fi

  if appletExistsInDb "$applet"; then continue; fi

  echo "(new applet) - appending record to migration"

  name=$(getAppletDetails "$applet" 'name')
  summary=$(getAppletDetails "$applet" 'summary')
  desc=$(getAppletDetails "$applet" 'desc')
  author=$(getAppletDetails "$applet" 'author')
  fileName=$(getAppletDetails "$applet" 'fileName')
  packageName=$(getAppletDetails "$applet" 'packageName')
  appendAppletToMigration "$name" "$summary" "$desc" "$author" "$fileName" "$packageName"

  echo
done <<< "$applets"

finalizeMigrationFile
