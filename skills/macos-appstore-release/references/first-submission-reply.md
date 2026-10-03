# Replying to "Guideline 2.1 — Information Needed — New App Submission"

## What this is (and isn't)

A brand-new developer account's first submission commonly gets this automatic request. It is
**not** a bug or crash rejection — App Review is asking for context because the account has no
review history yet. Don't spend time looking for a reproduction step or a crash log; there isn't
one. The fix is answering the questions, not changing the app.

Apple's request asks for six things. Reply with all six **in two places**:
1. **Reply to App Review** (App Store Connect may label this "Resolution Center" on older UI) —
   the actual reply thread.
2. **Copied into the Notes field of App Review Information** on the same version — Apple
   explicitly asks for this duplicate so the information is available for future submissions too,
   not just this one.

Keep Apple's own numbering (1–6) in your reply so the reviewer can match it against their
checklist at a glance.

## Template

Fill in the bracketed app-specific paragraphs. Keep the structure and numbering; this is the
shape Apple's own request uses.

```
Hello,

Thank you for reviewing [App Name]. Please find the requested information below.

1. Screen recording
[LINK TO VIDEO]
The recording shows [launching the app, the core user flow, and — if the app gates any feature
behind a purchase — triggering that purchase flow explicitly, since Apple calls out "accessing
paid content" as something the recording must show].

2. App purpose and target audience
[What the app does, in plain terms. Who it's for. What problem it solves and why that audience
specifically needs it. Two short paragraphs is usually enough — this doesn't need to be the App
Store description, just enough for a reviewer unfamiliar with the space to understand what
they're about to test.]

3. Setup and accessing main features
[State plainly whether an account/login is required. If not, say so explicitly — it answers one
of Apple's own "Prevent Common Issues" bullets about demo credentials before they have to ask.
Then: a short numbered setup sequence, and a list of the main features/shortcuts with one line
each on what they do. If any feature is paywalled, say so here too and mention any free-trial
mechanism.]

4. External services
[Name every external service, SDK, or API the app talks to, however minor — including Apple's own
(StoreKit for IAP, etc.). If the honest answer is "none beyond store purchase processing," say
that plainly: it's a stronger, clearer answer than a vague "we use standard services."]

5. Regional differences
[State whether the app behaves identically everywhere it's offered. If you've deliberately
excluded any storefronts (e.g. not yet offered in the EU pending a trader-status decision), say so
here as a deliberate, known choice — not something a reviewer needs to flag.]

6. Regulated industry / protected material
[Usually: "Not applicable" plus one sentence on why (no licensed/third-party content, not
operating in a regulated space). If it does apply, provide the actual documentation/credentials
Apple asks for here.]

Please let me know if any further information is needed. Thank you for your time.

Best regards,
[Your name]
```

## The screen recording specifically

See the main SKILL.md's section on recording this safely — the short version is: have a human
record it with QuickTime's "Record Selected Portion" rather than an agent driving a full-screen
capture, unless the privacy/coordinate-math tradeoffs are explicitly understood and accepted.

The recording must:
- Start from launching the app.
- Show the typical user flow, not just a splash/login screen (guideline 2.3.3 calls this out
  specifically for screenshots, and the same spirit applies to the recording).
- Include account registration/login/deletion if the app has any — if it doesn't, you don't need
  to perform anything to prove a negative, just say so in section 3.
- Include accessing paid content/features if the app has any — don't skip past a paywall; show it
  actually appearing.
