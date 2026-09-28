public with sharing class SLAMonitoringService {
    private static final String ACTIVE_SUBSCRIPTION_STATUS = 'Active';
    private static final String STATUS_ON_TRACK = 'On Track';
    private static final String STATUS_AT_RISK = 'At Risk';
    private static final String STATUS_BREACHED = 'Breached';
    private static final String STATUS_COMPLETED = 'Completed';
    private static final String LEVEL_ONE = 'Level 1';
    private static final String LEVEL_TWO = 'Level 2';
    private static final String SLA_TYPE_FIRST_RESPONSE = 'First Response';
    private static final String SLA_TYPE_RESOLUTION = 'Resolution';
    private static final String KEY_SEPARATOR = '|';

    public static void process(List<Case> scope) {
        processAt(scope, System.now());
    }

    @TestVisible
    private static void processAt(List<Case> scope, Datetime evaluationTime) {
        if (scope == null || scope.isEmpty() || evaluationTime == null) {
            return;
        }

        Map<Id, Support_Subscription__c> subscriptionsById = loadSubscriptions(scope);
        Map<String, Support_SLA_Policy__mdt> policiesByKey = loadActivePolicies();
        processWithConfiguration(scope, evaluationTime, subscriptionsById, policiesByKey);
    }

    @TestVisible
    private static void processWithConfiguration(
        List<Case> scope,
        Datetime evaluationTime,
        Map<Id, Support_Subscription__c> subscriptionsById,
        Map<String, Support_SLA_Policy__mdt> policiesByKey
    ) {
        if (scope == null || scope.isEmpty() || evaluationTime == null) {
            return;
        }

        List<Case> caseUpdates = new List<Case>();
        Map<Id, List<SLA_Escalation_History__c>> pendingHistoriesByCaseId =
            new Map<Id, List<SLA_Escalation_History__c>>();

        for (Case supportCase : scope) {
            if (supportCase.Id == null) {
                continue;
            }

            EvaluationOutcome outcome = evaluateCase(
                supportCase,
                evaluationTime,
                subscriptionsById,
                policiesByKey
            );
            if (outcome == null || !outcome.hasChanges) {
                continue;
            }

            caseUpdates.add(outcome.caseUpdate);
            if (!outcome.pendingHistories.isEmpty()) {
                pendingHistoriesByCaseId.put(supportCase.Id, outcome.pendingHistories);
            }
        }

        persistTransitions(caseUpdates, pendingHistoriesByCaseId);
    }

    private static EvaluationOutcome evaluateCase(
        Case supportCase,
        Datetime evaluationTime,
        Map<Id, Support_Subscription__c> subscriptionsById,
        Map<String, Support_SLA_Policy__mdt> policiesByKey
    ) {
        EvaluationOutcome outcome = new EvaluationOutcome(new Case(Id = supportCase.Id));

        if (supportCase.IsClosed == true) {
            if (supportCase.SLA_Status__c != STATUS_COMPLETED) {
                outcome.caseUpdate.SLA_Status__c = STATUS_COMPLETED;
                outcome.hasChanges = true;
            }
            return outcome;
        }

        Support_SLA_Policy__mdt policy = findPolicy(supportCase, subscriptionsById, policiesByKey);
        if (!isUsablePolicy(policy)) {
            return null;
        }

        Boolean lateFirstResponse = supportCase.First_Responded_At__c != null
            && supportCase.First_Response_Due__c != null
            && supportCase.First_Responded_At__c > supportCase.First_Response_Due__c
            && supportCase.SLA_Breached__c != true;

        if (lateFirstResponse) {
            outcome.caseUpdate.SLA_Breached__c = true;
            outcome.caseUpdate.Escalation_Level__c = LEVEL_TWO;
            outcome.caseUpdate.Escalated_At__c = evaluationTime;
            outcome.hasChanges = true;
            outcome.pendingHistories.add(createHistory(
                supportCase,
                supportCase.SLA_Status__c,
                STATUS_BREACHED,
                LEVEL_TWO,
                evaluationTime,
                SLA_TYPE_FIRST_RESPONSE,
                supportCase.First_Response_Due__c,
                'First response was recorded after the SLA deadline.'
            ));
        }

        CurrentObligation obligation = currentObligation(supportCase, policy);
        if (obligation == null || obligation.dueAt == null || obligation.durationMinutes == null) {
            return outcome.hasChanges ? outcome : null;
        }

        String newStatus = evaluateStatus(
            evaluationTime,
            obligation.dueAt,
            obligation.durationMinutes,
            policy.At_Risk_Threshold__c
        );
        if (newStatus == null) {
            return outcome.hasChanges ? outcome : null;
        }

        if (supportCase.SLA_Status__c != newStatus) {
            outcome.caseUpdate.SLA_Status__c = newStatus;
            outcome.hasChanges = true;
        }

        if (newStatus == STATUS_AT_RISK && supportCase.SLA_Status__c != STATUS_AT_RISK) {
            outcome.caseUpdate.Escalation_Level__c = LEVEL_ONE;
            outcome.caseUpdate.Escalated_At__c = evaluationTime;
            outcome.hasChanges = true;
            outcome.pendingHistories.add(createHistory(
                supportCase,
                supportCase.SLA_Status__c,
                STATUS_AT_RISK,
                LEVEL_ONE,
                evaluationTime,
                obligation.slaType,
                obligation.dueAt,
                obligation.slaType + ' SLA entered the at-risk threshold.'
            ));
        } else if (newStatus == STATUS_BREACHED && supportCase.SLA_Status__c != STATUS_BREACHED) {
            outcome.caseUpdate.SLA_Breached__c = true;
            outcome.caseUpdate.Escalation_Level__c = LEVEL_TWO;
            outcome.caseUpdate.Escalated_At__c = evaluationTime;
            outcome.hasChanges = true;
            outcome.pendingHistories.add(createHistory(
                supportCase,
                supportCase.SLA_Status__c,
                STATUS_BREACHED,
                LEVEL_TWO,
                evaluationTime,
                obligation.slaType,
                obligation.dueAt,
                obligation.slaType + ' SLA deadline was exceeded.'
            ));
        }

        return outcome;
    }

    private static Support_SLA_Policy__mdt findPolicy(
        Case supportCase,
        Map<Id, Support_Subscription__c> subscriptionsById,
        Map<String, Support_SLA_Policy__mdt> policiesByKey
    ) {
        if (supportCase.Support_Subscription__c == null || String.isBlank(supportCase.Priority)) {
            return null;
        }
        Support_Subscription__c subscription = subscriptionsById.get(supportCase.Support_Subscription__c);
        if (subscription == null || String.isBlank(subscription.Support_Plan__c)) {
            return null;
        }
        return policiesByKey.get(buildPolicyKey(subscription.Support_Plan__c, supportCase.Priority));
    }

    private static Boolean isUsablePolicy(Support_SLA_Policy__mdt policy) {
        return policy != null
            && policy.First_Response_Minutes__c != null
            && policy.First_Response_Minutes__c > 0
            && policy.Resolution_Minutes__c != null
            && policy.Resolution_Minutes__c > 0
            && policy.At_Risk_Threshold__c != null
            && policy.At_Risk_Threshold__c >= 0
            && policy.At_Risk_Threshold__c <= 100;
    }

    private static CurrentObligation currentObligation(Case supportCase, Support_SLA_Policy__mdt policy) {
        if (supportCase.First_Responded_At__c == null) {
            return new CurrentObligation(
                SLA_TYPE_FIRST_RESPONSE,
                supportCase.First_Response_Due__c,
                policy.First_Response_Minutes__c
            );
        }
        return new CurrentObligation(
            SLA_TYPE_RESOLUTION,
            supportCase.Resolution_Due__c,
            policy.Resolution_Minutes__c
        );
    }

    private static String evaluateStatus(
        Datetime evaluationTime,
        Datetime dueAt,
        Decimal durationMinutes,
        Decimal thresholdPercent
    ) {
        Decimal window = durationMinutes * thresholdPercent / 100;
        Integer atRiskWindowMinutes = window.setScale(0, RoundingMode.CEILING).intValue();
        Datetime atRiskStartsAt = dueAt.addMinutes(-atRiskWindowMinutes);

        if (evaluationTime > dueAt) {
            return STATUS_BREACHED;
        }
        if (evaluationTime >= atRiskStartsAt) {
            return STATUS_AT_RISK;
        }
        return STATUS_ON_TRACK;
    }

    private static Map<Id, Support_Subscription__c> loadSubscriptions(List<Case> scope) {
        Set<Id> subscriptionIds = new Set<Id>();
        for (Case supportCase : scope) {
            if (supportCase.Support_Subscription__c != null) {
                subscriptionIds.add(supportCase.Support_Subscription__c);
            }
        }
        if (subscriptionIds.isEmpty()) {
            return new Map<Id, Support_Subscription__c>();
        }
        return new Map<Id, Support_Subscription__c>([
            SELECT Id, Support_Plan__c
            FROM Support_Subscription__c
            WHERE Id IN :subscriptionIds
            AND Status__c = :ACTIVE_SUBSCRIPTION_STATUS
        ]);
    }

    private static Map<String, Support_SLA_Policy__mdt> loadActivePolicies() {
        Map<String, Support_SLA_Policy__mdt> policiesByKey = new Map<String, Support_SLA_Policy__mdt>();
        for (Support_SLA_Policy__mdt policy : [
            SELECT Support_Plan__c, Priority__c, First_Response_Minutes__c,
                Resolution_Minutes__c, At_Risk_Threshold__c
            FROM Support_SLA_Policy__mdt
            WHERE Active__c = true
        ]) {
            if (!String.isBlank(policy.Support_Plan__c) && !String.isBlank(policy.Priority__c)) {
                policiesByKey.put(buildPolicyKey(policy.Support_Plan__c, policy.Priority__c), policy);
            }
        }
        return policiesByKey;
    }

    private static String buildPolicyKey(String supportPlan, String priority) {
        return supportPlan.trim().toLowerCase() + KEY_SEPARATOR + priority.trim().toLowerCase();
    }

    private static SLA_Escalation_History__c createHistory(
        Case supportCase,
        String previousStatus,
        String newStatus,
        String escalationLevel,
        Datetime evaluationTime,
        String slaType,
        Datetime dueAt,
        String reason
    ) {
        return new SLA_Escalation_History__c(
            Case__c = supportCase.Id,
            Previous_SLA_Status__c = previousStatus,
            New_SLA_Status__c = newStatus,
            Escalation_Level__c = escalationLevel,
            Escalated_At__c = evaluationTime,
            Reason__c = reason,
            SLA_Type__c = slaType,
            SLA_Due_At__c = dueAt
        );
    }

    private static void persistTransitions(
        List<Case> caseUpdates,
        Map<Id, List<SLA_Escalation_History__c>> pendingHistoriesByCaseId
    ) {
        if (caseUpdates.isEmpty()) {
            return;
        }

        Database.SaveResult[] caseResults = Database.update(caseUpdates, false);
        List<SLA_Escalation_History__c> historiesToInsert = new List<SLA_Escalation_History__c>();
        for (Integer index = 0; index < caseResults.size(); index++) {
            Database.SaveResult result = caseResults[index];
            Id caseId = caseUpdates[index].Id;
            if (result.isSuccess()) {
                List<SLA_Escalation_History__c> pendingHistories = pendingHistoriesByCaseId.get(caseId);
                if (pendingHistories != null) {
                    historiesToInsert.addAll(pendingHistories);
                }
            } else {
                logDmlErrors('Case SLA update', caseId, result.getErrors());
            }
        }

        if (!historiesToInsert.isEmpty()) {
            Database.SaveResult[] historyResults = Database.insert(historiesToInsert, false);
            for (Integer index = 0; index < historyResults.size(); index++) {
                if (!historyResults[index].isSuccess()) {
                    logDmlErrors(
                        'SLA escalation history insert',
                        historiesToInsert[index].Case__c,
                        historyResults[index].getErrors()
                    );
                }
            }
        }
    }

    private static void logDmlErrors(String operation, Id relatedId, Database.Error[] errors) {
        for (Database.Error error : errors) {
            System.debug(LoggingLevel.ERROR, operation + ' failed for ' + relatedId + ': ' + error.getMessage());
        }
    }

    private class CurrentObligation {
        private String slaType;
        private Datetime dueAt;
        private Decimal durationMinutes;

        private CurrentObligation(String slaType, Datetime dueAt, Decimal durationMinutes) {
            this.slaType = slaType;
            this.dueAt = dueAt;
            this.durationMinutes = durationMinutes;
        }
    }

    private class EvaluationOutcome {
        private Case caseUpdate;
        private Boolean hasChanges = false;
        private List<SLA_Escalation_History__c> pendingHistories =
            new List<SLA_Escalation_History__c>();

        private EvaluationOutcome(Case caseUpdate) {
            this.caseUpdate = caseUpdate;
        }
    }
}