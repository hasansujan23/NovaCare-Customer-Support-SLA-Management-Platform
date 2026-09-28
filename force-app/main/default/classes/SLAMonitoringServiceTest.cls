@IsTest
private class SLAMonitoringServiceTest {
    private static final String STATUS_ON_TRACK = 'On Track';
    private static final String STATUS_AT_RISK = 'At Risk';
    private static final String STATUS_BREACHED = 'Breached';
    private static final String STATUS_COMPLETED = 'Completed';
    private static final String LEVEL_NONE = 'None';
    private static final String LEVEL_ONE = 'Level 1';
    private static final String LEVEL_TWO = 'Level 2';

    @TestSetup
    static void setupSubscription() {
        Account account = new Account(Name = 'SLA Monitoring Account');
        insert account;
        insert new Support_Subscription__c(
            Account__c = account.Id,
            Support_Plan__c = 'Enterprise',
            Status__c = 'Active',
            Start_Date__c = Date.today(),
            End_Date__c = Date.today().addYears(1),
            X24x7_Support__c = true
        );
    }

    @IsTest
    static void onTrackCaseRemainsOnTrackWithoutHistory() {
        Datetime evaluationTime = System.now();
        Case supportCase = createMonitoredCase();
        setState(supportCase, evaluationTime.addMinutes(10), evaluationTime.addMinutes(60), null,
            STATUS_ON_TRACK, false, LEVEL_NONE, null);

        processAt(supportCase.Id, evaluationTime);

        Case result = loadCase(supportCase.Id);
        System.assertEquals(STATUS_ON_TRACK, result.SLA_Status__c);
        System.assertEquals(LEVEL_NONE, result.Escalation_Level__c);
        System.assertEquals(0, historyFor(supportCase.Id).size());
    }

    @IsTest
    static void firstResponseAtRiskAtDueBoundaryCreatesLevelOneHistory() {
        Datetime evaluationTime = System.now();
        Case supportCase = createMonitoredCase();
        setState(supportCase, evaluationTime, evaluationTime.addHours(2), null,
            STATUS_ON_TRACK, false, LEVEL_NONE, null);
        evaluationTime = loadCase(supportCase.Id).First_Response_Due__c;

        processAt(supportCase.Id, evaluationTime);

        assertEscalated(supportCase.Id, STATUS_AT_RISK, false, LEVEL_ONE, evaluationTime);
        assertSingleHistory(supportCase.Id, STATUS_ON_TRACK, STATUS_AT_RISK, LEVEL_ONE, 'First Response');
    }

    @IsTest
    static void firstResponseBreachCreatesLevelTwoHistory() {
        Datetime evaluationTime = System.now();
        Case supportCase = createMonitoredCase();
        setState(supportCase, evaluationTime.addMinutes(-1), evaluationTime.addHours(2), null,
            STATUS_ON_TRACK, false, LEVEL_NONE, null);

        processAt(supportCase.Id, evaluationTime);

        assertEscalated(supportCase.Id, STATUS_BREACHED, true, LEVEL_TWO, evaluationTime);
        assertSingleHistory(supportCase.Id, STATUS_ON_TRACK, STATUS_BREACHED, LEVEL_TWO, 'First Response');
    }

    @IsTest
    static void onTimeFirstResponseSwitchesToHealthyResolutionSla() {
        Datetime evaluationTime = System.now();
        Case supportCase = createMonitoredCase();
        setState(supportCase, evaluationTime, evaluationTime.addMinutes(60), evaluationTime.addMinutes(-5),
            STATUS_AT_RISK, false, LEVEL_ONE, evaluationTime.addMinutes(-10));

        processAt(supportCase.Id, evaluationTime);

        Case result = loadCase(supportCase.Id);
        System.assertEquals(STATUS_ON_TRACK, result.SLA_Status__c);
        System.assertEquals(false, result.SLA_Breached__c);
        System.assertEquals(0, historyFor(supportCase.Id).size());
    }

