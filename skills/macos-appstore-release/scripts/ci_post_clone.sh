#!/bin/sh
# Xcode Cloud hook: runs right after cloning the repo, before any build step.
#
# If your .xcodeproj isn't committed (XcodeGen output regenerated locally with
# `xcodegen generate` before every build/archive/test — the usual setup when project.yml is the
# source of truth), Xcode Cloud's VM clones the repo fresh with no project file in it at all,
# and every workflow fails immediately with:
#   "Project YourApp.xcodeproj does not exist at the root of the repository"
#
# This script must live at ci_scripts/ci_post_clone.sh *at the repository root* when there's no
# checked-in .xcodeproj/.xcworkspace for Xcode Cloud to find it next to (if one exists elsewhere
# in the repo, ci_scripts goes beside that instead — this template assumes the no-project-file
# case). It needs the executable bit set:
#   chmod +x ci_scripts/ci_post_clone.sh
set -euo pipefail

echo "==> Installing XcodeGen"
brew install xcodegen

echo "==> Generating the Xcode project"
cd "$CI_PRIMARY_REPOSITORY_PATH"
xcodegen generate
