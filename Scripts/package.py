#!/usr/bin/env python3
"""Developer-only: create drag-to-Applications DMG and app/source ZIPs."""
from pathlib import Path
import shutil
import subprocess
import zipfile
ROOT = Path(__file__).resolve().parents[1]
DIST = ROOT / 'dist'
APP = DIST / 'iOS 7 Assistant.app'
STAGE = ROOT / 'Build/DMG'
if STAGE.exists(): shutil.rmtree(STAGE)
STAGE.mkdir(parents=True)
shutil.copytree(APP, STAGE / APP.name, symlinks=True)
(STAGE / 'Applications').symlink_to('/Applications')
(STAGE / 'LEEME - README.txt').write_text('''iOS 7 Assistant 0.2.3

Apple Silicon · macOS 14 o posterior / macOS 14 or later
iPhone 5s Global: iPhone6,2 / n53ap

Arrastra la app a Aplicaciones y ábrela. No requiere instalar otras herramientas.
Drag the app into Applications and open it. No prerequisite tools are needed.

Selecciona Español o English dentro de la app.
Prepare the original iOS 7.1.2 + 12.5.8 IPSWs once, then reuse the prepared folder.

DFU: Lightning → USB-A + adaptador USB-C.
pwnDFU y cargas / uploads: Lightning → USB-C directo / direct.
Reconecta manualmente USB-C después de iBSS y de iBEC cuando lo pida la app.
Manually reconnect USB-C after iBSS and iBEC when prompted.

Instalar borra los datos. Arrancar conserva el sistema.
Install erases data. Boot preserves the installed system.
Tras activar, continúa con Cydia y parches, el arranque final y las comprobaciones.
After activation, continue to Cydia and fixes, the final boot and checks.

Firma local; esta versión aún no está notarizada con Developer ID.
Local ad-hoc signature; this build is not yet Developer ID notarized.
macOS puede pedir “Abrir igualmente” / “Open Anyway” tras descargarla.

@criss.repair_ · https://www.youtube.com/@CrissRepair
Desarrollado con asistencia de Codex / Developed with assistance from Codex.
Créditos, licencias y fuentes de terceros: dentro de la app.
Third-party credits, licenses and source code: inside the app.
''')
shutil.copy2(ROOT / 'README.md', STAGE / 'Guia - Guide.md')
subprocess.run(['/usr/bin/hdiutil', 'create', '-ov', '-volname', 'iOS 7 Assistant',
                '-srcfolder', str(STAGE), '-format', 'UDZO',
                str(DIST / 'iOS7Assistant-0.2.3-arm64.dmg')], check=True)
subprocess.run(['/usr/bin/ditto', '-c', '-k', '--sequesterRsrc', '--keepParent',
                str(APP), str(DIST / 'iOS7Assistant-0.2.3-arm64.zip')], check=True)
with zipfile.ZipFile(DIST / 'iOS7Assistant-0.2.3-source.zip', 'w', zipfile.ZIP_DEFLATED) as archive:
    for folder in ['Sources', 'Resources', 'Scripts', 'Tests', 'Vendor']:
        for path in sorted((ROOT / folder).rglob('*')):
            if path.is_file() and path.name != '.DS_Store':
                archive.write(path, 'iOS7Assistant/' + str(path.relative_to(ROOT)))
    for file in ['README.md', 'LICENSE', 'VALIDATION.md', 'CHANGELOG.md']:
        if (ROOT / file).exists(): archive.write(ROOT / file, 'iOS7Assistant/' + file)
print('DMG, standalone app ZIP and source ZIP ready.')
