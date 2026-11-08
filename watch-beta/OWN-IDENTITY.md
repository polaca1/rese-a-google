# Own-identity variant 720

Host canonical ID: com.SideStore.SideStore.PabloWatch. Own Watch ID: actual signed parent + .watch. Parent and Watch require different App IDs. Latest user instruction expressly requests creating a dedicated identity and automatic Watch identity registration, superseding earlier reuse-only constraints for this variant.

The source remains in the SideStore family so the currently installed SideStore signer recognizes it as a store app and embeds its own signing certificate. Main, widget and helper carry legacy + own app groups in that order: the 719 installer replaces the first matching old group; the dedicated own group survives and is selected by this variant. No private session or pairing files are read from another app sandbox. New app requires initial Apple login and phone pairing; active app and ID quotas apply. Do not auto-revoke certificates, delete IDs or deactivate other apps.

Watch bootstrap uses only its dedicated child, not .AltWidget or .SideBackup. Recover its own embedded signing certificate, check the host-profile team matches the signed-in team, ensure the phone can see its one paired Watch, register child once if absent, then sign/install with the child's profile. On uncertain creation failure re-read rather than repeat POST. Quota failures are specific.

Native Watch installation/renewal and autonomous Watch signing are still unverified/unimplemented. No claim that a new identity alone resolves code51. No automatic feed change; separate main bundle ID requires a separate source identity later.

Build, tests and public IPA verification passed; see below.


## Verified public build 720

Source commit: cac0b356df1b88b9beda2d0042b563bf78e59da4. Actions https://github.com/polaca1/rese-a-google/actions/runs/42486481278, job 128749363626: success. Own identity/group compatibility checks, native crypto/request checks, 106 Swift model checks and both native iPhone/watchOS10 builds passed. Public IPA downloaded and checked by size, SHA256, ZIP CRC, exact own host ID, canonical Watch ID and buddy ID. IPA https://github.com/polaca1/rese-a-google/releases/download/sidestore-watch-beta-0.7.1-build720/SideStore-Watch-Beta-0.7.1-build720.ipa. Size 32360204, sha256:a30578844d87daabf952a1415b4c35710f50b290f6d37859c6d5ed2034bac1b6. Source ZIP and PUBLIC-RECOVERY-VERIFICATION.json are release assets. Next build must be721+; never overwrite720 assets.

This is a separate app, not an update to the legacy main ID. Install through the current SideStore, with a free active-app slot and available App IDs (widget also uses one). Its own Apple login and iPhone pairing configuration are needed once; private sessions/pairing files are not automatically copied across app sandboxes. The current SideStore family signing route can embed the signing key in the installed app, which is then recovered locally. Watch ID is actual signed parent+.watch and is checked/registered at runtime only after account, key and local Watch checks. There is no actual Apple portal App ID registration performed in this cloud environment.

No physical installation/renewal result exists for720; creating an own ID is not proof that Pair code51 is resolved. No autonomous Watch store engine. Old source feeds remain unchanged. The full personal app identity branch is work/watch-own-identity.
