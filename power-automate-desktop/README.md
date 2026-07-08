# C TWO — Power Automate Desktop Orchestration

Trigger, monitor, and govern **Power Automate Desktop (PAD)** flows from the **C TWO Agentic Management Platform** using a single PowerShell script — with live JSON telemetry and **zero changes to your flows**. The script is deployed **as-is**; nothing in it needs to be edited to onboard it into C TWO.

This is the **desktop** counterpart to the cloud integration. Where the [custom connector](../README.md) connects C TWO to **Power Automate Cloud / Power Apps / Logic Apps / Copilot Studio** over HTTPS, this script lets C TWO orchestrate **Power Automate *Desktop*** flows on a runner machine via PAD's native CLI protocol.

---

## What's in this folder

| File | What it is |
|---|---|
| [`ctwo-pad-script.ps1`](ctwo-pad-script.ps1) | The drop-in PowerShell script C TWO runs to trigger a PAD flow, monitor it to completion, and stream live telemetry — so C TWO can report a **Completed** or **Failed** session outcome. Deploy as-is. |
| [`DisablePADUpdates.ps1`](DisablePADUpdates.ps1) | One-time helper (run as administrator) that disables PAD's update-notification popup — the most common cause of failed scheduled runs. See [Known Limitations](#10-known-limitations). |

---

## Quick start

1. On the runner machine: install PAD, sign in, confirm `UIFlowService` is running, and run [`DisablePADUpdates.ps1`](DisablePADUpdates.ps1) once as administrator.
2. Copy [`ctwo-pad-script.ps1`](ctwo-pad-script.ps1) to the machine (e.g. `C:\Scripts\ctwo-pad-script.ps1`). No edits required.
3. In C TWO: register a PowerShell engine, register the script, enable the desktop-session toggle, and map three Variables (`FlowId`, `EnvironmentId`, `InputJson`).
4. Run a validation test with `InputJson` = `{}` and watch the Session Monitoring Dashboard.

