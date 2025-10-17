@IsTest(SeeAllData=false)
private class BulletinServiceTest {
    
    @testSetup
    static void seedData() {
        upsertStatus('New',         true,  true,  1, 1);
        upsertStatus('In Progress', true,  true,  2, 2);
        upsertStatus('Working',     true,  true,  3, 3);
        upsertStatus('Resolved',    false, true,  4, 4); 
        upsertStatus('Closed',      true,  true,  5, 5);
        ensureSupportQueue(); 
    }

    private static Id upsertStatus(
        String name, Boolean forSuggestions, Boolean forSupport, Integer sugOrder, Integer supOrder
    ){
        List<Bulletin_Status__c> existing = [
            SELECT Id FROM Bulletin_Status__c WHERE Name = :name LIMIT 1
        ];
        if (!existing.isEmpty()) return existing[0].Id;

        Bulletin_Status__c s = new Bulletin_Status__c(
            Name = name,
            Active__c = true,
            Suggestion_Status__c = forSuggestions,
            Support_Status__c    = forSupport,
            Status_Order_Suggestion__c = sugOrder,   
            Status_Order_Support__c    = supOrder    
        );
        insert s;
        return s.Id;
    }

    private static void ensureSupportQueue(){
        Group q;
        try {
            q = [SELECT Id FROM Group WHERE Type='Queue' AND DeveloperName='Bulletin_Support' LIMIT 1];
        } catch (QueryException e) {
            q = new Group(Name='Bulletin Support', DeveloperName='Bulletin_Support', Type='Queue');
            insert q;
        }
        if ([
            SELECT COUNT() FROM QueueSobject
            WHERE QueueId = :q.Id AND SObjectType = 'Bulletin_Request__c'
        ] == 0){
            insert new QueueSobject(QueueId=q.Id, SObjectType='Bulletin_Request__c');
        }
    }

    // ---------- Helpers ----------
    private static User makeUser(String suffix) {
        Profile p = [SELECT Id FROM Profile WHERE Id = :UserInfo.getProfileId()];
        String ts = String.valueOf(Datetime.now().getTime());
        return new User(
            FirstName='Test', LastName='User' + suffix,
            Email='test+' + suffix + '_' + ts + '@example.com',
            Username='test+' + suffix + '_' + ts + '@example.com',
            Alias=('t' + suffix).substring(0, Math.min(8, ('t' + suffix).length())),
            TimeZoneSidKey='America/Los_Angeles', LocaleSidKey='en_US',
            EmailEncodingKey='UTF-8', LanguageLocaleKey='en_US',
            ProfileId=p.Id, Title='QA ' + suffix
        );
    }

    private static Group makeSupportQueue() {
        Group q = new Group(Name='Bulletin Support', DeveloperName='Bulletin_Support', Type='Queue');
        try {
            insert q;
        } catch (DmlException e) {
            // Retry with safe alphanumeric DeveloperName
            Integer rnd = Math.abs(Crypto.getRandomInteger());
            q = new Group(Name='Bulletin Support', DeveloperName='Bulletin_Support_' + String.valueOf(rnd), Type='Queue');
            insert q;
        }
        // Ensure queue can own Bulletin_Request__c
        try { insert new QueueSobject(QueueId=q.Id, SObjectType='Bulletin_Request__c'); } catch (Exception ignore) {}
        return q;
    }

    private static Bulletin_Category__c makeCategory(String name, Boolean activeFlag) {
        Bulletin_Category__c c = new Bulletin_Category__c(Name=name, Active__c=activeFlag);
        insert c;
        return c;
    }

    @IsTest static void testCategories_and_CategoryNames_activeOnly_and_Order() {
        makeCategory('Zeta (inactive)', false);
        makeCategory('Bravo', true); makeCategory('Alpha', true); makeCategory('Delta', true);
        List<BulletinService.CategoryOption> opts = BulletinService.listActiveCategories();
        System.assertEquals(3, opts.size());
        System.assertEquals('Alpha', opts[0].name); System.assertEquals('Bravo', opts[1].name); System.assertEquals('Delta', opts[2].name);
        List<String> names = BulletinService.listActiveCategoryNames();
        System.assertEquals(3, names.size());
        System.assertEquals('Alpha', names[0]); System.assertEquals('Bravo', names[1]); System.assertEquals('Delta', names[2]);
    }

