Perfect—here’s a tightened **README.md** with your updates baked in:

---

# Bulletin by Delegate

A lightweight, Salesforce-native bulletin board that unifies two workflows:

* **Suggestion Box** – collect & browse product ideas.
* **Help Desk** – triage & resolve internal support tickets.

Bulletin ships as a set of **LWCs** backed by a single **Apex service**. It uses standard Salesforce features (Queues, Permission Sets) and a small set of custom objects for requests, categories, tags, and comments.

---

## 1) High-Level Architecture

```
LWC: bulletinBoard (container)
  ├─ suggestionBox (table)
  ├─ supportConsole (table)
  ├─ bulletinDetailModal (view/edit + comments)
  └─ bulletinSubmitRequest (modal composer)

Apex: BulletinService (single facade for all reads/writes)
Objects: Bulletin_Request__c, Bulletin_Category__c, Bulletin_Tag__c, Bulletin_Comment__c
Std: User, Group(Queue), QueueSobject, PermissionSetAssignment
```

Core flow:

* `bulletinBoard` loads context (who’s admin/user, category list), owns filters, calls **BulletinService**, and feeds records to children.
* Mutations (status, owner, description, comments, create request) all go through **BulletinService**.

---

## 2) Data Model

**Bulletin\_Request\_\_c**

* `Type__c` = *Suggestion* or *Support Request*
* `Status__c` (unified picklist; UI shows the relevant subset per type)
* `Priority__c` (support)
* `Title__c` (auto-derived from body if blank)
* `Description__c` *(Rich Text)* — includes a header (“Suggested By / Date”)
* `OwnerId` — used for support (user or **Bulletin Support** queue)
* Standard audit fields (CreatedBy, CreatedDate, LastModifiedDate)

**Bulletin\_Category\_\_c**

* `Name`, `Active__c` (drives filters and submit form tag selector)

**Bulletin\_Tag\_\_c** (junction)

* `Request__c` ↔ `Bulletin_Request__c`
* `Category__c` ↔ `Bulletin_Category__c`
* `Name` (denormalized label)

**Bulletin\_Comment\_\_c**

* `Request__c`, `Body__c`
* CreatedBy / CreatedDate (shown in thread)

---

## 3) Permissions & Visibility

**Permission Sets Included**

* **Bulletin Admin**

  * Full access to Bulletin objects.
  * UI: sees **Owner** filter (Any/Me/Unassigned/Admin user), can **reassign owners**, **change status**, and **edit any description**.

* **Bulletin User**

  * Create requests, comment, and view all requests.
  * UI: Suggestion Box defaults to **My (CreatedBy)** scope.
  * Can edit **description only** on their own requests.
  * Cannot change status or owner.

**Queue Included**

* **Bulletin Support** (`Bulletin_Support`) linked to `Bulletin_Request__c` object.

  * *Optional:* set a **Queue Email** if you want inbound or notification routing.

---

## 4) Apex Service (API Surface)

`BulletinService.cls` (single facade)

**Reads**

* `listSuggestions(filtersJson)` → `List<RequestDto>`
* `listSupportTickets(filtersJson)` → `List<RequestDto>`
* `getRequest(id)` → `RequestDto`
* `listComments(requestId)` → `List<CommentDto>`
* `listActiveCategoryNames()` → `List<String>`
* `getSupportOwnerOptions()` → `List<UserOption>` (queue + admins)
* `getBulletinContext()` → `BulletinContext` (isAdmin, adminUsers, bulletinUsers)

**Writes**

* `updateStatus(id, status)` → `RequestDto`
* `updateOwner(id, ownerId)` → `RequestDto`
* `updateDescription(id, bodyHtml)` → `RequestDto`
* `createComment(requestId, body)` → `CommentDto`
* `createRequest(type, title, bodyHtml, categoryIds)` → `RequestDto`

**Key fields surfaced**

* `RequestDto`: `id, recordNumber, title, type, status, priority, categories, ownerId, ownerName, createdById, createdByName, createdByTitle, createdDate, updatedDate, commentCount, descriptionHtml`

---

## 5) LWC Components

