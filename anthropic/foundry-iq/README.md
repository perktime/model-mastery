# Foundry IQ knowledge base

Module 1.3 gives the Sparkles agent a second MCP tool: a Foundry IQ knowledge
base holding the shop's policies (hours, delivery, returns, allergens,
loyalty program, bulk-order rules). Foundry IQ is the managed knowledge
layer in Microsoft Foundry, built on Azure AI Search, and every knowledge
base exposes an MCP endpoint. The agent only needs that endpoint and your
Azure sign-in. No Search keys are created or used.

Who runs the steps below:

- **Skillable workshop:** instructors, once, before the event. Attendees get
  the endpoint in their seat's `.env`, and the Search Index Data Reader role
  on the service (step 3).
- **On your own:** you, as step 4 of [SETUP.md](../standalone/SETUP.md).

Derived in part from Shilpa Jain's Foundry IQ sample; see
[THIRD-PARTY-NOTICES.md](../THIRD-PARTY-NOTICES.md).

## Retrieval settings

The knowledge base is created with retrieval reasoning effort `minimal` and
output mode `extractiveData`. It returns matching passages only, and Claude
does the query planning and answer synthesis in the agent. Those two steps
are otherwise performed by the knowledge base itself, which needs its own
model deployment in the project.

Leaving the effort unset is not the same thing: the service then defaults to
`low`, which plans queries with its own model. The index is text only (no
vectorizer), so retrieval makes no embedding calls either. The script asserts
both settings took; if an assertion fails, the SDK is older than 12.1.0b2
(see `requirements.txt`).

## 1. Create an Azure AI Search service

The Free tier is enough: it supports knowledge bases (3 per service) and
semantic ranking with a monthly free allowance, and each subscription gets
one Free service. Basic is only needed for managed identity. On Free,
knowledge retrieval and semantic ranker are offered only in some regions, and
some of those currently refuse new services. Use the region you chose at the
top of [SETUP.md](../standalone/SETUP.md), which lists the ones that work. The
search service doesn't have to be in the same region as your Foundry project.

**Choose two names and set your region.** Edit these three lines, then run them. Everything below
uses them, so keep the same terminal window open.

```
RG=my-sparkles-rg          # resource group: any name you like
SEARCH=my-sparkles-search  # search service: globally unique, lowercase letters, digits, dashes
REGION=southcentralus      # the region you chose in SETUP.md
```

Then paste the rest unchanged:

```
az group create -n $RG -l $REGION
az search service create -n $SEARCH -g $RG -l $REGION --sku free \
  --auth-options aadOrApiKey --aad-auth-failure-mode http401WithBearerChallenge
```

If your subscription requires an `owner` tag on resource groups, add
`--tags owner=$USER` to the first command. If the second fails with
`InsufficientResourcesAvailable`, the region is out of capacity. Set
`REGION` to the next one on your row of the list in SETUP.md and run the second
command again.

Then turn API keys off, so the service accepts only Entra ID sign-in. The same
call clears `authOptions`, which the service refuses to keep once keys are off:

```
az resource update --ids $(az search service show -n $SEARCH -g $RG --query id -o tsv) \
  --api-version 2025-05-01 \
  --set properties.disableLocalAuth=true properties.authOptions=null
```

Give yourself the two roles that step 2 needs. Skip this if you created the
service as an Owner, since you already hold them:

```
ME=$(az ad signed-in-user show --query id -o tsv)
SEARCH_ID=$(az search service show -n $SEARCH -g $RG --query id -o tsv)
for ROLE in "Search Service Contributor" "Search Index Data Contributor"; do
  az role assignment create --assignee-object-id $ME --assignee-principal-type User \
    --role "$ROLE" --scope $SEARCH_ID
done
```

Role assignments can take a few minutes to take effect.

## 2. Build the knowledge base

```
pip install -r foundry-iq/requirements.txt
AZURE_SEARCH_ENDPOINT="https://$SEARCH.search.windows.net" \
  python foundry-iq/ingest_foundry_iq.py
```

The script signs in with `az login`. No key is involved.

It prints the MCP endpoint URL at the end. The knowledge base also appears in
the Foundry portal under Build, then Knowledge. The MCP URL's `api-version`
must be `2026-08-01-preview`, the same version the script creates the
knowledge base with; the agent code uses that version.

`docs/cupcake-store-info.md` is the source document. Modules 1.5 and 1.6
depend on three facts in it: the facility processes tree nuts, bulk orders of
25 or more need 72 hours notice, and bulk orders carry a 50 percent deposit.
Keep those if you edit it.

## 3. Let the agent read it

The agent signs in as whoever runs it and needs read access to the knowledge
base. Run this for each person, using their object ID (yours is `$ME` above):

```
az role assignment create --assignee-object-id <object-id> --assignee-principal-type User \
  --role "Search Index Data Reader" --scope $(az search service show -n $SEARCH -g $RG --query id -o tsv)
```

If you have opened a new terminal since step 1, set `RG` and `SEARCH` again
first. Put the endpoint in `.env` (in a workshop, in the Skillable image
`.env`). There is no key to add:

```
AZURE_SEARCH_ENDPOINT="https://<service>.search.windows.net"
KNOWLEDGE_BASE_NAME="cupcake-store-kb"
```

Never commit a key. This service has none.

## 4. Verify

From the repo root, after `pip install -r requirements.txt`:

```
python foundry-iq/verify_knowledge_base.py
```

It builds the Module 1.3 agent with only the knowledge base (no Cupcake
Store server), asks the four policy questions from Module 1.3, and checks
that each answer used the knowledge base and contains the required facts:
$6.99 delivery and free over $50; a 48-hour window with a photo for damaged
orders; 72 hours notice and a 50 percent deposit for 25 or more. Expect
`Result: 4/4 questions passed`. Add `--answers` to read the replies.
