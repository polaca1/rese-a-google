#!/usr/bin/env python3
"""Publish verified, explicitly unsigned Watch preparation without changing the stable IPA."""
import base64
import hashlib
import json
import pathlib
import plistlib
import subprocess
import zipfile

REPO = 'polaca1/rese-a-google'
TAG = 'reviewnfcgo-watch-xcode-7.2.0-build38'
RAW = 'https://raw.githubusercontent.com/' + REPO + '/refs/heads/sidestore/'

def api(path, method='GET', body=None):
    command = ['gh','api','--method',method,'repos/'+REPO+'/'+path]
    if body is not None: command += ['--input','-']
    result = subprocess.run(command,input=json.dumps(body) if body is not None else None,text=True,capture_output=True)
    if result.returncode: raise RuntimeError(result.stderr)
    return json.loads(result.stdout) if result.stdout.strip() else None

def main():
    phone = next(pathlib.Path('phone').glob('*.ipa'))
    with zipfile.ZipFile(phone) as archive:
        info = plistlib.loads(archive.read('Payload/reviewNfcGo.app/Info.plist'))
        assert info['CFBundleIdentifier']=='com.pablo.resenagoogle.20261004'
        assert info['CFBundleShortVersionString']=='7.2.0' and info['CFBundleVersion']=='38'
        assert not any('/Watch/' in x for x in archive.namelist())
    result = json.loads(pathlib.Path('phone-checks/phone-watch-verification.log').read_text())
    assert result['passed'] and result['realBalance'] and result['privateOwner'] and result['boundedPayload']
    assert json.loads(pathlib.Path('watch/watch-verification.log').read_text())['passed']
    for screen in ['visit','businesses','money']:
        assert 'rendered content verified' in pathlib.Path('watch/watch-screen-'+screen+'.log').read_text()
    folder = pathlib.Path('prepared');folder.mkdir(exist_ok=True)
    buddy = folder/'reviewNfcGo-iPhone-7.2.0-build38-para-Watch.ipa';buddy.write_bytes(phone.read_bytes())
    subprocess.run(['bash','ios/reviewNfcGo/Scripts/package-xcode.sh',str(folder.resolve())],check=True)
    source = folder/'reviewNfcGo-Watch-Xcode-7.2.0-build38.zip'
    (folder/'reviewNfcGo-7.2.0-Xcode.zip').rename(source)
    readme = folder/'LEEME-WATCH-CUENTA-GRATUITA.md';readme.write_bytes(pathlib.Path('watchos/LEEME.md').read_bytes())
    assets = [buddy,source,readme]+list(pathlib.Path('watch').glob('watch-*.png'))
    manifest = {'schema':1,'status':'preparation-requires-compatible-mac','nativeVersion':'7.2.0','build':'38',
        'sourceArchiveCommit':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),
        'phoneSourceCommit':'6da9cd83d9ecf978bf9986425d0f15081d54bf68','phoneRun':40400181353,
        'watchSourceCommit':'ad2c9126df2b470f527aeddba9bcf888529fc143','watchRun':40402062572,
        'automaticFreeWatchRenewalVerified':False,'physicalWatchInstallationVerified':False,
        'requiresXcode':True,'assets':{x.name:{'size':x.stat().st_size,'sha256':hashlib.sha256(x.read_bytes()).hexdigest()} for x in assets}}
    metadata = folder/'VERIFICACION-WATCH.json';metadata.write_text(json.dumps(manifest,indent=2)+'\n');assets.append(metadata)
    check = subprocess.run(['gh','release','view',TAG,'--repo',REPO],capture_output=True)
    if check.returncode:
        subprocess.run(['gh','release','create',TAG,'--repo',REPO,'--target',manifest['sourceArchiveCommit'],'--title','Apple Watch: preparación con cuenta gratuita y Xcode','--notes-file',str(readme),'--prerelease','--latest=false'],check=True)
    release = api('releases/tags/'+TAG)
    assert release['prerelease'] and not release['draft']
    for item in assets:
        existing = next((x for x in release['assets'] if x['name']==item.name),None)
        if existing:
            assert existing['size']==item.stat().st_size and existing.get('digest')=='sha256:'+hashlib.sha256(item.read_bytes()).hexdigest(),'No se sustituyen assets publicados por bytes diferentes'
        else:
            subprocess.run(['gh','release','upload',TAG,str(item),'--repo',REPO],check=True)
    head = api('git/ref/heads/sidestore')['object']['sha']
    base = api('git/commits/'+head)['tree']['sha']
    prefix = 'screenshots/watch-7.2.0-build38/'
    files = {prefix+x.name:x.read_bytes() for x in pathlib.Path('watch').glob('watch-*.png')}
    files[prefix+'manifest.json']=(json.dumps(manifest,indent=2)+'\n').encode()
    news = {'title':'Apple Watch con cuenta gratuita: preparación para Xcode','identifier':TAG,
        'caption':'Requiere un Mac compatible y renovar la firma con Xcode. No se instala desde SideStore ni se anuncia renovación automática.',
        'date':release['published_at'],'notify':False,'url':release['html_url'],
        'appID':'com.pablo.resenagoogle.20261004','imageURL':RAW+prefix+'watch-money.png'}
    for name in ['source.json','source-compatible.json']:
        response = api('contents/'+name+'?ref='+head)
        document = json.loads(base64.b64decode(response['content']))
        document['news']=[x for x in document.get('news',[]) if x['identifier']!=TAG]+[news]
        files[name]=(json.dumps(document,ensure_ascii=False,indent=2)+'\n').encode()
    entries=[]
    for name,data in files.items():
        blob=api('git/blobs','POST',{'content':base64.b64encode(data).decode(),'encoding':'base64'})
        entries.append({'path':name,'mode':'100644','type':'blob','sha':blob['sha']})
    tree=api('git/trees','POST',{'base_tree':base,'tree':entries})
    commit=api('git/commits','POST',{'message':'Add verified Watch Xcode preparation and captures without changing stable app downloads','tree':tree['sha'],'parents':[head]})
    api('git/refs/heads/sidestore','PATCH',{'sha':commit['sha'],'force':False})
    print('Preparación publicada: '+release['html_url'])

if __name__=='__main__':main()
