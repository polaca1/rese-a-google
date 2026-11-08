# Own-identity variant 720

Host canonical ID: com.SideStore.SideStore.PabloWatch. Own Watch ID: actual signed parent + .watch. Parent and Watch require different App IDs. Latest user instruction expressly requests creating a dedicated identity and automatic Watch identity registration, superseding earlier reuse-only constraints for this variant.

The source remains in the SideStore family so the currently installed SideStore signer recognizes it as a store app and embeds its own signing certificate. Main, widget and helper carry legacy + own app groups in that order: the 719 installer replaces the first matching old group; the dedicated own group survives and is selected by this variant. No private session or pairing files are read from another app sandbox. New app requires initial Apple login and phone pairing; active app and ID quotas apply. Do not auto-revoke certificates, delete IDs or deactivate other apps.

Watch bootstrap uses only its dedicated child, not .AltWidget or .SideBackup. Recover its own embedded signing certificate, check the host-profile team matches the signed-in team, ensure the phone can see its one paired Watch, register child once if absent, then sign/install with the child's profile. On uncertain creation failure re-read rather than repeat POST. Quota failures are specific.

Native Watch installation/renewal and autonomous Watch signing are still unverified/unimplemented. No claim that a new identity alone resolves code51. No automatic feed change; separate main bundle ID requires a separate source identity later.

Build/tests/public IPA verification pending.
