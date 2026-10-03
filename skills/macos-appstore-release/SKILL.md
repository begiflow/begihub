---
name: macos-appstore-release
description: Guides building, signing, and uploading a macOS app to App Store Connect — especially for XcodeGen-based projects (project.yml, no committed .xcodeproj). Use this whenever the user wants to archive/export/submit a Mac app for the Mac App Store, hits any xcodebuild or Xcode Organizer signing/export error, needs to create or diagnose Apple Distribution / Mac Installer Distribution certificates or a Mac App Store provisioning profile, sets up Xcode Cloud for a project whose .xcodeproj isn't in git, or sees errors like "doesn't support distributing archive", "Unknown Distribution Error", "expected one {} but found app-store-connect", "CODE_SIGN_IDENTITY ... -", or "conflicting code signing identity". Also covers safely recording an App Review demo video and answering a first-submission "Guideline 2.1 — Information Needed" request. Trigger this proactively — don't wait for the user to ask "how do I fix this Xcode error," a vague "my app won't upload" or "archive failed" is enough.
---

# macOS App Store release

Everything here was earned the hard way on a real submission: hours of chasing certificate/account
theories before finding the actual bug. Read this before touching `xcodebuild archive`,
`-exportArchive`, Xcode Cloud, or Organizer for a Mac App Store submission — it will save you
that time.

## The one-paragraph version

`xcodebuild -exportArchive` for the `app-store-connect` method is broken in ways that have
nothing to do with your certificates, your Apple ID, or your Developer Program enrollment —
confirmed by reproducing the identical failure from a plain Terminal, from Xcode's own Organizer,
and on Xcode Cloud's own build servers. **Don't fight it. Skip it entirely**: sign the archived
`.app` correctly (the real fix, see below), then build the `.pkg` with `productbuild` and upload
with `altool --upload-package`. `scripts/release-appstore.sh` in this skill does the whole
pipeline — copy it into the project's `scripts/` and adapt the three identity strings at the top.

## Pre-flight checklist (do this first, in order)

Skipping ahead to "just run the script" when one of these is missing produces confusing failures
later that look unrelated. Confirm each one before building anything:

1. **Apple Developer Program membership is active** (not a brand-new pending enrollment — those
   can take hours to fully propagate through Apple's distribution-eligibility systems even though
   the portal itself already works).
2. **Bundle ID registered** as an explicit App ID in developer.apple.com → Certificates,
   Identifiers & Profiles → Identifiers, with every capability the app actually uses ticked
   (e.g. In-App Purchase). App Sandbox is *not* a capability toggled here — it lives purely in the
   app's own `.entitlements` file.
3. **Two certificates**, created manually — `-allowProvisioningUpdates` and an API key do **not**
   reliably create these on their own, confirmed across three different build environments in this
   same session:
   - **Apple Distribution** (signs the app itself)
   - **Mac Installer Distribution**, a.k.a. "3rd Party Mac Developer Installer" (signs the `.pkg`)

   Both need a CSR first: Keychain Access → Certificate Assistant → Request a Certificate from a
   Certificate Authority → Saved to disk. Upload that same CSR for each cert on
   developer.apple.com → Certificates → **+**, download each `.cer`, double-click to install.
4. **A Mac App Store provisioning profile** for the bundle ID, using the Apple Distribution
   certificate from step 3. Create it under Profiles → **+** → the App Store Connect / Mac App
   Store distribution type. Name it something you'll recognize (e.g. `"<App> App Store"`) — you
   reference that exact name later. Download the `.provisionprofile`; if double-clicking doesn't
   visibly install it, confirm with `ls ~/Library/MobileDevice/Provisioning\ Profiles/` and copy it
   there yourself if the folder doesn't exist yet.
5. Verify both certs actually landed with a private key attached:
   ```bash
   security find-identity -v -p codesigning
   ```
   You want to see both `Apple Distribution: ...` and `3rd Party Mac Developer Installer: ...` in
   the list. If either is missing, the cert creation in step 3 didn't finish — redo it before going
   any further.
