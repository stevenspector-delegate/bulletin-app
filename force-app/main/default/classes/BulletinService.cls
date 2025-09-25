public without sharing class BulletinService {
    /* ==================== Filters & DTOs ==================== */
    public class Filters {
        @AuraEnabled public String  search;
        @AuraEnabled public String  status;
        @AuraEnabled public String  categoryName;
        @AuraEnabled public Integer pageSize;
        // Suggestions: 'ANY' | 'ME' | 'USER:<Id>'
        // Support:     'ANY' | 'ME' | 'UNASSIGNED' | 'USER:<Id>'
        @AuraEnabled public String  ownerScope;
    }
    public class RequestDto {
        @AuraEnabled public Id           id;
        @AuraEnabled public String       recordNumber;
        @AuraEnabled public String       title;
        @AuraEnabled public String       type;
        @AuraEnabled public String       status;
        @AuraEnabled public String       priority;
        @AuraEnabled public List<String> categories;
        @AuraEnabled public Id           ownerId;
        @AuraEnabled public String       ownerName;
        @AuraEnabled public Id           createdById;
        @AuraEnabled public String       createdByName;
        @AuraEnabled public String       createdByTitle;
        @AuraEnabled public String       createdDate;
        @AuraEnabled public String       updatedDate;
        @AuraEnabled public Integer      commentCount;
        @AuraEnabled public String       descriptionHtml;
    }
    public class CommentDto {
        @AuraEnabled public Id       id;
        @AuraEnabled public String   authorName;
        @AuraEnabled public Datetime createdOn;
        @AuraEnabled public String   body;
    }
    public class UserOption {
        @AuraEnabled public Id     id;
        @AuraEnabled public String name;
        public UserOption(Id i, String n){ id=i; name=n; }
    }
    public class CategoryOption {
        @AuraEnabled public Id     id;
        @AuraEnabled public String name;
        public CategoryOption(Id i, String n){ id=i; name=n; }
    }
    public class BulletinContext {
        @AuraEnabled public Boolean           isAdmin;
        @AuraEnabled public List<UserOption>  adminUsers;
        @AuraEnabled public List<UserOption>  bulletinUsers;
        @AuraEnabled public String            adminQueueName; // informational
    }

    /* ==================== Entry Points ==================== */
    @AuraEnabled
    public static List<RequestDto> listSuggestions(String filtersJson){
        return queryRequests(new Set<String>{ 'Suggestion' }, parse(filtersJson), /*supportView*/ false);
    }
    @AuraEnabled
    public static List<RequestDto> listSupportTickets(String filtersJson){
        return queryRequests(new Set<String>{ 'Support Request' }, parse(filtersJson), /*supportView*/ true);
    }

    @AuraEnabled(cacheable=true)
    public static BulletinContext getBulletinContext(){
        BulletinContext ctx = new BulletinContext();
        ctx.isAdmin = hasBulletinAdmin();

        Set<Id> adminIds = new Set<Id>();
        for (PermissionSetAssignment psa : [
            SELECT AssigneeId
            FROM PermissionSetAssignment
            WHERE PermissionSet.Name = 'Bulletin_Admin' OR PermissionSet.Label = 'Bulletin Admin'
        ]) adminIds.add(psa.AssigneeId);

        Set<Id> userIds = new Set<Id>();
        for (PermissionSetAssignment psa : [
            SELECT AssigneeId
            FROM PermissionSetAssignment
            WHERE PermissionSet.Name = 'Bulletin_User' OR PermissionSet.Label = 'Bulletin User'
        ]) userIds.add(psa.AssigneeId);

        ctx.adminUsers = new List<UserOption>();
        if(!adminIds.isEmpty()){
            for (User u : [SELECT Id, Name FROM User WHERE Id IN :adminIds ORDER BY Name])
                ctx.adminUsers.add(new UserOption(u.Id, u.Name));
        }

        ctx.bulletinUsers = new List<UserOption>();
        if(!userIds.isEmpty()){
            for (User u : [SELECT Id, Name FROM User WHERE Id IN :userIds ORDER BY Name])
                ctx.bulletinUsers.add(new UserOption(u.Id, u.Name));
        }

        ctx.adminQueueName = 'Bulletin_Admin_Queue';
        return ctx;
    }

    /* Owner options (Support only): Queue + Admin users */
    @AuraEnabled(cacheable=true)
    public static List<UserOption> getSupportOwnerOptions(){
        List<UserOption> out = new List<UserOption>();
        Id qid = findSupportQueueId();
        if (qid != null){
            String qname = [SELECT Name FROM Group WHERE Id = :qid LIMIT 1].Name;
            out.add(new UserOption(qid, qname)); // "Unassigned" path
        }
        // Admins
        for (PermissionSetAssignment psa : [
            SELECT AssigneeId, Assignee.Name
            FROM PermissionSetAssignment
            WHERE PermissionSet.Name = 'Bulletin_Admin' OR PermissionSet.Label = 'Bulletin Admin'
        ]) out.add(new UserOption(psa.AssigneeId, psa.Assignee.Name));
        return out;
    }

    /* ======= Categories for filters & form ======= */
    @AuraEnabled(cacheable=true)
    public static List<CategoryOption> listActiveCategories(){
        List<CategoryOption> out = new List<CategoryOption>();
        for (Bulletin_Category__c c : [
            SELECT Id, Name
            FROM Bulletin_Category__c
            WHERE Active__c = true
            ORDER BY Name
        ]) out.add(new CategoryOption(c.Id, c.Name));
        return out;
    }
    @AuraEnabled(cacheable=true)
    public static List<String> listActiveCategoryNames(){
        List<String> out = new List<String>();
        for (Bulletin_Category__c c : [
            SELECT Name
            FROM Bulletin_Category__c
            WHERE Active__c = true
            ORDER BY Name
        ]) out.add(c.Name);
        return out;
    }

    /* ==================== Core Listing (SOSL + SOQL) ==================== */
    private static List<RequestDto> queryRequests(Set<String> types, Filters f, Boolean supportView){
        Integer lim = (f != null && f.pageSize != null && f.pageSize > 0) ? Math.min(f.pageSize, 200) : 50;

        String statusVal  = (f != null && String.isNotBlank(f.status)) ? f.status : null;
        String catName    = (f != null && String.isNotBlank(f.categoryName)) ? f.categoryName : null;
        String scope      = (f != null ? f.ownerScope : null);
        String rawSearch  = (f != null && String.isNotBlank(f.search)) ? f.search.trim() : null;

        Boolean isAdmin = hasBulletinAdmin();
        Id      uid     = UserInfo.getUserId();

        // If a search term exists, use SOSL to find matching request Ids (Title__c + Description__c via ALL FIELDS),
        // then apply all other filters via SOQL.
        Set<Id> searchMatchedIds = null;
        if (rawSearch != null) {
            // Basic sanitization for SOSL reserved characters; keep it simple and generous.
            String q = sanitizeSoslQuery(rawSearch) + '*';

            // Narrow by Type__c in the SOSL RETURNING filter to reduce result set early.
            List<List<SObject>> sosl = Search.query(
                'FIND :q IN ALL FIELDS RETURNING ' +
                'Bulletin_Request__c (Id WHERE Type__c IN :types)'
            );
            if (!sosl.isEmpty()) {
                searchMatchedIds = new Set<Id>();
                for (SObject sob : sosl[0]) searchMatchedIds.add((Id)sob.get('Id'));
                if (searchMatchedIds.isEmpty()) return new List<RequestDto>(); // no matches at all
            }
        }

        // Build WHERE parts with bind variables
        List<String> whereParts = new List<String>();
        if (!types.isEmpty())  whereParts.add('Type__c IN :types');
        if (searchMatchedIds != null) whereParts.add('Id IN :searchMatchedIds');

        if (supportView) {
            if (!isAdmin) {
                whereParts.add('CreatedById = :uid');
            } else if (String.isNotBlank(scope) && scope != 'ANY') {
                if (scope == 'ME') {
                    whereParts.add('OwnerId = :uid');
                } else if (scope == 'UNASSIGNED') {
                    Set<Id> qids = getRequestQueueIds();
                    if (!qids.isEmpty()) whereParts.add('OwnerId IN :qids');
                    else whereParts.add('OwnerId = \'000000000000000AAA\''); // impossible match placeholder
                } else if (scope != null && scope.startsWith('USER:')) {
                    Id ownerId = (Id) (scope.length() > 5 ? scope.substring(5) : null);
                    if (ownerId != null) whereParts.add('OwnerId = :ownerId');
                }
            }
        } else {
            String eff = scope;
            if (String.isBlank(eff)) eff = (isAdmin ? 'ANY' : 'ME');
            if (eff == 'ME') {
                whereParts.add('CreatedById = :uid');
            } else if (eff != null && eff.startsWith('USER:')) {
                Id createdById = (Id) (eff.length() > 5 ? eff.substring(5) : null);
                if (createdById != null) whereParts.add('CreatedById = :createdById');
            }
        }

        if (statusVal != null) whereParts.add('Status__c = :statusVal');
        if (catName   != null) whereParts.add('Id IN (SELECT Request__c FROM Bulletin_Tag__c WHERE Category__r.Name = :catName)');

        // If no WHERE parts (unlikely), inject a harmless true condition to keep the query valid
        if (whereParts.isEmpty()) whereParts.add('Id != null');

        String soql =
            'SELECT Id, Name, Title__c, Type__c, Status__c, Priority__c, ' +
            '       Description__c, OwnerId, Owner.Name, CreatedById, CreatedBy.Name, CreatedBy.Title, CreatedDate, LastModifiedDate ' +
            'FROM Bulletin_Request__c ' +
            'WHERE ' + String.join(whereParts, ' AND ') + ' ' +
            'ORDER BY CreatedDate DESC ' +
            'LIMIT ' + String.valueOf(lim);

        List<Bulletin_Request__c> rows = (List<Bulletin_Request__c>) Database.query(soql);
        if (rows.isEmpty()) return new List<RequestDto>();

        Set<Id> reqIds = new Set<Id>();
        for (Bulletin_Request__c r : rows) reqIds.add(r.Id);

        Map<Id, List<String>> catsByReq = new Map<Id, List<String>>();
        for (Bulletin_Tag__c t : [
            SELECT Request__c, Category__r.Name
            FROM Bulletin_Tag__c
            WHERE Request__c IN :reqIds
        ]) {
            if (!catsByReq.containsKey(t.Request__c)) catsByReq.put(t.Request__c, new List<String>());
            if (t.Category__r != null) catsByReq.get(t.Request__c).add(t.Category__r.Name);
        }

        Map<Id, Integer> cmtMap = new Map<Id, Integer>();
        for (AggregateResult ar : [
            SELECT Request__c rid, COUNT(Id) cnt
            FROM Bulletin_Comment__c
            WHERE Request__c IN :reqIds
            GROUP BY Request__c
        ]) cmtMap.put((Id)ar.get('rid'), (Integer)ar.get('cnt'));

        List<RequestDto> out = new List<RequestDto>();
        for (Bulletin_Request__c r : rows){
            out.add(toDto(
                r,
                catsByReq.containsKey(r.Id) ? catsByReq.get(r.Id) : new List<String>(),
                cmtMap.containsKey(r.Id) ? cmtMap.get(r.Id) : 0
            ));
        }
        return out;
    }

    /* ==================== Get One ==================== */
    @AuraEnabled(cacheable=true)
    public static RequestDto getRequest(Id id){
        Bulletin_Request__c r = [
            SELECT Id, Name, Title__c, Type__c, Status__c, Priority__c,
                   Description__c, OwnerId, Owner.Name, CreatedById, CreatedBy.Name, CreatedBy.Title, CreatedDate, LastModifiedDate
            FROM Bulletin_Request__c
            WHERE Id = :id
            LIMIT 1
        ];
        List<String> cats = new List<String>();
        for (Bulletin_Tag__c t : [
            SELECT Category__r.Name
            FROM Bulletin_Tag__c
            WHERE Request__c = :id
        ]) if (t.Category__r != null) cats.add(t.Category__r.Name);
        Integer ccount = [SELECT COUNT() FROM Bulletin_Comment__c WHERE Request__c = :id];
        return toDto(r, cats, ccount);
    }

    /* ==================== Mutations ==================== */
    @AuraEnabled
    public static RequestDto updateStatus(Id id, String status){
        if (String.isBlank(status)) throw new AuraHandledException('Status required');
        update new Bulletin_Request__c(Id = id, Status__c = status);
        return getRequest(id);
    }
    @AuraEnabled
    public static RequestDto updateDescription(Id id, String bodyHtml){
        if (String.isBlank(bodyHtml)) throw new AuraHandledException('Description body required');
        update new Bulletin_Request__c(Id = id, Description__c = bodyHtml);
        return getRequest(id);
    }
    @AuraEnabled
    public static RequestDto updateOwner(Id id, Id ownerId){
        if (ownerId == null) throw new AuraHandledException('Owner required');
        update new Bulletin_Request__c(Id = id, OwnerId = ownerId);
        return getRequest(id);
    }

    /* ==================== Comments ==================== */
    @AuraEnabled(cacheable=true)
    public static List<CommentDto> listComments(Id requestId){
        List<CommentDto> out = new List<CommentDto>();
        for (Bulletin_Comment__c c : [
            SELECT Id, Body__c, CreatedBy.Name, CreatedDate
            FROM Bulletin_Comment__c
            WHERE Request__c = :requestId
            ORDER BY CreatedDate ASC
        ]) {
            CommentDto d = new CommentDto();
            d.id = c.Id;
            d.authorName = (c.CreatedBy != null ? c.CreatedBy.Name : null);
            d.createdOn = c.CreatedDate;
            d.body = c.Body__c;
            out.add(d);
        }
        return out;
    }
    @AuraEnabled
    public static CommentDto createComment(Id requestId, String body){
        if (String.isBlank(body)) throw new AuraHandledException('Comment body required');
        Bulletin_Comment__c c = new Bulletin_Comment__c(Request__c = requestId, Body__c = body);
        insert c;
        Bulletin_Comment__c reloaded = [
            SELECT Id, Body__c, CreatedBy.Name, CreatedDate
            FROM Bulletin_Comment__c
            WHERE Id = :c.Id
        ];
        CommentDto d = new CommentDto();
        d.id = reloaded.Id;
        d.authorName = (reloaded.CreatedBy != null ? reloaded.CreatedBy.Name : null);
        d.createdOn = reloaded.CreatedDate;
        d.body = reloaded.Body__c;
        return d;
    }

    /* ==================== Create (single RTE form) ==================== */
    @AuraEnabled
    public static RequestDto createRequest(String type, String title, String bodyHtml, List<Id> categoryIds){
        String t = (String.isBlank(type) ? 'Suggestion' : type.trim());
        if (t != 'Suggestion' && t != 'Support Request') t = 'Suggestion';

        String finalTitle;
        if (!String.isBlank(title)) {
            finalTitle = title.trim();
        } else {
            String plain = (bodyHtml == null) ? '' : bodyHtml.replaceAll('<[^>]*>', ' ');
            String compact = plain != null ? plain.trim().replaceAll('\\s+', ' ') : '';
            finalTitle = (compact.length() > 28) ? compact.substring(0,25) + '...' : (String.isBlank(compact) ? 'New request' : compact);
        }

        String who = UserInfo.getFirstName() + ' ' + UserInfo.getLastName();
        String dateStr = Datetime.now().format('MMM d, yyyy');
        String header =
            '<div style="font-size:13px; margin:0 0 16px 0; color:#444;">' +
            '<span style="font-weight:600; color:#000;">Suggested By:</span> <i>' + htmlEscape(who) + '</i><br/>' +
            '<span style="font-weight:600; color:#000;">Date:</span> <i>' + htmlEscape(dateStr) + '</i>' +
            '</div>' +
            '<hr style="border:0; border-top:1px solid #e5e7eb; margin:12px 0;">';

        String wrapperStart = '<div style="font-family: Arial,Helvetica,sans-serif; line-height:1.5; font-size:14px; padding:12px 14px; border:1px solid #e5e7eb; border-radius:8px;">';
        String wrapperEnd   = '</div>';
        String safeBody     = (bodyHtml == null ? '' : bodyHtml);
        String finalHtml    = wrapperStart + header + safeBody + wrapperEnd;

        Bulletin_Request__c req = new Bulletin_Request__c();
        req.Type__c        = t;
        req.Status__c      = 'New';
        req.Title__c       = finalTitle;
        req.Description__c = finalHtml;

        if (t == 'Support Request') {
            Id q = findSupportQueueId();
            if (q != null) req.OwnerId = q;
        }

        insert req;

        if (categoryIds != null && !categoryIds.isEmpty()){
            Map<Id, Bulletin_Category__c> catsById = new Map<Id, Bulletin_Category__c>([
                SELECT Id, Name FROM Bulletin_Category__c WHERE Id IN :categoryIds
            ]);
            List<Bulletin_Tag__c> toInsert = new List<Bulletin_Tag__c>();
            for (Id cid : catsById.keySet()){
                Bulletin_Tag__c tag = new Bulletin_Tag__c();
                tag.Request__c  = req.Id;
                tag.Category__c = cid;
                tag.Name        = catsById.get(cid).Name;
                toInsert.add(tag);
            }
            if (!toInsert.isEmpty()) insert toInsert;
        }
        return getRequest(req.Id);
    }

    /* ==================== Helpers ==================== */
    private static Filters parse(String filtersJson){
        try {
            return (Filters) JSON.deserialize(filtersJson == null ? '{}' : filtersJson, Filters.class);
        } catch (Exception e) {
            return new Filters();
        }
    }
    private static String fmt(Datetime dt){
        return (dt == null) ? null : dt.format('MMM d');
    }
    private static RequestDto toDto(Bulletin_Request__c r, List<String> cats, Integer ccount){
        RequestDto d = new RequestDto();
        d.id              = r.Id;
        d.recordNumber    = r.Name;
        d.title           = r.Title__c;
        d.type            = r.Type__c;
        d.status          = r.Status__c;
        d.priority        = r.Priority__c;
        d.categories      = (cats != null ? cats : new List<String>());
        d.ownerId         = r.OwnerId;
        d.ownerName       = (r.Owner != null ? r.Owner.Name : null);
        d.createdById     = r.CreatedById;
        d.createdByName   = (r.CreatedBy != null ? r.CreatedBy.Name : null);
        d.createdByTitle  = (r.CreatedBy != null ? r.CreatedBy.Title : null);
        d.createdDate     = fmt(r.CreatedDate);
        d.updatedDate     = fmt(r.LastModifiedDate);
        d.commentCount    = (ccount == null ? 0 : ccount);
        d.descriptionHtml = r.Description__c;
        return d;
    }

    // Minimal SOSL reserved character handling
    private static String sanitizeSoslQuery(String s){
        // Replace characters that often break SOSL syntax with spaces; collapse whitespace
        String t = s.replaceAll('[\\?\\|\\!\\{\\}\\[\\]\\(\\)\\^\\~\\*\\:\\\\\"\\+\\-]+', ' ');
        t = t.replaceAll('\\s+', ' ').trim();
        return t;
    }

    // HTML escape helper
    private static String htmlEscape(String s){
        if (s == null) return null;
        String out = s;
        out = out.replaceAll('&', '&amp;');
        out = out.replaceAll('<', '&lt;');
        out = out.replaceAll('>', '&gt;');
        out = out.replaceAll('"', '&quot;');
        out = out.replaceAll('\'' , '&#39;');
        return out;
    }

    // ===== UNASSIGNED support queue logic =====
    private static Set<Id> REQUEST_QUEUE_IDS;
    private static Set<Id> getRequestQueueIds(){
        if (REQUEST_QUEUE_IDS != null) return REQUEST_QUEUE_IDS;
        REQUEST_QUEUE_IDS = new Set<Id>();
        for (QueueSobject qs : [
            SELECT QueueId FROM QueueSobject
            WHERE SObjectType = 'Bulletin_Request__c'
        ]) REQUEST_QUEUE_IDS.add(qs.QueueId);
        return REQUEST_QUEUE_IDS;
    }

    private static Boolean hasBulletinAdmin(){
        try {
            Integer cnt = [
                SELECT COUNT()
                FROM PermissionSetAssignment
                WHERE AssigneeId = :UserInfo.getUserId()
                AND (PermissionSet.Name = 'Bulletin_Admin' OR PermissionSet.Label = 'Bulletin Admin')
            ];
            return cnt > 0;
        } catch (Exception e) { return false; }
    }

    private static Id SUPPORT_QUEUE_ID;
    private static Id findSupportQueueId(){
        if (SUPPORT_QUEUE_ID != null) return SUPPORT_QUEUE_ID;
        try {
            for (Group g : [SELECT Id FROM Group WHERE Type='Queue' AND DeveloperName='Bulletin_Support' LIMIT 1]){
                SUPPORT_QUEUE_ID = g.Id; return SUPPORT_QUEUE_ID;
            }
            for (Group g : [SELECT Id FROM Group WHERE Type='Queue' AND Name='Bulletin Support' LIMIT 1]){
                SUPPORT_QUEUE_ID = g.Id; return SUPPORT_QUEUE_ID;
            }
            for (QueueSobject qs : [SELECT QueueId FROM QueueSobject WHERE SObjectType='Bulletin_Request__c' LIMIT 1]){
                SUPPORT_QUEUE_ID = qs.QueueId; return SUPPORT_QUEUE_ID;
            }
        } catch (Exception e) { /* ignore */ }
        return null;
    }

    @TestVisible private static void resetCaches(){
        REQUEST_QUEUE_IDS = null;
        SUPPORT_QUEUE_ID  = null;
    }
}
