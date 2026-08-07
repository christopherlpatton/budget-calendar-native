#!/bin/zsh
set -euo pipefail

script_dir="$(cd "$(dirname "$0")/.." && pwd)"
output_dir="$script_dir/dist"
app_path="$output_dir/Budget Calendar Native.app"

cd "$script_dir"
swift build -c release --product BudgetCalendarApp

rm -rf "$app_path"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$script_dir/Packaging/Info.plist" "$app_path/Contents/Info.plist"
cp "$script_dir/.build/release/BudgetCalendarApp" "$app_path/Contents/MacOS/BudgetCalendarApp"

echo "Created unsigned development app: $app_path"
echo "Open it locally with: open \"$app_path\""
