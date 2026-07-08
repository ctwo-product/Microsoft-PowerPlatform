#Requires -Version 5.1
<#
.SYNOPSIS
    Triggers a Power Automate Desktop flow and streams results to C TWO.

.DESCRIPTION
    FlowId, EnvironmentId, and InputJson
    are mandatory parameters always supplied by C TWO at runtime via Variable
    mapping — there is no configuration block for those three values.

    Only PADExePath and TimeoutSeconds have local defaults in the CONFIGURATION
    section below.

    What this script does, in order:
      1. Logs the incoming parameters (FlowId, EnvironmentId, InputJson)
      2. Validates the PAD environment (exe, service, protocol handler, GUIDs)
      3. Triggers the PAD flow via the ms-powerautomate:// protocol
      4. Monitors the runner process to detect completion - no output files needed
      5. Reads the PAD session logs and forwards them as C TWO telemetry
      6. Exits with a code the Machine Agent uses for SLA tracking and retries

    C TWO Variable to Parameter mapping:
        FlowId         -FlowId          [REQUIRED]
        EnvironmentId  -EnvironmentId   [REQUIRED]
        InputJson      -InputJson       [REQUIRED]
        TimeoutSeconds -TimeoutSeconds  (optional - overrides CONFIGURATION default)

EXIT CODES
    0  Flow completed successfully
    1  Flow timed out or PAD reported a failure
    2  Environment or configuration error (check the logs above)
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$FlowId,
    [Parameter(Mandatory)][string]$EnvironmentId,
    [Parameter(Mandatory)][string]$InputJson,
    [string]$PADExePath,
    [int]$TimeoutSeconds,
    [switch]$PadTrace          # Include this switch to emit PAD internal Trace logs to C TWO telemetry
)

# ============================================================================
#  CONFIGURATION - Only machine-level defaults live here.
#  FlowId, EnvironmentId, and InputJson are always passed by C TWO at runtime.
# ============================================================================

$cfg_PADExePath     = "C:\Program Files (x86)\Power Automate Desktop\PAD.Console.Host.exe"
$cfg_TimeoutSeconds = 150

# ============================================================================
#  C TWO TELEMETRY - Do not modify.
#  Every Write-CTwoLog call emits one JSON line to stdout.
#  The Machine Agent reads stdout via Named Pipe and forwards it to the
#  C TWO platform, where it appears in the Session Monitoring Dashboard.
# ============================================================================
function Write-CTwoLog {
    param(
        [ValidateSet("Trace","Debug","Information","Warning","Error","Fatal")]
        [string]$Level = "Information",
        [Parameter(Mandatory)][string]$Message
    )
    if ($Level -eq "Trace" -and -not $PadTrace) { return }
    @{ level = $Level; message = $Message } | ConvertTo-Json -Compress | Write-Output
}

function Write-ExitStatus {
    param(
        [Parameter(Mandatory)][int]$Code,
        [Parameter(Mandatory)][string]$Message
    )
    $color  = if ($Code -eq 0) { "Green" } else { "Red" }
    $prefix = if ($Code -eq 0) { "[SUCCESS]" } elseif ($Code -eq 2) { "[CONFIG ERROR]" } else { "[FAILED]" }
    Write-Host "$prefix $Message (exit $Code)" -ForegroundColor $color
}

# Apply optional overrides for machine-level settings
if (-not $PADExePath)     { $PADExePath     = $cfg_PADExePath }
if (-not $TimeoutSeconds) { $TimeoutSeconds = $cfg_TimeoutSeconds }

# ============================================================================
#  STEP 1 - Log incoming parameters
# ============================================================================
$whoamiOutput = (whoami) 2>$null

Write-CTwoLog -Level Information -Message "=== C TWO PAD Trigger (Dynamic) starting on $env:COMPUTERNAME | $whoamiOutput ==="
Write-CTwoLog -Level Information -Message "Hostname:      $env:COMPUTERNAME"
Write-CTwoLog -Level Information -Message "User:          $whoamiOutput"
Write-CTwoLog -Level Information -Message "EnvironmentId: $EnvironmentId"
Write-CTwoLog -Level Information -Message "FlowId:        $FlowId"
Write-CTwoLog -Level Information -Message "InputJson:     $InputJson"