* **`bulletinBoard`** (container)

  * Brand header (“**Bulletin** by Delegate”).
  * Tabs: **Suggestion Box** / **Help Desk**.
  * Hosts two modals:

    * **`bulletinDetailModal`** (record view/edit + comments).
    * **`bulletinSubmitRequest`** (single-RTA composer).
  * Manages filters and calls Apex; passes data into children.

* **`suggestionBox`** (table only)

  * Filters: search, decision (status subset), category, **owner scope**.
  * Owner scope: **Users → Me** (default). **Admins → Any** (default) or a specific Bulletin User.

* **`supportConsole`** (table + admin owner filter)

  * Filters: search, status, category, **owner scope** (Any/Me/Unassigned/Admin user).

* **`bulletinDetailModal`**

  * Left: **Description** (rich HTML, inline edit when allowed) + **Comments**.
  * Right: **Meta/Actions** (Status, Owner for support, categories, facts).
  * Save banners for instant visual confirmation.
  * Shows **Submitted By** and **Submitter Title**.

* **`bulletinSubmitRequest`**

  * Modal composer with **Type**, optional **Title**, **single Rich Text Area** (pre-seeded with headings), and **Categories**.
  * Creates the record and tags in one pass.

---

## 6) Filtering & Scoping Rules

Filters payload (`filtersJson`):

```json
{
  "search": "string",
  "status": "string",
  "categoryName": "string",
  "pageSize": 50,
  "ownerScope": "ANY | ME | UNASSIGNED | USER:<Id>"
}
```

* **Suggestion Box**: `ownerScope` applies to **CreatedBy**

  * Users default to **ME**, Admins default to **ANY**.
* **Help Desk**: `ownerScope` applies to **Owner**

  * Admins choose: **Any**, **Me**, **Unassigned** (queue), or **User**.

**Sorting**: Both tables default to **CreatedDate DESC** (no “Created” column shown in the table to reduce clutter).

---

## 7) Install & Setup (Package Flow)

1. **Install the package.**
2. **Assign Permission Sets** to users:

   * **Bulletin Admin** (admins/triagers)
   * **Bulletin User** (submitters/viewers)
3. *(Optional)* Open **Bulletin Support** queue and set a **Queue Email** if desired.
4. **Create Categories** (make sure **Active\_\_c = true**).
5. **You’re done.** The app’s **home page already includes `bulletinBoard`**—it’s plug-and-play.

---

## 8) Configuration Checklist

* [ ] Package installed
* [ ] Permission sets assigned
* [ ] (Optional) Queue Email set on **Bulletin Support**
* [ ] Categories created & **Active**

---

## 9) Gotchas & FAQs (Troubleshooting by Design)

* **“Why can’t I change the status?”**
  Only **Bulletin Admins** can change status (and owner). Standard users can comment and edit the **description** of **their own** requests.

* **“Why do I only see my suggestions by default?”**
  Suggestion Box defaults to **My** (CreatedBy) for regular users—so you can focus on your items. Admins default to **Any** and can switch to specific users.

* **“Why is ‘Unassigned’ empty?”**
  It lists support tickets **owned by the queue**. If nothing’s shown, there may simply be **no tickets currently owned** by the **Bulletin Support** queue.

* **“Why can’t I upload files in comments?”**
  File attachments are on the **roadmap** (see below). For now, add files to the record via standard Salesforce file related lists as needed.

* **“Why can’t I @mention someone?”**
  Mentions are part of upcoming **richer comments**.

* **“Categories aren’t showing in the filter/form.”**
  Ensure you have **active** `Bulletin_Category__c` records and your profile/perm set grants access.

---

## 10) Extensibility & Customization

* **Status/Decision sets:** Add picklist values to `Status__c` and tailor which subsets the UI exposes per type.
* **HTML template:** Adjust the header and default body in the submit LWC to match your brand/tone.

---

## 11) Roadmap

* **Richer comments**: @mentions and **file uploads**.
* **Admin Setup Console**: manage categories, permission set assignments, integration settings, and optionally customize **stages** and **labels**.
* **Slack integration**: submit & discuss requests directly from Slack with the same UX.
* **Jira integration**: deeper cross-system linkage for downstream delivery tracking.

---

**Questions or ideas?** Open an issue in the repo.
