# The `-exportArchive` / IDEDistributionMethodManager bug

## Symptom

```
error: exportArchive exportOptionsPlist error for key "method" expected one {} but found app-store-connect
** EXPORT FAILED **
```

preceded by:

```
[MT] IDEDistribution: -[IDEDistributionMethodManager orderedDistributionMethodsForTask:archive:logAspect:]:
Error = Error Domain=IDEDistributionMethodManagerErrorDomain Code=2 "Unknown Distribution Error"
```

This reproduced identically in three independent environments on the project where this was
diagnosed:
- A plain Terminal `xcodebuild -exportArchive` call, with a valid App Store Connect API key.
- Xcode's own Organizer → Distribute App, which never offered more than "Custom" as a
  distribution method (and "Custom" → "Build Products" just copies the already-built .app as-is,
  with whatever signing it already has — not useful for App Store submission).
- Xcode Cloud's own build servers, running the project's real, committed workflow — ruling out
  anything specific to the local machine, Apple ID session, or shell environment.

It also reproduced with `method: development` — the simplest possible export method, needing no
certificate at all beyond what a totally fresh Apple ID already has. That's the detail that rules
out certificates, provisioning profiles, team membership, and account standing as the cause: if a
*development* export fails the same way, the problem isn't about what you're authorized to sign
with.

## Root cause

Compare a freshly built archive's own `Info.plist` (not the app's Info.plist inside it — the
archive wrapper's) against what a healthy one should have:

```bash
/usr/libexec/PlistBuddy -c "Print" YourApp.xcarchive/Info.plist
```

A broken archive looks like this — note what's missing:

```
Dict {
    ArchiveVersion = 2
    Name = YourApp
    SchemeName = YourApp
    CreationDate = ...
}
```

A healthy archive has an additional `ApplicationProperties` dict (bundle identifier, version,
signing identity, team) that `IDEDistributionMethodManager` reads to decide which distribution
methods a given archive is even eligible for. Without it, every method gets evaluated and
rejected the same way — the verbose distribution log (downloadable from a failed Xcode Cloud
build, or via `-IDEDistributionLogDirectory` locally) shows literally every method rejected for
"doesn't support distributing archive", including Developer ID, plain "Export Archive", and
"Save Built Products" ending up as the only thing accepted:

```
Rejected distribution method <IDEDistributionMethodMacAppStoreDistribution: ...> because it doesn't support distributing archive
Rejected distribution method <IDEDistributionMethodDeveloperID: ...> because it doesn't support distributing archive
Rejected distribution method <IDEDistributionMethodExportArchive: ...> because it doesn't support distributing archive
Accepted distribution method <IDEDistributionMethodSaveBuiltProducts: ...>
Available distribution methods: { <IDEDistributionMethodSaveBuiltProducts>, <IDEDistributionMethodExportArchive> }
```

(`ExportArchive` shows as "accepted" in one pass of the log and "rejected" in the next — the
method list gets evaluated multiple times with inconsistent results, which is itself a signal
this is an internal Xcode bug rather than a configuration issue you can fix by changing project
settings.)

Why `ApplicationProperties` doesn't get populated wasn't fully root-caused (it would require
Apple's own source/symbols to confirm) — what's confirmed is that it's reproducible across
`xcodebuild archive` runs regardless of scheme, configuration, or signing identity used, so it
isn't something a `project.yml`/build-settings change fixes. Treat it as an environment/toolchain
bug in the Xcode version in use at the time (Xcode 26.x), not something to keep chasing a project
fix for.

## The workaround

Don't use `-exportArchive` at all. The archived `.app` itself, once correctly signed (see the
XcodeGen signing trap in the main SKILL.md — verify this *first*, it's a separate, much more
common problem that produces similar-looking downstream symptoms), is already everything you
need:

```bash
# Sign + package in one step, straight from the archive — no export involved.
productbuild --component "$ARCHIVE/Products/Applications/YourApp.app" /Applications \
  --sign "3rd Party Mac Developer Installer: Your Name (TEAMID)" \
  YourApp.pkg

# A completely different upload path from -exportArchive's, unaffected by
# IDEDistributionMethodManager.
xcrun altool --upload-package YourApp.pkg --type macos \
  --api-key YOUR_KEY_ID --api-issuer YOUR_ISSUER_ID
```

`scripts/release-appstore.sh` in this skill implements the full pipeline (archive → verify
signing → verify sandbox/quarantine/icon → package → upload) with this workaround built in.

## If you hit this on a different project and want to confirm it's the same bug

1. Archive with any scheme/configuration you have, including a plain Developer ID one if the
   project has it.
2. Check that archive's `Info.plist` for `ApplicationProperties` as above — if it's missing there
   too, you've confirmed it's project-independent and the workaround applies.
3. If `ApplicationProperties` *is* present and export still fails, this is a different problem —
   don't apply this workaround blind; look at the actual exportOptionsPlist and signing identity
   being resolved instead.
