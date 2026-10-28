# Watch recovery candidate — not published

718 physically failed with InvalidPairRecord (51), despite valid application profile and certificate. The X.509 chain correction did not resolve it. No new public IPA or source update is authorized without physical installation verification.

The published installer reused RP identifier as both HostID and SystemBUID and generated a fresh candidate key chain whenever Pair failed. New candidate code creates independent persistent uppercase UUID host identities for Watch Lockdown, preserves pending keys before trust, and replays the same public certificate bytes after restart. These are corrections to state management, not proof of the physical rejection's cause.

The primary interface has one install action. IP/App ID/IPA controls are available only in advanced tools. An explicit attempt considers only this SideStore's current-build job. OS trust confirmation cannot be automated away.

Reference: Rzbck/isideload f7b9f3da570edd6824c29680545e710846d07df5, HANDOFF_ONE_CLICK_WATCH_SUCCESS.md documents an actual desktop/TCP install. That evidence does not validate our on-device RPPairing/RSD route or watchOS 10.6.2.

This branch runs native protocol/crypto tests and iPhone/watchOS compilation only. It does not package or publish an IPA, nor modify either source feed. Physical installation and renewal remain unverified. Full autonomous Watch store is not implemented.


## Verified checks, 2026-10-28

Code: 84a38534ff8bf875062d4f4583a4853a9b9fe7e3. Actions https://github.com/polaca1/rese-a-google/actions/runs/40752322947, job 123042008013: success. Actual native iPhone FFI built and linked; actual Watch certificate generator, UUID identities, explicit request field types, secret exclusion and persisted request replay tested; 98 Swift model checks; watchOS 10 arm64_32 and full iPhone archive compiled successfully. There is no packaged/distributed iPhone IPA from this workflow. Neither feed is changed. These checks do not prove physical Watch pairing, app installation, opening or renewal. The current actual user report remains build718/InvalidPairRecord51. No access to the user's physical Watch exists from this session.

Pending optional user clarification: with 718 does the Watch display Trust again or fail before displaying it? User has not answered. A Watch restart was suggested based on the documented desktop case; no physical result has been reported. Do not turn this suggestion into a confirmed fix.
