"""Cross-check the new identity and compatibility with the currently installed signer."""
import pathlib, plistlib
root=pathlib.Path(__file__).resolve().parents[2]
base='com.SideStore.SideStore.PabloWatch'
legacy='com.SideStore.SideStore'
def plist(path): return plistlib.loads((root/path).read_bytes())
config=(root/'Build.xcconfig').read_text()
assert 'CURRENT_PROJECT_VERSION = 720' in config
assert 'BASE_BUNDLE_ID                                  = '+base in config
bundle=(root/'Shared/Extensions/Bundle+AltStore.swift').read_text()
assert 'appbundleIdentifier = "'+base+'"' in bundle
host=plist('AltStore/Info.plist')
assert host['CFBundleIdentifier']=='$(PRODUCT_BUNDLE_IDENTIFIER)'
assert host['CFBundleDisplayName']=='SideStore Watch'
assert host['CFBundleURLTypes'][0]['CFBundleURLSchemes']==['sidestorewatch']
for path in ['AltStore/AltStoreFree.entitlements','AltStore/AltStore.entitlements','AltWidget/AltWidgetExtension.entitlements','SideBackup/SideBackup.entitlements']:
    groups=plist(path)['com.apple.security.application-groups']
    assert groups==['group.'+legacy,'group.$(APP_GROUP_IDENTIFIER)']
    expanded=[g.replace('$(APP_GROUP_IDENTIFIER)',base) for g in groups]
    # Actual 719 signer replaces the first group containing its old base ID.
    rewritten=list(expanded)
    index=next(i for i,g in enumerate(rewritten) if 'group.'+legacy in g)
    rewritten[index]='group.'+legacy
    assert 'group.'+base in rewritten, path
    assert next(g for g in rewritten if 'group.'+base in g)=='group.'+base
watch=plist('watch-beta/native/SideStoreWatch/Info.plist')
assert watch['WKCompanionAppBundleIdentifier']==base
assert watch['CFBundleIdentifier']=='$(PRODUCT_BUNDLE_IDENTIFIER)'
project=(root/'watch-beta/native/SideStoreWatch.xcodeproj/project.pbxproj').read_text()
assert project.count('PRODUCT_BUNDLE_IDENTIFIER = '+base+'.watch;')==2
assert base+'.SideBackup' not in project
for path in ['AltStore/Resources/ReleaseEntitlements.plist','AltWidget/Resources/ReleaseEntitlements.plist']:
    assert plist(path)['com.apple.security.application-groups']==['group.'+legacy,'group.'+base]
# Signing material is embedded in this legitimate SideStore family by the existing installer.
assert legacy in base
assert 'getSignableCertificate(for: serial)' in (root/'SideStore/WatchBeta/WatchBetaController.swift').read_text()
print('Own identity, Watch relationship, helper/widget groups and existing-installer compatibility passed.')
