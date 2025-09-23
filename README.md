
---

# Bulletin by Delegate

A lightweight, Salesforce-native “bulletin board” that centralizes two common workflows in one polished UI:

* **Suggestion Box** – collect, browse, and discuss product/feature ideas.
* **Help Desk** – triage and resolve internal support tickets.

Bulletin ships as a set of **LWCs** backed by a single **Apex service**. It runs on standard Salesforce objects/features (Queues, Permission Sets) and a small set of custom objects for requests, categories, and comments.

> **Audience:** Functional business analysts, admins, and Salesforce developers.
> **Goal:** Understand the purpose, data flow, permissions, and how the pieces fit together—plus how to deploy and extend safely.

---

## Table of Contents

1. [High-Level Architecture](#high-level-architecture)
2. [Data Model](#data-model)
3. [Permissions & Visibility](#permissions--visibility)
4. [Apex Service (API Surface)](#apex-service-api-surface)
5. [LWC Components](#lwc-components)
6. [Filtering & Scoping Rules](#filtering--scoping-rules)
7. [UI Behavior & UX Notes](#ui-behavior--ux-notes)
8. [Install & Setup](#install--setup)
9. [Configuration Checklist](#configuration-checklist)
10. [Troubleshooting](#troubleshooting)
11. [Extensibility & Customization](#extensibility--customization)
12. [Roadmap Ideas](#roadmap-ideas)

---

## High-Level Architecture

```
+-------------------+         +------------------------+
|  LWC: Bulletin    | <-----> |  Apex: BulletinService |
|  (container)      |         |  (@AuraEnabled methods)|
+---------+---------+         +-----------+------------+
          |                                 |
          | contains                       queries/mutates
          v                                 v
+---------+-----------+        +------------+------------------+
| Suggestion Box LWC  |        |  Custom Objects                |
| (table view)        |        |  - Bulletin_Request__c         |
+---------------------+        |  - Bulletin_Category__c        |
                               |  - Bulletin_Tag__c             |
+---------------------+        |  - Bulletin_Comment__c         |
| Support Console LWC |        +------------+-------------------+
| (table view, admin  |                     |
|  owner filter)      |                     | references
+---------------------+                     v
                                     Salesforce Standard:
+---------------------+            - User, Group (Queue),
| Detail Modal LWC    |              QueueSobject, PermissionSetAssignment
| (view/edit, comments|
|  & status/owner)    |
+---------------------+

+---------------------+
| Submit Request LWC  |
| (modal composer)    |
+---------------------+
```

**Key ideas**

* **Container → Children data flow.** `bulletinBoard` loads context (who’s admin/user, category list), owns filters, and feeds records into child components.
* **Single Apex facade.** All server reads/writes go through `BulletinService` for consistency and easy evolution.
* **Minimal security assumptions.** UI enforces who can edit what; Apex can be tightened later if needed.

---

## Data Model

### Custom Objects

* **Bulletin\_Request\_\_c**

  * **Type\_\_c**: `"Suggestion"` or `"Support Request"`
  * **Status\_\_c**: workflow/status values (unified list; UI renders the relevant subset)
  * **Priority\_\_c**: (support use)
  * **Title\_\_c**: short title (auto-derived if not provided)
  * **Description\_\_c** *(Rich Text)*: full HTML body (formatted, includes “Suggested By/Date” header)
  * **OwnerId**: for support; can be a user or the **Bulletin Support** queue
  * Standard audit fields: CreatedBy, CreatedDate, LastModifiedDate

* **Bulletin\_Category\_\_c**

  * **Name**
  * **Active\_\_c** (Boolean): included in filter picklists and submit form

* **Bulletin\_Tag\_\_c** (junction)

  * **Request\_\_c** → Bulletin\_Request\_\_c
  * **Category\_\_c** → Bulletin\_Category\_\_c
  * **Name** (denormalized label for simpler reporting)

* **Bulletin\_Comment\_\_c**

  * **Request\_\_c**
  * **Body\_\_c** (Long Text)
  * CreatedBy / CreatedDate (for display)

> The rich description uses semantic HTML (headings, lists). It’s stored in `Description__c` and displayed as formatted content in the modal.

---

## Permissions & Visibility

### Permission Sets

* **Bulletin Admin**

  * Full access to Bulletin objects.
  * UI: sees **owner filter** (Any/Me/Unassigned/other admins), can **reassign owners**, **change status**, and **edit description** for any request.

* **Bulletin User**

  * Create requests, comment, and view all requests.
  * UI: **Suggestion Box** defaults to “My (CreatedBy)” scope.
  * Can edit the **description only on their own requests** (in modal).
  * Cannot change status/owner.

> **Important:** Grant **Apex Class Access** for `BulletinService` to both permission sets. Missing class access causes tables to appear empty for non-admins.

### Queues

* **Bulletin Support** (DeveloperName: `Bulletin_Support`)

  * Used as the “Unassigned” owner for support tickets.
  * If the exact name isn’t found, the service falls back to any queue tied to `Bulletin_Request__c` via `QueueSobject`.

---

## Apex Service (API Surface)

`BulletinService.cls` (central facade)

**Listing & retrieval**

* `listSuggestions(String filtersJson)` → `List<RequestDto>`
* `listSupportTickets(String filtersJson)` → `List<RequestDto>`
* `getRequest(Id id)` → `RequestDto`
* `listComments(Id requestId)` → `List<CommentDto>`
* `listActiveCategoryNames()` → `List<String>`
* `getSupportOwnerOptions()` → `List<UserOption>` (queue + admins)
* `getBulletinContext()` → `BulletinContext` (isAdmin, adminUsers, bulletinUsers)

**Mutations**

* `updateStatus(Id id, String status)` → `RequestDto`
* `updateOwner(Id id, Id ownerId)` → `RequestDto`
* `updateDescription(Id id, String bodyHtml)` → `RequestDto`
* `createComment(Id requestId, String body)` → `CommentDto`
* `createRequest(String type, String title, String bodyHtml, List<Id> categoryIds)` → `RequestDto`

**DTOs (selected fields)**

* `RequestDto`: `id, recordNumber, title, type, status, priority, categories, ownerId, ownerName, createdById, createdByName, createdByTitle, createdDate, updatedDate, commentCount, descriptionHtml`
* `CommentDto`: `id, authorName, createdOn, body`
* `UserOption`: `id, name`
* `BulletinContext`: `isAdmin, adminUsers, bulletinUsers, adminQueueName`

---

## LWC Components

* **`bulletinBoard` (container)**

  * Hosts the **app header** and **tabs** (Suggestion Box / Help Desk).
  * Owns filters and loads data from Apex, passes to children.
  * Launches two modals:

    * **`bulletinDetailModal`** (view/edit + comments)
    * **`bulletinSubmitRequest`** (new request composer; 1 rich-text field + categories + type)

* **`suggestionBox`**

  * Table view of suggestions (created date desc).
  * Filters: search, decision/status, category, **owner scope** (for admins: Any/Me/User; for users: Me by default).
  * Emits `querychange` with filters; requests data from parent.

* **`supportConsole`**

  * Table view of support tickets (created date desc).
  * Filters: search, status, category, **owner scope** (Any/Me/Unassigned/User).
  * Emits `querychange`; parent refreshes records.

* **`bulletinDetailModal`**

  * Two-column layout: **Description** (rich display + inline edit when allowed) and **Meta/Actions**.
  * **Status** editor (admins only), **Owner** editor for support (admins only).
  * **Comments** thread with reactive post/append.
  * Shows **Submitted by** and **Title** (from the User record) for context.

* **`bulletinSubmitRequest`**

  * Modal composer to create a new Suggestion/Support Request.
  * Optional **Title** and a **single Rich Text Area** body (pre-seeded with helpful section headings).
  * Category multiselect from active categories.
  * On success, parent refreshes current view.

---

## Filtering & Scoping Rules

**Filters payload (`filtersJson`)**

```json
{
  "search": "string",
  "status": "string",
  "categoryName": "string",
  "pageSize": 50,
  "ownerScope": "ANY | ME | UNASSIGNED | USER:<Id>"
}
```

* **Suggestion Box:** `ownerScope` is evaluated against **CreatedBy**

  * Users default to `ME`; Admins default to `ANY`.
* **Help Desk:** `ownerScope` is evaluated against **Owner**

  * Admins can select `ANY`, `ME`, `UNASSIGNED` (queue), or `USER:<Id>`.

**Sorting:** Both tables default to **CreatedDate DESC**.

---

## UI Behavior & UX Notes

* **Unified header:** “Bulletin by Delegate” with tabs; brand-forward styling.
* **Tables:** Created and Updated columns; comment counts centered; “Open” buttons styled for affordance.
* **Detail modal:**

  * Shows `Description__c` HTML (bullets, headings, italics).
  * **Admins** can edit status/owner/description. **Users** can edit description only on their own records.
  * Inline “Saved successfully” feedback appears after changes.
  * Comments post instantly (thread updates without reopening).
* **Submit modal:** Opens as an overlay; prefilled rich body with suggested sections.

---

## Install & Setup

### 1) Deploy metadata

Using SFDX:

```bash
sfdx force:source:deploy -p force-app/main/default
```

### 2) Create permission sets (if not included)

* **Bulletin Admin** and **Bulletin User**

  * Add **Object/Field** access for the Bulletin objects.
  * Add **Apex Class Access** for `BulletinService`.

Assign to users:

```bash
# Example (update usernames / permset names)
sfdx force:user:permset:assign -n "Bulletin_Admin"
sfdx force:user:permset:assign -n "Bulletin_User"
```

### 3) Create the Support Queue

* **DeveloperName:** `Bulletin_Support` (preferred)
* Add `Bulletin_Request__c` to the queue’s **Queue Members / Supported Objects**.

> The service falls back to any queue tied to `Bulletin_Request__c` if the preferred name isn’t found.

### 4) Seed Categories

Create **Bulletin\_Category\_\_c** records with **Active\_\_c = true**. These drive the filter picklist and submit form tags.

### 5) Add the App Page

* Create a **Lightning App Page** (flexipage) and drop the **`bulletinBoard`** LWC onto it.
* Make the page available to intended profiles.

---

## Configuration Checklist

* [ ] Permission sets exist and are assigned (incl. **Apex class access**).
* [ ] Queue **Bulletin Support** exists and owns new Support Requests by default.
* [ ] Categories created and marked **Active**.
* [ ] App Page published with **`bulletinBoard`**.
* [ ] (Optional) Record Page overrides removed—intended UX is within the modal.

---

## Troubleshooting

* **Tables show no data for non-admins** → Most often **Apex class access** is missing for `BulletinService`. Add to `Bulletin User` perm set.
* **Unassigned filter returns nothing** → Ensure a Queue exists for `Bulletin_Request__c` (prefer `Bulletin_Support`).
* **Categories missing from filters** → Confirm **Active\_\_c = true** and user has read access.
* **Users can’t edit description** → They can only edit **their own** records; admins can edit all.

---

## Extensibility & Customization

* **Status/Decision dictionaries:** Add picklist values to `Status__c`. The UI already conditionally shows the correct subset per type.
* **HTML body template:** The submit LWC pre-seeds a clean layout. You can adjust the default HTML to match brand/tone.
* **Security hardening:**

  * Move from “without sharing” to “with sharing” (+ FLS checks) if you need stricter server-side enforcement.
  * Add HTML sanitization if you plan to allow external input channels.
* **File uploads:** Add a related files composer to the modal (ContentVersion create + linking).
* **Notifications:** Fire Platform Events or send emails on status changes.

---

## Roadmap Ideas

* Voting for suggestions; surfacing “Top this month”.
* Duplicate detection when creating new requests.
* Admin triage tools (bulk actions, quick replies).
* SLA indicators for support requests.
* Analytics dashboards (cycle time, acceptance rate, category heatmaps).

---