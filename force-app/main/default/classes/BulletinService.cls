public without sharing class BulletinService {
    /* ==================== Filters & DTOs ==================== */
    public class Filters {
        @AuraEnabled public String search;
        @AuraEnabled public String status;
        @AuraEnabled public String categoryName;
        @AuraEnabled public Integer pageSize;
        // Suggestions: 'ANY' | 'ME' | 'USER:<Id>'
        // Support:     'ANY' | 'ME' | 'UNASSIGNED' | 'USER:<Id>'
        @AuraEnabled public String ownerScope;
    }
    public class RequestDto {
        @AuraEnabled public Id id;
        @AuraEnabled public String recordNumber;
        @AuraEnabled public String title;
        @AuraEnabled public String type;
        @AuraEnabled public String status;
        @AuraEnabled public String priority;
        @AuraEnabled public List<String> categories;
        @AuraEnabled public String ownerName;
        @AuraEnabled public String createdByName;
        @AuraEnabled public String createdDate;
        @AuraEnabled public String updatedDate;
        @AuraEnabled public Integer commentCount;
        @AuraEnabled public String descriptionHtml;
    }
    public class CommentDto {
        @AuraEnabled public Id id;
        @AuraEnabled public String authorName;
        @AuraEnabled public Datetime createdOn;
        @AuraEnabled public String body;
    }
    public class UserOption {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        public UserOption(Id i, String n){ id=i; name=n; }
    }
    public class BulletinContext {
        @AuraEnabled public Boolean isAdmin;
        @AuraEnabled public List<UserOption> adminUsers;
        @AuraEnabled public List<UserOption> bulletinUsers;
        @AuraEnabled public String adminQueueName; // informational; not used for filtering anymore
    }

    /* ==================== Entry Points ==================== */
    @AuraEnabled
    public static List<RequestDto> listSuggestions(String filtersJson){
        // Keep strict type to your data model
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

        // Kept for reference; filtering no longer depends on a single queue name.
        ctx.adminQueueName = 'Bulletin_Admin_Queue';
        return ctx;
    }

    /* NEW: All active category names for filter dropdowns */
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

    /* ==================== Core Listing ==================== */
    private static List<RequestDto> queryRequests(Set<String> types, Filters f, Boolean supportView){
        Integer lim = (f != null && f.pageSize != null && f.pageSize > 0) ? Math.min(f.pageSize, 200) : 50;

        String searchLike = (f != null && String.isNotBlank(f.search)) ? '%' + String.escapeSingleQuotes(f.search) + '%' : null;
        String statusVal  = (f != null && String.isNotBlank(f.status)) ? String.escapeSingleQuotes(f.status) : null;
        String catName    = (f != null && String.isNotBlank(f.categoryName)) ? String.escapeSingleQuotes(f.categoryName) : null;
        String scope      = (f != null ? f.ownerScope : null);

        Boolean isAdmin = hasBulletinAdmin();
        String uid = UserInfo.getUserId();

        List<String> whereParts = new List<String>();

        if (!types.isEmpty()){
            List<String> esc = new List<String>();
            for (String t : types) esc.add('\'' + String.escapeSingleQuotes(t) + '\'');
            whereParts.add('Type__c IN (' + String.join(esc, ',') + ')');
        }
        if (searchLike != null){
            whereParts.add('(Title__c LIKE \'' + searchLike + '\' OR Description__c LIKE \'' + searchLike + '\')');
        }

        // Scoping (kept to your original meaning of "my")
        if (supportView) {
            // Non-admins: only tickets they CREATED
            if (!isAdmin) {
                whereParts.add('CreatedById = \'' + uid + '\'');
            } else if (String.isNotBlank(scope) && scope != 'ANY') {
                if (scope == 'ME') {
                    whereParts.add('OwnerId = \'' + uid + '\'');
                } else if (scope == 'UNASSIGNED') {
                    Set<Id> qids = getRequestQueueIds(); // <- all queues that can own Bulletin_Request__c
                    if (!qids.isEmpty()) {
                        whereParts.add('OwnerId IN (' + toIdCsv(qids) + ')');
                    } else {
                        whereParts.add('OwnerId = \'000000000000000AAA\''); // impossible fallback
                    }
                } else if (scope.startsWith('USER:')) {
                    whereParts.add('OwnerId = \'' + String.escapeSingleQuotes(scope.substring(5)) + '\'');
                }
            }
        } else {
            // Suggestions: default = ME (submitter) for users, ANY for admins
            String eff = scope;
            if (String.isBlank(eff)) eff = (isAdmin ? 'ANY' : 'ME');
            if (eff == 'ME') {
                whereParts.add('CreatedById = \'' + uid + '\'');
            } else if (eff.startsWith('USER:')) {
                whereParts.add('CreatedById = \'' + String.escapeSingleQuotes(eff.substring(5)) + '\'');
            } // ANY => no CreatedBy filter
        }

        if (statusVal != null) whereParts.add('Status__c = \'' + statusVal + '\'');
        if (catName != null)   whereParts.add('Id IN (SELECT Request__c FROM Bulletin_Tag__c WHERE Category__r.Name = \'' + catName + '\')');

        String soql =
            'SELECT Id, Name, Title__c, Type__c, Status__c, Priority__c, ' +
            '       Description__c, Owner.Name, CreatedBy.Name, CreatedDate, LastModifiedDate ' +
            'FROM Bulletin_Request__c ' +
            'WHERE ' + String.join(whereParts, ' AND ') + ' ' +
            'ORDER BY LastModifiedDate DESC ' +
            'LIMIT ' + String.valueOf(lim);

        List<Bulletin_Request__c> rows = (List<Bulletin_Request__c>) Database.query(soql);
        if (rows.isEmpty()) return new List<RequestDto>();

        Set<Id> reqIds = new Set<Id>();
        for (Bulletin_Request__c r : rows) reqIds.add(r.Id);

        // Categories per request
        Map<Id, List<String>> catsByReq = new Map<Id, List<String>>();
        for (Bulletin_Tag__c t : [
            SELECT Request__c, Category__r.Name
            FROM Bulletin_Tag__c
            WHERE Request__c IN :reqIds
        ]) {
            if (!catsByReq.containsKey(t.Request__c)) catsByReq.put(t.Request__c, new List<String>());
            if (t.Category__r != null) catsByReq.get(t.Request__c).add(t.Category__r.Name);
        }

        // Comment counts
        Map<Id, Integer> cmtMap = new Map<Id, Integer>();
        for (AggregateResult ar : [
            SELECT Request__c rid, COUNT(Id) cnt
            FROM Bulletin_Comment__c
            WHERE Request__c IN :reqIds
            GROUP BY Request__c
        ]) cmtMap.put((Id)ar.get('rid'), (Integer)ar.get('cnt'));

        // Map to DTOs
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
                   Description__c, Owner.Name, CreatedBy.Name, CreatedDate, LastModifiedDate
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

    /* ==================== Helpers ==================== */
    private static Filters parse(String filtersJson){
        return (Filters) JSON.deserialize(filtersJson == null ? '{}' : filtersJson, Filters.class);
    }
    private static String fmt(Datetime dt){
        return (dt == null) ? null : dt.format('MMM d');
    }
    private static RequestDto toDto(Bulletin_Request__c r, List<String> cats, Integer ccount){
        RequestDto d = new RequestDto();
        d.id = r.Id;
        d.recordNumber = r.Name;
        d.title = r.Title__c;
        d.type = r.Type__c;
        d.status = r.Status__c;
        d.priority = r.Priority__c;
        d.categories = (cats != null ? cats : new List<String>());
        d.ownerName = (r.Owner != null ? r.Owner.Name : null);
        d.createdByName = (r.CreatedBy != null ? r.CreatedBy.Name : null);
        d.createdDate = fmt(r.CreatedDate);
        d.updatedDate = fmt(r.LastModifiedDate);
        d.commentCount = (ccount == null ? 0 : ccount);
        d.descriptionHtml = r.Description__c;
        return d;
    }

    // ----- Queue helpers (for "UNASSIGNED") -----
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
    private static String toIdCsv(Set<Id> ids){
        List<String> parts = new List<String>();
        for (Id i : ids) parts.add('\'' + String.valueOf(i) + '\'');
        return String.join(parts, ',');
    }

    // ----- Admin helpers -----
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
}
