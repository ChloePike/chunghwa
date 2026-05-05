<!--
Thanks for contributing. A short PR is the fastest to review.
Delete any section that doesn't apply.
-->

## Summary

<!-- One or two sentences. Why does this PR exist? -->

## What changed

<!-- Bullet list of concrete edits -->

## Testing

<!--
How you exercised it. Whether you ran the app + which tab(s) you
touched. For changes that affect mihomo lifecycle (kernel start /
reload / restart) note whether you verified system proxy / TUN are
still functional. For changes to ConfigComposer say which profile
shapes you tested (default profile, subscription with `dns:` block,
subscription without).
-->

## Notes for reviewers

<!--
Tricky tradeoffs, follow-up PRs, areas where you'd like a sanity check.
-->

## Checklist

- [ ] `xcodebuild ... build` succeeds with no new warnings
- [ ] No personal identifiers in the diff (DEVELOPMENT_TEAM, real names,
      email addresses, certs)
- [ ] No `pkill ChungHwa` / explicit relaunch in scripts (CLAUDE.md)
- [ ] Comments and code are English; user-facing strings can be Chinese
- [ ] If the change persists state, it goes through SQLite (`Database`)
      or `ConfigStore.*Key` UserDefaults — no new ad-hoc JSON files
