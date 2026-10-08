"""Small desktop configurator. Only fixed owner actions run through PolicyKit."""
import json
import queue
import re
import subprocess
import threading
import tkinter as tk
from tkinter import messagebox, ttk
import webbrowser

ACTION = '/usr/local/sbin/reviewnfcgo-servidor'


class Configurator:
    def __init__(self):
        self.root = tk.Tk()
        self.root.title('reviewNfcGo — Servidor')
        self.root.geometry('680x540')
        self.root.minsize(620, 500)
        self.events = queue.Queue()
        self.public_url = ''
        self.busy = False
        self.opened_links = set()
        frame = ttk.Frame(self.root, padding=24)
        frame.pack(fill='both', expand=True)
        ttk.Label(frame, text='Todas las cuentas, en tu PC', font=('', 19, 'bold')).pack(anchor='w')
        ttk.Label(frame, text='El servidor arranca al encender el PC, aunque no inicies sesión.\nLos usuarios no configuran direcciones ni instalan Tailscale.', wraplength=610).pack(anchor='w', pady=(10, 20))
        self.buttons = []
        for text, callback in [
            ('1. Activar conexión', lambda: self.start('connect')),
            ('2. Copiar dirección para conectar todas las apps', self.copy_address),
            ('3. Mantener conexión: desactivar caducidad del PC', self.expiry),
            ('Comprobar conexión y arranque automático', lambda: self.start('status')),
            ('Ver cuentas registradas', lambda: self.start('accounts')),
            ('Guardar copia de seguridad ahora', lambda: self.start('backup')),
        ]:
            button = ttk.Button(frame, text=text, command=callback)
            button.pack(fill='x', pady=4)
            self.buttons.append(button)
        self.address = tk.StringVar()
        ttk.Entry(frame, textvariable=self.address, state='readonly').pack(fill='x', pady=(14, 10))
        self.message = tk.StringVar(value='Pulsa Activar conexión. Abre los enlaces del navegador y acepta los permisos de Tailscale. La contraseña que te pedirá el sistema es la de Debian.')
        ttk.Label(frame, textvariable=self.message, wraplength=610).pack(anchor='w', pady=4)
        self.root.after(100, self.drain)
        # Recover the public address without asking for administrator access at launch.
        try:
            raw = subprocess.check_output(['/usr/bin/tailscale', 'status', '--json'], text=True, stderr=subprocess.DEVNULL, timeout=5)
            state = json.loads(raw)
            raw = subprocess.check_output(['/usr/bin/tailscale', 'funnel', 'status', '--json'], text=True, stderr=subprocess.DEVNULL, timeout=5)
            from action import public_origin
            self.public_url = public_origin(state, json.loads(raw)) or ''
            self.address.set(self.public_url)
        except (OSError, ValueError, subprocess.SubprocessError):
            pass

    def start(self, action):
        if self.busy:
            return
        self.busy = True
        self.message.set('Completando… Si aparece una ventana de permisos, introduce tu contraseña de Debian.')
        for button in self.buttons:
            button.state(['disabled'])
        self.opened_links.clear()
        def worker():
            try:
                with subprocess.Popen(['/usr/bin/pkexec', ACTION, action], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1) as process:
                    for line in process.stdout:
                        self.events.put(('line', line.rstrip()))
                    code = process.wait()
                self.events.put(('done', code))
            except OSError:
                self.events.put(('line', 'No se pudo abrir el configurador. Vuelve a ejecutar el instalador.'))
                self.events.put(('done', 1))
        threading.Thread(target=worker, daemon=True).start()

    def drain(self):
        try:
            while True:
                kind, value = self.events.get_nowait()
                if kind == 'done':
                    self.busy = False
                    for button in self.buttons:
                        button.state(['!disabled'])
                    if value:
                        self.message.set('No se completó. Si cancelaste el permiso, vuelve a pulsar el botón. Si abriste Tailscale, termina la autorización y vuelve a activar la conexión.')
                else:
                    for link in re.findall(r'https://(?:login|console)\.tailscale\.com/[^\s]+', value):
                        if link not in self.opened_links:
                            self.opened_links.add(link)
                            webbrowser.open(link)
                    try:
                        result = json.loads(value)
                    except ValueError:
                        if value:
                            self.message.set(value[-700:])
                        continue
                    if isinstance(result, list):
                        window = tk.Toplevel(self.root)
                        window.title('Cuentas registradas')
                        text = tk.Text(window, width=76, height=20)
                        text.pack(fill='both', expand=True)
                        for account in result:
                            text.insert('end', f"{account['Nombre']} — {account['Correo']} — {account['Registro']}\n")
                        if not result:
                            text.insert('end', 'Todavía no hay cuentas registradas en este servidor.')
                        text.configure(state='disabled')
                    elif isinstance(result, dict):
                        self.public_url = result.get('publicURL') or ''
                        self.address.set(self.public_url)
                        if result.get('localOK') and result.get('publicOK') and result.get('autostart'):
                            self.message.set('Conexión comprobada. Copia la dirección y envíala al desarrollador para activar todas las apps. Puedes cerrar esta ventana: el servidor sigue funcionando.')
                        elif result.get('localOK') and self.public_url:
                            self.message.set('Servidor local listo. La dirección pública todavía no responde; el DNS puede tardar unos minutos. Vuelve a pulsar Comprobar conexión.')
                        elif result.get('localOK'):
                            self.message.set('Servidor local listo. Pulsa Activar conexión para crear su dirección pública.')
                        else:
                            self.message.set('El servidor local no responde. Revisa la instalación antes de enviar la dirección.')
        except queue.Empty:
            pass
        self.root.after(100, self.drain)

    def copy_address(self):
        if not self.public_url:
            messagebox.showinfo('Falta activar la conexión', 'Pulsa Activar conexión y termina los permisos en el navegador.')
            return
        self.root.clipboard_clear()
        self.root.clipboard_append(self.public_url)
        self.message.set('Dirección copiada. Pégala en el chat con el desarrollador. Ningún usuario tendrá que introducirla.')

    def expiry(self):
        webbrowser.open('https://login.tailscale.com/admin/machines')
        self.message.set('Busca este PC → menú ⋯ → Disable key expiry. Conserva el nombre del PC y de tu red de Tailscale para mantener la dirección.')


if __name__ == '__main__':
    Configurator().root.mainloop()
