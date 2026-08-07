#!/bin/zsh
set -euo pipefail

script_dir="$(cd "$(dirname "$0")/.." && pwd)"
output_dir="$script_dir/dist"
app_path="$output_dir/Budget Calendar Native.app"
version="$(tr -d '[:space:]' < "$script_dir/VERSION")"
build_number="$(tr -d '[:space:]' < "$script_dir/BUILD_NUMBER")"
marketing_version="$(tr -d '[:space:]' < "$script_dir/MARKETING_VERSION")"

cd "$script_dir"
if ! print -r -- "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.-]+)?$'; then
  echo "Invalid VERSION: $version" >&2
  exit 1
fi
if ! print -r -- "$build_number" | grep -Eq '^[1-9][0-9]*$'; then
  echo "Invalid BUILD_NUMBER: $build_number" >&2
  exit 1
fi
if ! print -r -- "$marketing_version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "Invalid MARKETING_VERSION: $marketing_version" >&2
  exit 1
fi
swift build -c release --product BudgetCalendarApp

rm -rf "$app_path"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
sed -e "s/@VERSION@/$version/g" -e "s/@MARKETING_VERSION@/$marketing_version/g" -e "s/@BUILD_NUMBER@/$build_number/g" "$script_dir/Packaging/Info.plist" > "$app_path/Contents/Info.plist"
cp "$script_dir/.build/release/BudgetCalendarApp" "$app_path/Contents/MacOS/BudgetCalendarApp"

echo "Created unsigned preview app v$version ($build_number): $app_path"
echo "Open it locally with: open \"$app_path\""