# ============================================================================
#  STEP 2 - Environment validation
# ============================================================================
Write-CTwoLog -Level Information -Message "=== Validating environment ==="

$validationFailed = $false

# PAD executable
if (Test-Path $PADExePath) {
    $ver = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($PADExePath)
    Write-CTwoLog -Level Information -Message "PASS: PAD executable found - version $($ver.FileVersion)"
} else {
    Write-CTwoLog -Level Fatal -Message "FAIL: PAD executable not found at '$PADExePath' - update the CONFIGURATION section"
    $validationFailed = $true
}

# UIFlowService
try {
    $svc = Get-Service -Name "UIFlowService" -ErrorAction Stop

    # If the service is still starting up (common when the script runs at boot/login),
    # wait up to 30s for it to reach Running before failing
    if ($svc.Status -eq "StartPending") {
        Write-CTwoLog -Level Warning -Message "UIFlowService is StartPending - waiting up to 30s for it to start..."
        $svcDeadline = (Get-Date).AddSeconds(30)
        while ($svc.Status -ne "Running" -and (Get-Date) -lt $svcDeadline) {
            Start-Sleep -Seconds 2
            $svc.Refresh()
        }
    }

    if ($svc.Status -eq "Running") {
        Write-CTwoLog -Level Information -Message "PASS: UIFlowService is Running"
    } else {
        Write-CTwoLog -Level Fatal -Message "FAIL: UIFlowService status is '$($svc.Status)' - start it with Start-Service UIFlowService"
        $validationFailed = $true
    }
} catch {
    Write-CTwoLog -Level Fatal -Message "FAIL: UIFlowService not found - PAD may not be installed"
    $validationFailed = $true
}

# Protocol handler
if (Test-Path "HKLM:\SOFTWARE\Classes\ms-powerautomate") {
    Write-CTwoLog -Level Information -Message "PASS: ms-powerautomate:// protocol handler is registered"
} else {
    Write-CTwoLog -Level Fatal -Message "FAIL: ms-powerautomate:// not registered - re-install Power Automate Desktop"
    $validationFailed = $true
}

# Environment GUID format
$guid = [System.Guid]::Empty
if ([System.Guid]::TryParse($EnvironmentId, [ref]$guid)) {
    Write-CTwoLog -Level Information -Message "PASS: EnvironmentId GUID is valid"
} else {
    Write-CTwoLog -Level Fatal -Message "FAIL: EnvironmentId is not a valid GUID - '$EnvironmentId'"
    $validationFailed = $true
}

# Flow GUID format
if ([System.Guid]::TryParse($FlowId, [ref]$guid)) {
    Write-CTwoLog -Level Information -Message "PASS: FlowId GUID is valid"
} else {
    Write-CTwoLog -Level Fatal -Message "FAIL: FlowId is not a valid GUID - '$FlowId'"
    $validationFailed = $true
}

if ($validationFailed) {
    Write-CTwoLog -Level Fatal -Message "Validation failed - fix the errors above before retrying"
    Write-ExitStatus -Code 2 -Message "Validation failed"
    exit 2
}

# ============================================================================
#  STEP 3 - Trigger the PAD flow
# ============================================================================
Add-Type -AssemblyName System.Web
$encodedJson = [System.Web.HttpUtility]::UrlEncode($InputJson)
$url = "ms-powerautomate:/console/flow/run?environmentid=$EnvironmentId&workflowid=$FlowId&source=Other&inputArguments=$encodedJson"

Write-CTwoLog -Level Information -Message "=== Triggering flow ==="
Write-CTwoLog -Level Information -Message "Timeout: ${TimeoutSeconds}s"

