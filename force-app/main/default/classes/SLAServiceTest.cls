@IsTest
private class SLAServiceTest {
    private static final String STATUS_ACTIVE = 'Active';
    private static final String STATUS_EXPIRED = 'Expired';
    private static final String SLA_STATUS_ON_TRACK = 'On Track';
    private static final String ESCALATION_LEVEL_NONE = 'None';

    @TestSetup
    static void setupData() {
        Account account = new Account(Name = 'NovaCare Test Account');
        insert account;

        insert new List<Support_Subscription__c>{
            createSubscription(account.Id, 'Standard', STATUS_ACTIVE),
            createSubscription(account.Id, 'Premium', STATUS_ACTIVE),
            createSubscription(account.Id, 'Enterprise', STATUS_ACTIVE),
            createSubscription(account.Id, 'Enterprise', STATUS_EXPIRED),
            createSubscription(account.Id, null, STATUS_ACTIVE)
        };
    }

    @IsTest
    static void enterpriseCriticalReceivesConfiguredSla() {
        Case insertedCase = insertAndReload(createCase(subscriptionId('Enterprise', STATUS_ACTIVE), 'Critical'), 30, 240);

        assertSlaInitialized(insertedCase);
    }

    @IsTest
    static void premiumHighReceivesConfiguredSla() {
        Case insertedCase = insertAndReload(createCase(subscriptionId('Premium', STATUS_ACTIVE), 'High'), 120, 720);

        assertSlaInitialized(insertedCase);
    }

    @IsTest
    static void standardLowReceivesConfiguredSla() {
        Case insertedCase = insertAndReload(createCase(subscriptionId('Standard', STATUS_ACTIVE), 'Low'), 1440, 4320);

        assertSlaInitialized(insertedCase);
    }

    @IsTest
    static void missingSupportSubscriptionSkipsSlaCalculation() {
        Case insertedCase = insertAndReload(createCase(null, 'Critical'));

        assertSlaSkipped(insertedCase);
    }

    @IsTest
    static void inactiveSupportSubscriptionSkipsSlaCalculation() {
        Case insertedCase = insertAndReload(createCase(subscriptionId('Enterprise', STATUS_EXPIRED), 'Critical'));

        assertSlaSkipped(insertedCase);
    }

    @IsTest
    static void missingPrioritySkipsSlaCalculation() {
        Case insertedCase = insertAndReload(createCase(subscriptionId('Enterprise', STATUS_ACTIVE), null));

        assertSlaSkipped(insertedCase);
    }

    @IsTest
    static void bulkInsertInitializesAllEligibleCases() {
        Id subscriptionId = subscriptionId('Enterprise', STATUS_ACTIVE);
        List<Case> casesToInsert = new List<Case>();
        for (Integer i = 0; i < 200; i++) {
            casesToInsert.add(createCase(subscriptionId, 'Critical'));
        }

        Test.startTest();
        insert casesToInsert;
        Test.stopTest();

        for (Case insertedCase : queryCases(casesToInsert)) {
            System.assertNotEquals(null, insertedCase.First_Response_Due__c, 'Expected first response due date for every eligible bulk Case.');
            System.assertNotEquals(null, insertedCase.Resolution_Due__c, 'Expected resolution due date for every eligible bulk Case.');
            assertSlaInitialized(insertedCase);
        }
    }

    @IsTest
    static void mixedBulkTransactionAppliesCorrectPolicies() {
        Id standardSubscriptionId = subscriptionId('Standard', STATUS_ACTIVE);
        Id premiumSubscriptionId = subscriptionId('Premium', STATUS_ACTIVE);
        Id enterpriseSubscriptionId = subscriptionId('Enterprise', STATUS_ACTIVE);

        List<Case> casesToInsert = new List<Case>{
            createCase(standardSubscriptionId, 'Medium'),
            createCase(premiumSubscriptionId, 'Critical'),
            createCase(enterpriseSubscriptionId, 'High')
        };

        Datetime beforeInsert = System.now();
        Test.startTest();
        insert casesToInsert;
        Test.stopTest();
        Datetime afterInsert = System.now();

        Map<String, Case> casesBySubject = new Map<String, Case>();
        for (Case insertedCase : queryCases(casesToInsert)) {
            casesBySubject.put(insertedCase.Subject, insertedCase);
        }

        assertDueDatesWithinTolerance(casesBySubject.get(casesToInsert[0].Subject), beforeInsert, afterInsert, 480, 2880);
        assertDueDatesWithinTolerance(casesBySubject.get(casesToInsert[1].Subject), beforeInsert, afterInsert, 60, 480);
        assertDueDatesWithinTolerance(casesBySubject.get(casesToInsert[2].Subject), beforeInsert, afterInsert, 60, 480);
    }

    @IsTest
    static void missingSupportPlanSkipsSlaCalculation() {
        Case insertedCase = insertAndReload(createCase(subscriptionId(null, STATUS_ACTIVE), 'Critical'));

        assertSlaSkipped(insertedCase);
    }

    @IsTest
    static void unavailablePolicySkipsSlaCalculation() {
        Case supportCase = createCase(subscriptionId('Enterprise', STATUS_ACTIVE), 'No Matching Policy');

        Test.startTest();
        SLAService.applyInitialSla(new List<Case>{ supportCase });
        Test.stopTest();

        assertSlaSkipped(supportCase);
    }

