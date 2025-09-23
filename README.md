
---

# Bulletin by Delegate

A lightweight, Salesforce-native bulletin board that unifies two workflows:

* **Suggestion Box** – collect & browse product ideas
* **Help Desk** – triage & resolve internal support tickets

Bulletin ships as a set of **LWCs** backed by a single **Apex service**. It uses standard Salesforce features (Queues, Permission Sets) and a small set of custom objects for requests, categories, tags, and comments.

---

## 1) High-Level Architecture

```
LWC (ui)
  ├─ bulletinBoard              ← container & header
  ├─ suggestionBox              ← table view (suggestions)
  ├─ supportConsole             ← table view (support)
  ├─ bulletinDetailModal        ← record view/edit + comments
  └─ bulletinSubmitRequest      ← “new request” form (RTA + tags)

Aura (global action wrapper)
  ├─ BulletinSubmitQuickAction  ← opens modal overlay
  └─ bulletinSubmitModalBody    ← modal body hosting the LWC

Apex
  └─ BulletinService            ← single facade for all reads/writes

Custom Objects
  Bulletin_Request__c, Bulletin_Category__c, Bulletin_Tag__c, Bulletin_Comment__c

Standard
  User, Group(Queue), QueueSobject, PermissionSetAssignment
```

> **Removed/legacy**: `bulletinSubmitRequestModal` and `bulletinSubmitRequestQuickAction` LWCs were deleted and are no longer used.

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

**Bulletin\_Category\_\_c** – `Name`, `Active__c` (drives filters & submit form)

**Bulletin\_Tag\_\_c** – junction: `Request__c` ↔ `Category__c` (+ `Name`)

**Bulletin\_Comment\_\_c** – `Request__c`, `Body__c` (uses CreatedBy/CreatedDate)

---

## 3) Permissions & Visibility

**Permission Sets (included in package)**

* **Bulletin Admin**

  * Full access to Bulletin objects.
  * UI: sees **Owner** filter (Any/Me/Unassigned/Admin user), can **reassign owners**, **change status**, and **edit any description**.

* **Bulletin User**

  * Create requests, comment, and view all requests.
  * UI: Suggestion Box defaults to **My (CreatedBy)**.
  * Can edit **description only** on their own requests.
  * Cannot change status or owner.

**Queue (included in package)**

* **Bulletin Support** (`Bulletin_Support`) already linked to `Bulletin_Request__c`.

  * *Optional:* set a **Queue Email** if you want notifications or inbound routing.

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

**DTO highlights**

* `RequestDto` includes: `id, recordNumber, title, type, status, priority, categories, ownerId, ownerName, createdById, createdByName, createdByTitle, createdDate, updatedDate, commentCount, descriptionHtml`

---

## 5) LWC & Aura Components

### LWCs

* **`bulletinBoard`** — App header (“**Bulletin** by Delegate”), tabs for **Suggestion Box** / **Help Desk**, owns filters and calls Apex. Hosts:

  * **`bulletinDetailModal`** — rich description (inline edit when allowed), status/owner controls (with “Saved” banners), comments thread (reactive).
  * **`bulletinSubmitRequest`** — single RTA composer (optional title) + category chooser; pre-seeded with helpful headings.

* **`suggestionBox`** — Table view with filters: search, decision, category, **owner scope** (Users default **Me**, Admins default **Any**).

* **`supportConsole`** — Table view with filters: search, status, category, **owner scope** (Any/Me/Unassigned/Admin user).

### Aura (Global Action)

* **`BulletinSubmitQuickAction`** — Global Action wrapper that opens an overlay modal.
* **`bulletinSubmitModalBody`** — The modal body; hosts the `bulletinSubmitRequest` LWC and closes the overlay/action on **submit** or **cancel**.

### Quick Action (metadata)

* **`New_Bulletin_Request.quickAction`** — Global action that launches `BulletinSubmitQuickAction`.

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

  * Users default **ME**; Admins default **ANY**
* **Help Desk**: `ownerScope` applies to **Owner**

  * Admins choose **Any**, **Me**, **Unassigned** (queue), or a specific admin

**Sorting**: Both tables default to **CreatedDate DESC** (no “Created” column in the table to keep the view clean).

---

## 7) Install & Setup (Package Flow)

1. **Install the package.**
2. **Assign Permission Sets** to users:

   * **Bulletin Admin**
   * **Bulletin User**
3. *(Optional)* Open the packaged **Bulletin Support** queue and set a **Queue Email**.
4. **Create Categories** (ensure **Active\_\_c = true**).
5. **Global Action (manual layout step):**

   * The **New Bulletin Request** global action is included.
   * Add it to your **Global Publisher Layout**:
     *Setup → Global Actions → Publisher Layouts → Edit → add “New Bulletin Request” → Save.*
6. **You’re done.** The Bulletin app’s home page already contains `bulletinBoard`—it’s plug-and-play.

---

## 8) Configuration Checklist

* [ ] Package installed
* [ ] Permission sets assigned
* [ ] (Optional) Queue Email set on **Bulletin Support**
* [ ] Categories created & **Active**
* [ ] “New Bulletin Request” action added to **Global Publisher Layout**

---

## 9) Gotchas & FAQs

* **“Why can’t I change the status or owner?”**
  Only **Bulletin Admins** can. Standard users can comment and edit the **description** of **their own** requests.

* **“Why do I only see my suggestions by default?”**
  That’s by design—Suggestion Box defaults to **My (CreatedBy)** for standard users. Admins default to **Any**.

* **“Why is ‘Unassigned’ empty?”**
  It shows support tickets owned by the **Bulletin Support** queue. If none appear, there may be no queue-owned items right now.

* **“Why can’t I upload files or @mention?”**
  Coming soon—see **Roadmap** below.

* **“Filters don’t show categories.”**
  Make sure you’ve created **active** `Bulletin_Category__c` records and have access via your profile/perm set.

---

## 10) Roadmap

* **Richer comments**: @mentions and **file uploads**.
* **Admin Setup Console**: manage categories, permission set assignments, integration settings, and optionally customize **stages** and **labels**.
* **Slack integration**: submit & discuss requests directly from Slack with the same UX.
* **Jira integration**: deeper cross-system linkage for downstream delivery tracking.

---

**Questions or ideas?** Open an issue in the repo.
