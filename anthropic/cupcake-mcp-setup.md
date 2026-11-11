# Deploying the Cupcake MCP server to Azure

Reusable runbook for standing up the Cupcake Store MCP server for a workshop.

Source: [GlobalAICommunity/cupcake-mcp](https://github.com/GlobalAICommunity/cupcake-mcp) — Henk Boelman, MIT.
FastAPI + Azure Table Storage, MCP mounted at `/mcp/`.

**This runbook is keyless and private.** It works in subscriptions that
disable storage shared-key access, public blob access, and container registry
admin credentials. The app reaches Table Storage and the registry through a
managed identity, so no storage key, connection string, or registry password is
ever created or stored. The upstream app only supports connection strings, so
Stage 2 applies a small patch,
[cupcake-mcp-keyless.patch](cupcake-mcp-keyless.patch).

It also keeps storage off the public network. Many subscriptions enforce this
with a policy that forces **public network access Disabled** on every storage
account and reverts any attempt to turn it back on, so the app reaches storage
through a private endpoint in a virtual network (Stage 7,
[cupcake-mcp-private.bicep](cupcake-mcp-private.bicep)).

**This is not a Foundry resource.** It's a plain Container App. The Foundry
project only ever sees it as a URL in `CUPCAKE_MCP_URL`.

Budget 20-30 minutes; most of that is provisioning and build time.

The commands here are written for bash, so they run as they are on a Mac, on
Linux, and in a Codespace. On Windows, run them in a Codespace.

---

## Stage 0 — Prerequisites

Azure CLI, Git, and a subscription you can create resources in. You also need
permission to create role assignments on the resource group (Owner or User
Access Administrator): Stage 6 grants the app's identity access to storage and
the registry. Contributor alone is not enough.

```
az login
az account show --output table
az account set --subscription "<subscription name or id>"   # if the wrong one
az extension add --name containerapp --upgrade
```

If extension installation fails with `/usr/bin/python3: No module named pip`,
the Azure CLI's system Python is missing pip. Installing packages into the
workshop's Python environment does not fix that interpreter. In a Debian or
Ubuntu dev container, install the system package, then retry:

```
sudo apt-get install -y python3-pip
az extension add --name containerapp --upgrade
```

If apt cannot locate the package, run `sudo apt-get update` first. Once the
extension installs, rerun the `az containerapp` command that failed.

Register the resource providers. **Do this before anything else** — each one
fails the relevant create step if missing, and registration takes a few minutes:

```
az provider register --namespace Microsoft.Storage
az provider register --namespace Microsoft.ManagedIdentity
az provider register --namespace Microsoft.ContainerRegistry
az provider register --namespace Microsoft.App
az provider register --namespace Microsoft.OperationalInsights
```

Check progress with `az provider show -n Microsoft.Storage --query registrationState -o tsv`
(want `Registered`).

The Container Apps environment in Stage 7 sits in a virtual network, which needs
one subscription feature. Without it the environment fails with
`ManagedEnvironmentOperationFailedDueToSubscriptionNotRegisteredForFeature`.
Register the feature, then register the provider **again** so it takes effect:

```
az feature register --namespace Microsoft.Network --name AllowBringYourOwnPublicIpAddress
az feature show --namespace Microsoft.Network --name AllowBringYourOwnPublicIpAddress --query properties.state -o tsv
az provider register --namespace Microsoft.Network
```

Wait until the feature shows `Registered` before the last command.

---

## Stage 1 — Pick names

| Thing | Rule | Example |
|---|---|---|
| Region | Near the attendees. Any region with Container Apps works for this server; keep all of this server's resources in the same region. | `uksouth` / `japaneast` |
| Resource group | Any | `rg-cupcake-mcp` |
| ACR | **Globally unique, alphanumeric only, no hyphens** | `crcupcake01` |
| Storage account | **Globally unique, lowercase alphanumeric, 3–24 chars** | `stcupcake01` |
| Managed identity | Any | `id-cupcake-mcp` |
| Virtual network | Any | `vnet-cupcake-mcp` |
| Container Apps env | Any | `cae-cupcake-mcp` |
| Container app | Any | `ca-cupcake-mcp` |

Name conflicts on the two globally-unique ones are the usual snag — add digits.

The commands below use `uksouth`. If you picked another region, change it in
Stages 3 and 4; Stage 7 uses the resource group's location. It does not have to
match the region of the Search service or the Foundry project: the agent
reaches each one by its own address.

---

## Stage 2 — Get the code

Run this from the `anthropic/` folder of your `model-mastery` clone. It clones
the app **outside** the workshop repo, pins the commit the patch was tested
against, and applies the keyless patch:

```
PATCH="$PWD/cupcake-mcp-keyless.patch"
BICEP="$PWD/cupcake-mcp-private.bicep"
cd ../..
git clone https://github.com/GlobalAICommunity/cupcake-mcp
cd cupcake-mcp
git checkout 2c96c51d80dc6df392c9cc5cdd1d7ea655554178
git apply "$PATCH"
git status --short
grep -q AZURE_STORAGE_ACCOUNT_NAME backend/storage.py && echo "PATCHED" || echo "NOT PATCHED: stop and fix before continuing"
```

**Do not skip this step.** Without the patch the app only accepts a connection
string, which this runbook never creates, so it crashes on startup with
`Connection string is either blank or malformed`. `git status` should list
`.env.example`, `backend/storage.py`, and `requirements.txt` as modified, and
the last line must print `PATCHED`. The patch makes the app use Entra ID
(`DefaultAzureCredential`) against `AZURE_STORAGE_ACCOUNT_NAME`; a connection
string is still honored for local development with Azurite, but the deployment
below never sets one. If you check out a newer upstream commit, the patch may
need adjusting.

Build context only. Nothing runs locally; Azure does the build.

---

## Stage 3 — Resource group

```
az group create -n rg-cupcake-mcp -l uksouth
```

---

## Stage 4 — Storage account

```
az storage account create \
  -g rg-cupcake-mcp -n stcupcake01 \
  -l uksouth --sku Standard_LRS --kind StorageV2 \
  --allow-shared-key-access false \
  --allow-blob-public-access false \
  --public-network-access Disabled \
  --min-tls-version TLS1_2
```

Shared-key access is off, so the account has no usable key and there is no
connection string to copy. The only way in is an Entra ID role, granted in
Stage 6, over the private endpoint created in Stage 7. The app uses **Table
Storage only**; no blob container is created.

**Holds all store config** — flavours, prices, stock, orders, admin password.
Keep it even if the app is torn down.

---

## Stage 5 — Registry and image build

```
az acr create -g rg-cupcake-mcp -n crcupcake01 --sku Basic
az acr build -r crcupcake01 -t cupcake-mcp:latest .
```

The registry's admin user stays disabled (its default). Run the build from
inside `cupcake-mcp/`, the folder where you applied the patch in Stage 2 (its
last line must have printed `PATCHED`). Builds in Azure, no local Docker. Wait
for `Run ID ... succeeded`.

---

## Stage 6 — Identity and access

The app runs as a user-assigned managed identity. Create it, then grant it
exactly two roles: read and write the storage tables, and pull from the
registry.

```
az identity create -g rg-cupcake-mcp -n id-cupcake-mcp

IDENTITY_PRINCIPAL_ID=$(az identity show -g rg-cupcake-mcp -n id-cupcake-mcp --query principalId -o tsv)
STORAGE_ID=$(az storage account show -g rg-cupcake-mcp -n stcupcake01 --query id -o tsv)
ACR_ID=$(az acr show -g rg-cupcake-mcp -n crcupcake01 --query id -o tsv)

az role assignment create \
  --assignee-object-id "$IDENTITY_PRINCIPAL_ID" --assignee-principal-type ServicePrincipal \
  --role "Storage Table Data Contributor" --scope "$STORAGE_ID"

az role assignment create \
  --assignee-object-id "$IDENTITY_PRINCIPAL_ID" --assignee-principal-type ServicePrincipal \
  --role AcrPull --scope "$ACR_ID"
```

Roles can take a few minutes to take effect; the network deployment in Stage 7
gives them time.

---

## Stage 7 — Private network, environment, and app

Storage has public network access disabled, so the app needs a private path to
it. One Bicep template, [cupcake-mcp-private.bicep](cupcake-mcp-private.bicep),
creates all of it:

| Resource | Why |
|---|---|
| Virtual network `vnet-cupcake-mcp`, two subnets | One for the Container Apps environment, one for the private endpoint |
| Private endpoint `pe-stcupcake01-table` | Gives the storage account's Table service a private IP in the network |
| Private DNS zone `privatelink.table.core.windows.net`, linked to the network | Makes `stcupcake01.table.core.windows.net` resolve to that private IP from inside it |
| Container Apps environment `cae-cupcake-mcp`, in the network | Public ingress stays on, and the app's outbound traffic can reach the private endpoint |
| Container app `ca-cupcake-mcp` | Runs as the Stage 6 managed identity, pulls the image with it, and reads `AZURE_STORAGE_ACCOUNT_NAME` and `AZURE_CLIENT_ID` |

```
az deployment group create \
  -g rg-cupcake-mcp -n cupcake-mcp-private \
  -f "$BICEP" \
  --query properties.outputs.mcpUrl.value -o tsv
```

`BICEP` was set in Stage 2. If you opened a new terminal since, set it again
from the `anthropic/` folder: `BICEP="$PWD/cupcake-mcp-private.bicep"`.

It prints your MCP URL; keep it for Stage 10. Allow 5 to 10 minutes, mostly for
the environment. The defaults match the names in Stage 1; if you chose
different ones, override them, for example
`--parameters storageAccountName=<name> registryName=<name>`. The other
parameters are `identityName`, `vnetName`, `environmentName`, `appName`, and
`imageTag`.

There is no registry password, no storage key, and no storage secret. The
template also generates the cookie-signing `SESSION_SECRET` for you; it only
signs the admin login cookie and is not an Azure credential.
`SESSION_COOKIE_SECURE=true` is set because it is required on HTTPS or the
admin login cookie won't stick.

An existing Container Apps environment cannot be moved into a virtual network.
To change the network setup later, delete the app and environment (the
environment takes 10 to 15 minutes to delete) and deploy again.

**The template pins `minReplicas` and `maxReplicas` to 1, as required for a
workshop.** The server keeps each agent's MCP session in memory, in one process. Without the pin,
Container Apps uses its defaults, 0 to 10 replicas, and both ends break
sessions:

- **Scale to zero when idle.** The next request starts a fresh replica and
  every existing session is gone.
- **Scale out under load.** A full room can start a second replica, and a
  request routed there does not know the session.

Attendees see `session was terminated` from the agent, part-way through a lab.

**Already deployed without it?** Pin it before the event:

```
az containerapp update -g rg-cupcake-mcp -n ca-cupcake-mcp \
  --min-replicas 1 --max-replicas 1
```

One replica is enough for a room of 30 making light JSON calls. It costs a
little more while it runs, so turn the app off afterwards (Stage 11).

---

## Stage 8 — URL and smoke test

```
az containerapp show -g rg-cupcake-mcp -n ca-cupcake-mcp \
  --query properties.configuration.ingress.fqdn -o tsv
```

| URL | What |
|---|---|
| `https://<fqdn>/dashboard` | Order queue + rotating voucher (project this) |
| `https://<fqdn>/admin` | Admin portal |
| `https://<fqdn>/mcp/` | Agent endpoint — **trailing slash required** |

Open `/dashboard` first. If it loads, app and storage are both healthy. Tables
are created and `admin`/`admin` seeded on first start. If it shows an error
right after deploy, wait a few minutes for the Stage 6 roles to take effect and
reload. If the app has scaled to zero, the first request after idle is a cold
start and can take a minute or more.

---

## Stage 9 — Configure the store

Log in at `/admin` (`admin`/`admin`).

1. **Users → change the admin password.** First.
2. **Flavours → add every flavour** on the catering photo and in the Module 1.6 prompt.
3. **Every price to 4.00.**
4. **Hazelnut at stock 0** — zero-stock flavours are hidden from the agent, which is what makes it "sold out".
5. Any non-zero stock for the rest.

Skipping 3 or 4 makes Module 1.6 fail in a way that looks like a model problem.

---

## Stage 10 — Wire into the lab

In the `.env` in the workshop's `anthropic` folder:

```
CUPCAKE_MCP_URL="https://<fqdn>/mcp/"
```

---

## Checking it's up

Quickest is to hit the endpoints:

```
FQDN=$(az containerapp show -g rg-cupcake-mcp -n ca-cupcake-mcp \
  --query properties.configuration.ingress.fqdn -o tsv)

for p in /dashboard /cupcakes /mcp/; do
  printf "%-12s %s\n" "$p" "$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 https://$FQDN$p)"
done
```

| Path | Healthy | Meaning |
|---|---|---|
| `/dashboard` | `200` | App and storage both working |
| `/cupcakes` | `200` | API serving |
| `/mcp/` | **`406`** | Correct. Streamable HTTP needs specific `Accept` headers, so a plain GET is "Not Acceptable". A `404` here is the bad sign. |

Azure's own view:

```
az containerapp show -g rg-cupcake-mcp -n ca-cupcake-mcp \
  --query "{running:properties.runningStatus, provisioning:properties.provisioningState}" -o table

az containerapp revision list -g rg-cupcake-mcp -n ca-cupcake-mcp \
  --query "[].{name:name, active:properties.active, replicas:properties.replicas, health:properties.healthState}" -o table
```

Want `Running` / `Succeeded`, and a revision that is `Active` and `Healthy`.

Want `replicas: 1`. `replicas: 0` with an `Active`, `Healthy` revision means
the app was created without the pin in Stage 7. It is not down, and the next
request will start it, but starting it drops every live MCP session. Pin it
before the event. Deactivated is the real off state (see below).

### "Session was terminated" during a lab

The attendee runs `agent.py` again. A new session starts on the next call and
nothing is lost: orders and customer IDs are in Table Storage. Then check the
replica count above. If it is not 1, pin it.

**Check the server is actually down before you restart it.** Most "cannot
reach it" reports are a company network or VPN blocking
`*.azurecontainerapps.io`. Run the endpoint check above from a phone on mobile
data: that separates "the server is down" from "our network blocks it" in ten
seconds.

To restart it:

```
az containerapp revision restart -g rg-cupcake-mcp -n ca-cupcake-mcp \
  --revision $(az containerapp revision list -g rg-cupcake-mcp -n ca-cupcake-mcp \
               --query "[0].name" -o tsv)
```

A restart loses no store data. Flavours, stock, orders, customers and the
admin password are all in the storage account. It does drop every live
session, and the voucher code starts again.

## Stage 11 — Security and shutting down

The MCP endpoint has no authentication by design. Don't leave it up between
events.

### What's exposed

| Surface | Risk |
|---|---|
| `list_cupcakes`, `/cupcakes`, `/dashboard` | Read-only, nothing sensitive |
| `register_customer` | Junk records — nuisance |
| `order_cupcake` | Voucher-gated, one per customer, stock-limited, throttled |
| `/docs` | Swagger UI, advertises the whole API |
| `/admin` | bcrypt + signed cookies |

Blast radius is small: no real data, and the app holds no stored keys. Its
managed identity can only read and write one storage account's tables and pull
from one registry. Nothing reaches the
Foundry project. The realistic downside is **nuisance and some cost** — pinned
to one replica the bill has a ceiling, but a hammered endpoint still slows the
room down and pollutes the dashboard you're demoing on.

### Lock to your own IP while testing

Solo dry run? Allowlist yourself. No code change, no fork.

```
MY_IP=$(curl -s ifconfig.me)

az containerapp ingress access-restriction set \
  -g rg-cupcake-mcp -n ca-cupcake-mcp \
  --rule-name allow-me --ip-address $MY_IP/32 --action Allow
```

One Allow rule means everything else is denied. Your IP changes with a network
or VPN switch — re-run it then. **Remove the rule before the workshop:**

```
az containerapp ingress access-restriction remove \
  -g rg-cupcake-mcp -n ca-cupcake-mcp --rule-name allow-me
```

### Turning it off

Store config lives in Table Storage, so the app is disposable.

**Use revision deactivate.** There is no `az containerapp stop` (checked on CLI
2.86.0). Deactivating the revision stops the replicas without touching ingress
config, so **the FQDN is preserved** — verified 2026-09-13: 404 while
deactivated, 200 on the same URL after activating.

```
REV=$(az containerapp revision list -g rg-cupcake-mcp -n ca-cupcake-mcp \
  --query "[0].name" -o tsv)

az containerapp revision deactivate -g rg-cupcake-mcp -n ca-cupcake-mcp --revision $REV   # off
az containerapp revision activate   -g rg-cupcake-mcp -n ca-cupcake-mcp --revision $REV   # on
```

Allow ~30s after activating before it serves again.

Heavier options:

| Command | Effect |
|---|---|
| `az containerapp ingress disable -g rg-cupcake-mcp -n ca-cupcake-mcp` | Unreachable. Throws away ingress config — `enable` needs `--type external --target-port 8000` restated. Not tested; no reason to use it over revision deactivate. |
| `az containerapp delete -g rg-cupcake-mcp -n ca-cupcake-mcp` | Gone; recreate with Stage 7 |
| `az group delete -n rg-cupcake-mcp` | Everything, including store config |

Between sessions: **Clear All Orders** in the admin portal — wipes orders,
leaves stock.

### Suggested rhythm

IP-restrict while testing → deactivate the revision overnight → delete the app
when the dry run is done, keeping the storage account so the next region starts
with the flavours already configured.

---

## Running in two regions

Environments and storage accounts can't be moved between regions — deploy a
second stack instead, it's just Stages 3–7 with different names.

- **Separate storage account per region.** Sharing one sends every Table
  Storage call across continents.
- **The FQDN differs**, so `CUPCAKE_MCP_URL` changes — including in the
  Skillable image if attendee `.env` files come from there.
- **Reconfigure the store** in the new region (Stage 9, ~10 min).

Latency matters because every tool call is a round trip from the attendee's
laptop, and the dashboard refreshes every 5s on the projector. Model calls go
to Foundry, not here — if the Foundry project is far away, that dominates.

---

## Gotchas

- `Microsoft.Storage` not registered → storage create fails. Stage 0.
- `/dashboard` errors with `AuthorizationPermissionMismatch` or a 403 right
  after deploy → the Stage 6 role has not taken effect yet. Wait a few minutes
  and reload. If it persists, check the role is on the storage account:
  `az role assignment list --assignee "$IDENTITY_PRINCIPAL_ID" --scope "$STORAGE_ID" -o table`.
- Logs show `ValueError: Connection string is either blank or malformed` from
  `from_connection_string` in `storage.py` → the image was built from
  **unpatched** code, so the Stage 2 patch was skipped. Apply it, rebuild, and
  roll out a new revision (a running app does not pick up a rebuilt `latest`
  image on its own):

  ```
  cd cupcake-mcp
  git apply "$PATCH"      # as in Stage 2
  grep -q AZURE_STORAGE_ACCOUNT_NAME backend/storage.py && echo "PATCHED"
  az acr build -r crcupcake01 -t cupcake-mcp:latest .
  az containerapp update -g rg-cupcake-mcp -n ca-cupcake-mcp \
    --image crcupcake01.azurecr.io/cupcake-mcp:latest --revision-suffix fix1
  ```

  Use a different `--revision-suffix` each time you do this.
- Logs end with `ErrorCode:AuthorizationFailure` ("This request is not
  authorized to perform this operation") from `create_table` → this is a
  **network** block, not a missing role. Storage has public network access
  disabled and the app has no private path to it. Check Stage 7: the private
  endpoint is `Approved`, the private DNS zone is linked to the virtual
  network, and the environment is in that network. (A missing role looks
  different: `AuthorizationPermissionMismatch`.)
- Environment create fails with
  `ManagedEnvironmentOperationFailedDueToSubscriptionNotRegisteredForFeature`
  → the `AllowBringYourOwnPublicIpAddress` feature is not registered. Stage 0.
  Delete the failed environment before redeploying; that takes 10 to 15
  minutes.
- Logs say `Set AZURE_STORAGE_ACCOUNT_NAME` → the env var is missing from the
  app (Stage 7).
- Image pull `unauthorized` → the registry must allow ARM audience tokens
  (normally the default): `az acr config authentication-as-arm update -r crcupcake01 --status enabled`.
- `az storage table ...` commands fail with key-based auth errors because
  shared-key access is off. Add `--auth-mode login` and give yourself the
  **Storage Table Data Contributor** role on the account.
- Policy forces storage **public network access Disabled** and you turn it
  back on? It is usually reverted. Keep it disabled and use the private
  endpoint from Stage 7.
- ACR name with hyphens → rejected. Alphanumeric only.
- `/mcp` without trailing slash → doesn't resolve. `main.py` mounts at `/mcp`
  over `http_app(path="/")`, so the trailing slash is required even though the
  source repo's URL table shows `/mcp`.
- `SESSION_COOKIE_SECURE=false` on HTTPS → admin login appears to succeed then
  bounces back to the login page.
- No `--min-replicas 1 --max-replicas 1` → `session was terminated` part-way
  through a lab. Stage 7.
- "You have already had your one real cupcake" → not a fault. It is the limit
  of one order per customer. A new customer ID clears it.