# Load Win32 API for window management (best-effort, non-blocking)
$winApiAvailable = $false
$WM_CLOSE        = [uint32]0x0010
try {
    if (-not ([System.Management.Automation.PSTypeName]'CTwoPAD.WinAPI').Type) {
        Add-Type -Namespace CTwoPAD -Name WinAPI -MemberDefinition @'
            [System.Runtime.InteropServices.DllImport("user32.dll")]
            public static extern bool ShowWindow(System.IntPtr hWnd, int nCmdShow);

            [System.Runtime.InteropServices.DllImport("user32.dll", CharSet=System.Runtime.InteropServices.CharSet.Unicode)]
            public static extern System.IntPtr FindWindow(string lpClassName, string lpWindowName);

            [System.Runtime.InteropServices.DllImport("user32.dll")]
            public static extern System.IntPtr SendMessage(System.IntPtr hWnd, uint Msg, System.IntPtr wParam, System.IntPtr lParam);
'@
    }
    $winApiAvailable = $true
} catch {
    Write-CTwoLog -Level Trace -Message "Win32 API unavailable - PAD UI may be visible: $($_.Exception.Message)"
}

# Known PAD blocking dialog titles (exact match via FindWindow)
$padBlockingDialogs = @(
    "Power Automate update",
    "Power Automate Desktop update"
)

