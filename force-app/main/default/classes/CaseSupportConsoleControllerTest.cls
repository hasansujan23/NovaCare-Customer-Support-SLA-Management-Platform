@IsTest
private class CaseSupportConsoleControllerTest {
    private static final String AGENT_USERNAME_PREFIX = 'novacare.console.agent';
    private static final String BASIC_USERNAME_PREFIX = 'novacare.console.basic';
    private static final String CONNECTED_SUBJECT = 'API Integration Authentication Failure';
    private static final String BARE_SUBJECT = 'Case without related records';

    @TestSetup
    static void setupData() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            User agent = createUser(AGENT_USERNAME_PREFIX, 'Standard User');
            User basicUser = createUser(BASIC_USERNAME_PREFIX, 'Standard User');
            insert new List<User>{ agent, basicUser };
            insert new PermissionSetAssignment(
                AssigneeId = agent.Id,
                PermissionSetId = [SELECT Id FROM PermissionSet WHERE Name = 'NovaCare_Support_Agent'].Id
            );
        }

        Account account = new Account(Name = 'Acme Corporation');
        insert account;
        Contact contact = new Contact(FirstName = 'John', LastName = 'Smith', AccountId = account.Id);
        insert contact;
        Asset asset = new Asset(Name = 'API Gateway Enterprise', AccountId = account.Id, ContactId = contact.Id);
        insert asset;
        Support_Subscription__c subscription = new Support_Subscription__c(
            Account__c = account.Id,
            Contact__c = contact.Id,
            Support_Plan__c = 'Enterprise',
            Status__c = 'Active',
            Start_Date__c = Date.newInstance(2026, 1, 1),
            End_Date__c = Date.newInstance(2026, 12, 31),
            X24x7_Support__c = true
        );
        insert subscription;

        insert new List<Case>{
            new Case(
                Subject = CONNECTED_SUBJECT,
                Status = 'New',
                Origin = 'Phone',
                Priority = 'Critical',
                Issue_Category__c = 'Integration',
                AccountId = account.Id,
                ContactId = contact.Id,
                AssetId = asset.Id,
                Support_Subscription__c = subscription.Id
            ),
            new Case(Subject = BARE_SUBJECT, Status = 'New', Origin = 'Web', Priority = 'Low')
        };
    }

    @IsTest
    static void validCaseReturnsCaseCustomerAndSlaData() {
        Case expected = loadCase(CONNECTED_SUBJECT);

        CaseSupportConsoleDTO result = loadAsAgent(expected.Id);

        System.assertEquals(expected.Id, result.caseInfo.caseId);
        System.assertEquals(expected.CaseNumber, result.caseInfo.caseNumber, 'Case Number must be returned.');
        System.assertEquals(CONNECTED_SUBJECT, result.caseInfo.subject);
        System.assertEquals('Critical', result.caseInfo.priority);
        System.assertEquals('Integration', result.caseInfo.issueCategory);
        System.assertEquals(false, result.caseInfo.isClosed);

        System.assertEquals('Acme Corporation', result.customer.accountName);
        System.assertEquals(expected.AccountId, result.customer.accountId);
        System.assertEquals('John Smith', result.customer.contactName);
        System.assertEquals(expected.ContactId, result.customer.contactId);
        System.assertEquals('API Gateway Enterprise', result.customer.assetName);
        System.assertEquals(expected.AssetId, result.customer.assetId);

        System.assertEquals(expected.SLA_Status__c, result.sla.slaStatus);
        System.assertEquals('On Track', result.sla.slaStatus, 'SLAService applies the initial SLA on insert.');
        System.assertEquals(expected.SLA_Breached__c, result.sla.slaBreached);
        System.assertEquals(expected.Escalation_Level__c, result.sla.escalationLevel);
        System.assertEquals(expected.First_Response_Due__c, result.sla.firstResponseDue);
        System.assertEquals(expected.Resolution_Due__c, result.sla.resolutionDue);
        System.assertEquals(null, result.sla.firstRespondedAt);
        System.assertNotEquals(null, result.sla.firstResponseDue);
    }

    @IsTest
    static void supportSubscriptionIsReturned() {
        CaseSupportConsoleDTO result = loadAsAgent(loadCase(CONNECTED_SUBJECT).Id);

        System.assertEquals(true, result.subscriptionAccessible);
        System.assertNotEquals(null, result.subscription);
        System.assertEquals('Enterprise', result.subscription.supportPlan);
        System.assertEquals('Active', result.subscription.subscriptionStatus);
        System.assertEquals(Date.newInstance(2026, 1, 1), result.subscription.startDate);
        System.assertEquals(Date.newInstance(2026, 12, 31), result.subscription.endDate);
        System.assertEquals(true, result.subscription.support24x7);
        System.assertNotEquals(null, result.subscription.subscriptionName);
    }

    @IsTest
    static void userOwnerIsReportedAsUser() {
        Case supportCase = loadCase(CONNECTED_SUBJECT);
        User agent = agentUser();
        update new Case(Id = supportCase.Id, OwnerId = agent.Id);

        CaseSupportConsoleDTO result = loadAsAgent(supportCase.Id);

        System.assertEquals(agent.Id, result.assignment.ownerId);
        System.assertEquals('User', result.assignment.ownerType);
        System.assertEquals([SELECT Name FROM User WHERE Id = :agent.Id].Name, result.assignment.ownerName);
    }

    @IsTest
    static void queueOwnerIsReportedAsQueue() {
        Case supportCase = loadCase(CONNECTED_SUBJECT);
        Group caseQueue = [
            SELECT Id, Name
            FROM Group
            WHERE Type = 'Queue'
            AND Id IN (SELECT QueueId FROM QueueSobject WHERE SobjectType = 'Case')
            LIMIT 1
        ];
        update new Case(Id = supportCase.Id, OwnerId = caseQueue.Id);

        CaseSupportConsoleDTO result = loadAsAgent(supportCase.Id);

        System.assertEquals(caseQueue.Id, result.assignment.ownerId);
        System.assertEquals('Queue', result.assignment.ownerType);
        System.assertEquals(caseQueue.Name, result.assignment.ownerName);
    }

    @IsTest
    static void noHistoryReturnsEmptyAccessibleTimeline() {
        CaseSupportConsoleDTO result = loadAsAgent(loadCase(CONNECTED_SUBJECT).Id);

        System.assertEquals(true, result.historyAccessible);
        System.assertNotEquals(null, result.history);
        System.assertEquals(0, result.history.size());
    }

    @IsTest
    static void multipleHistoryRecordsAreMappedNewestFirst() {
        Case supportCase = loadCase(CONNECTED_SUBJECT);
        Datetime baseTime = System.now().addHours(-3);
        insert new List<SLA_Escalation_History__c>{
            history(supportCase.Id, baseTime, 'On Track', 'At Risk', 'Level 1', 'First Response'),
            history(supportCase.Id, baseTime.addMinutes(45), 'At Risk', 'Breached', 'Level 2', 'First Response')
        };

        CaseSupportConsoleDTO result = loadAsAgent(supportCase.Id);

        System.assertEquals(2, result.history.size());
        CaseSupportConsoleDTO.EscalationHistoryItem newest = result.history[0];
        System.assertEquals(baseTime.addMinutes(45), newest.escalatedAt, 'Newest escalation must be first.');
        System.assertEquals('At Risk', newest.previousSlaStatus);
        System.assertEquals('Breached', newest.newSlaStatus);
        System.assertEquals('Level 2', newest.escalationLevel);
        System.assertEquals('First Response', newest.slaType);
        System.assertEquals('Test escalation reason', newest.reason);
        System.assertEquals(baseTime.addMinutes(30), newest.slaDueAt);
        System.assertNotEquals(null, newest.historyId);
        System.assertEquals(baseTime, result.history[1].escalatedAt);
    }

    @IsTest
    static void historyIsLimitedAndSortedDescending() {
        Case supportCase = loadCase(CONNECTED_SUBJECT);
        Datetime baseTime = System.now().addDays(-1);
        List<SLA_Escalation_History__c> records = new List<SLA_Escalation_History__c>();
        for (Integer index = 0; index < 12; index++) {
            records.add(history(supportCase.Id, baseTime.addMinutes(index * 10), 'On Track', 'At Risk', 'Level 1', 'Resolution'));
        }
        insert records;

        CaseSupportConsoleDTO result = loadAsAgent(supportCase.Id);

        System.assertEquals(CaseSupportConsoleController.HISTORY_LIMIT, result.history.size());
        System.assertEquals(baseTime.addMinutes(110), result.history[0].escalatedAt, 'Latest record must be first.');
        for (Integer index = 1; index < result.history.size(); index++) {
            System.assert(
                result.history[index - 1].escalatedAt >= result.history[index].escalatedAt,
                'History must be ordered newest first.'
            );
        }
        System.assertEquals(baseTime.addMinutes(20), result.history[9].escalatedAt, 'Oldest two records are excluded.');
    }

    @IsTest
    static void historyOfOtherCasesIsExcluded() {
        Case supportCase = loadCase(CONNECTED_SUBJECT);
        Case otherCase = loadCase(BARE_SUBJECT);
        insert history(otherCase.Id, System.now(), 'On Track', 'At Risk', 'Level 1', 'Resolution');

        CaseSupportConsoleDTO result = loadAsAgent(supportCase.Id);

        System.assertEquals(0, result.history.size());
    }

    @IsTest
    static void missingSubscriptionAndOptionalRecordsReturnEmptyValues() {
        CaseSupportConsoleDTO result = loadAsAgent(loadCase(BARE_SUBJECT).Id);

        System.assertEquals(true, result.subscriptionAccessible);
        System.assertEquals(null, result.subscription, 'A missing subscription must not be fabricated.');
        System.assertEquals(null, result.customer.accountId);
        System.assertEquals(null, result.customer.accountName);
        System.assertEquals(null, result.customer.contactName);
        System.assertEquals(null, result.customer.assetName);
        System.assertEquals(null, result.caseInfo.issueCategory);
        System.assertEquals(null, result.sla.firstResponseDue, 'No SLA is applied without a subscription.');
        System.assertNotEquals(null, result.assignment.ownerId);
    }

    @IsTest
    static void nullCaseIdReturnsControlledError() {
        assertLoadFails(null);
    }

    @IsTest
    static void nonCaseIdReturnsControlledError() {
        assertLoadFails([SELECT Id FROM Account LIMIT 1].Id);
    }

    @IsTest
    static void deletedCaseReturnsControlledError() {
        Case supportCase = loadCase(BARE_SUBJECT);
        delete supportCase;

        assertLoadFails(supportCase.Id);
    }

    @IsTest
    static void userWithoutAgentPermissionsDoesNotReceiveProtectedData() {
        Case supportCase = loadCase(CONNECTED_SUBJECT);
        insert history(supportCase.Id, System.now(), 'On Track', 'At Risk', 'Level 1', 'First Response');

        CaseSupportConsoleDTO result;
        Boolean canReadSubscriptions;
        Boolean canReadHistory;
        Boolean canReadSlaStatus;
        System.runAs(basicUser()) {
            canReadSubscriptions = Schema.sObjectType.Support_Subscription__c.isAccessible()
                && Schema.sObjectType.Case.fields.Support_Subscription__c.isAccessible();
            canReadHistory = Schema.sObjectType.SLA_Escalation_History__c.isAccessible()
                && Schema.sObjectType.SLA_Escalation_History__c.fields.Escalated_At__c.isAccessible();
            canReadSlaStatus = Schema.sObjectType.Case.fields.SLA_Status__c.isAccessible();
            result = CaseSupportConsoleController.getConsoleData(supportCase.Id);
        }

        System.assertEquals(supportCase.CaseNumber, result.caseInfo.caseNumber);
        System.assertEquals(canReadSubscriptions, result.subscriptionAccessible);
        if (!canReadSubscriptions) {
            System.assertEquals(null, result.subscription, 'Inaccessible subscription data must not be returned.');
        }
        System.assertEquals(canReadHistory, result.historyAccessible);
        if (!canReadHistory) {
            System.assertEquals(0, result.history.size(), 'Inaccessible history must not be returned.');
        }
        if (!canReadSlaStatus) {
            System.assertEquals(null, result.sla.slaStatus, 'Inaccessible SLA fields must be stripped.');
        }
    }

    @IsTest
    static void userWithoutCaseAccessReceivesControlledError() {
        User restrictedUser = minimumAccessUser();
        if (restrictedUser == null) {
            return; // The org has no minimum-access profile; object-level denial cannot be simulated.
        }
        Id caseId = loadCase(CONNECTED_SUBJECT).Id;

        System.runAs(restrictedUser) {
            assertLoadFails(caseId);
        }
    }

    @IsTest
    static void openUnrespondedCaseAllowsFirstResponse() {
        CaseSupportConsoleDTO result = loadAsAgent(loadCase(CONNECTED_SUBJECT).Id);

        System.assertEquals(true, result.canMarkFirstResponse);
    }

    @IsTest
    static void closedCaseDoesNotAllowFirstResponse() {
        Case supportCase = loadCase(CONNECTED_SUBJECT);
        closeCase(supportCase.Id);

        CaseSupportConsoleDTO result = loadAsAgent(supportCase.Id);

        System.assertEquals(true, result.caseInfo.isClosed);
        System.assertNotEquals(null, result.caseInfo.closedDate);
        System.assertEquals(false, result.canMarkFirstResponse);
    }

    @IsTest
    static void markFirstResponseUsesServerTimeWithoutChangingSlaState() {
        Case before = loadCase(CONNECTED_SUBJECT);
        Datetime startedAt = System.now();

        Datetime respondedAt;
        Test.startTest();
        System.runAs(agentUser()) {
            respondedAt = CaseSupportConsoleController.markFirstResponse(before.Id);
        }
        Test.stopTest();

        Case after = loadCase(CONNECTED_SUBJECT);
        System.assertEquals(respondedAt, after.First_Responded_At__c);
        System.assert(after.First_Responded_At__c >= startedAt.addSeconds(-1), 'Server time must be used.');
        System.assertEquals(before.SLA_Status__c, after.SLA_Status__c, 'SLA Status is owned by the SLA engine.');
        System.assertEquals(before.SLA_Breached__c, after.SLA_Breached__c);
        System.assertEquals(before.Escalation_Level__c, after.Escalation_Level__c);
        System.assertEquals(before.Escalated_At__c, after.Escalated_At__c);
    }

    @IsTest
    static void markFirstResponseRejectsExistingResponse() {
        Case supportCase = loadCase(CONNECTED_SUBJECT);
        Datetime originalResponse = System.now().addMinutes(-15);
        update new Case(Id = supportCase.Id, First_Responded_At__c = originalResponse);

        assertMarkFails(supportCase.Id, CaseSupportConsoleController.FIRST_RESPONSE_EXISTS_MESSAGE);
        System.assertEquals(originalResponse, loadCase(CONNECTED_SUBJECT).First_Responded_At__c);
    }

    @IsTest
    static void markFirstResponseRejectsClosedCase() {
        Case supportCase = loadCase(CONNECTED_SUBJECT);
        closeCase(supportCase.Id);

        assertMarkFails(supportCase.Id, CaseSupportConsoleController.FIRST_RESPONSE_CLOSED_MESSAGE);
        System.assertEquals(null, loadCase(CONNECTED_SUBJECT).First_Responded_At__c);
    }

    @IsTest
    static void markFirstResponseRejectsInvalidIds() {
        assertMarkFails(null, CaseSupportConsoleController.FIRST_RESPONSE_ERROR_MESSAGE);
        assertMarkFails([SELECT Id FROM Account LIMIT 1].Id, CaseSupportConsoleController.FIRST_RESPONSE_ERROR_MESSAGE);
    }

    private static CaseSupportConsoleDTO loadAsAgent(Id caseId) {
        CaseSupportConsoleDTO result;
        System.runAs(agentUser()) {
            result = CaseSupportConsoleController.getConsoleData(caseId);
        }
        return result;
    }

    private static void assertLoadFails(Id caseId) {
        try {
            CaseSupportConsoleController.getConsoleData(caseId);
            System.assert(false, 'Expected a controlled error.');
        } catch (AuraHandledException error) {
            System.assertEquals(CaseSupportConsoleController.LOAD_ERROR_MESSAGE, error.getMessage());
        }
    }

    private static void assertMarkFails(Id caseId, String expectedMessage) {
        System.runAs(agentUser()) {
            try {
                CaseSupportConsoleController.markFirstResponse(caseId);
                System.assert(false, 'Expected a controlled error.');
            } catch (AuraHandledException error) {
                System.assertEquals(expectedMessage, error.getMessage());
            }
        }
    }

    private static Case loadCase(String subject) {
        return [
            SELECT Id, CaseNumber, AccountId, ContactId, AssetId, OwnerId, SLA_Status__c, SLA_Breached__c,
                Escalation_Level__c, Escalated_At__c, First_Response_Due__c, First_Responded_At__c, Resolution_Due__c
            FROM Case
            WHERE Subject = :subject
            LIMIT 1
        ];
    }

    private static void closeCase(Id caseId) {
        update new Case(Id = caseId, Status = [SELECT MasterLabel FROM CaseStatus WHERE IsClosed = true LIMIT 1].MasterLabel);
    }

    private static SLA_Escalation_History__c history(
        Id caseId,
        Datetime escalatedAt,
        String previousStatus,
        String newStatus,
        String level,
        String slaType
    ) {
        return new SLA_Escalation_History__c(
            Case__c = caseId,
            Escalated_At__c = escalatedAt,
            Previous_SLA_Status__c = previousStatus,
            New_SLA_Status__c = newStatus,
            Escalation_Level__c = level,
            SLA_Type__c = slaType,
            SLA_Due_At__c = escalatedAt.addMinutes(-15),
            Reason__c = 'Test escalation reason'
        );
    }

    private static User agentUser() {
        return [SELECT Id FROM User WHERE Username LIKE :AGENT_USERNAME_PREFIX + '%' LIMIT 1];
    }

    private static User basicUser() {
        return [SELECT Id FROM User WHERE Username LIKE :BASIC_USERNAME_PREFIX + '%' LIMIT 1];
    }

    private static User minimumAccessUser() {
        List<Profile> profiles = [SELECT Id FROM Profile WHERE Name = 'Minimum Access - Salesforce' LIMIT 1];
        if (profiles.isEmpty()) {
            return null;
        }
        User restrictedUser = createUser('novacare.console.restricted', null);
        restrictedUser.ProfileId = profiles[0].Id;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert restrictedUser;
        }
        return restrictedUser;
    }

    private static User createUser(String usernamePrefix, String profileName) {
        String uniqueSuffix = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
        User newUser = new User(
            Username = usernamePrefix + '.' + uniqueSuffix + '@novacare.test',
            Email = usernamePrefix + '@novacare.test',
            LastName = 'Console Tester',
            Alias = 'nctest',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        if (profileName != null) {
            newUser.ProfileId = [SELECT Id FROM Profile WHERE Name = :profileName LIMIT 1].Id;
        }
        return newUser;
    }
}
