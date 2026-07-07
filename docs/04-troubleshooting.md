# Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| **`401 Unauthorized`** on every call | API Key missing the `Bearer ` prefix, or the token is expired/revoked | Re‑enter the API Key as **`Bearer <your-token>`** (include the word `Bearer` and a space). Generate a fresh Service Account token in C TWO if it was revoked. Check for stray spaces when pasting. |
| **Could not connect to server / timeout** | Wrong **Host**/**Base URL**, or an on‑premises C TWO server not reachable from Power Platform | Verify Host (no `https://`, no trailing slash) and Base URL (leading slash, no trailing slash). For on‑prem, confirm the server is reachable over HTTPS and your firewall allows Microsoft's Power Automate outbound IP ranges (Azure Service Tags for your Geo). |
| **`404 Not Found`** on an operation | Base URL wrong (missing division or `/CTWO.Server/api`), or a trailing slash causing a double `//` | Set Base URL to your full API base, e.g. `/DEFAULT/CTWO.Server/api`, with **no** trailing slash. |
| **Item data stored as an escaped string** (e.g. `"{\"k\":\"v\"}"`) instead of a JSON object | JSON supplied as plain text into an object field | In a **flow**, wrap the value in the `json()` expression: `json('{"k":"v"}')` (or `json(outputs('Compose'))`). In the connector **Test** tab, turn **Raw Body → On** and type the full JSON body. |
| **A trigger never fires** | The wrong C TWO task was selected, or the task isn't exposed to Power Automate | In C TWO, confirm the workflow task is configured as an exposed flow. In the trigger, pick that task from the **Task ID** dropdown. Triggers fire only when C TWO dispatches a session for that task. |
| **Connector shows a default (globe) icon** | `paconn` sometimes doesn't persist the icon on create/update | Open the connector → **General → Upload connector icon** → select `paconn/icon.png`, then save. (Doesn't affect operations.) |
| **A schema/definition change isn't reflected** after updating the connector | Power Platform caches operation schemas per region and per flow action | Give it a few minutes to propagate. In the **Test** tab, hard‑refresh (Ctrl+F5) or reopen the connector. In a **flow**, delete and re‑add the affected action so it picks up the new schema. |
| **Form operations error with a type mismatch** on an ID field | (Handled in the connector) some form ID fields can be integer, string, or null | The connector defines these fields as type‑agnostic, so this shouldn't occur on the current version. If you see it, make sure you're on the latest connector from this repo. |
| **A queue action fails on sequencing** (e.g. lock/retry) | The item isn't in the required state for that operation | Sequence actions correctly (create → lock → modify → unlock; retry only applies to failed/pending items) and pass the `queueItemId` from a prior action's output. |

## Getting help

- **Knowledge base:** *(see your C TWO support portal)*
- **Email:** [customersuccess@ctwo.com](mailto:customersuccess@ctwo.com)

When contacting support, include: the operation name, the full request URL shown in **Peek code** (redact the token), the HTTP status/response, and your C TWO version.
