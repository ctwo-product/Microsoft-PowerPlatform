# C TWO Microsoft Power Platform Custom Connector

The **C TWO custom connector** lets Microsoft Power Platform — **Power Automate, Power Apps, Azure Logic Apps, and Copilot Studio** — connect to your C TWO environment. C TWO is an Agentic Management Platform that orchestrates automation workflows, manages human‑robot interactions, and processes work items through universal queues.

This repository contains everything you need to **install and configure** the connector in your own Power Platform environment, pointing at your own C TWO server (whether you self‑host C TWO or use a C TWO‑hosted cloud environment).

> **Looking for the certified connector?** C TWO is also going through Microsoft certification, after which "C TWO" will appear in the in‑product connector list automatically. Use this repository to install the connector **now**, in any environment or region, before/independently of that rollout.

---

## Repository contents

| Path | What it is |
|---|---|
| [`solution/CTWO-Connector_managed.zip`](solution/CTWO-Connector_managed.zip) | The connector as a **managed** Power Platform solution — **recommended for simply using the connector**. Includes the connection parameters, host‑routing policy, and icon. |
| [`solution/CTWO-Connector_unmanaged.zip`](solution/CTWO-Connector_unmanaged.zip) | The connector as an **unmanaged** solution — use this only if you want to **view or customize** the connector definition in your own environment. |
| [`paconn/`](paconn/) | The raw connector source (`apiDefinition.swagger.json`, `apiProperties.json`, `icon.png`) for installing via the **Power Platform Connectors CLI (`paconn`)**. |
| [`docs/`](docs/) | Detailed guides: [installation](docs/01-installation.md), [configuration](docs/02-configuration.md), [operations](docs/03-operations.md), [troubleshooting](docs/04-troubleshooting.md). |
| [`power-automate-desktop/`](power-automate-desktop/) | **Power Automate *Desktop* orchestration** — a drop-in PowerShell script that lets C TWO trigger, monitor, and govern PAD flows on a runner machine (a different integration path from the connector). See its [README](power-automate-desktop/README.md). |

**Managed vs. unmanaged:** if you just want to *use* the connector, import the **managed** solution — it installs cleanly and uninstalls cleanly. Choose the **unmanaged** solution only if you intend to modify the connector definition inside your environment. Don't import both into the same environment.

---

## Prerequisites

1. **A C TWO environment** reachable over **HTTPS** — either:
   - **C TWO Cloud** (hosted by C TWO — you're given the host), or
   - **C TWO on your own servers** (you control the host).
2. **C TWO credentials** — a **Service Account token** (recommended) or a **Personal Access Token**. See [Obtaining credentials](docs/02-configuration.md#obtaining-credentials).
3. **A Power Platform environment** where you can create custom connectors (System Customizer / Environment Maker or higher).
4. A licence tier that permits custom connectors (**Power Automate Premium** or equivalent). Custom connectors are premium.
5. If C TWO is **on‑premises**, it must be reachable from Power Platform over HTTPS (open your firewall to Microsoft's Power Automate outbound IP ranges — Azure Service Tags `AzureConnectors.<region>` and `PowerPlatformPlex` for your Power Platform Geo).

---

## Quick start

### 1. Install the connector

**Recommended — import the solution:**
1. Go to [make.powerautomate.com](https://make.powerautomate.com) → **Solutions** → **Import solution**.
2. Upload [`solution/CTWO-Connector_managed.zip`](solution/CTWO-Connector_managed.zip) → **Next** → **Import**.

**Alternative — `paconn` CLI:** see [docs/01-installation.md](docs/01-installation.md#method-b--paconn-cli).

> ⚠️ **Do not** import `paconn/apiDefinition.swagger.json` on its own via "Import an OpenAPI file" — the swagger alone does **not** carry the connection parameters or host‑routing policy, so the connection won't work. Use the **solution** or **`paconn`** (which includes `apiProperties.json`).

### 2. Create a connection

Open the **C TWO** connector → create a **New connection**. You'll be asked for **three values**:

| Field | What to enter | Example |
|---|---|---|
| **C TWO Host** | Your C TWO server hostname only — no `https://`, no trailing slash | `connect24.ctwo.cloud` or `ctwo.contoso.com:8443` |
| **C TWO Base URL** | Your C TWO API base path including your division — leading slash, no trailing slash | `/DEFAULT/CTWO.Server/api` |
| **API Key** | Your token in the form `Bearer <your-token>` | `Bearer eyJhbGciOi…` |

The connector routes every request to `https://{Host}{Base URL}/…`, so each connection reaches **your** C TWO environment. Full details: [docs/02-configuration.md](docs/02-configuration.md).

### 3. Use it

Add C TWO actions/triggers to your flows, apps, or Copilot Studio agents. See the [operations reference](docs/03-operations.md).

---

## What the connector can do

- **Triggers** — start a flow when C TWO dispatches a session (with or without an enforced timeout).
- **Session management** — report completion/failure, write typed session logs, adjust timeouts, check for graceful‑stop requests.
- **Universal Queue** — create, list, lock, unlock, retry, defer queue items; update item data; add item‑level logs; manage tags; retrieve attachments; create custom item states; list queues.
- **Human‑in‑the‑loop** — create, assign, unassign, complete, and query structured human‑assistance forms.

Full list with methods and inputs: [docs/03-operations.md](docs/03-operations.md).

---

## Power Automate Desktop

The connector above covers **cloud** Power Platform (Power Automate Cloud, Power Apps, Logic Apps, Copilot Studio). To orchestrate **Power Automate *Desktop*** flows, C TWO uses a different mechanism — a drop-in PowerShell script on the runner machine that triggers PAD via its native CLI protocol and streams live telemetry back to C TWO. No connector, no changes to your flows.

See [`power-automate-desktop/`](power-automate-desktop/) for the script, the one-time update-popup fix, and the full setup guide.

---

## Support

- **Knowledge base:** [c-two.zendesk.com](https://c-two.zendesk.com/)
- **Email:** [customersuccess@ctwo.com](mailto:customersuccess@ctwo.com)
- **Website:** [ctwo.com](https://ctwo.com/) · [Privacy policy](https://ctwo.com/privacy-policy/) · [Terms](https://ctwo.com/terms-conditions/)

*C TWO Automate AS · 58 Nøstegaten, 5011 Bergen, Norway*