6. **App Store Connect API key** for scripted uploads: Users and Access → Integrations → App Store
   Connect API → generate with the **App Manager** role, download the `.p8` once, then:
   ```bash
   mkdir -p ~/.appstoreconnect/private_keys
   cp ~/Downloads/AuthKey_XXXXXXXXXX.p8 ~/.appstoreconnect/private_keys/
   ```
   `altool --upload-package` only looks in that exact directory (and a couple of siblings) — not
   wherever you pass as a path argument elsewhere. See the gotchas table below.

## The XcodeGen signing trap (do this before your first archive)

If `project.yml` doesn't set an explicit `CODE_SIGN_IDENTITY` for the App Store build
configuration, Xcode silently defaults that target+config combination to
`CODE_SIGN_IDENTITY[sdk=macosx*] = "-"` — **ad hoc signing**. The archive still "succeeds" with no
error, looks completely normal, and is permanently unusable for any real distribution. This is the
single most time-costly trap in the whole pipeline because every symptom downstream (export
failures, Organizer missing the App Store option, Xcode Cloud rejecting every distribution method)
*looks* like a certificate or account problem and isn't.

Set this explicitly once certs + profile exist (step 3–4 above):

```yaml
settings:
  configs:
    AppStore:                                  # or whatever your App Store config is named
      CODE_SIGN_STYLE: Manual
      CODE_SIGN_IDENTITY: "Apple Distribution"
      PROVISIONING_PROFILE_SPECIFIER: "<exact profile name from step 4>"
```

`CODE_SIGN_STYLE: Automatic` with just an identity override will fail archiving outright once a
profile exists too — `"... is automatically signed for development, but a conflicting code
signing identity Apple Distribution has been manually specified"`. Manual signing with an exact
identity + exact profile name removes the ambiguity that produces both failure modes.

**Verify the fix before trusting it**: archive, then check what actually got used — don't just
check that the archive step exited 0.

```bash
codesign -dvvv path/to/Built.app 2>&1 | grep Authority
# must show: Authority=Apple Distribution: ...
# NOT: Authority=Apple Development: ... (means the trap is still active)
```

## Why `-exportArchive` fails and what to do instead