    @IsTest static void testComments_create_and_list_ordering() {
        User u = makeUser('cmt'); insert u;
        System.runAs(u) {
            BulletinService.RequestDto req = BulletinService.createRequest('Suggestion', 'With Comments', '<p>hi</p>', null);
            BulletinService.CommentDto c1 = BulletinService.createComment(req.id, 'First');  Test.setCreatedDate(c1.id, System.now().addMinutes(-2));
            BulletinService.CommentDto c2 = BulletinService.createComment(req.id, 'Second'); Test.setCreatedDate(c2.id, System.now().addMinutes(-1));
            BulletinService.CommentDto c3 = BulletinService.createComment(req.id, 'Third');
            List<BulletinService.CommentDto> listed = BulletinService.listComments(req.id);
            System.assertEquals(3, listed.size());
            System.assertEquals('First', listed[0].body); System.assertEquals('Second', listed[1].body); System.assertEquals('Third', listed[2].body);
            System.assertEquals(3, BulletinService.getRequest(req.id).commentCount);
        }
    }

    @IsTest static void testCreateSuggestion_and_Query_and_GetOne() {
        User u1 = makeUser('u1'); insert u1;
        Bulletin_Category__c cat = makeCategory('Alpha', true);
        System.runAs(u1) {
            BulletinService.RequestDto dto = BulletinService.createRequest('Suggestion', 'Hello Title', '<p>Body</p>', new List<Id>{cat.Id});
            System.assertEquals('Suggestion', dto.type); System.assertEquals('New', dto.status);
            System.assertEquals('Hello Title', dto.title); System.assertEquals('Alpha', dto.categories[0]);
            System.assertEquals(u1.Id, dto.createdById); System.assertEquals(u1.Title, dto.createdByTitle);
            BulletinService.RequestDto fetched = BulletinService.getRequest(dto.id);
            System.assertEquals(dto.id, fetched.id); System.assertEquals(dto.recordNumber, fetched.recordNumber);
            BulletinService.Filters f = new BulletinService.Filters(); f.pageSize=200; f.status='New'; f.categoryName='Alpha';
            System.assertEquals(1, BulletinService.listSuggestions(JSON.serialize(f)).size());
            User u2 = makeUser('u2'); insert u2;
            System.runAs(u2) { BulletinService.createRequest('Suggestion', 'Other Title', '<p>Other</p>', new List<Id>{cat.Id}); }
            System.assertEquals(1, BulletinService.listSuggestions(JSON.serialize(new BulletinService.Filters())).size());
        }
    }

    @IsTest
    static void testCreateSupport_assignsQueue_and_SupportListing() {
        makeSupportQueue(); // ensure at least one exists; actual method may still pick an existing org queue

        // Build the set of valid queue IDs for Bulletin_Request__c
        Set<Id> validQueueIds = new Set<Id>();
        for (QueueSobject qs : [SELECT QueueId FROM QueueSobject WHERE SObjectType='Bulletin_Request__c']) validQueueIds.add(qs.QueueId);
        System.assert(!validQueueIds.isEmpty(), 'There must be at least one valid queue');

        User u1 = makeUser('supportA'); insert u1;
        User u2 = makeUser('supportB'); insert u2;

        System.runAs(u1) {
            BulletinService.RequestDto r1 = BulletinService.createRequest('Support Request', 'SR One', '<p>foo</p>', null);
            BulletinService.RequestDto r2 = BulletinService.createRequest('Support Request', 'SR Two', '<p>bar</p>', null);

            // Assert owner is a valid Bulletin queue (not necessarily the one we just created)
            System.assert(validQueueIds.contains(r1.ownerId), 'SR One owner must be a Bulletin queue');
            System.assert(validQueueIds.contains(r2.ownerId), 'SR Two owner must be a Bulletin queue');

            List<BulletinService.RequestDto> mineInSupport = BulletinService.listSupportTickets('{}');
            System.assertEquals(2, mineInSupport.size(), 'Non-admin sees only their created SRs');
        }

        System.runAs(u2) {
            BulletinService.createRequest('Support Request', 'SR Three', '<p>baz</p>', null);
            List<BulletinService.RequestDto> mineOnly = BulletinService.listSupportTickets('{}');
            System.assertEquals(1, mineOnly.size());
        }
    }