    @IsTest
    static void lateFirstResponseRetainsHistoricalBreachWhileMonitoringResolution() {
        Datetime evaluationTime = System.now();
        Case supportCase = createMonitoredCase();
        setState(supportCase, evaluationTime.addMinutes(-10), evaluationTime.addMinutes(60),
            evaluationTime.addMinutes(-5), STATUS_ON_TRACK, false, LEVEL_NONE, null);

        processAt(supportCase.Id, evaluationTime);

        Case result = loadCase(supportCase.Id);
        System.assertEquals(STATUS_ON_TRACK, result.SLA_Status__c, 'Resolution SLA is currently healthy.');
        System.assertEquals(true, result.SLA_Breached__c, 'The late first response must remain historical fact.');
        System.assertEquals(LEVEL_TWO, result.Escalation_Level__c);
        assertSingleHistory(supportCase.Id, STATUS_ON_TRACK, STATUS_BREACHED, LEVEL_TWO, 'First Response');
    }

    @IsTest
    static void resolutionAtRiskCreatesResolutionHistory() {
        Datetime evaluationTime = System.now();
        Case supportCase = createMonitoredCase();
        setState(supportCase, evaluationTime.addMinutes(10), evaluationTime.addMinutes(20),
            evaluationTime.addMinutes(-5), STATUS_ON_TRACK, false, LEVEL_NONE, null);

        processAt(supportCase.Id, evaluationTime);

        assertEscalated(supportCase.Id, STATUS_AT_RISK, false, LEVEL_ONE, evaluationTime);
        assertSingleHistory(supportCase.Id, STATUS_ON_TRACK, STATUS_AT_RISK, LEVEL_ONE, 'Resolution');
    }

    @IsTest
    static void resolutionBreachCreatesResolutionHistory() {
        Datetime evaluationTime = System.now();
        Case supportCase = createMonitoredCase();
        setState(supportCase, evaluationTime.addMinutes(10), evaluationTime.addMinutes(-1),
            evaluationTime.addMinutes(-5), STATUS_ON_TRACK, false, LEVEL_NONE, null);

        processAt(supportCase.Id, evaluationTime);

        assertEscalated(supportCase.Id, STATUS_BREACHED, true, LEVEL_TWO, evaluationTime);
        assertSingleHistory(supportCase.Id, STATUS_ON_TRACK, STATUS_BREACHED, LEVEL_TWO, 'Resolution');
    }

    @IsTest
    static void repeatedAtRiskProcessingIsIdempotent() {
        Datetime evaluationTime = System.now();
        Datetime originalEscalationTime = evaluationTime.addMinutes(-5);
        Case supportCase = createMonitoredCase();
        setState(supportCase, evaluationTime.addMinutes(5), evaluationTime.addHours(2), null,
            STATUS_AT_RISK, false, LEVEL_ONE, originalEscalationTime);

        processAt(supportCase.Id, evaluationTime);

        Case result = loadCase(supportCase.Id);
        System.assertEquals(originalEscalationTime, result.Escalated_At__c);
        System.assertEquals(0, historyFor(supportCase.Id).size());
    }

    @IsTest
    static void repeatedBreachProcessingIsIdempotent() {
        Datetime evaluationTime = System.now();
        Datetime originalEscalationTime = evaluationTime.addMinutes(-5);
        Case supportCase = createMonitoredCase();
        setState(supportCase, evaluationTime.addMinutes(-5), evaluationTime.addHours(2), null,
            STATUS_BREACHED, true, LEVEL_TWO, originalEscalationTime);

        processAt(supportCase.Id, evaluationTime);

        Case result = loadCase(supportCase.Id);
        System.assertEquals(originalEscalationTime, result.Escalated_At__c);
        System.assertEquals(0, historyFor(supportCase.Id).size());
    }

