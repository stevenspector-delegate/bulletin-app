
---

# Bulletin by Delegate

A lightweight, Salesforce-native “bulletin board” that centralizes two common workflows in one polished UI:

* **Suggestion Box** – collect, browse, and discuss product/feature ideas.
* **Help Desk** – triage and resolve internal support tickets.

Bulletin ships as a set of **LWCs** backed by a single **Apex service**. It runs on standard Salesforce features (Queues, Permission Sets) and a small set of custom objects for requests, categories, tags, and comments.

> **Audience:** Functional business analysts, admins, and Salesforce developers.
> **Goal:** Understand the purpose, data flow, permissions, and how the parts fit together—plus how to deploy and extend safely.

---

## Table of Contents

1. [High-Level Architecture](#high-level-architecture)
2. [Data Model](#data-model)
3. [Permissions & Visibility](#permissions--visibility)
4. [Apex Service (API Surface)](#apex-service-api-surface)
5. [LWC Components](#lwc-components)
6. [Filtering & Scoping Rules](#filtering--scoping-rules)
7. [UI Behavior & UX Notes](#ui-behavior--ux-notes)
8. [Install & Setup (Package Flow)](#install--setup-package-flow)
9. [Configuration Checklist](#configuration-checklist)
10. [Troubleshooting](#troubleshooting)
11. [Extensibility & Customization](#extensibility--customization)
12. [Upcoming Features / Roadmap](#upcoming-features--roadmap)

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

* **Container → children data flow.** `bulletinBoard` loads context (who’s admin/user, category list), owns filters, and feeds records into child components.
* **Single Apex facade.** All server reads/writes go through `BulletinService` for consistency and easy evolution.
* **Minimal assumptions.** UI enforces who can edit what; server can be tightened later if needed.

---

## Data Model

### Custom Objects

* **Bulletin\_Request\_\_c**

  * **Type\_\_c**: `"Suggestion"` or `"Support Request"`
  * **Status\_\_c**: unified picklist; UI shows the relevant subset per type
  * **Priority\_\_c** (support use)
  * **Title\_\_c** (auto-derived from body if blank)
  * **Description\_\_c** *(Rich Text)* – formatted HTML (includes “Suggested By / Date” header)
  * **OwnerId**: used for support (user or **Bulletin Support** queue)
  * Standard audit fields: CreatedBy, CreatedDate, LastModifiedDate

* **Bulletin\_Category\_\_c**

  * **Name**, **Active\_\_c** (drives filter & submit picklists)

* **Bulletin\_Tag\_\_c** (junction)

  * **Request\_\_c** → Bulletin\_Request\_\_c
  * **Category\_\_c** → Bulletin\_Category\_\_c
  * **Name** (denormalized label)

* **Bulletin\_Comment\_\_c**

  * **Request\_\_c**, **Body\_\_c**
  * CreatedBy / CreatedDate (shown in thread)

---

## Permissions & Visibility

### Permission Sets (included in the package)

* **Bulletin Admin**

  * Full access to Bulletin objects.
  * UI: sees **owner filter** (Any/Me/Unassigned/other admins), can **reassign owners**, **change status**, and **edit any description**.

* **Bulletin User**

  * Create requests, comment, and view all requests.
  * UI: **Suggestion Box** defaults to “My (CreatedBy)” scope.
  * Can edit the **description only on their own requests** (in the modal).
  * Cannot change status/owner.

### Queues

* **Bulletin Support** (DeveloperName: `Bulletin_Support`)

  * Used as the “Unassigned” owner for support tickets.
  * If not found, the app falls back to any queue tied to `Bulletin_Request__c`.

---

## Apex Service (API Surface)

`BulletinService.cls` (single facade)

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

  * Hosts the **brand header** and **tabs** (Suggestion Box / Help Desk).
  * Owns filters; loads data via Apex; passes to children.
  * Launches two modals:

    * **`bulletinDetailModal`** (view/edit + comments)
    * **`bulletinSubmitRequest`** (new request composer; single RTA + categories + type)

* **`suggestionBox`**

  * Table view of suggestions (CreatedDate DESC).
  * Filters: search, decision/status, category, **owner scope** (Admins: Any/Me/User; Users: Me).
  * Emits `querychange`; parent refreshes.

* **`supportConsole`**

  * Table view of support tickets (CreatedDate DESC).
  * Filters: search, status, category, **owner scope** (Any/Me/Unassigned/User).
  * Emits `querychange`; parent refreshes.

* **`bulletinDetailModal`**

  * Two-column layout: **Description** (rich display + inline edit when allowed) and **Meta/Actions**.
  * **Status** editor (admins only), **Owner** editor for support (admins only).
  * **Comments** thread with instant append on post.
  * Shows **Submitted by** and **Submitter Title** for extra context.

* **`bulletinSubmitRequest`**

  * Modal composer to create a new Suggestion/Support request.
  * Optional **Title** and a **single Rich Text Area** pre-seeded with helpful section headings.
  * Category multiselect sourced from active categories.

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

* **Suggestion Box:** `ownerScope` is applied to **CreatedBy**

  * Users default to `ME`; Admins default to `ANY`.
* **Help Desk:** `ownerScope` is applied to **Owner**

  * Admins can select `ANY`, `ME`, `UNASSIGNED` (queue), or `USER:<Id>`.

**Sorting:** Both tables default to **CreatedDate DESC**.

---

## UI Behavior & UX Notes

* **Unified header:** “Bulletin by Delegate” with strong brand styling.
* **Tables:** Created & Updated columns; centered comment counts; prominent “Open” buttons.
* **Detail modal:**

  * Renders `Description__c` HTML (bullets, headings, italics).
  * **Admins** can edit status/owner/description; **Users** can edit description on their records.
  * Inline “Saved successfully” feedback after changes.
  * Comments are reactive; newly posted comments appear immediately.
* **Submit modal:** Overlays the table; prefilled rich body with suggested sections.

---

## Install & Setup (Package Flow)

1. **Install the Managed (or Unmanaged) Package**

   * Use the provided package install link.

2. **Assign Permission Sets**

   * Grant **Bulletin Admin** to administrators/triagers.
   * Grant **Bulletin User** to end users who will submit and discuss requests.

3. **Create the Support Queue (optional but recommended)**

   * Name: **Bulletin Support** (DeveloperName: `Bulletin_Support`).
   * Add `Bulletin_Request__c` to the queue’s supported objects.
   * New support requests will default to this queue as “Unassigned”.

4. **Create Categories** (UI)

   * Add **Bulletin\_Category\_\_c** records and mark **Active\_\_c = true**.
   * These appear in filter picklists and in the submit form’s tag selector.

5. **Add the App Page**

   * Create or open a **Lightning App Page** and drop the **`bulletinBoard`** LWC onto it.
   * Make it visible to the intended profiles.

Users can now submit requests; admins can triage from the **Help Desk** tab; everyone can browse the **Suggestion Box**.

---

## Configuration Checklist

* [ ] Package installed.
* [ ] Permission sets assigned (Bulletin Admin / Bulletin User).
* [ ] (Recommended) **Bulletin Support** queue created and tied to `Bulletin_Request__c`.
* [ ] Categories created and set **Active**.
* [ ] App Page published with **`bulletinBoard`**.

---

## Troubleshooting

* **Unassigned filter returns nothing** → Ensure a Queue exists for `Bulletin_Request__c` (prefer `Bulletin_Support`).
* **Categories missing from filters** → Confirm **Active\_\_c = true** and users have read access.
* **Users can’t edit description** → They can only edit **their own** requests; admins can edit all.

---

## Extensibility & Customization

* **Status/Decision dictionaries:** Add picklist values to `Status__c`. The UI shows the relevant subset per type.
* **HTML body template:** Adjust the pre-seeded HTML in the submit LWC to match your brand/tone.
* **Security hardening:**

  * If needed, move to `with sharing` + FLS checks server-side.
  * Add HTML sanitization if exposing external intake channels.
* **Files:** Add a related-files composer (ContentVersion + linking).
* **Notifications:** Platform Events or email on status changes.
* **Analytics:** Dashboards for cycle time, acceptance rate, category heatmaps.

---

## Upcoming Features / Roadmap

* **Richer comments**: @mentions and **file uploads**.
* **Admin Setup Console**: manage categories, permission set assignments, integration settings, and optionally customize **stages** and **labels** for requests—all in one place.
* **Slack integration**: submit and discuss requests directly from Slack with the same UX.
* **Jira integration**: deeper cross-system linkage for delivery tracking downstream.

---

**Questions or ideas?** Open an issue or drop a note in the project discussions.