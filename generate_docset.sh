#!/bin/sh
# build-chapel-docset-wget.sh
# Generate Zeal/Dash docset for Chapel 2.6 downloading HTML documentation with wget.
# FreeBSD compatible, no external app needed (No Sphinx no Python)

set -eu

CHPL_VERSION="${1:-2.6}"
BASE_URL="https://chapel-lang.org/docs/"
WORK_DIR="$(pwd)/chapel-docset-$CHPL_VERSION"
DOCSET_NAME="Chapel-$CHPL_VERSION.docset"
DOCSET_DIR="$WORK_DIR/$DOCSET_NAME"
DOCSET_RES="$DOCSET_DIR/Contents/Resources"
DOCSET_DOCS="$DOCSET_RES/Documents"
DOCSET_DB="$DOCSET_RES/docSet.dsidx"
DOCSET_PLIST="$DOCSET_DIR/Contents/Info.plist"

msg() { printf '\033[1;36m==>\033[0m %s\n' "$@"; }

# --- Requisitos ---
for cmd in wget sqlite3 awk sed tar; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: falta el comando $cmd"
    exit 1
  fi
done

# --- Prepare structure ---
msg "Creating structure..."
rm -rf "$WORK_DIR"
mkdir -p "$DOCSET_DOCS"

# --- Download documentation with wget ---
msg "Downloading Chapel $CHPL_VERSION documentation ..."
cd "$WORK_DIR"

wget --mirror \
     --convert-links \
     --adjust-extension \
     --page-requisites \
     --no-parent \
     --no-verbose \
     --directory-prefix="$DOCSET_DOCS" \
     --domains=chapel-lang.org \
     "$BASE_URL/"

# Sometimmes, wgets create file tree with  chapel-lang.org/docs, move it to rigth pwd:
if [ -d "$DOCSET_DOCS/chapel-lang.org/docs" ]; then
  mv "$DOCSET_DOCS/chapel-lang.org/docs"/* "$DOCSET_DOCS"/
  rm -rf "$DOCSET_DOCS/chapel-lang.org"
fi

# --- Create Info.plist ---
msg "Buildind Info.plist..."
mkdir -p "$(dirname "$DOCSET_PLIST")"
cat > "$DOCSET_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleIdentifier</key>
	<string>chapel</string>
	<key>CFBundleName</key>
	<string>Chapel $CHPL_VERSION</string>
	<key>DocSetPlatformFamily</key>
	<string>chapel</string>
	<key>isDashDocset</key>
	<true/>
	<key>dashIndexFilePath</key>
	<string>index.html</string>
</dict>
</plist>
EOF

# --- Indexing with SQLite ---
msg "Indexing ..."
mkdir -p "$DOCSET_RES"
sqlite3 "$DOCSET_DB" <<'SQL'
CREATE TABLE searchIndex(id INTEGER PRIMARY KEY, name TEXT, type TEXT, path TEXT);
CREATE UNIQUE INDEX anchor ON searchIndex (name, type, path);
SQL

find "$DOCSET_DOCS" -type f -name '*.html' | while read -r f; do
  relpath=$(echo "$f" | sed "s|^$DOCSET_DOCS/||")
  title=$(awk 'BEGIN{IGNORECASE=1} /<title>/{
      gsub(/.*<title>/,"",$0);
      gsub(/<\/title>.*/,"",$0);
      print; exit
  }' "$f" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' |
  # Decode common HTML entities
  sed -e 's/&mdash;/—/g' \
    -e 's/&ndash;/–/g' \
    -e 's/&lt;/</g' \
    -e 's/&gt;/>/g' \
    -e 's/&amp;/\&/g' \
    -e "s/&quot;/\"/g" \
    -e "s/&#39;/'/g" \
    -e 's/&nbsp;/ /g') 
  [ -z "$title" ] && title=$(basename "$f")

  low=$(echo "$title" | tr '[:upper:]' '[:lower:]')
  if echo "$low" | grep -q "module"; then type="Module"
  elif echo "$low" | grep -q "function"; then type="Function"
  elif echo "$low" | grep -Eq "record|class"; then type="Type"
  elif echo "$low" | grep -q "keyword"; then type="Keyword"
  else type="Guide"
  fi

  sqlite3 "$DOCSET_DB" "INSERT OR IGNORE INTO searchIndex(name,type,path) VALUES('$title','$type','$relpath');" 2>/dev/null || true
done

# --- Verify ---
msg "Verifying index.html..."
if [ ! -f "$DOCSET_DOCS/index.html" ]; then
  echo '<meta http-equiv="refresh" content="0; url=usingchapel/index.html">' > "$DOCSET_DOCS/index.html"
fi

# --- Compact ---
msg "Compressing docset..."
cd "$WORK_DIR"
tar --exclude='.DS_Store' -czf "Chapel-$CHPL_VERSION.tgz" "$DOCSET_NAME"

msg "Docset done:"
echo "   $DOCSET_DIR"
echo "   $WORK_DIR/Chapel-$CHPL_VERSION.tgz"
echo
echo "For use in Zeal:"
echo "   cp -r $DOCSET_DIR ~/.local/share/Zeal/Zeal/docsets/"
echo "   # or import .tgz from Zeal -> File -> Import Docset"
