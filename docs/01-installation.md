# Installation

There are two ways to install the C TWO custom connector into your Power Platform environment. **Method A (solution import)** is recommended for most customers.

Both methods install the same connector, including its connection parameters (Host, Base URL, API Key) and the host‑routing policy. After installing, continue to [Configuration](02-configuration.md) to create a connection.

> ⚠️ **Do not** install by importing `paconn/apiDefinition.swagger.json` on its own via the maker portal's "Import an OpenAPI file" option. The swagger alone does **not** include `apiProperties.json` (the connection parameters and host policy), so the resulting connector cannot reach your C TWO server. Use Method A or Method B below.

---

## Method A — Import the solution (recommended)

1. Sign in to [make.powerautomate.com](https://make.powerautomate.com) (or [make.powerapps.com](https://make.powerapps.com)).
2. Select the target **environment** (top‑right).
3. In the left nav, choose **Solutions**.
4. Click **Import solution** → **Browse** → select [`solution/CTWO-Connector_managed.zip`](../solution/CTWO-Connector_managed.zip).
5. Click **Next**, then **Import**. Wait for the import to complete (usually under a minute).
6. The **C TWO** custom connector is now available in this environment. Continue to [Configuration](02-configuration.md).

To install into more environments, repeat in each one.

---

## Method B — `paconn` CLI

Use this if you prefer the command line or are automating deployment.

### Prerequisites
- **Python 3** installed.
- The Power Platform Connectors CLI:
  ```bash
  python -m pip install paconn
  ```
  > On Windows, if the `paconn` command isn't found or is blocked, run it as a module: `python -m paconn …` (add `-u` so interactive prompts display: `python -u -m paconn …`).

### Steps
1. **Sign in** (device‑code flow — opens `microsoft.com/devicelogin`):
   ```bash
   python -u -m paconn login
   ```
2. From the [`paconn/`](../paconn/) folder, **create** the connector in your environment (get your **Environment ID** from the Power Platform Admin Center):
   ```bash
   python -u -m paconn create -e <ENVIRONMENT_ID> \
     --api-def apiDefinition.swagger.json \
     --api-prop apiProperties.json \
     --icon icon.png
   ```
   This writes a `settings.json` containing the new connector ID.
3. To **update** later (after pulling a newer version of this repo):
   ```bash
   python -u -m paconn update -s settings.json
   ```

> **Note:** `paconn` occasionally doesn't persist the icon (the connector imports fine, but shows a default icon). If that happens, open the connector in the maker portal → **General** → **Upload connector icon** → select `paconn/icon.png`.

Continue to [Configuration](02-configuration.md).

---

## Updating an existing connector

If you already have the C TWO connector installed and configured, choose the update method based on **what changed** in the new release:

### Option 1 — Update from OpenAPI file *(quick refresh of operations)*

Best when the update only changes **operations or their input/output schemas** — the most common case. It keeps your connection parameters, host‑routing policy, and existing connections intact (those aren't part of the OpenAPI file).

1. In the maker portal, open your **C TWO** custom connector.
2. Click the **⋯** menu → **Update from OpenAPI file**.
3. Select [`paconn/apiDefinition.swagger.json`](../paconn/apiDefinition.swagger.json) from this repo.
4. Step through the wizard and **Update connector**.

**What this updates:** operations, response schemas, `host`, `basePath`, security definition.
**What it leaves untouched:** the *C TWO Host* / *C TWO Base URL* connection parameters, the host‑routing policy, and all existing connections.

> ⚠️ This is safe **only if** your connector was installed from the **solution** or via **`paconn`** (so it already has the *C TWO Host* / *Base URL* parameters + policy). If instead someone hardcoded a host directly in the connector's **Host** field, updating from the swagger will reset that Host to the placeholder (`connect24.ctwo.cloud`) — use Option 2 in that case.

### Option 2 — Solution re‑import or `paconn update` *(full update)*

Required when a release **changes the connection parameters or the host policy** (rare), because those live in `apiProperties.json`, which the OpenAPI file doesn't include.

- **Solution:** **Solutions → Import solution** → upload the newer `solution/CTWO-Connector_managed.zip`. Importing a newer version upgrades in place.
- **`paconn`:** from the `paconn/` folder, `python -u -m paconn update -s settings.json`.

### After any update

- Existing **connections are preserved** — users don't need to reconnect.
- If an operation's **inputs/outputs changed**, **delete and re‑add that action** in affected flows so it picks up the new schema (existing actions cache the old one).
- Allow a few minutes for Power Platform to propagate the change across regions.

---

## Uninstalling

Remove the connector via **Solutions → …(your solution)… → Delete**, or delete the custom connector directly under **Custom Connectors**. Delete any connections you no longer need under **Connections**.
