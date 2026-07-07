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

## Uninstalling / upgrading

- **Solution:** re‑import a newer `CTWO-Connector_managed.zip` to upgrade in place; remove via **Solutions → … → Delete**.
- **`paconn`:** run `paconn update -s settings.json` to upgrade.

Upgrading the connector does **not** change existing connections. If an operation's inputs/outputs changed, delete and re‑add that action in your flows so it picks up the new schema.
