
---

# Bulletin by Delegate

A lightweight, Salesforce-native bulletin board that unifies two workflows:

* **Suggestion Box** – collect & browse product ideas
* **Help Desk** – triage & resolve internal support tickets

Bulletin ships as a set of **LWCs** backed by a single **Apex service**. It uses standard Salesforce features (Queues, Permission Sets) and a small set of custom objects for requests, categories, tags, comments, and statuses. 

---

## 1) High-Level Architecture

```
LWC (ui)
  ├─ bulletinBoard              ← container & header
  ├─ suggestionBox              ← list (suggestions)
  ├─ supportConsole             ← list (support; table/kanban)
  ├─ bulletinDetailModal        ← record view/edit + comments
  └─ bulletinSubmitRequest      ← “new request” form (RTA + tags)

Aura (global action wrapper)
  ├─ BulletinSubmitQuickAction  ← opens modal overlay
  └─ bulletinSubmitModalBody    ← modal body hosting the LWC

Apex
  └─ BulletinService            ← single facade for all reads/writes

Custom Objects
  Bulletin_Request__c, Bulletin_Category__c, Bulletin_Tag__c, Bulletin_Comment__c,
  Bulletin_Status__c

Standard
  User, Group(Queue), QueueSobject, PermissionSetAssignment
```

(Architecture matches current code & components.) 

---

## 2) Data Model

### `Bulletin_Request__c`

* `Type__c` — **Suggestion** or **Support Request**
* `Bulletin_Status__c` — **Lookup** to `Bulletin_Status__c` (current status label comes from the related record’s `Name`)
* `Priority__c` — used for support
* `Title__c` — auto-derived from body if blank (in Apex)
* `Description__c` — Rich Text; includes a small header for “Suggested By / Date”
* `OwnerId` — for support, can be a user or the **Bulletin Support** queue
* Standard audit fields (CreatedBy, CreatedDate, LastModifiedDate)
  (Fields align with service DTO and UI needs.) 

### `Bulletin_Category__c`

* `Name`, `Active__c` (active categories drive filters & submit form options). 

### `Bulletin_Tag__c`

* Junction between Request and Category; stores `Name` for quick, orderable display. 

### `Bulletin_Comment__c`

* `Request__c`, `Body__c`; CreatedBy/CreatedDate are used for author & timestamp. 

### `Bulletin_Status__c`  (**new**)

* `Active__c` — only active statuses appear in pickers
* `Suggestion_Status__c` (checkbox) — indicates usable for **Suggestion** type
* `Support_Status__c` (checkbox) — indicates usable for **Support Request** type
* `Status_Order_Suggestion__c` (Number) — controls display order for Suggestion statuses
* `Status_Order_Support__c` (Number) — controls display order for Support statuses
  (Fields as defined in metadata.)   

---

## 3) Permissions & Visibility

### Permission Sets (included)

* **Bulletin Admin**

  * Full access to Bulletin objects.
  * UI: sees **Owner** filter (Any/Me/Unassigned/Admin user), can reassign owners, change status, and edit any description. 
* **Bulletin User**

  * Create requests, comment, and view requests.
  * UI: Suggestion Box defaults to **My (CreatedBy)**; can edit description on own requests; cannot change status or owner. 

### Queue (included)

* **Bulletin Support** (`Bulletin_Support`) is linked to `Bulletin_Request__c`. Optionally set a Queue Email. 

---

## 4) Apex Service (API Surface)

**Class:** `BulletinService.cls` (single facade)

### Reads

* `listSuggestions(filtersJson)` → `List<RequestDto)`
* `listSupportTickets(filtersJson)` → `List<RequestDto>`
* `getRequest(id)` → `RequestDto`
* `listComments(requestId)` → `List<CommentDto>`
* `listActiveCategoryNames()` → `List<String>`
* `getSupportOwnerOptions()` → `List<UserOption>` (queue + admins)
* `getBulletinContext()` → `BulletinContext` (isAdmin, adminUsers, bulletinUsers)
* `listActiveStatusOptions(type)` → `List<StatusOption>` — **dynamically** returns active statuses valid for the given type, ordered by the type-specific order field.

### Writes

* `updateStatus(id, status)` → `RequestDto` — accepts **Status Id or Name**; resolves to a valid, active status for the record’s type
* `updateOwner(id, ownerId)` → `RequestDto`
* `updateDescription(id, bodyHtml)` → `RequestDto`
* `createComment(requestId, body)` → `CommentDto`
* `createRequest(type, title, bodyHtml, categoryIds)` → `RequestDto` — sets default status dynamically for the given type (first active by order) and assigns the Support queue owner for Support tickets when available

