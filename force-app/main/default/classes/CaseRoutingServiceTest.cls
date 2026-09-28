@IsTest
private class CaseRoutingServiceTest {
    private static final String STATUS_ACTIVE = 'Active';

    @TestSetup
    static void setupSlaData() {
        Account account = new Account(Name = 'Routing SLA Account');
        insert account;
        insert new Support_Subscription__c(
            Account__c = account.Id,
            Support_Plan__c = 'Enterprise',
            Status__c = STATUS_ACTIVE,
            Start_Date__c = Date.today(),
            End_Date__c = Date.today().addYears(1),
            X24x7_Support__c = true
        );
    }

    @IsTest
    static void technicalHighRoutesToTechnicalSupport() {
        assertInsertedCaseOwner('Technical', 'High', 'Technical_Support');
    }

    @IsTest
    static void integrationHighRoutesToIntegrationSupport() {
        assertInsertedCaseOwner('Integration', 'High', 'Integration_Support');
    }

    @IsTest
    static void integrationCriticalRoutesToCriticalSupport() {
        assertInsertedCaseOwner('Integration', 'Critical', 'Critical_Support');
    }

    @IsTest
    static void billingMediumRoutesToBillingSupport() {
        assertInsertedCaseOwner('Billing', 'Medium', 'Billing_Support');
    }

    @IsTest
    static void accessLowRoutesToAccessSupport() {
        assertInsertedCaseOwner('Access', 'Low', 'Access_Support');
    }

    @IsTest
    static void productHighRoutesToProductSupport() {
        assertInsertedCaseOwner('Product', 'High', 'Product_Support');
    }

    @IsTest
    static void serviceMediumRoutesToServiceSupport() {
        assertInsertedCaseOwner('Service', 'Medium', 'Service_Support');
    }

    @IsTest
    static void unmatchedCategoryUsesGeneralSupportFallback() {
        assertInsertedCaseOwner('Other', 'Medium', 'General_Support');
    }

    @IsTest
    static void missingCategoryUsesGeneralSupportFallback() {
        assertInsertedCaseOwner(null, 'Medium', 'General_Support');
    }

    @IsTest
    static void missingPriorityUsesGeneralSupportFallback() {
        assertInsertedCaseOwner('Other', null, 'General_Support');
    }

    @IsTest
    static void missingTargetQueueLeavesOwnerUnchanged() {
        Case supportCase = createCase('Technical', 'High');
        Case_Routing_Rule__mdt rule = routingRule(
            'Missing_Queue_Rule',
            'Technical',
            'High',
            'Queue_That_Does_Not_Exist',
            10
        );

        Test.startTest();
        CaseRoutingService.applyRouting(
            new List<Case>{ supportCase },
            new List<Case_Routing_Rule__mdt>{ rule },
            new Map<String, Id>()
        );
        Test.stopTest();

        System.assertEquals(null, supportCase.OwnerId, 'A missing target queue must leave the owner unchanged.');
    }

    @IsTest
    static void explicitOwnerIsPreserved() {
        Case supportCase = createCase('Technical', 'High');
        Id explicitOwnerId = queueId('General_Support');
        supportCase.OwnerId = explicitOwnerId;

        insert supportCase;

        System.assertEquals(
            explicitOwnerId,
            [SELECT OwnerId FROM Case WHERE Id = :supportCase.Id].OwnerId,
            'Routing must preserve a caller-supplied owner.'
        );
    }

    @IsTest
    static void lowerRoutingPriorityWinsForDuplicateRules() {
        Id technicalQueueId = queueId('Technical_Support');
        Id criticalQueueId = queueId('Critical_Support');
        Case supportCase = createCase('Technical', 'High');
        List<Case_Routing_Rule__mdt> duplicateRules = new List<Case_Routing_Rule__mdt>{
            routingRule('Lower_Precedence', 'Technical', 'High', 'Technical_Support', 20),
            routingRule('Higher_Precedence', 'Technical', 'High', 'Critical_Support', 10)
        };

        CaseRoutingService.applyRouting(
            new List<Case>{ supportCase },
            duplicateRules,
            new Map<String, Id>{
                'Technical_Support' => technicalQueueId,
                'Critical_Support' => criticalQueueId
            }
        );

        System.assertEquals(criticalQueueId, supportCase.OwnerId, 'The lowest routing priority must win.');
    }

    @IsTest
    static void bulkInsertRoutesTwoHundredCases() {
        List<Case> casesToInsert = new List<Case>();
        for (Integer index = 0; index < 200; index++) {
            casesToInsert.add(createCase('Technical', 'High'));
        }

        Test.startTest();
        insert casesToInsert;
        Test.stopTest();

        Id expectedOwnerId = queueId('Technical_Support');
        Set<Id> insertedCaseIds = caseIds(casesToInsert);
        for (Case insertedCase : [SELECT OwnerId FROM Case WHERE Id IN :insertedCaseIds]) {
            System.assertEquals(expectedOwnerId, insertedCase.OwnerId, 'Every eligible bulk Case must be routed.');
        }
    }