    private static Support_Subscription__c createSubscription(Id accountId, String supportPlan, String status) {
        return new Support_Subscription__c(
            Account__c = accountId,
            Support_Plan__c = supportPlan,
            Status__c = status,
            Start_Date__c = Date.today(),
            End_Date__c = Date.today().addYears(1),
            X24x7_Support__c = supportPlan == 'Enterprise'
        );
    }

    private static Case createCase(Id subscriptionId, String priority) {
        return new Case(
            Subject = 'SLA Test ' + String.valueOf(Crypto.getRandomInteger()),
            Status = 'New',
            Origin = 'Phone',
            Priority = priority,
            Support_Subscription__c = subscriptionId
        );
    }

    private static Id subscriptionId(String supportPlan, String status) {
        List<Support_Subscription__c> subscriptions = [
            SELECT Id
            FROM Support_Subscription__c
            WHERE Support_Plan__c = :supportPlan
            AND Status__c = :status
            LIMIT 1
        ];
        System.assertEquals(1, subscriptions.size(), 'Expected test subscription to exist.');
        return subscriptions[0].Id;
    }

    private static Case insertAndReload(Case supportCase) {
        insert supportCase;
        return queryCase(supportCase.Id);
    }

    private static Case insertAndReload(Case supportCase, Integer expectedFirstResponseMinutes, Integer expectedResolutionMinutes) {
        Datetime beforeInsert = System.now();
        insert supportCase;
        Datetime afterInsert = System.now();

        Case insertedCase = queryCase(supportCase.Id);
        assertDueDatesWithinTolerance(insertedCase, beforeInsert, afterInsert, expectedFirstResponseMinutes, expectedResolutionMinutes);
        return insertedCase;
    }

    private static Case queryCase(Id caseId) {
        return [
            SELECT First_Response_Due__c, Resolution_Due__c, SLA_Status__c, SLA_Breached__c, Escalation_Level__c
            FROM Case
            WHERE Id = :caseId
        ];
    }

    private static List<Case> queryCases(List<Case> casesToQuery) {
        Set<Id> caseIds = new Set<Id>();
        for (Case supportCase : casesToQuery) {
            caseIds.add(supportCase.Id);
        }
        return [
            SELECT Subject, First_Response_Due__c, Resolution_Due__c, SLA_Status__c, SLA_Breached__c, Escalation_Level__c
            FROM Case
            WHERE Id IN :caseIds
        ];
    }

    private static void assertSlaInitialized(Case insertedCase) {
        System.assertEquals(SLA_STATUS_ON_TRACK, insertedCase.SLA_Status__c, 'Expected SLA status to be initialized.');
        System.assertEquals(false, insertedCase.SLA_Breached__c, 'Expected SLA breached to initialize as false.');
        System.assertEquals(ESCALATION_LEVEL_NONE, insertedCase.Escalation_Level__c, 'Expected escalation level to initialize as None.');
    }

    private static void assertSlaSkipped(Case insertedCase) {
        System.assertEquals(null, insertedCase.First_Response_Due__c, 'Expected first response due date to remain blank.');
        System.assertEquals(null, insertedCase.Resolution_Due__c, 'Expected resolution due date to remain blank.');
        System.assertEquals(null, insertedCase.SLA_Status__c, 'Expected SLA status to remain blank.');
        System.assertEquals(false, insertedCase.SLA_Breached__c, 'Checkbox default should remain false when SLA calculation is skipped.');
        System.assertEquals(null, insertedCase.Escalation_Level__c, 'Expected escalation level to remain blank.');
    }

    private static void assertDueDatesWithinTolerance(
        Case insertedCase,
        Datetime beforeInsert,
        Datetime afterInsert,
        Integer expectedFirstResponseMinutes,
        Integer expectedResolutionMinutes
    ) {
        System.assert(
            insertedCase.First_Response_Due__c >= beforeInsert.addMinutes(expectedFirstResponseMinutes).addMinutes(-2)
                && insertedCase.First_Response_Due__c <= afterInsert.addMinutes(expectedFirstResponseMinutes).addMinutes(2),
            'First response due date should match configured calendar-minute SLA.'
        );
        System.assert(
            insertedCase.Resolution_Due__c >= beforeInsert.addMinutes(expectedResolutionMinutes).addMinutes(-2)
                && insertedCase.Resolution_Due__c <= afterInsert.addMinutes(expectedResolutionMinutes).addMinutes(2),
            'Resolution due date should match configured calendar-minute SLA.'
        );
        System.assertEquals(
            expectedResolutionMinutes - expectedFirstResponseMinutes,
            minutesBetween(insertedCase.First_Response_Due__c, insertedCase.Resolution_Due__c),
            'Expected deadline gap to match configured response/resolution duration difference.'
        );
    }

    private static Integer minutesBetween(Datetime startTime, Datetime endTime) {
        Long millisecondsBetween = endTime.getTime() - startTime.getTime();
        return Integer.valueOf(String.valueOf(millisecondsBetween / (1000 * 60)));
    }
}