    @IsTest
    static void atRiskTransitionsToBreachWithSecondHistory() {
        Datetime evaluationTime = System.now();
        Case supportCase = createMonitoredCase();
        setState(supportCase, evaluationTime.addMinutes(-1), evaluationTime.addHours(2), null,
            STATUS_AT_RISK, false, LEVEL_ONE, evaluationTime.addMinutes(-10));
        insert historyRecord(supportCase.Id, STATUS_ON_TRACK, STATUS_AT_RISK, LEVEL_ONE,
            'First Response', evaluationTime.addMinutes(-10), supportCase.First_Response_Due__c);

        processAt(supportCase.Id, evaluationTime);

        assertEscalated(supportCase.Id, STATUS_BREACHED, true, LEVEL_TWO, evaluationTime);
        System.assertEquals(2, historyFor(supportCase.Id).size(), 'Expected one risk and one breach event.');
    }

    @IsTest
    static void directOnTrackToBreachCreatesOnlyBreachHistory() {
        Datetime evaluationTime = System.now();
        Case supportCase = createMonitoredCase();
        setState(supportCase, evaluationTime.addMinutes(-20), evaluationTime.addHours(2), null,
            STATUS_ON_TRACK, false, LEVEL_NONE, null);

        processAt(supportCase.Id, evaluationTime);

        assertEscalated(supportCase.Id, STATUS_BREACHED, true, LEVEL_TWO, evaluationTime);
        List<SLA_Escalation_History__c> histories = historyFor(supportCase.Id);
        System.assertEquals(1, histories.size());
        System.assertEquals(LEVEL_TWO, histories[0].Escalation_Level__c);
    }

    @IsTest
    static void closedBeforeBreachCompletesWithoutHistory() {
        Datetime evaluationTime = System.now();
        Case supportCase = createMonitoredCase();
        setState(supportCase, evaluationTime.addMinutes(10), evaluationTime.addHours(2), null,
            STATUS_ON_TRACK, false, LEVEL_NONE, null);
        closeCase(supportCase.Id);

        processAt(supportCase.Id, evaluationTime);

        Case result = loadCase(supportCase.Id);
        System.assertEquals(STATUS_COMPLETED, result.SLA_Status__c);
        System.assertEquals(false, result.SLA_Breached__c);
        System.assertEquals(0, historyFor(supportCase.Id).size());
    }

    @IsTest
    static void closedAfterBreachCompletesAndPreservesBreach() {
        Datetime evaluationTime = System.now();
        Case supportCase = createMonitoredCase();
        setState(supportCase, evaluationTime.addMinutes(-10), evaluationTime.addHours(2), null,
            STATUS_BREACHED, true, LEVEL_TWO, evaluationTime.addMinutes(-5));
        closeCase(supportCase.Id);

        processAt(supportCase.Id, evaluationTime);

        Case result = loadCase(supportCase.Id);
        System.assertEquals(STATUS_COMPLETED, result.SLA_Status__c);
        System.assertEquals(true, result.SLA_Breached__c);
        System.assertEquals(0, historyFor(supportCase.Id).size());
    }

    @IsTest
    static void missingSubscriptionIsSkipped() {
        Datetime evaluationTime = System.now();
        Case supportCase = createMonitoredCase();
        supportCase.Support_Subscription__c = null;
        setState(supportCase, evaluationTime.addMinutes(-1), evaluationTime.addHours(2), null,
            STATUS_ON_TRACK, false, LEVEL_NONE, null);

        processAt(supportCase.Id, evaluationTime);

        Case result = loadCase(supportCase.Id);
        System.assertEquals(STATUS_ON_TRACK, result.SLA_Status__c);
        System.assertEquals(0, historyFor(supportCase.Id).size());
    }