    @IsTest
    static void mixedTransactionUsesExactRulesAndFallback() {
        List<Case> casesToInsert = new List<Case>{
            createCase('Technical', 'High'),
            createCase('Integration', 'Critical'),
            createCase('Billing', 'Medium'),
            createCase('Product', 'Low'),
            createCase('Other', 'Medium')
        };

        insert casesToInsert;

        Map<String, Id> expectedQueuesBySubject = new Map<String, Id>{
            casesToInsert[0].Subject => queueId('Technical_Support'),
            casesToInsert[1].Subject => queueId('Critical_Support'),
            casesToInsert[2].Subject => queueId('Billing_Support'),
            casesToInsert[3].Subject => queueId('Product_Support'),
            casesToInsert[4].Subject => queueId('General_Support')
        };
        Set<Id> insertedCaseIds = caseIds(casesToInsert);
        for (Case insertedCase : [SELECT Subject, OwnerId FROM Case WHERE Id IN :insertedCaseIds]) {
            System.assertEquals(
                expectedQueuesBySubject.get(insertedCase.Subject),
                insertedCase.OwnerId,
                'Each Case must use its independently selected routing rule.'
            );
        }
    }

    @IsTest
    static void routingAndSlaInitializationRunTogether() {
        Id subscriptionId = [
            SELECT Id
            FROM Support_Subscription__c
            WHERE Support_Plan__c = 'Enterprise'
            AND Status__c = :STATUS_ACTIVE
            LIMIT 1
        ].Id;
        Case supportCase = createCase('Integration', 'Critical');
        supportCase.Support_Subscription__c = subscriptionId;

        insert supportCase;

        Case insertedCase = [
            SELECT OwnerId, First_Response_Due__c, Resolution_Due__c,
                SLA_Status__c, SLA_Breached__c, Escalation_Level__c
            FROM Case
            WHERE Id = :supportCase.Id
        ];
        System.assertEquals(queueId('Critical_Support'), insertedCase.OwnerId, 'Expected queue routing.');
        System.assertNotEquals(null, insertedCase.First_Response_Due__c, 'Expected first response SLA.');
        System.assertNotEquals(null, insertedCase.Resolution_Due__c, 'Expected resolution SLA.');
        System.assertEquals('On Track', insertedCase.SLA_Status__c, 'Expected initialized SLA status.');
        System.assertEquals(false, insertedCase.SLA_Breached__c, 'Expected non-breached initial SLA.');
        System.assertEquals('None', insertedCase.Escalation_Level__c, 'Expected initial escalation level.');
    }

    private static void assertInsertedCaseOwner(String issueCategory, String priority, String queueDeveloperName) {
        Case supportCase = createCase(issueCategory, priority);
        insert supportCase;

        System.assertEquals(
            queueId(queueDeveloperName),
            [SELECT OwnerId FROM Case WHERE Id = :supportCase.Id].OwnerId,
            'Case was not assigned to the configured queue.'
        );
    }

    private static Case createCase(String issueCategory, String priority) {
        return new Case(
            Subject = 'Routing Test ' + String.valueOf(Crypto.getRandomInteger()),
            Status = 'New',
            Origin = 'Phone',
            Priority = priority,
            Issue_Category__c = issueCategory
        );
    }

    private static Id queueId(String developerName) {
        List<Group> queues = [
            SELECT Id
            FROM Group
            WHERE Type = 'Queue'
            AND DeveloperName = :developerName
            AND Id IN (
                SELECT QueueId
                FROM QueueSobject
                WHERE SobjectType = 'Case'
            )
            LIMIT 1
        ];
        System.assertEquals(1, queues.size(), 'Expected Case queue to exist: ' + developerName);
        return queues[0].Id;
    }

    private static Set<Id> caseIds(List<Case> supportCases) {
        Set<Id> caseIds = new Set<Id>();
        for (Case supportCase : supportCases) {
            caseIds.add(supportCase.Id);
        }
        return caseIds;
    }

    private static Case_Routing_Rule__mdt routingRule(
        String developerName,
        String issueCategory,
        String priority,
        String targetQueue,
        Decimal routingPriority
    ) {
        return new Case_Routing_Rule__mdt(
            DeveloperName = developerName,
            Issue_Category__c = issueCategory,
            Priority__c = priority,
            Target_Queue_Developer_Name__c = targetQueue,
            Routing_Priority__c = routingPriority,
            Active__c = true
        );
    }
}