# Helper: dismiss any visible PAD blocking dialogs - called from multiple phases
function Invoke-DismissPADDialogs {
    if (-not $winApiAvailable) { return }
    try {
        # Exact title match
        foreach ($title in $padBlockingDialogs) {
            $hwnd = [CTwoPAD.WinAPI]::FindWindow($null, $title)
            if ($hwnd -ne [IntPtr]::Zero) {
                [CTwoPAD.WinAPI]::SendMessage($hwnd, $WM_CLOSE, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
                Write-CTwoLog -Level Warning -Message "PAD dialog '$title' dismissed - consider updating PAD outside scheduled runs"
            }
        }
        # Partial title match across all PAD processes
        foreach ($proc in (Get-Process -Name "PAD*" -ErrorAction SilentlyContinue)) {
            $proc.Refresh()
            if ($proc.MainWindowHandle -ne [IntPtr]::Zero -and $proc.MainWindowTitle -match "(?i)update") {
                [CTwoPAD.WinAPI]::SendMessage($proc.MainWindowHandle, $WM_CLOSE, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
                Write-CTwoLog -Level Warning -Message "PAD update dialog dismissed on '$($proc.ProcessName)' - consider updating PAD outside scheduled runs"
            }
        }
    } catch {
        Write-CTwoLog -Level Trace -Message "Dialog dismissal error (non-critical): $($_.Exception.Message)"
    }
}

# Snapshot existing runner + console PIDs so we only track new instances
$runnerNames    = @("PAD.FlowEngine", "PAD.RobotV2", "PAD.Robot.Host")
$priorRunnerIds = @(
    foreach ($n in $runnerNames) {
        Get-Process -Name $n -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id
    }
)
$priorPADIds = @(Get-Process -Name "PAD*" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
$sessionStart = Get-Date

try {
    $padProcess = Start-Process -FilePath $PADExePath -ArgumentList $url -WindowStyle Hidden -PassThru
    Write-CTwoLog -Level Information -Message "PAD.Console.Host launched (PID: $($padProcess.Id))"
} catch {
    Write-CTwoLog -Level Fatal -Message "Failed to launch PAD: $($_.Exception.Message)"
    Write-ExitStatus -Code 2 -Message "Failed to launch PAD"
    exit 2
}

# Suppress the PAD UI window and dismiss blocking dialogs - best-effort, will not block or fail the script
try {
    $winApiAvailable = ([System.Management.Automation.PSTypeName]'CTwoPAD.WinAPI').Type -ne $null
    if ($winApiAvailable) {
        $WM_CLOSE     = [uint32]0x0010
        $deadline     = (Get-Date).AddSeconds(30)
        $windowHidden = $false

        # Keep looping the full 5 seconds - dialogs can appear at any point after launch
        while ((Get-Date) -lt $deadline) {

            # 1. Dismiss dialogs by exact title (FindWindow)
            foreach ($title in $padBlockingDialogs) {
                $hwnd = [CTwoPAD.WinAPI]::FindWindow($null, $title)
                if ($hwnd -ne [IntPtr]::Zero) {
                    [CTwoPAD.WinAPI]::SendMessage($hwnd, $WM_CLOSE, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
                    Write-CTwoLog -Level Warning -Message "PAD dialog '$title' dismissed - consider updating PAD outside scheduled runs"
                }
            }

            # 2. Check all PAD processes - dismiss any whose main window title contains "update",
            #    and hide the main window of any new process we haven't seen before
            foreach ($proc in (Get-Process -Name "PAD*" -ErrorAction SilentlyContinue)) {
                $proc.Refresh()
                if ($proc.MainWindowHandle -eq [IntPtr]::Zero) { continue }

                if ($proc.MainWindowTitle -match "(?i)update") {
                    # Update dialog is the main window of this process - close it
                    [CTwoPAD.WinAPI]::SendMessage($proc.MainWindowHandle, $WM_CLOSE, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
                    Write-CTwoLog -Level Warning -Message "PAD update dialog dismissed on '$($proc.ProcessName)' - consider updating PAD outside scheduled runs"
                } elseif (-not $windowHidden -and $proc.Id -notin $priorPADIds) {
                    # New PAD process with a normal window - hide it
                    [CTwoPAD.WinAPI]::ShowWindow($proc.MainWindowHandle, 0) | Out-Null
                    Write-CTwoLog -Level Trace -Message "PAD UI window suppressed (PID: $($proc.Id))"
                    $windowHidden = $true
                }
            }

            # 3. Also check the process we launched directly
            if (-not $windowHidden) {
                $padProcess.Refresh()
                if ($padProcess.MainWindowHandle -ne [IntPtr]::Zero -and
                    $padProcess.MainWindowTitle -notmatch "(?i)update") {
                    [CTwoPAD.WinAPI]::ShowWindow($padProcess.MainWindowHandle, 0) | Out-Null
                    Write-CTwoLog -Level Trace -Message "PAD UI window suppressed"
                    $windowHidden = $true
                }
            }

            Start-Sleep -Milliseconds 300
        }
    }
} catch {
    # Window management is non-critical - log and continue regardless
    Write-CTwoLog -Level Trace -Message "Could not manage PAD UI window: $($_.Exception.Message)"
}

# ============================================================================
#  STEP 4 - Monitor completion via runner process lifecycle
# ============================================================================
Write-CTwoLog -Level Information -Message "=== Waiting for flow to complete ==="

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$runnerProcess = $null

# Wait up to 60s for a new runner process to appear
# Also dismiss PAD blocking dialogs on every tick - the update dialog can appear AFTER the initial 15s window phase
while ($sw.Elapsed.TotalSeconds -lt [Math]::Min(60, $TimeoutSeconds)) {
    Invoke-DismissPADDialogs
    foreach ($n in $runnerNames) {
        $runnerProcess = Get-Process -Name $n -ErrorAction SilentlyContinue |
                         Where-Object { $_.Id -notin $priorRunnerIds } |
                         Select-Object -First 1
        if ($runnerProcess) { break }
    }
    if ($runnerProcess) { break }
    Start-Sleep -Seconds 1
}

$completed = $false
if ($runnerProcess) {
    Write-CTwoLog -Level Information -Message "Runner process '$($runnerProcess.ProcessName)' detected (PID: $($runnerProcess.Id)) - waiting for it to finish..."
    $remainingMs = [int](($TimeoutSeconds - $sw.Elapsed.TotalSeconds) * 1000)
    $completed   = $runnerProcess.WaitForExit([Math]::Max($remainingMs, 1000))
} else {
    # No dedicated runner found - PAD.Console.Host handles the flow directly in this version
    Write-CTwoLog -Level Information -Message "Waiting for PAD.Console.Host to finish (PID: $($padProcess.Id))..."
    $remainingMs = [int](($TimeoutSeconds - $sw.Elapsed.TotalSeconds) * 1000)
    $completed   = $padProcess.WaitForExit([Math]::Max($remainingMs, 1000))
}

$sw.Stop()
$duration = [math]::Round($sw.Elapsed.TotalSeconds, 1)

# ============================================================================
#  STEP 5 - Read PAD session logs and forward as C TWO telemetry
# ============================================================================
Write-CTwoLog -Level Information -Message "=== PAD session logs ==="

$padLogDir = "C:\ProgramData\Microsoft\Power Automate\Logs"

if (Test-Path $padLogDir) {
    try {
        $sessionLogs = Get-ChildItem $padLogDir -Filter "*.log" -File -ErrorAction Stop |
            Where-Object { $_.LastWriteTime -ge $sessionStart.AddSeconds(-10) } |
            Sort-Object LastWriteTime

        if ($sessionLogs.Count -gt 0) {
            Write-CTwoLog -Level Information -Message "Forwarding $($sessionLogs.Count) PAD log file(s)"

            foreach ($logFile in $sessionLogs) {
                try {
                    foreach ($line in (Get-Content $logFile.FullName -ErrorAction Stop)) {
                        $trimmed = $line.Trim()
                        if (-not $trimmed) { continue }

                        # PAD log lines are JSON telemetry objects - extract readable fields
                        if ($trimmed.StartsWith('{')) {
                            try {
                                $obj = $trimmed | ConvertFrom-Json -ErrorAction Stop

                                $event = if ($obj.event) { $obj.event } else { "" }
                                $msg   = if ($obj.message) { $obj.message }
                                        elseif ($obj.msg)  { $obj.msg }
                                        elseif ($event)    { $event }
                                        else               { $trimmed.Substring(0, [Math]::Min(120, $trimmed.Length)) }

                                $entry = if ($event -and $msg -ne $event) { "[PAD] [$event] $msg" } else { "[PAD] $msg" }
                                Write-CTwoLog -Level Trace -Message $entry
                                continue
                            } catch {
                                # Not valid JSON - fall through to text parsing below
                            }
                        }

                        # Plain-text log line: [timestamp] [level] message
                        if ($trimmed -match '^\[?(\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}[\.\d]*)\]?\s*\[?(\w+)\]?\s*(.+)$') {
                            $ts  = $Matches[1]
                            $msg = $Matches[3]
                        } else {
                            $ts  = ""
                            $msg = $trimmed
                        }

                        $entry = if ($ts) { "[PAD] [$ts] $msg" } else { "[PAD] $msg" }
                        Write-CTwoLog -Level Trace -Message $entry
                    }
                } catch {
                    Write-CTwoLog -Level Warning -Message "Could not read '$($logFile.Name)': $($_.Exception.Message)"
                }
            }
        } else {
            Write-CTwoLog -Level Information -Message "No PAD log files found for this session"
        }
    } catch {
        Write-CTwoLog -Level Warning -Message "Cannot access PAD log directory (administrator rights may be required)"
    }
} else {
    Write-CTwoLog -Level Warning -Message "PAD log directory not found: $padLogDir"
}

# ============================================================================
#  STEP 6 - Final status and exit code
# ============================================================================
Write-CTwoLog -Level Information -Message "=== Result ==="

if (-not $completed) {
    Write-CTwoLog -Level Error -Message "Flow timed out after ${duration}s (limit: ${TimeoutSeconds}s) - exit code 1"
    Write-ExitStatus -Code 1 -Message "Flow timed out after ${duration}s"
    exit 1
}

if (-not $runnerProcess) {
    # Console.Host exited but no runner process ever spawned - the flow did not start.
    # Common causes: incorrect EnvironmentId, incorrect FlowId, PAD not signed in, or no network connectivity.
    Write-CTwoLog -Level Error -Message "Flow did not start - no runner process was detected after ${duration}s. Verify EnvironmentId, FlowId, and that PAD is signed in - exit code 1"
    Write-ExitStatus -Code 1 -Message "Flow did not start - verify EnvironmentId, FlowId, and PAD sign-in"
    exit 1
}

# ExitCode is only reliable on processes started by this script (Start-Process -PassThru).
# For processes discovered via Get-Process, ExitCode may be $null even on clean exit.
# Treat $null, empty string, and 0 all as success.
$exitCode = $runnerProcess.ExitCode
if ($null -eq $exitCode -or $exitCode -eq "" -or $exitCode -eq 0) {
    Write-CTwoLog -Level Information -Message "Flow completed successfully in ${duration}s - exit code 0"
    Write-ExitStatus -Code 0 -Message "Flow completed successfully in ${duration}s"
    exit 0
} else {
    Write-CTwoLog -Level Error -Message "Flow finished in ${duration}s but runner reported error code $exitCode - exit code 1"
    Write-ExitStatus -Code 1 -Message "Flow finished in ${duration}s but runner reported error code $exitCode"
    exit 1
}