    @IsTest
    static void missingPolicyIsSkippedThroughConfigurationSeam() {
        Datetime evaluationTime = System.now();
        Case supportCase = createMonitoredCase();
        setState(supportCase, evaluationTime.addMinutes(-1), evaluationTime.addHours(2), null,
            STATUS_ON_TRACK, false, LEVEL_NONE, null);
        Case loadedCase = loadCase(supportCase.Id);
        Support_Subscription__c subscription = [
            SELECT Id, Support_Plan__c
            FROM Support_Subscription__c
            WHERE Id = :loadedCase.Support_Subscription__c
        ];

        SLAMonitoringService.processWithConfiguration(
            new List<Case>{ loadedCase },
            evaluationTime,
            new Map<Id, Support_Subscription__c>{ subscription.Id => subscription },
            new Map<String, Support_SLA_Policy__mdt>()
        );

        System.assertEquals(STATUS_ON_TRACK, loadCase(supportCase.Id).SLA_Status__c);
        System.assertEquals(0, historyFor(supportCase.Id).size());
    }

    @IsTest
    static void bulkMixedScopeProcessesCasesIndependently() {
        Datetime evaluationTime = System.now();
        List<Case> casesToInsert = new List<Case>();
        for (Integer index = 0; index < 40; index++) {
            casesToInsert.add(baseCase());
        }
        insert casesToInsert;

        String closedStatus = closedStatusValue();
        for (Integer index = 0; index < casesToInsert.size(); index++) {
            Case supportCase = casesToInsert[index];
            supportCase.SLA_Status__c = STATUS_ON_TRACK;
            supportCase.SLA_Breached__c = false;
            supportCase.Escalation_Level__c = LEVEL_NONE;
            supportCase.Resolution_Due__c = evaluationTime.addHours(2);
            if (index < 10) {
                supportCase.First_Response_Due__c = evaluationTime.addMinutes(10);
            } else if (index < 20) {
                supportCase.First_Response_Due__c = evaluationTime.addMinutes(5);
            } else if (index < 30) {
                supportCase.First_Response_Due__c = evaluationTime.addMinutes(-1);
            } else {
                supportCase.First_Response_Due__c = evaluationTime.addMinutes(10);
                supportCase.Status = closedStatus;
            }
        }
        update casesToInsert;

        SLAMonitoringService.processAt(loadCases(caseIds(casesToInsert)), evaluationTime);

        Map<String, Integer> countsByStatus = new Map<String, Integer>();
        for (Case result : loadCases(caseIds(casesToInsert))) {
            Integer count = countsByStatus.containsKey(result.SLA_Status__c)
                ? countsByStatus.get(result.SLA_Status__c) : 0;
            countsByStatus.put(result.SLA_Status__c, count + 1);
        }
        System.assertEquals(10, countsByStatus.get(STATUS_ON_TRACK));
        System.assertEquals(10, countsByStatus.get(STATUS_AT_RISK));
        System.assertEquals(10, countsByStatus.get(STATUS_BREACHED));
        System.assertEquals(10, countsByStatus.get(STATUS_COMPLETED));
        System.assertEquals(20, [SELECT COUNT() FROM SLA_Escalation_History__c]);
    }

    private static Case createMonitoredCase() {
        Case supportCase = baseCase();
        insert supportCase;
        return supportCase;
    }

    private static Case baseCase() {
        return new Case(
            Subject = 'SLA Monitoring ' + String.valueOf(Crypto.getRandomInteger()),
            Status = 'New',
            Origin = 'Phone',
            Priority = 'Critical',
            Issue_Category__c = 'Technical',
            Support_Subscription__c = subscriptionId()
        );
    }

    private static void setState(
        Case supportCase,
        Datetime firstResponseDue,
        Datetime resolutionDue,
        Datetime firstRespondedAt,
        String slaStatus,
        Boolean breached,
        String escalationLevel,
        Datetime escalatedAt
    ) {
        supportCase.First_Response_Due__c = firstResponseDue;
        supportCase.Resolution_Due__c = resolutionDue;
        supportCase.First_Responded_At__c = firstRespondedAt;
        supportCase.SLA_Status__c = slaStatus;
        supportCase.SLA_Breached__c = breached;
        supportCase.Escalation_Level__c = escalationLevel;
        supportCase.Escalated_At__c = escalatedAt;
        update supportCase;
    }