Full detail below.

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Local Execution Context Model](#2-local-execution-context-model)
3. [Prerequisites](#3-prerequisites)
4. [How It Works](#4-how-it-works)
5. [Configuration and Parameters](#5-configuration-and-parameters)
6. [C TWO Variable to Parameter Mapping](#6-c-two-variable-to-parameter-mapping)
7. [PAD Licensing](#7-pad-licensing)
8. [Telemetry and Logging](#8-telemetry-and-logging)
9. [Execution Outcomes](#9-execution-outcomes)
10. [Known Limitations](#10-known-limitations)
11. [Troubleshooting](#11-troubleshooting)
12. [End to End Setup Guide](#12-end-to-end-setup-guide)
13. [Shell Quoting for Manual Invocation](#13-shell-quoting-for-manual-invocation)

---

## 1. Architecture Overview

C TWO does not execute flows directly. It sits above the PAD installation and uses a PowerShell script to trigger PAD via its native CLI protocol. The complete execution chain is:

```
C TWO Agentic Management Platform
    │
    │  SignalR WebSocket (outbound-initiated)
    ▼
Machine Agent Service  (Session 0)
    │
    │  Windows Named Pipe + stdout JSON stream
    ▼
C TWO PAD Script · PowerShell  (Session 1+)
    │
    │  ms-powerautomate:/ URI trigger
    ▼
PAD.Console.Host.exe
    │
    │  spawns runner process
    ▼
PAD.RobotV2.exe / PAD.FlowEngine.exe
    │
    │  executes flow, exits on completion
    ▼
PAD session logs, forwarded as Trace telemetry  (when -PadTrace is active)
```

**Key design facts:**

- The Machine Agent runs in **Session 0** (the system service session). The PAD script runs in **Session 1+** (the interactive desktop session). C TWO's auto-login mechanism establishes this session automatically.
- Communication between the Machine Agent and the script happens over a **Windows Named Pipe**. Every JSON line the script writes to stdout is forwarded to the C TWO Session Monitoring Dashboard in real time.
- Telemetry lines written to **stdout** must be valid JSON in the form `{"level":"...","message":"..."}`. The Machine Agent parses this stream and, from it, C TWO determines the session outcome shown in the dashboard.

---

## 2. Local Execution Context Model

C TWO operates on a **Local Execution Context** model:

- The platform does **not** distribute script files to machines.
- It stores only the **path** to a script that must already reside on the runner machine.
- Power Automate Desktop must be **installed, signed in, and running** on the machine before C TWO can orchestrate anything.

**Responsibility split:**

| Responsibility | Owner |
|---|---|
| PAD installation | Customer |
| Script deployment to the machine | Customer |
| PAD sign-in and license assignment | Customer |
| Scheduling, triggering, parameter supply | C TWO |
| Live telemetry and session monitoring | C TWO |
| SLA tracking, alerts, and self-healing | C TWO |

C TWO distributes a single, ready-to-use PowerShell script. It accepts three mandatory values — **FlowId**, **EnvironmentId**, and **InputJson** — which C TWO supplies at runtime via Variable mapping. Because nothing flow-specific is hardcoded, the same file is reusable across any flow or environment, and **no edits to the script are required to onboard it into C TWO**.

---

## 3. Prerequisites

The script performs an automatic pre-flight validation on every run. All of the following must pass before the flow can execute.

### 3.1 Power Automate Desktop Installed

PAD must be installed on the runner machine. Default executable path:

```
C:\Program Files (x86)\Power Automate Desktop\PAD.Console.Host.exe
```

The script checks this path at startup and logs the detected PAD version.

### 3.2 UIFlowService Running

The **UIFlowService** Windows service must be in `Running` state.

- If still `StartPending` at boot, the script waits up to **30 seconds** automatically.
- If `Stopped`, run as administrator:

```powershell
Start-Service UIFlowService
```

### 3.3 Protocol Handler Registered

The `ms-powerautomate://` URI scheme must be registered in the Windows registry (under `HKLM:\SOFTWARE\Classes\ms-powerautomate`). This is installed automatically with PAD. If missing, reinstall PAD.

### 3.4 PAD Signed In

PAD must be signed in with an account that has access to the target environment and flow. If not authenticated, the flow will fail to start and the script logs a clear diagnostic error.

### 3.5 Valid Environment and Flow GUIDs

Both **EnvironmentId** and **FlowId** must be valid GUIDs. The script validates GUID format at startup and rejects placeholder values before attempting to trigger anything.

### 3.6 Interactive Desktop Session

PAD flows run in the interactive user session (Session 1+). C TWO's auto-login establishes this session automatically. Ensure auto-login is configured in C TWO resource settings.

### 3.7 Windows PowerShell 5.1+

The script declares `#Requires -Version 5.1` and is written for **Windows PowerShell 5.1** — the build shipped with Windows and registered in C TWO as the engine (`C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe`). No additional PowerShell installation is needed.

---

## 4. How It Works

### Step 1: Parameter Logging

Logs the machine hostname and Windows session identity (`whoami`) to the C TWO Session Monitoring Dashboard as the very first log entry. EnvironmentId, FlowId, and InputJson are logged immediately after, making every execution fully auditable from the first line.

```json
{"level":"Information","message":"=== C TWO PAD Trigger starting on PRD1 | domain\\user ==="}
{"level":"Information","message":"FlowId:        bd8e761e-fb25-4af7-805e-90b6d62f351f"}
{"level":"Information","message":"EnvironmentId: 187be595-9474-e84d-8200-46f40bb62f57"}
{"level":"Information","message":"InputJson:     {\"Input_text\": \"C TWO orchestrating PAD flows\"}"}
```

### Step 2: Environment Validation

Pre-flight checks, in order:

1. PAD executable exists at the configured path (logs PAD version if found)
2. UIFlowService is `Running` (polls up to 30s if `StartPending`)
3. `ms-powerautomate://` protocol handler is registered in the registry
4. EnvironmentId is a valid GUID (not a placeholder)
5. FlowId is a valid GUID (not a placeholder)

Any failure logs a `Fatal`-level message and the run stops immediately — no flow trigger is attempted, and C TWO records the session as **Failed**.

### Step 3: Flow Trigger and Window Management

Snapshots the PIDs of any pre-existing PAD/runner processes (so only *new* ones are attributed to this run), URL-encodes `InputJson`, constructs the PAD trigger URI, and launches `PAD.Console.Host.exe` with it (hidden window):

```
ms-powerautomate:/console/flow/run?environmentid=<EnvironmentId>&workflowid=<FlowId>&source=Other&inputArguments=<url-encoded InputJson>
```

> Note the exact parameter names the script uses: `environmentid`, `workflowid` (**not** `flowId`), `source=Other`, and `inputArguments` (**not** `inputJson`). The JSON is URL-encoded before being appended.

For the following **30 seconds**, the script:

- Actively suppresses the PAD UI window via Win32 API (`ShowWindow` with `SW_HIDE`)
- Calls `Invoke-DismissPADDialogs` every 300ms to dismiss any blocking dialogs (including the update notification popup) via `FindWindow` + `SendMessage(WM_CLOSE)`

### Step 4: Runner Process Detection

Waits up to **60 seconds** (or `TimeoutSeconds`, whichever is lower) for a new runner process to appear. Monitored process names:

- `PAD.RobotV2`
- `PAD.FlowEngine`
- `PAD.Robot.Host`

The script records the PIDs of any pre-existing runner processes at startup and only considers **new** ones as belonging to this execution. `Invoke-DismissPADDialogs` continues running on every 1-second tick during this loop.

When a runner is detected, the script calls `WaitForExit()`, blocking until the flow completes. If no runner is detected, the script logs a clear diagnostic error and the session is reported as **Failed**.

### Step 5: PAD Session Log Forwarding (`-PadTrace`)

After the runner exits, the script reads all PAD log files written during the session (those modified since ~10s before the session started) from:

```
C:\ProgramData\Microsoft\Power Automate\Logs\
```

Each line is parsed and forwarded to C TWO as a `Trace`-level log entry. Because `Trace` entries are dropped unless `-PadTrace` is set, this per-line PAD content only reaches the dashboard when `-PadTrace` is active. (The wrapper `Information` lines — e.g. `=== PAD session logs ===` and `Forwarding N PAD log file(s)` — always appear.)

### Step 6: Final Status

Evaluates the runner result, the no-runner condition, and the timeout, then emits the final telemetry line with total duration. From this, C TWO identifies the **session outcome** — **Completed** or **Failed** — which it records in the Session Monitoring Dashboard and uses to drive any response actions you have configured (see [Execution Outcomes](#9-execution-outcomes)).

---

## 5. Configuration and Parameters

The script exposes the following parameters. Machine-level defaults (`PADExePath`, `TimeoutSeconds`) are the only values set inside the script file, and they are pre-set, so no editing is required to onboard. All flow-specific values are supplied by C TWO at runtime.

| Parameter | Type | Required | Default | Description |
|---|---|---|---|---|
| `-FlowId` | `string` | Mandatory | n/a | GUID of the PAD desktop flow to execute |
| `-EnvironmentId` | `string` | Mandatory | n/a | GUID of the Power Platform environment |
| `-InputJson` | `string` | Mandatory | n/a | JSON object of input variables. Pass `{}` if the flow has no inputs |
| `-PADExePath` | `string` | Optional | Default install path | Override the PAD executable path for non-standard installs |
| `-TimeoutSeconds` | `int` | Optional | `150` | Max seconds to wait for the runner to finish |
| `-PadTrace` | `switch` | Optional | Off | When present, forwards PAD internal log files as Trace entries |

The two machine-level defaults live in the `CONFIGURATION` block at the top of the script:

```powershell
$cfg_PADExePath     = "C:\Program Files (x86)\Power Automate Desktop\PAD.Console.Host.exe"
$cfg_TimeoutSeconds = 150
```

You normally leave these as-is; override them per-run via `-PADExePath` / `-TimeoutSeconds` (or the mapped C TWO Variables) instead of editing the file.

### Write-CTwoLog

All logging goes through a single function that emits compact JSON to stdout:

```powershell
function Write-CTwoLog {
    param(
        [ValidateSet("Trace","Debug","Information","Warning","Error","Fatal")]
        [string]$Level = "Information",
        [Parameter(Mandatory)][string]$Message
    )
    if ($Level -eq "Trace" -and -not $PadTrace) { return }
    @{ level = $Level; message = $Message } | ConvertTo-Json -Compress | Write-Output
}
```

Six levels are valid — `Trace`, `Debug`, `Information`, `Warning`, `Error`, `Fatal` — though the script itself uses all except `Debug`. When `-PadTrace` is **not** specified, `Trace`-level calls are silently dropped (see the guard line above), so there is no log-volume impact on production runs. The function writes each JSON line to **stdout** via `Write-Output`; the Machine Agent reads that stream.

---

## 6. C TWO Variable to Parameter Mapping

In the C TWO Script Registry, each script parameter is mapped to a C TWO Variable. C TWO resolves and injects the values at execution time. No GUIDs or credentials are ever stored inside the script file.

### FlowId

**How to find it:** go to [make.powerautomate.com](https://make.powerautomate.com), open **My Flows → Desktop flows**, then open the target flow. The Flow ID is the GUID in the browser URL after `/flows/`.

```
https://make.powerautomate.com/environments/187be595-.../flows/bd8e761e-fb25-4af7-805e-90b6d62f351f
                                                                 ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
```

### EnvironmentId

**How to find it:**

- **Option A — Power Automate portal:** click the environment name (top-right), select the target environment. The Environment ID appears in the browser URL after `/environments/`.
- **Option B — Power Platform Admin Center** ([admin.powerplatform.microsoft.com](https://admin.powerplatform.microsoft.com)): open Environments → select the environment → Settings. The Environment ID is shown in Session details.

### InputJson

**How to find the variable names:** open the flow in the portal and inspect its **input variables** (the "Inputs" section at the top of the flow). Each input has a name and type.

Build a JSON object where each **key** is the exact input variable name (case-sensitive) and each **value** is the runtime value:

```json
{"Input_text": "C TWO orchestrating PAD flows", "Customer": "ACME Corp"}
```

If the flow has **no input variables**, pass:

```json
{}
```

> **Shell note:** when invoking the script manually from a PowerShell terminal, wrap the JSON value in single quotes so PowerShell doesn't parse `{` as a script block:
> ```powershell
> -InputJson '{"Input_text": "C TWO orchestrating PAD flows"}'
> ```

### TimeoutSeconds

No portal lookup needed. Set to the expected maximum duration of your flow in seconds, with a reasonable buffer. The default is `150` seconds.

---

## 7. PAD Licensing

### The trigger works with any license

The script triggers PAD flows via the `ms-powerautomate://` protocol — the same mechanism PAD uses when a flow is run from the console. This works identically across all PAD license types. **The license controls what your flow can do, not how C TWO starts it.**

### License compatibility

| License Type | Compatibility | Notes |
|---|---|---|
| Power Automate Premium (per user) | Confirmed | Attended execution in interactive session. Full premium connector and UI automation access. |
| Power Automate Process (per flow) | Confirmed | Machine-based license. Same PAD client and trigger mechanism, works identically regardless of how the license is assigned. |
| Power Automate Premium + Unattended Add-on | Confirmed | C TWO's auto-login satisfies the OS-level session requirement while the flow itself runs unattended. |
| Windows 11 Built-in PAD (free) | Limited | Trigger mechanism works, but the free version supports only standard actions. Premium connectors require a paid Microsoft license. |

### C TWO responsibility boundary

C TWO is responsible for orchestrating the execution of PAD flows: triggering them on schedule, streaming telemetry, tracking SLA, and self-healing on failure. **C TWO does not manage or provide Power Automate licenses.** Customers must procure and maintain the appropriate Microsoft license for their flows independently.

---

## 8. Telemetry and Logging

### JSON protocol

Every telemetry line the script writes to stdout is a compact JSON object:

```json
{"level":"Information","message":"PASS: UIFlowService is Running"}
```

The Machine Agent reads this stream via Named Pipe and forwards it to the C TWO Session Monitoring Dashboard in real time.

### Typical log output for a successful run

```json
{"level":"Information","message":"=== C TWO PAD Trigger starting on PRD1 | domain\\user ==="}
{"level":"Information","message":"FlowId:        bd8e761e-fb25-4af7-805e-90b6d62f351f"}
{"level":"Information","message":"EnvironmentId: 187be595-9474-e84d-8200-46f40bb62f57"}
{"level":"Information","message":"InputJson:     {\"Input_text\": \"C TWO orchestrating PAD flows\"}"}
{"level":"Information","message":"PASS: PAD executable found - version 2.x.x"}
{"level":"Information","message":"PASS: UIFlowService is Running"}
{"level":"Information","message":"PASS: ms-powerautomate:// protocol handler is registered"}
{"level":"Information","message":"PASS: EnvironmentId GUID is valid"}
{"level":"Information","message":"PASS: FlowId GUID is valid"}
{"level":"Information","message":"PAD.Console.Host launched (PID: 9332)"}
{"level":"Information","message":"Runner process 'PAD.RobotV2' detected (PID: 11240) - waiting for it to finish..."}
{"level":"Information","message":"Flow completed successfully in 47.2s"}
```

### Log level reference

| Level | Used For | Example |
|---|---|---|
| `Trace` | PAD internal session log events, only when `-PadTrace` is active | `[PAD] [robin.execution.start]` |
| `Debug` | Valid level, not used by the script by default | — |
| `Information` | Normal progress: validation passes, trigger, completion | `PASS: UIFlowService is Running` |
| `Warning` | Non-fatal: UIFlowService still starting, PAD dialog dismissed | `UIFlowService is StartPending - waiting...` |
| `Error` | Flow-level failures: timeout, runner reported a failure, flow not started | `Flow timed out after 150s` |
| `Fatal` | Configuration errors: exe not found, service stopped, invalid GUID | `FAIL: PAD executable not found` |

### `-PadTrace` switch

When `-PadTrace` is included, the script forwards PAD's internal session log files after the flow completes, each line as a `Trace`-level entry.

- **Log source:** `C:\ProgramData\Microsoft\Power Automate\Logs\`
- **Level emitted:** `Trace`
- **Default:** not forwarded (dropped silently when `-PadTrace` is absent)

**When to use:** enable when a flow is failing with no clear cause in the standard `Information`-level logs. Not recommended as a default for production runs due to high log volume.

---

## 9. Execution Outcomes

At the end of every run, C TWO classifies the **session outcome** and records it in the Session Monitoring Dashboard. You then configure **response actions** against each outcome — retries, alerts, escalations, or downstream workflow steps — directly in C TWO, with no change to the script.

| Session outcome | What it means | Telemetry signal | Response actions you can configure |
|---|---|---|---|
| **Completed** | The PAD flow ran and the runner finished cleanly | Final `Information` line, e.g. `Flow completed successfully in 47.2s` | Continue the workflow; mark the session complete in the audit trail |
| **Failed** | The flow timed out, the runner reported a failure, no runner was detected, or a pre-flight validation check failed | `Error`- or `Fatal`-level line, e.g. `Flow timed out after 150s` or `FAIL: PAD executable not found` | Automatic retry per policy; raise an alert; escalate to a fallback process |

> C TWO decides whether to retry, alert, or escalate based on the session outcome and the policy you configure — you don't need to script any of that logic.

### Common causes of a failed run

- Runner process never appeared within the detection window (wrong FlowId/EnvironmentId, PAD not signed in, or a blocking dialog prevented PAD from starting)
- Runner reported a failure (flow execution error inside PAD)
- Flow exceeded the `TimeoutSeconds` limit

### Common causes of a configuration failure (pre-flight check)

- PAD executable not found at the configured path
- UIFlowService stopped and did not recover within 30 seconds
- `ms-powerautomate://` protocol handler not registered
- FlowId or EnvironmentId is not a valid GUID
- PAD failed to launch

---

## 10. Known Limitations

### 10.1 Power Automate Desktop update popup (high impact)

**What happens:** when a new version of PAD is available, PAD displays a modal update notification dialog on startup. This blocks the flow runner from loading, causing the script to fail with `Flow did not start - no runner process was detected`.

**Automatic mitigation:** the script attempts to dismiss this dialog via Win32 API calls (`FindWindow` + `SendMessage(WM_CLOSE)`) during both the 30-second window-management phase and on every tick of the runner-detection loop. However, depending on the Windows session security context and VM configuration, these calls may be blocked by the OS.

**Recommended fix — disable PAD update notifications permanently.** Run [`DisablePADUpdates.ps1`](DisablePADUpdates.ps1) **once on the runner machine, as administrator**. It sets `DisableUpdate=1` in the policy key (`HKLM:\SOFTWARE\Policies\Microsoft\Power Automate Desktop`, highest precedence, survives PAD self-updates) and the app key as a fallback. Restart PAD afterwards and confirm the update dialog no longer appears. When you want to update PAD, do it manually outside scheduled C TWO execution windows.

### 10.2 Interactive desktop session always required (by design)

PAD requires an active interactive Windows desktop session (Session 1+). C TWO handles this automatically via its auto-login mechanism. If the runner machine has no active session (e.g. auto-login was not configured or was interrupted), PAD will launch but flows will fail silently.

**Resolution:** ensure auto-login is enabled in the C TWO resource settings for the runner machine.

### 10.3 UIFlowService startup race at boot (mitigated)

When the script runs shortly after machine boot, UIFlowService may still be in `StartPending` state. The script handles this by polling every 2 seconds for up to 30 seconds, waiting for the service to reach `Running` before proceeding. A `Warning`-level entry appears in the dashboard when this delay occurs — no action required.

---

## 11. Troubleshooting

| Symptom in Dashboard | Root Cause | Fix |
|---|---|---|
| `FAIL: PAD executable not found` | PAD not installed or wrong path | Pass `-PADExePath` (or update `$cfg_PADExePath` in the script) to the correct path |
| `FAIL: UIFlowService status is 'Stopped'` | UIFlowService has stopped | Run `Start-Service UIFlowService` as administrator |
| `UIFlowService is StartPending - waiting...` | Script ran at boot before service started | No action needed — the script waits automatically |
| `FAIL: ms-powerautomate:// not registered` | Protocol handler missing | Reinstall Power Automate Desktop |
| `FAIL: EnvironmentId is not a valid GUID` | Placeholder or malformed GUID in the C TWO Variable | Replace with the correct GUID from the Power Automate portal URL |
| `Flow did not start - no runner process was detected` | Wrong GUIDs, PAD not signed in, or update dialog blocked PAD | Verify GUIDs, confirm PAD sign-in, run [`DisablePADUpdates.ps1`](DisablePADUpdates.ps1) |
| `PAD dialog 'Power Automate update' dismissed` | Update popup appeared; Win32 API dismissed it this time | Run [`DisablePADUpdates.ps1`](DisablePADUpdates.ps1) to prevent it permanently |
| `Flow timed out after Xs` | Flow exceeded `TimeoutSeconds` | Increase `TimeoutSeconds` via the C TWO Variable mapping; investigate flow performance |
| No `[PAD]` Trace entries visible | `-PadTrace` switch not included | Add `-PadTrace` for the investigation run, then remove it to reduce log volume |

---

## 12. End to End Setup Guide

### Step 1: Prepare the runner machine

- Install Power Automate Desktop
- Start `UIFlowService` (or confirm it starts automatically)
- Sign in to PAD with an account that has access to the target flows and environments
- Run [`DisablePADUpdates.ps1`](DisablePADUpdates.ps1) once as administrator (see [10.1](#101-power-automate-desktop-update-popup-high-impact))
- Confirm C TWO auto-login is configured for this machine

### Step 2: Deploy the script

Copy [`ctwo-pad-script.ps1`](ctwo-pad-script.ps1) from this repository to the runner machine, as-is. Recommended path:

```
C:\Scripts\ctwo-pad-script.ps1
```

No flow-specific values need to be hardcoded, and no edits are required to onboard. All runtime values are supplied by C TWO via Variable mapping.

### Step 3: Register the PowerShell engine in C TWO

In **Apps and Connections**, add a PowerShell engine entry pointing to:

```
C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe
```

### Step 4: Register the script in C TWO

Create a new script entry:

- **Path:** path to the deployed script (e.g. `C:\Scripts\ctwo-pad-script.ps1`)
- **Engine:** the PowerShell engine registered in Step 3
- **Desktop session toggle:** enabled (PAD requires an interactive session)
- **Variables:** define three Variables (`FlowId`, `EnvironmentId`, `InputJson`) and map them to the parameters:

```
-FlowId [FlowId] -EnvironmentId [EnvironmentId] -InputJson [InputJson]
```

### Step 5: Run a validation test

Trigger the script manually from C TWO with valid GUIDs and `InputJson` set to `{}`. Confirm in the Session Monitoring Dashboard:

- First log line shows the correct hostname and Windows identity
- All pre-flight checks show `PASS`
- `PAD.Console.Host launched (PID: ...)` appears
- Runner process is detected
- The final result confirms the flow completed successfully (session outcome **Completed**)

Add `-PadTrace` for the test run to capture full PAD internal logs and confirm the flow executed correctly end to end.

### Step 6: Schedule or connect to your workflow

Attach the script to a C TWO schedule, event trigger, or multi-step workflow. Use the `InputJson` Variable to pass dynamic data at runtime. C TWO reads the session outcome and telemetry stream to drive SLA tracking, alerts, and automatic retry logic.

---

## 13. Shell Quoting for Manual Invocation

When triggering the script manually from a terminal (not via C TWO), the `InputJson` argument requires careful quoting because PowerShell interprets `{` as the start of a script block.

### PowerShell (recommended — single quotes)

```powershell
C:\Scripts\ctwo-pad-script.ps1 `
  -FlowId        bd8e761e-fb25-4af7-805e-90b6d62f351f `
  -EnvironmentId 187be595-9474-e84d-8200-46f40bb62f57 `
  -InputJson     '{"Input_text": "C TWO orchestrating PAD flows"}' `
  -PadTrace
```

### CMD (escape inner quotes with backslash)

```cmd
powershell.exe -File C:\Scripts\ctwo-pad-script.ps1 -FlowId bd8e761e-... -EnvironmentId 187be595-... -InputJson "{\"Input_text\": \"C TWO orchestrating PAD flows\"}"
```

### Why this only affects manual runs

When C TWO invokes the script via the Machine Agent, it passes parameters **programmatically**, bypassing shell parsing entirely — the JSON string arrives at the script intact. Quoting issues only apply when typing commands directly in a terminal. This applies to **any** script engine (Python, Bash, etc.): the single-quote rule is a shell concern, not an engine one.

---

## Support

- **Knowledge base:** [c-two.zendesk.com](https://c-two.zendesk.com/)
- **Email:** [customersuccess@ctwo.com](mailto:customersuccess@ctwo.com)
- **Website:** [ctwo.com](https://ctwo.com/)

*C TWO Automate AS · 58 Nøstegaten, 5011 Bergen, Norway*
