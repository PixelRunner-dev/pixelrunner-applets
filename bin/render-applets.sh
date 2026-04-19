#!/bin/bash

set -e

DATABASE_FILE="../db.sqlite"
WEBP_LOCATION="./public"

getAvailableApplets() {
  local applets=$(cat ./applets.yml | yq -r '.[]')
  echo "$applets"
}

getAppletsFromDbByPackageName() {
  local records=$(sqlite3 -json $DATABASE_FILE "select * from applets where package_name = '$1';")
  echo "$records"
}

getAppletSchema() {
  local schema=$(node ./bin/pixlet.mjs schema "$SCRIPT_DIR/$VENDOR_APPS_PATH/$1/$2")
  echo "$schema"
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
  local manifest_file="$SCRIPT_DIR/$VENDOR_APPS_PATH/$1/manifest.yaml"

  if [[ ! -f "$manifest_file" ]]; then
    echo "ERROR: Manifest file not found: $manifest_file" >&2
    exit 1
  fi

  local manifest=$(cat "$manifest_file" | yq ".$2")
  echo "$manifest"
}

insertAppletInDb() {
  local name="$1" summary="$2" desc="$3" author="$4" tags="$5" fileName="$6" packageName="$7" schema="$8"
  local sql="INSERT INTO applets (name, summary, desc, author, tags, file_name, package_name, schema) VALUES ('$name', '$summary', '$desc', '$author', '$tags', '$fileName', '$packageName', '$schema');"

  # echo "SQL: $sql"
  sqlite3 "$DATABASE_FILE" "$sql"
}

checkWebpDirectory() {
  if [ ! -d "$WEBP_LOCATION" ]; then
    mkdir -p "$WEBP_LOCATION"
  fi
}

escape() {
  local s="$1"
  s="${s//$'\r'/}"
  s="${s//$'\n'/ }"
  s="$(printf '%s' "$s" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  s="${s//\'/''}"
  printf '%s' "$s"
}

################################################################################

if ! command -v yq &> /dev/null; then
  echo "Error: install 'yq' as this is a required dependency."
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR_APPS_PATH="vendor/tidbyt/apps"

checkWebpDirectory
applets=$(getAvailableApplets)
for applet in $applets; do
  echo "Render $applet"
  renderAppletImage "$applet"

  if [ "$1" == "--skip-db" ]; then
    echo "-skipping database tasks-"
    continue
  fi

  appletRows=$(getAppletsFromDbByPackageName "$applet")
  if [ -n "$appletRows" ]; then continue; fi

  echo "(new applet) - adding record in database"

  name=$(escape "$(getAppletDetails "$applet" 'name')")
  summary=$(escape "$(getAppletDetails "$applet" 'summary')")
  desc=$(escape "$(getAppletDetails "$applet" 'desc')")
  author=$(escape "$(getAppletDetails "$applet" 'author')")
  fileName=$(escape "$(getAppletDetails "$applet" 'fileName')")
  packageName=$(escape "$(getAppletDetails "$applet" 'packageName')")
  appletSchema=$(escape "$(getAppletSchema "$packageName" "$fileName")")
  insertAppletInDb "$name" "$summary" "$desc" "$author" "" "$fileName" "$packageName" "$appletSchema"

  echo
done