### DTO Highlights

`RequestDto` includes: `id, recordNumber, title, type, status, priority, categories, ownerId, ownerName, createdById, createdByName, createdByTitle, createdDate, updatedDate, commentCount, descriptionHtml`. 

---

## 5) LWC & Aura Components

### LWCs

* **`bulletinBoard`** — App header + tab switcher; owns filters and calls Apex. Hosts the modal and submit form, and routes events. (See app CSS for layout.) 
* **`suggestionBox`** — Table with filters: search, decision (status), category, **owner scope** (Users default **Me**, Admins default **Any**). Emits `querychange` to parent. (Status options are dynamic when using service method.)  
* **`supportConsole`** — Table/kanban with filters: search, status, category, **owner scope** (Any/Me/Unassigned/Admin user). Status options are populated via the service for Support type. Emits `querychange`.  
* **`bulletinDetailModal`** — Record view/edit: description editor, status selector, owner selector (admins on Support), and comments. Emits `savestatus`, `recordupdated`, and `postcomment`. (UI arrangement & styles in component files.)  
* **`bulletinSubmitRequest`** — Single RTA composer; auto-derives a title if blank; lets the user select categories and type (Suggestion/Support). On submit, calls `createRequest(...)` and raises a success event.  

### Aura (Global Action)

* **`BulletinSubmitQuickAction`** — Opens overlay containing
* **`bulletinSubmitModalBody`** — Hosts the `bulletinSubmitRequest` LWC; closes on submit/cancel. 

---

## 6) Filtering & Search

**Filters payload** passed from the list components to Apex:

```json
{
  "search": "string",
  "status": "string",            // Status Id or Name
  "categoryName": "string",
  "pageSize": 50,
  "ownerScope": "ANY | ME | UNASSIGNED | USER:<Id>"
}
```

(Owner scope semantics: CreatedBy for Suggestion, Owner for Support.) 

* **Search**: Title-only “contains” match (no description search).
* **Status**: Accepts **Id or Name**; resolved to active statuses valid for the requested type.
* **Owner Scope**:

  * Suggestion Box: filters by **CreatedBy** (Users default **ME**, Admins default **ANY**)
  * Help Desk: filters by **Owner** (Admin options: Any, Me, Unassigned (queue), or a specific admin)
* **Sort**: CreatedDate DESC. 

---

## 7) Install & Setup

1. **Install the package** and assign Permission Sets:

* **Bulletin Admin**
* **Bulletin User** 

2. *(Optional)* Open **Bulletin Support** queue and set a **Queue Email**. 

3. **Create Categories** and set **Active**. 

4. **Create Statuses** (`Bulletin_Status__c`):

* Set **Active** on each record to expose it in pickers.
* Check **Suggestion Status** and/or **Support Status** to scope per request type.
* Set display order using **Status Order (Suggestion)** and/or **Status Order (Support)**.
  (Fields from object metadata.)  

5. **Global Action**
   The **New Bulletin Request** action is included. Add it to your **Global Publisher Layout**. 

---

## 8) Configuration Checklist

* [ ] Package installed
* [ ] Permission sets assigned
* [ ] (Optional) Queue Email set on **Bulletin Support**
* [ ] Categories created & **Active**
* [ ] Statuses created, **Active**, scoped per type, and ordered
* [ ] “New Bulletin Request” action added to **Global Publisher Layout** 

---

## 9) Gotchas & FAQs

* **“Why can’t I change the status or owner?”**
  Only **Bulletin Admins** can. Standard users can comment and edit the **description** of **their own** requests. 

* **“Why do I only see my suggestions by default?”**
  Suggestion Box defaults to **My (CreatedBy)** for standard users; Admins default to **Any**. 

* **“Unassigned shows nothing.”**
  It lists items owned by the **Bulletin Support** queue; there may be none currently. 

* **“Status picklists differ between pages.”**
  Status options are **type-scoped** and ordered dynamically from `Bulletin_Status__c` using active flags and order fields; lists show the relevant subset for each surface (suggestions/support). (See service + list components.)  

---

## 10) Roadmap

* Richer comments: @mentions and file uploads
* Admin Setup Console: manage categories, permission sets, and status labels in one place
* Slack integration
* Jira integration 

---

**Questions or ideas?** Open an issue in the repo.
