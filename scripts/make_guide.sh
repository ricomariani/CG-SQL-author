#!/bin/bash

set -o errexit -o nounset -o pipefail

readonly CLI_NAME=${0##*/}
readonly SCRIPT_DIR_RELATIVE=$(dirname "$0")
readonly OUT=$SCRIPT_DIR_RELATIVE/out

mkdir -p $OUT
debug() { echo $@ >&2; }


guide_type=$1
guide_name=$2

debug "Building $guide_type"


# Clean up previous build outputs

mkdir -p "$OUT"
rm -f "$OUT/$guide_type.*"


# Build Intermediate Markdown output

shift 2
sources=$@
target="$OUT/$guide_type.md"

echo "<!--- @generated by $CLI_NAME -->\n" > $target
for source in $sources; do
    cat "$source" >> "$target"
    echo -e "\n\n" >> "$target"
done

debug "$target was successfully created" >&2


# Build Final HTML output

source="$OUT/$guide_type.md"
target="$OUT/$guide_type.html"

pandoc $source \
    --metadata title="$guide_name" \
    --toc \
    --standalone \
    --wrap=none \
    --from markdown \
    --to html \
    --output $target

echo -e "<!--- @generated by $CLI_NAME -->\n" > $target

debug "$target was successfully created"