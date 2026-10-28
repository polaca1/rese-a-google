"""Publish both SideStore feeds only after verifying the public release bytes."""
import hashlib, io, json, pathlib, plistlib, subprocess, urllib.request, zipfile, datetime
root=pathlib.Path(__file__).resolve().parents[1]
manifest=json.loads((root/'build/watch-beta/BETA-MANIFEST.json').read_text())
version=manifest['version']; build=manifest['build']
tag=f"sidestore-watch-beta-{version}-build{build}"
url=f"https://github.com/polaca1/rese-a-google/releases/download/{tag}/SideStore-Watch-Beta-{version}-build{build}.ipa"
with urllib.request.urlopen(url,timeout=120) as response: data=response.read()
assert len(data)==manifest['size']
assert hashlib.sha256(data).hexdigest()==manifest['sha256']
with zipfile.ZipFile(io.BytesIO(data)) as archive:
    assert archive.testzip() is None
    info=plistlib.loads(archive.read('Payload/SideStore.app/Info.plist'))
    assert info['CFBundleIdentifier']=='com.SideStore.SideStore'
    assert info['CFBundleVersion']==build and info['CFBundleShortVersionString']==version
    with zipfile.ZipFile(io.BytesIO(archive.read('Payload/SideStore.app/WatchBootstrap.ipa'))) as watch:
        assert watch.testzip() is None
        details=plistlib.loads(watch.read('Payload/SideStoreWatch.app/Info.plist'))
        assert details['WKApplication'] and tuple(map(int,details['MinimumOSVersion'].split('.'))) <= (10,6,2)
checkout=root/'build/source-publish'
subprocess.run(['git','fetch','origin','sidestore-watch-source'],check=True)
subprocess.run(['git','worktree','add','--detach',str(checkout),'FETCH_HEAD'],check=True)
base='https://raw.githubusercontent.com/polaca1/rese-a-google/refs/heads/sidestore-watch-source/'
date=datetime.datetime.now(datetime.timezone.utc).isoformat().replace('+00:00','Z')
description=("Beta experimental: detecta las apps de Watch/ incluidas en un IPA de iPhone, solicita sus perfiles existentes y conserva una cola de instalación. "
"Contiene un componente nativo para watchOS 10 que se intenta instalar al abrir SideStore. "
"Ese componente verifica apertura y acceso local: todavía NO es una tienda autónoma ni ejecuta la firma dentro del Watch. "
"Requiere cuenta Apple, certificado activo, App IDs ya registrados, perfiles válidos, un único Watch y emparejamiento TCP. No crea App IDs de Watch. "
"Actualizaciones de esta beta desde la fuente al abrir la app cuando la conexión y la firma lo permitan. iOS no garantiza ejecución en segundo plano. "
"Actualiza sin borrar SideStore y con la misma cuenta Apple. La instalación física con cuenta gratuita sigue pendiente de prueba.")
release={'version':version,'buildVersion':build,'date':date,'localizedDescription':description,'downloadURL':url,'size':len(data),'sha256':manifest['sha256'],'minOSVersion':info['MinimumOSVersion']}
app={'name':'SideStore Watch · Beta','bundleIdentifier':'com.SideStore.SideStore','developerName':'Variante personal · basada en SideStore Team',
'subtitle':'Instalación Watch experimental','localizedDescription':description,'iconURL':base+'icon.png','tintColor':'9B20EB',
'version':version,'buildVersion':build,'versionDate':date,'versionDescription':description,'downloadURL':url,'size':len(data),
'versions':[release],'appPermissions':{'entitlements':['com.apple.security.application-groups'],
'privacy':{key:value for key,value in info.items() if key.endswith('UsageDescription')}}}
for name in ['source.json','source-compatible.json']:
    feed={'name':'SideStore Watch · Beta','identifier':'com.polaca1.sidestorewatch.beta','sourceURL':base+name,'iconURL':base+'icon.png','tintColor':'9B20EB',
    'description':description,'apps':[app],'news':[]}
    (checkout/name).write_text(json.dumps(feed,ensure_ascii=False,indent=2)+'\n')
(checkout/'SOURCE-PROVENANCE.json').write_text(json.dumps({'manifest':manifest,'releaseURL':url,'verifiedPublicDownload':True,'watchMinimumOS':details['MinimumOSVersion']},indent=2)+'\n')
subprocess.run(['git','-C',str(checkout),'config','user.name','SideStore Watch Beta'],check=True)
subprocess.run(['git','-C',str(checkout),'config','user.email','41898282+github-actions[bot]@users.noreply.github.com'],check=True)
subprocess.run(['git','-C',str(checkout),'add','source.json','source-compatible.json','SOURCE-PROVENANCE.json'],check=True)
subprocess.run(['git','-C',str(checkout),'commit','-m',f'Publish verified personal Watch beta {version} ({build})'],check=True)
subprocess.run(['git','-C',str(checkout),'push','origin','HEAD:sidestore-watch-source'],check=True)
print('Public IPA, native Watch payload and both feeds verified and published.')
