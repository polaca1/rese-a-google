# Owner-only setup. The app's users do not install or configure anything here.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$installDir = Join-Path $env:ProgramFiles 'reviewNfcGo Accounts'
$dataDir = Join-Path $env:ProgramData 'reviewNfcGo\Cuentas'
$taskName = 'reviewNfcGo - Cuentas'
$tailscaleExe = Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe'
$runtimeExe = Join-Path $installDir 'runtime\Cuentas.exe'
$sourceDir = $PSScriptRoot
$script:busy = $false
$script:publicURL = ''

$form = New-Object Windows.Forms.Form
$form.Text = 'Configurar reviewNfcGo en este PC'
$form.Size = New-Object Drawing.Size(660,590)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.Font = New-Object Drawing.Font('Segoe UI',10)
$layout = New-Object Windows.Forms.FlowLayoutPanel
$layout.Dock = 'Fill'; $layout.FlowDirection = 'TopDown'; $layout.WrapContents = $false
$layout.Padding = New-Object Windows.Forms.Padding(24)
$form.Controls.Add($layout)
function Label([string]$text, [int]$height=45) {
    $control = New-Object Windows.Forms.Label
    $control.Text=$text; $control.Size=New-Object Drawing.Size(590,$height)
    $layout.Controls.Add($control); return $control
}
function Button([string]$text) {
    $control=New-Object Windows.Forms.Button
    $control.Text=$text; $control.Size=New-Object Drawing.Size(590,38)
    $layout.Controls.Add($control); return $control
}
$heading = Label 'Todas las cuentas, en tu PC' 35
$heading.Font = New-Object Drawing.Font('Segoe UI',17,[Drawing.FontStyle]::Bold)
$null = Label 'Haz estos pasos una sola vez. El servidor arrancará al encender Windows, aunque no inicies sesión. Los usuarios solo tendrán que crear su cuenta en la app.' 65
$prepare = Button '1. Instalar y preparar este PC'
$connect = Button '2. Activar la conexión de la app'
$connect.Enabled = Test-Path $runtimeExe
$address = New-Object Windows.Forms.TextBox
$address.ReadOnly=$true; $address.Size=New-Object Drawing.Size(590,30)
$layout.Controls.Add($address)
$copy = Button '3. Copiar dirección para conectar todas las apps'
$copy.Enabled = $false
$expiry = Button '4. Mantener la conexión: desactivar caducidad del PC'
$accounts = Button 'Ver cuentas registradas en este PC'
$backups = Button 'Abrir las copias de seguridad'
$status = Label 'El PC debe seguir encendido y conectado a Internet. No necesitas abrir puertos del router.' 65
function Status([string]$message) { $status.Text=$message; $form.Refresh() }
function Run([string]$exe, [string[]]$arguments, [int]$timeout=300, [bool]$showLinks=$false) {
    $stdout = Join-Path $dataDir ('salida-' + [Guid]::NewGuid().ToString() + '.txt')
    $stderr = $stdout + '.err'
    $process = Start-Process -FilePath $exe -ArgumentList $arguments -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $deadline = [DateTime]::UtcNow.AddSeconds($timeout)
    $opened = @{}
    try {
        while (-not $process.HasExited) {
            [Windows.Forms.Application]::DoEvents()
            if ($showLinks -and (Test-Path $stdout)) {
                $output = [string](Get-Content $stdout -Raw -ErrorAction SilentlyContinue) + [string](Get-Content $stderr -Raw -ErrorAction SilentlyContinue)
                foreach ($match in [regex]::Matches([string]$output,'https://(?:login|console)\.tailscale\.com/[^\s]+')) {
                    if (-not $opened.ContainsKey($match.Value)) { Start-Process $match.Value; $opened[$match.Value]=$true }
                }
            }
            if ([DateTime]::UtcNow -gt $deadline) { $process.Kill(); throw 'Completa la autorización en el navegador y vuelve a pulsar Activar conexión.' }
            Start-Sleep -Milliseconds 150
        }
        $process.WaitForExit()
        $output = [string](Get-Content $stdout -Raw -ErrorAction SilentlyContinue)
        $errorOutput = [string](Get-Content $stderr -Raw -ErrorAction SilentlyContinue)
        if ($showLinks) {
            foreach ($match in [regex]::Matches($output + $errorOutput,'https://(?:login|console)\.tailscale\.com/[^\s]+')) {
                if (-not $opened.ContainsKey($match.Value)) { Start-Process $match.Value }
            }
        }
        if ($process.ExitCode -ne 0) { throw "No se ha podido completar la conexión. Termina los permisos de Tailscale en el navegador y vuelve a pulsar Activar conexión." }
        return $output
    } finally { Remove-Item $stdout,$stderr -ErrorAction SilentlyContinue }
}
function Busy([bool]$value) {
    $script:busy=$value; $prepare.Enabled=-not $value
    $connect.Enabled=(-not $value) -and (Test-Path $runtimeExe)
    $accounts.Enabled=(-not $value) -and (Test-Path $runtimeExe)
}
$prepare.Add_Click({
    Busy $true
    try {
        Status 'Preparando el servidor y el arranque automático…'
        New-Item -ItemType Directory -Force $installDir,$dataDir | Out-Null
        # Program files protect executable code; only SYSTEM and Administrators can read account files.
        & icacls.exe $dataDir /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'No se han podido proteger los archivos de cuentas.' }
        Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        Copy-Item (Join-Path $sourceDir 'runtime') $installDir -Recurse -Force
        Copy-Item (Join-Path $sourceDir 'Configurar.ps1') $installDir -Force
        Copy-Item (Join-Path $sourceDir 'Instalar.cmd') $installDir -Force
        $action=New-ScheduledTaskAction -Execute $runtimeExe -Argument ('--data "' + $dataDir + '"') -WorkingDirectory $installDir
        $trigger=New-ScheduledTaskTrigger -AtStartup
        $principal=New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
        $settings=New-ScheduledTaskSettingsSet -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
        Start-ScheduledTask -TaskName $taskName
        & powercfg.exe /change standby-timeout-ac 0 | Out-Null
        & powercfg.exe /change hibernate-timeout-ac 0 | Out-Null
        if (-not (Test-Path $tailscaleExe)) {
            Status 'Descargando la conexión segura. Puede tardar unos minutos…'
            $download = Join-Path $dataDir 'tailscale-setup.exe'
            [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -UseBasicParsing 'https://pkgs.tailscale.com/stable/tailscale-setup-latest.exe' -OutFile $download
            $signature=Get-AuthenticodeSignature $download
            if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'Tailscale') { throw 'No se ha podido verificar el instalador oficial de Tailscale.' }
            $null=Run $download @('/quiet','/norestart') 600
            Remove-Item $download -ErrorAction SilentlyContinue
        }
        if (-not (Test-Path $tailscaleExe)) { throw 'Termina de instalar Tailscale y vuelve a abrir este configurador.' }
        Status 'Servidor instalado. Pulsa Activar conexión e inicia sesión en el navegador que se abrirá.'
    } catch { Status $_.Exception.Message; [Windows.Forms.MessageBox]::Show($_.Exception.Message,'reviewNfcGo') | Out-Null }
    finally { Busy $false }
})
$connect.Add_Click({
    Busy $true
    try {
        Status 'Inicia sesión y acepta habilitar HTTPS/Funnel cuando aparezca en el navegador. Solo lo harás una vez.'
        $state=(& $tailscaleExe status --json | Out-String | ConvertFrom-Json)
        if ($state.BackendState -ne 'Running') { $null=Run $tailscaleExe @('up','--unattended=true') 300 $true }
        $null=Run $tailscaleExe @('set','--unattended=true') 30
        $null=Run $tailscaleExe @('funnel','--bg','--yes','http://127.0.0.1:8080') 300 $true
        $state=(& $tailscaleExe status --json | Out-String | ConvertFrom-Json)
        $hostName=[string]$state.Self.DNSName
        if (-not $hostName.EndsWith('.ts.net.')) { throw 'No se ha podido obtener la dirección HTTPS. Revisa la conexión de Tailscale.' }
        $script:publicURL='https://' + $hostName.TrimEnd('.')
        # Save only the PUBLIC endpoint, never passwords, tokens or database files.
        @{schema=1;serverURL=$script:publicURL} | ConvertTo-Json | Set-Content (Join-Path $dataDir 'direccion-publica.json') -Encoding UTF8
        $address.Text=$script:publicURL; $copy.Enabled=$true
        try {
            $health=Invoke-RestMethod -Uri ($script:publicURL + '/health') -TimeoutSec 20
            if ($health.status -ne 'ok') { throw 'Sin respuesta' }
            Status 'Conexión lista. Copia la dirección y envíasela al desarrollador una vez. Después todos los registros llegarán a este PC automáticamente.'
        } catch { Status 'Dirección creada. El DNS puede tardar hasta 10 minutos. Vuelve a pulsar Activar conexión para comprobarla antes de enviar la dirección.' }
    } catch { Status $_.Exception.Message; [Windows.Forms.MessageBox]::Show($_.Exception.Message,'reviewNfcGo') | Out-Null }
    finally { Busy $false }
})
$copy.Add_Click({ [Windows.Forms.Clipboard]::SetText($script:publicURL); Status 'Dirección copiada. Envíala al desarrollador. Los usuarios no deberán introducirla ni instalar Tailscale.' })
$expiry.Add_Click({
    Start-Process 'https://login.tailscale.com/admin/machines'
    Status 'En el navegador: busca este PC → menú ⋯ → Disable key expiry (desactivar caducidad). Mantén el nombre del PC y de la red para conservar su dirección.'
})
$accounts.Add_Click({
    try {
        $output=Run $runtimeExe @('--data',('"' + $dataDir + '"'),'--list-accounts') 30
        $rows=@($output | ConvertFrom-Json)
        if ($rows.Count -eq 0) { [Windows.Forms.MessageBox]::Show('Todavía no hay cuentas registradas.','Cuentas') | Out-Null }
        else { $rows | Out-GridView -Title 'Cuentas guardadas en este PC (sin contraseñas)' }
    } catch { Status $_.Exception.Message }
})
$backups.Add_Click({
    try { $null=Run $runtimeExe @('--data',('"' + $dataDir + '"'),'--backup') 30; Start-Process explorer.exe (Join-Path $dataDir 'copias') }
    catch { Status $_.Exception.Message }
})
$form.Add_FormClosing({ param($sender,$event) if ($script:busy) { $event.Cancel=$true; Status 'Espera a que termine este paso antes de cerrar.' } })
if (Test-Path (Join-Path $dataDir 'direccion-publica.json')) {
    try { $script:publicURL=(Get-Content (Join-Path $dataDir 'direccion-publica.json') -Raw | ConvertFrom-Json).serverURL; $address.Text=$script:publicURL; $copy.Enabled=$true } catch {}
}
[Windows.Forms.Application]::EnableVisualStyles()
[void]$form.ShowDialog()
