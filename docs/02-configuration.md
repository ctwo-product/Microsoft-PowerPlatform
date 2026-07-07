# Configuration

After [installing](01-installation.md) the connector, you configure it by creating a **connection** to your C TWO environment. The same connector works for every C TWO environment — each connection points at whichever host you provide.

## Creating a connection

1. In [make.powerautomate.com](https://make.powerautomate.com), go to **Connections** (or open the **C TWO** custom connector → **Test** → **New connection**).
2. Select **C TWO**. You'll be prompted for **three values**:

| Field | What to enter | Notes / examples |
|---|---|---|
| **C TWO Host** | The hostname of your C TWO server. **No** `https://`, **no** trailing slash. | `connect24.ctwo.cloud` (C TWO Cloud) · `ctwo.contoso.com` or `ctwo.contoso.com:8443` (on‑prem, optional port) |
| **C TWO Base URL** | The base path of your C TWO API, including your **division**. **Leading** slash, **no** trailing slash. | `/DEFAULT/CTWO.Server/api` |
| **API Key** | Your C TWO token in the format **`Bearer <your-token>`**. | `Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6…` |

3. Click **Create**.

At runtime the connector builds each request URL as **`https://{Host}{Base URL}/{operation path}`** — for example
`https://connect24.ctwo.cloud/DEFAULT/CTWO.Server/api/universalqueues/v2/queues`.

> **Where do Host and Base URL come from?** Open your C TWO environment in a browser and look at the address / your admin‑provided endpoint. The host is the domain; the base URL is everything after it up to and including `/CTWO.Server/api` (with your division in place of `DEFAULT` if different).

## Obtaining credentials

The connector authenticates with a **Bearer token** in the `Authorization` header. Two token types work:

### Service Account token — recommended for production
Not tied to an individual user, so it survives staff changes and can be rotated independently.
1. Sign in to your C TWO instance.
2. Go to **Apps and Connections → Microsoft Power Automate → Create service account**.
3. Copy the generated token **immediately** — it's shown only once.

### Personal Access Token — for development/testing
Tied to your user account; invalidated if that account is disabled.
1. Open your C TWO **user profile → API Tokens**.
2. **Generate** a new token and copy it immediately.

> **Enter the token as `Bearer <token>`** — include the word `Bearer` and a space. Omitting it causes `401 Unauthorized`. Treat tokens as secrets: store them only in the Power Platform connection, never in flow variables or source control.

## On‑premises vs. C TWO Cloud

- **C TWO Cloud:** use the host and base URL provided by C TWO. No networking setup required.
- **On‑premises:** your C TWO server must be reachable from Power Platform over **HTTPS**. Open your firewall to Microsoft's Power Automate outbound IP ranges — use the **Azure Service Tags** `AzureConnectors.<region>` and `PowerPlatformPlex` for your Power Platform Geo, and review them periodically (Microsoft rotates the ranges).

## Sharing the connection

Once created, share the connection with the makers/flows that need it (or use **connection references** in solutions). Individual makers don't need to re‑enter the token — they select the shared connection.
