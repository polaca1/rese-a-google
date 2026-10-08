"""Open the real Tk app under Xvfb; desktop startup must work before Tailscale login."""
import importlib.util
from pathlib import Path

spec = importlib.util.spec_from_file_location('configurator', '/opt/reviewnfcgo-cuentas/Configurar.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
application = module.Configurator()
try:
    application.root.update()
    assert application.root.winfo_viewable()
    assert application.busy is False
    assert len(application.buttons) == 6
finally:
    application.root.destroy()
print('Configurador gráfico iniciado correctamente sin sesión de Tailscale.')
