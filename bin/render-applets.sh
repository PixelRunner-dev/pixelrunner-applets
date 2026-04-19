#!/bin/bash

set -e

DATABASE_FILE="../db.sqlite"
WEBP_LOCATION="./public"

getAvailableApplets() {
  local files=$(find applets -type l)
  echo "${files//applets\//}"
}

getAppletsFromDbByPackageName() {
  local records=$(sqlite3 -json $DATABASE_FILE "select * from applets where package_name = '$1';")
  echo "$records"
}

getAppletSchema() {
  local schema=$(node ./bin/pixlet.mjs schema "applets/$1/$2")
  echo "$schema"
}

renderAppletImage() {
  local packageName=$(getAppletDetails "$1" 'packageName')
  local fileName=$(getAppletDetails "$1" 'fileName')
  local image=$(node ./bin/pixlet.mjs render -o "$WEBP_LOCATION/$packageName.webp" -w 64 -t 32 -z 5 --locale en --format webp "applets/$packageName/$fileName")
  echo "$image"
}

getAppletDetails() {
  local manifest=$(cat "applets/$1/manifest.yaml" | yq ".$2")
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

checkWebpDirectory
appletFiles=$(getAvailableApplets)
for file in $appletFiles; do
  echo "Render $file"
  renderAppletImage "$file"

  appletRows=$(getAppletsFromDbByPackageName "$file")
  if [ "$1" == "--skip-db" ] || [ -n "$appletRows" ]; then continue; fi

  echo "(new applet) - adding record in database"

  name=$(escape "$(getAppletDetails "$file" 'name')")
  summary=$(escape "$(getAppletDetails "$file" 'summary')")
  desc=$(escape "$(getAppletDetails "$file" 'desc')")
  author=$(escape "$(getAppletDetails "$file" 'author')")
  fileName=$(escape "$(getAppletDetails "$file" 'fileName')")
  packageName=$(escape "$(getAppletDetails "$file" 'packageName')")
  appletSchema=$(escape "$(getAppletSchema "$packageName" "$fileName")")
  insertAppletInDb "$name" "$summary" "$desc" "$author" "" "$fileName" "$packageName" "$appletSchema"

  echo
done
