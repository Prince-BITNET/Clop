#!/bin/bash
# build_and_install.sh
# Single command to pull latest from upstream, apply local dev patches, build, and install Clop
#
# Usage:
#   ./build_and_install.sh          # pull + build + install
#   ./build_and_install.sh --clean  # also clean SPM cache (use if dependencies changed)
#   ./build_and_install.sh --local  # skip git pull, just build + install

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Xcode/SPM cannot build C shims when the shell sets CC="ccache clang".
unset CC CXX USE_CCACHE CCACHE_CPP2 CCACHE_DIR CCACHE_MAXSIZE
PATH="$(echo "$PATH" | tr ':' '\n' | grep -v 'ccache/libexec' | tr '\n' ':' | sed 's/:$//')"

CLEAN=false
SKIP_PULL=false
PULLED_UPSTREAM=false
for arg in "$@"; do
  case "$arg" in
    --clean) CLEAN=true ;;
    --local) SKIP_PULL=true ;;
  esac
done

# ── 1. Pull latest from upstream ──────────────────────────────────────────────
if [ "$SKIP_PULL" = false ]; then
  echo "📥 Pulling latest from upstream..."

  # Backup this script (upstream doesn't have it)
  cp "$SCRIPT_DIR/build_and_install.sh" /tmp/_clop_build_and_install.sh.bak

  # Fetch latest from upstream
  git fetch upstream main

  # Hard-reset to upstream/main (safe because all local patches are re-applied below)
  git reset --hard upstream/main

  # Restore this script
  cp /tmp/_clop_build_and_install.sh.bak "$SCRIPT_DIR/build_and_install.sh"
  chmod +x "$SCRIPT_DIR/build_and_install.sh"

  PULLED_UPSTREAM=true
  echo "✅ Updated to latest upstream"
fi

# ── 2. Apply local dev patches ────────────────────────────────────────────────
echo "🔧 Applying local development patches..."

# 2a. Set DEVELOPMENT_TEAM to empty for ad-hoc signing
sed -i '' 's/DEVELOPMENT_TEAM = RDDXV84A73/DEVELOPMENT_TEAM = ""/g' Clop.xcodeproj/project.pbxproj
echo "   ✓ DEVELOPMENT_TEAM set to ad-hoc"

# 2b. Remove iCloud entitlements (require development certificate)
cat > Clop/Clop.entitlements << 'ENTITLEMENTS_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.automation.apple-events</key>
	<true/>
	<key>com.apple.security.temporary-exception.mach-lookup.global-name</key>
	<array>
		<string>com.lowtechguys.Clop.optimisationServiceResponse</string>
		<string>com.lowtechguys.Clop.optimisationServiceResponseCLI</string>
	</array>
	<key>com.apple.security.temporary-exception.mach-register.global-name</key>
	<array>
		<string>com.lowtechguys.Clop.optimisationService</string>
		<string>com.lowtechguys.Clop.optimisationServiceStop</string>
	</array>
</dict>
</plist>
ENTITLEMENTS_EOF
echo "   ✓ iCloud entitlements removed"

# 2c. Pro/license stubs live in required.swift since Clop 3.0.0 (see step 2e)

# 2d. Remove 'import Defaults' from Shared.swift if present (breaks FinderOptimiser)
sed -i '' '/^import Defaults$/d' Shared.swift
echo "   ✓ Shared.swift patched"

# 2e. Ensure required.swift exists with stub functions
cat > Clop/required.swift << 'REQUIRED_EOF'
// required.swift — Local development stubs (gitignored)
import Foundation

@inline(__always) var proactive: Bool { true }

func validReq() -> Bool { true }

@discardableResult
func invalidReq(_ products: [Any], _ window: Any?) -> Bool { true }

@discardableResult
func invalidReq2(_ products: [Any], _ window: Any?) -> Bool { true }

@discardableResult
func invalidReq3(_ products: [Any], _ window: Any?) -> Bool { true }

func meetsInternalRequirements() -> Bool { true }

@discardableResult
func checkInternalRequirements(_ products: [Any], _ window: Any?) -> Bool { true }

@discardableResult
func checkInternalRequirements2(_ products: [Any], _ window: Any?) -> Bool { true }

@discardableResult
func checkInternalRequirements3(_ products: [Any], _ window: Any?) -> Bool { true }

func hasShortcutsDB() -> Bool { true }
REQUIRED_EOF
echo "   ✓ required.swift stubs created (Pro features unlocked)"

# 2f. Fix type inference in Images.swift if needed (x86_64 empty array)
if grep -q 'let archDependentArgs = \[\]' Clop/Images.swift 2>/dev/null; then
  sed -i '' 's/let archDependentArgs = \[\]/let archDependentArgs: [String] = []/g' Clop/Images.swift
  echo "   ✓ Images.swift type fix applied"
fi

# 2g. WarpDrop is a local-only SPM dependency in upstream (alin23's machine path).
#     Provide a compile-time stub and point the Xcode project at it.
WARP_DROP_DIR="$SCRIPT_DIR/Vendor/warpdrop/swift"
mkdir -p "$WARP_DROP_DIR/Sources/WarpDrop"

cat > "$WARP_DROP_DIR/Package.swift" << 'WARPDROP_PACKAGE_EOF'
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WarpDrop",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "WarpDrop", targets: ["WarpDrop"]),
    ],
    targets: [
        .target(name: "WarpDrop"),
    ]
)
WARPDROP_PACKAGE_EOF