    @IsTest
    static void testMutations_updateStatus_updateDescription_updateOwner() {
        makeSupportQueue();

        User creator = makeUser('mut'); insert creator;
        User newOwner = makeUser('owner'); insert newOwner;

        System.runAs(creator) {
            BulletinService.RequestDto dto = BulletinService.createRequest('Suggestion', 'Mut Title', '<p>x</p>', null);

            BulletinService.RequestDto afterStatus = BulletinService.updateStatus(dto.id, 'In Progress');
            System.assertEquals('In Progress', afterStatus.status);

            BulletinService.RequestDto afterDesc = BulletinService.updateDescription(dto.id, '<b>Updated</b>');
            System.assertEquals('<b>Updated</b>', afterDesc.descriptionHtml);

            BulletinService.RequestDto afterOwner = BulletinService.updateOwner(dto.id, newOwner.Id);
            System.assertEquals(newOwner.Id, afterOwner.ownerId);
            System.assertEquals([SELECT Name FROM User WHERE Id=:newOwner.Id].Name, afterOwner.ownerName);

            // Negatives
            Boolean threw;
            threw=false; try { BulletinService.updateStatus(null, ''); } catch (AuraHandledException e) { threw=true; } System.assert(threw);
            threw=false; try { BulletinService.updateDescription(null, ''); } catch (AuraHandledException e) { threw=true; } System.assert(threw);
            threw=false; try { BulletinService.updateOwner(null, null); } catch (AuraHandledException e) { threw=true; } System.assert(threw);
        }
    }

    @IsTest
    static void testSupportOwnerOptions_includesQueue_and_AdminsIfAny() {
        makeSupportQueue();

        // Valid queues in org (could include pre-existing ones)
        Map<Id, String> queueNamesById = new Map<Id, String>();
        for (Group g : [SELECT Id, Name FROM Group WHERE Id IN (SELECT QueueId FROM QueueSobject WHERE SObjectType='Bulletin_Request__c')]) {
            queueNamesById.put(g.Id, g.Name);
        }
        System.assert(!queueNamesById.isEmpty(), 'There must be at least one queue wired to Bulletin_Request__c');

        List<BulletinService.UserOption> owners = BulletinService.getSupportOwnerOptions();
        System.assert(!owners.isEmpty(), 'Should include at least the queue');

        // Assert there exists at least one option that matches a valid queue and its name
        Boolean foundQueue = false;
        for (BulletinService.UserOption o : owners) {
            if (queueNamesById.containsKey(o.id)) {
                System.assertEquals(queueNamesById.get(o.id), o.name, 'Owner option name should match Group name');
                foundQueue = true; break;
            }
        }
        System.assert(foundQueue, 'Owner options should include at least one valid Bulletin queue');
    }

    @IsTest
    static void testGetBulletinContext_nonAdmin_defaults() {
        User u = makeUser('ctx'); insert u;
        System.runAs(u) {
            BulletinService.BulletinContext ctx = BulletinService.getBulletinContext();
            System.assertNotEquals(null, ctx);
            System.assertEquals(false, ctx.isAdmin);
            System.assertEquals('Bulletin_Admin_Queue', ctx.adminQueueName);
            System.assertNotEquals(null, ctx.adminUsers);
            System.assertNotEquals(null, ctx.bulletinUsers);
        }
    }

    @IsTest
    static void testSuggestion_status_and_CategoryScope_only() {
        User u = makeUser('filters'); insert u;
        Bulletin_Category__c alpha = makeCategory('Alpha', true);
        Bulletin_Category__c beta  = makeCategory('Beta',  true);

        System.runAs(u) {
            BulletinService.RequestDto r1 = BulletinService.createRequest('Suggestion', 'Improve Search', '<p>search speed</p>', new List<Id>{ alpha.Id });
            BulletinService.RequestDto r2 = BulletinService.createRequest('Suggestion', 'Dark Mode', '<p>theme</p>', new List<Id>{ beta.Id });

            BulletinService.Filters f2 = new BulletinService.Filters(); f2.status='New';
            List<BulletinService.RequestDto> bothNew = BulletinService.listSuggestions(JSON.serialize(f2));
            System.assertEquals(2, bothNew.size());

            BulletinService.Filters f3 = new BulletinService.Filters(); f3.categoryName='Alpha';
            List<BulletinService.RequestDto> onlyAlpha = BulletinService.listSuggestions(JSON.serialize(f3));
            System.assertEquals(1, onlyAlpha.size()); System.assertEquals(r1.id, onlyAlpha[0].id);

            BulletinService.Filters f4 = new BulletinService.Filters(); f4.ownerScope='ME';
            List<BulletinService.RequestDto> meOnly = BulletinService.listSuggestions(JSON.serialize(f4));
            System.assertEquals(2, meOnly.size());
        }
    }
}
