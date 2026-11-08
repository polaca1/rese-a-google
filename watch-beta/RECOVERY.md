# Current branch: own-identity variant 720

See [OWN-IDENTITY.md](OWN-IDENTITY.md) for the current separately installed app, its dedicated automatic Watch ID and verified public package. The following records the older legacy-identity build719.

# Watch recovery — build 719 delivered

Personal prerelease: https://github.com/polaca1/rese-a-google/releases/tag/sidestore-watch-beta-0.7.1-build719
IPA: https://github.com/polaca1/rese-a-google/releases/download/sidestore-watch-beta-0.7.1-build719/SideStore-Watch-Beta-0.7.1-build719.ipa

## Verified package
- Source commit: 490cde59f00d3676b6a4acc6a7512d999c627fd7
- Actions: https://github.com/polaca1/rese-a-google/actions/runs/42483652794
- Job: 128740740117; success.
- Size: 32353668 bytes.
- SHA-256: 9188a2c09092fead715fa944028b66b8e4ee74760454ce2a33a482d5799cee34
- Native FFI and crypto/request/identity tests passed; 98 Swift checks passed.
- Full iPhone and watchOS 10 arm64_32 builds passed.
- CI downloaded the actual public IPA and verified size, SHA-256, ZIP CRC, host identity/version and native Watch payload.
- PUBLIC-RECOVERY-VERIFICATION.json and source ZIP are release assets.
- Automatic source feeds were not changed.

## Correction and use
718 physically failed with InvalidPairRecord (51), despite a valid app profile/certificate. Its certificate-chain change did not solve the rejection.

719 contains the previously checked recovery code that was never included in 718: separate persistent uppercase UUID Watch HostID/SystemBUID; save pending pairing credentials before trust; replay the same public certificate bytes after interruption/relaunch; explicit allowed wire fields and private-key exclusion. It does not change iPhone pairing or create App IDs.

One primary action installs the included SideStore Watch component: detect, choose only an existing eligible SideStore child ID, request profile, sign and transfer. IP/ID/IPA controls are only in advanced tools. An explicit attempt considers only this SideStore's current-build job. OS Trust confirmation remains required if prompted.

Update over SideStore without deleting it, keep the Watch unlocked/near, open Apple Watch and press Install SideStore on Watch.

## Physical boundary
No result from build719 on the user's Watch has been reported. Do not claim it resolves code51, installs/opens apps or renews profiles on the real Watch. The included Watch component is a native probe, not an autonomous signing/store engine.

Reference physical desktop/TCP success: Rzbck/isideload f7b9f3da570edd6824c29680545e710846d07df5, HANDOFF_ONE_CLICK_WATCH_SUCCESS.md. It does not validate our iPhone RPPairing/RSD route or this watchOS10.6.2 device.

No calls. Keep token usage low. Next build must be 720 or later; do not overwrite published719 bytes. Full pairing recovery branch is work/watch-pairing-recovery; work/watch-automatic and the feeds remain at the previous stage.