    private static void processAt(Id caseId, Datetime evaluationTime) {
        SLAMonitoringService.processAt(new List<Case>{ loadCase(caseId) }, evaluationTime);
    }

    private static Case loadCase(Id caseId) {
        return loadCases(new Set<Id>{ caseId })[0];
    }

    private static List<Case> loadCases(Set<Id> caseIds) {
        return [
            SELECT Id, IsClosed, Priority, Support_Subscription__c,
                First_Response_Due__c, Resolution_Due__c, First_Responded_At__c,
                SLA_Status__c, SLA_Breached__c, Escalation_Level__c, Escalated_At__c
            FROM Case
            WHERE Id IN :caseIds
        ];
    }

    private static void assertEscalated(
        Id caseId,
        String expectedStatus,
        Boolean expectedBreach,
        String expectedLevel,
        Datetime expectedTime
    ) {
        Case result = loadCase(caseId);
        System.assertEquals(expectedStatus, result.SLA_Status__c);
        System.assertEquals(expectedBreach, result.SLA_Breached__c);
        System.assertEquals(expectedLevel, result.Escalation_Level__c);
        System.assertEquals(expectedTime, result.Escalated_At__c);
    }

    private static void assertSingleHistory(
        Id caseId,
        String previousStatus,
        String newStatus,
        String level,
        String slaType
    ) {
        List<SLA_Escalation_History__c> histories = historyFor(caseId);
        System.assertEquals(1, histories.size());
        System.assertEquals(previousStatus, histories[0].Previous_SLA_Status__c);
        System.assertEquals(newStatus, histories[0].New_SLA_Status__c);
        System.assertEquals(level, histories[0].Escalation_Level__c);
        System.assertEquals(slaType, histories[0].SLA_Type__c);
    }

    private static List<SLA_Escalation_History__c> historyFor(Id caseId) {
        return [
            SELECT Previous_SLA_Status__c, New_SLA_Status__c, Escalation_Level__c,
                Escalated_At__c, SLA_Type__c, SLA_Due_At__c, Reason__c
            FROM SLA_Escalation_History__c
            WHERE Case__c = :caseId
            ORDER BY CreatedDate
        ];
    }

    private static SLA_Escalation_History__c historyRecord(
        Id caseId,
        String previousStatus,
        String newStatus,
        String level,
        String slaType,
        Datetime escalatedAt,
        Datetime dueAt
    ) {
        return new SLA_Escalation_History__c(
            Case__c = caseId,
            Previous_SLA_Status__c = previousStatus,
            New_SLA_Status__c = newStatus,
            Escalation_Level__c = level,
            SLA_Type__c = slaType,
            Escalated_At__c = escalatedAt,
            SLA_Due_At__c = dueAt,
            Reason__c = 'Existing test escalation.'
        );
    }

    private static void closeCase(Id caseId) {
        update new Case(Id = caseId, Status = closedStatusValue());
    }

    private static String closedStatusValue() {
        return [SELECT MasterLabel FROM CaseStatus WHERE IsClosed = true LIMIT 1].MasterLabel;
    }

    private static Id subscriptionId() {
        return [
            SELECT Id
            FROM Support_Subscription__c
            WHERE Support_Plan__c = 'Enterprise'
            AND Status__c = 'Active'
            LIMIT 1
        ].Id;
    }

    private static Set<Id> caseIds(List<Case> supportCases) {
        Set<Id> ids = new Set<Id>();
        for (Case supportCase : supportCases) {
            ids.add(supportCase.Id);
        }
        return ids;
    }
}