cat > "$WARP_DROP_DIR/Sources/WarpDrop/WarpDropClient.swift" << 'WARPDROP_CLIENT_EOF'
import Foundation

public enum WarpDropError: Error, LocalizedError {
    case stubImplementation

    public var errorDescription: String? {
        "WarpDrop is unavailable in local dev builds (upstream uses a private package)."
    }
}

public struct WarpDropClient: Sendable {
    public init() {}

    public func send(
        files: [URL],
        keep: Bool,
        onRoomCreated: @escaping @Sendable (String) -> Void,
        onDownloadCompleted: @escaping @Sendable (Int) -> Void
    ) async throws -> String {
        throw WarpDropError.stubImplementation
    }
}
WARPDROP_CLIENT_EOF

sed -i '' \
  -e 's|relativePath = ../../../Github/alin23/warpdrop/swift|relativePath = Vendor/warpdrop/swift|g' \
  -e 's|relativePath = ../Vendor/warpdrop/swift|relativePath = Vendor/warpdrop/swift|g' \
  Clop.xcodeproj/project.pbxproj
echo "   ✓ WarpDrop stub package configured"

# 2h. Update WarpDropManager.swift to match the stub API (keep instead of multi/maxReceivers)
python3 -c "
import re
with open('Clop/WarpDropManager.swift') as f:
    content = f.read()

# Replace the two client.send calls — remove multi/maxReceivers, add keep: true
content = content.replace(
    '''            files: files,
            multi: true, // serve every receiver at once instead of one-at-a-time
            maxReceivers: 20, // 0 = server default (256); old backends ignore multi and fall back to sequential
            onRoomCreated:''',
    '''            files: files,
            keep: true,
            onRoomCreated:'''
)
content = content.replace(
    '''            files: [url],
            multi: true, // serve every receiver at once instead of one-at-a-time
            maxReceivers: 20, // 0 = server default (256); old backends ignore multi and fall back to sequential
            onRoomCreated:''',
    '''            files: [url],
            keep: true,
            onRoomCreated:'''
)
with open('Clop/WarpDropManager.swift', 'w') as f:
    f.write(content)
"
echo "   ✓ WarpDropManager.swift patched for stub API"
# ── 3. Kill existing Clop ─────────────────────────────────────────────────────
pkill -9 Clop 2>/dev/null || true
sleep 1

# ── 4. Resolve SPM dependencies ───────────────────────────────────────────────
refresh_spm() {
  # Lowtech tracks the ventura branch; stale pins keep old revisions without bareKeys.
  if [ -f Clop.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved ]; then
    python3 - <<'PY'
import json
from pathlib import Path

path = Path("Clop.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved")
data = json.loads(path.read_text())
data["pins"] = [pin for pin in data.get("pins", []) if pin.get("identity") != "lowtech"]
path.write_text(json.dumps(data, indent=2) + "\n")
PY
  fi

  echo "📦 Resolving packages..."
  xcodebuild -resolvePackageDependencies \
    -project Clop.xcodeproj \
    -clonedSourcePackagesDirPath ./build/SourcePackages \
    -quiet 2>/dev/null || true
}

if [ "$PULLED_UPSTREAM" = true ] || [ "$CLEAN" = true ] || [ ! -d "./build/SourcePackages" ]; then
  echo "🧹 Cleaning SPM package cache..."
  rm -rf ./build/SourcePackages
fi
refresh_spm

# ── 5. Build ──────────────────────────────────────────────────────────────────
echo "🔨 Building Clop..."
if ! xcodebuild build \
  -project Clop.xcodeproj \
  -scheme Clop \
  -configuration Release \
  -derivedDataPath ./build \
  -clonedSourcePackagesDirPath ./build/SourcePackages \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=YES \
  DEVELOPMENT_TEAM="" \
  -quiet 2>/dev/null; then

  echo "⚠️  Build failed. Retrying with clean SPM cache..."
  rm -rf ./build/SourcePackages ./build/Build
  refresh_spm

  xcodebuild build \
    -project Clop.xcodeproj \
    -scheme Clop \
    -configuration Release \
    -derivedDataPath ./build \
    -clonedSourcePackagesDirPath ./build/SourcePackages \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=YES \
    DEVELOPMENT_TEAM="" \
    -quiet
fi

echo "✅ Build succeeded"

# ── 6. Install ────────────────────────────────────────────────────────────────
echo "📦 Installing to /Applications..."
rm -rf /Applications/Clop.app
cp -r ./build/Build/Products/Release/Clop.app /Applications/

# ── 7. Re-sign all components ─────────────────────────────────────────────────
echo "🔏 Signing app components..."
find /Applications/Clop.app -type d \( -name "*.framework" -o -name "*.appex" \) | while read f; do
  codesign --force --sign - "$f" 2>/dev/null || true
done
codesign --force --sign - /Applications/Clop.app/Contents/SharedSupport/ClopCLI 2>/dev/null || true
codesign --force --sign - /Applications/Clop.app 2>/dev/null || true

# ── 8. Remove quarantine ──────────────────────────────────────────────────────
xattr -rd com.apple.quarantine /Applications/Clop.app 2>/dev/null || true

echo ""
echo "✅ Clop installed successfully to /Applications/Clop.app"
echo "🚀 Launching..."
open /Applications/Clop.app