Full diagnosis (the IDEDistribution log evidence, how to confirm it's the same bug on a different
project) is in `references/exportarchive-bug.md` — read it if you want to understand *why*, or if
this skill's workaround doesn't apply cleanly to your situation. The short version: every archive
`xcodebuild archive` produces is missing the `ApplicationProperties` dict from its own
`Info.plist`. `IDEDistributionMethodManager` (the component inside `-exportArchive`, Organizer's
Distribute App, *and* Xcode Cloud's own export step — all three, confirmed independently) reads
that dict to decide which distribution methods apply to an archive. Missing it, every method is
rejected with "doesn't support distributing archive" — including Developer ID and even the bare
"Export Archive" method, which is what proves it's not a signing/account/certificate problem.

The fix: don't ask Xcode to export the archive at all.

```bash
# Sign + package straight from the archived .app — no -exportArchive involved.
productbuild --component "$ARCHIVE/Products/Applications/YourApp.app" /Applications \
  --sign "3rd Party Mac Developer Installer: Your Name (TEAMID)" \
  YourApp.pkg

# Upload via a completely separate code path, unaffected by IDEDistributionMethodManager.
xcrun altool --upload-package YourApp.pkg \
  --type macos \
  --api-key YOUR_KEY_ID \
  --api-issuer YOUR_ISSUER_ID
```

`scripts/release-appstore.sh` wraps this into a full archive → verify → package → upload pipeline.
Copy it into the project, update the three identity/team strings at the top, and run it. It
includes the verification checks (signing identity, sandbox entitlement, no quarantine, icon
present) that catch the XcodeGen trap and other silent failures *before* wasting time on a pkg
build or upload that was always going to be rejected.

## Gotchas that will cost you 20 minutes each if you don't know them

| Symptom | Cause | Fix |
|---|---|---|
| `altool` error: "Failed to load AuthKey file" even though you passed a path | `--upload-package` ignores explicit key-path arguments and only searches `./private_keys`, `~/private_keys`, `~/.private_keys`, `~/.appstoreconnect/private_keys` | Put the `.p8` at `~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8` exactly |
| `altool`: "Expected apple ID argument is missing" when you *did* pass auth | Used `--apiKey`/`--apiIssuer` (camelCase) | The real flags are hyphenated: `--api-key` / `--api-issuer` |
| A `codesign \| grep -q pattern` check fails even though the pattern is clearly in the output | Under `set -o pipefail`, `grep -q` exiting the instant it finds a match can SIGPIPE the still-writing upstream process, and `pipefail` reports *that* exit code instead of grep's success | Capture output to a variable first — `OUT="$(codesign ...)"; echo "$OUT" \| grep -q ...` — never pipe a live process straight into a `-q` grep under `pipefail` |
| Xcode Cloud fails instantly: "Project X.xcodeproj does not exist at the root of the repository" | The `.xcodeproj` is (correctly) gitignored — it's XcodeGen output, not source | Add `ci_scripts/ci_post_clone.sh` (template in this skill) that installs xcodegen and runs `xcodegen generate` before any build step |
| Organizer's Distribute App only ever offers "Custom", never "App Store Connect" | Same root cause as the exportArchive bug, or the XcodeGen signing trap if you haven't fixed that yet | Fix the signing trap first and re-check; if it's still only "Custom," that confirms the exportArchive bug — use the productbuild/altool path, don't keep hunting for the button |
| AppleScript `tell application "System Events" to click at {x, y}` silently does nothing to a custom-drawn list/table row | Synthetic `click at` doesn't reliably reach custom `NSTableRowView` click handlers — it's a different event path than a real click | Use `cliclick` (`brew install cliclick`) instead — `cliclick c:x,y` posts genuine HID-level events. For visible, human-paced cursor movement (e.g. recording a demo), use its `-e <easing>` option; `-e 1000` or higher is actually visible, `-e 100` still looks instantaneous |

## Recording an App Review demo video without leaking your screen

Apple's "Guideline 2.1 — Information Needed" request on a first submission (see next section) asks
for a screen recording. If you're tempted to record the *whole* screen and crop later: don't,
unless you can guarantee the crop region before you ever look at a frame of the raw file. A
full-screen recording on a machine actively being used — browser tabs, other windows, a live
terminal — captures all of it, and a wrong crop rectangle (multi-monitor setups are the usual
culprit) can leave unrelated windows fully visible in what you thought was a clean demo.

The reliable option is to have the human record it themselves with QuickTime Player's **Record
Selected Portion** (File → New Screen Recording → the dropdown next to the record button), dragging
the selection to just the app's window. It costs the user two minutes and sidesteps every privacy
and coordinate-math risk entirely. Prefer that over agent-driven full-screen capture unless the
user explicitly asks you to automate it *and* understands the tradeoff.

## Answering "Guideline 2.1 — Information Needed" on a first submission

A brand-new developer account's first submission commonly gets this automatic request — it is
**not** a bug/crash rejection, just App Review asking for context since the account has no history
yet. It asks for: a screen recording, the app's purpose/audience, setup instructions, external
services used, regional differences, and (if applicable) regulated-industry documentation. Reply
in **both** places — the "Reply to App Review" thread *and* copied into the Notes field of App
Review Information (Apple explicitly asks for both, and the Notes field persists for future
submissions). A template with the exact section headers Apple's own request uses is in
`references/first-submission-reply.md` — fill in the app-specific paragraphs, keep Apple's own
numbering so the reviewer can match your reply to their checklist.
