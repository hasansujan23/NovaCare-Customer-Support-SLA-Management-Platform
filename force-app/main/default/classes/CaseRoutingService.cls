public with sharing class CaseRoutingService {
    private static final String KEY_SEPARATOR = '|';
    private static final String WILDCARD = '*';
    private static final String FALLBACK_KEY = buildRoutingKey(WILDCARD, WILDCARD);

    public static void routeCases(List<Case> newCases) {
        if (newCases == null || newCases.isEmpty()) {
            return;
        }

        List<Case_Routing_Rule__mdt> activeRules = loadActiveRules();
        if (activeRules.isEmpty()) {
            return;
        }

        Map<String, Id> queueIdsByDeveloperName = loadCaseQueueIds(collectQueueDeveloperNames(activeRules));
        applyRouting(newCases, activeRules, queueIdsByDeveloperName);
    }

    private static List<Case_Routing_Rule__mdt> loadActiveRules() {
        return [
            SELECT DeveloperName, Issue_Category__c, Priority__c,
                Target_Queue_Developer_Name__c, Routing_Priority__c
            FROM Case_Routing_Rule__mdt
            WHERE Active__c = true
        ];
    }

    private static Set<String> collectQueueDeveloperNames(List<Case_Routing_Rule__mdt> rules) {
        Set<String> queueDeveloperNames = new Set<String>();
        for (Case_Routing_Rule__mdt rule : rules) {
            if (!String.isBlank(rule.Target_Queue_Developer_Name__c)) {
                queueDeveloperNames.add(rule.Target_Queue_Developer_Name__c.trim());
            }
        }
        return queueDeveloperNames;
    }

    private static Map<String, Id> loadCaseQueueIds(Set<String> queueDeveloperNames) {
        Map<String, Id> queueIdsByDeveloperName = new Map<String, Id>();
        if (queueDeveloperNames.isEmpty()) {
            return queueIdsByDeveloperName;
        }

        for (Group caseQueue : [
            SELECT Id, DeveloperName
            FROM Group
            WHERE Type = 'Queue'
            AND DeveloperName IN :queueDeveloperNames
            AND Id IN (
                SELECT QueueId
                FROM QueueSobject
                WHERE SobjectType = 'Case'
            )
        ]) {
            queueIdsByDeveloperName.put(caseQueue.DeveloperName, caseQueue.Id);
        }
        return queueIdsByDeveloperName;
    }

    @TestVisible
    private static void applyRouting(
        List<Case> newCases,
        List<Case_Routing_Rule__mdt> activeRules,
        Map<String, Id> queueIdsByDeveloperName
    ) {
        Map<String, Case_Routing_Rule__mdt> rulesByKey = selectPreferredRules(activeRules);
        Case_Routing_Rule__mdt fallbackRule = rulesByKey.get(FALLBACK_KEY);

        for (Case supportCase : newCases) {
            // Salesforce defaults an otherwise unassigned Case to the running user before this trigger.
            // Any different User or Queue owner is therefore treated as an explicit assignment.
            if (supportCase.OwnerId != null && supportCase.OwnerId != UserInfo.getUserId()) {
                continue;
            }

            Case_Routing_Rule__mdt rule = rulesByKey.get(
                buildRoutingKey(supportCase.Issue_Category__c, supportCase.Priority)
            );
            if (rule == null) {
                rule = fallbackRule;
            }
            if (rule == null || String.isBlank(rule.Target_Queue_Developer_Name__c)) {
                continue;
            }

            Id targetQueueId = queueIdsByDeveloperName.get(rule.Target_Queue_Developer_Name__c.trim());
            if (targetQueueId != null) {
                supportCase.OwnerId = targetQueueId;
            }
        }
    }

    private static Map<String, Case_Routing_Rule__mdt> selectPreferredRules(
        List<Case_Routing_Rule__mdt> activeRules
    ) {
        Map<String, Case_Routing_Rule__mdt> rulesByKey = new Map<String, Case_Routing_Rule__mdt>();
        for (Case_Routing_Rule__mdt candidate : activeRules) {
            if (String.isBlank(candidate.Issue_Category__c) || String.isBlank(candidate.Priority__c)) {
                continue;
            }

            String key = buildRoutingKey(candidate.Issue_Category__c, candidate.Priority__c);
            Case_Routing_Rule__mdt selected = rulesByKey.get(key);
            if (selected == null || hasHigherPrecedence(candidate, selected)) {
                rulesByKey.put(key, candidate);
            }
        }
        return rulesByKey;
    }

    private static Boolean hasHigherPrecedence(
        Case_Routing_Rule__mdt candidate,
        Case_Routing_Rule__mdt selected
    ) {
        Decimal candidatePriority = candidate.Routing_Priority__c;
        Decimal selectedPriority = selected.Routing_Priority__c;
        if (candidatePriority == null) {
            return false;
        }
        if (selectedPriority == null || candidatePriority < selectedPriority) {
            return true;
        }
        if (candidatePriority > selectedPriority) {
            return false;
        }

        String candidateName = candidate.DeveloperName == null ? '' : candidate.DeveloperName;
        String selectedName = selected.DeveloperName == null ? '' : selected.DeveloperName;
        return candidateName.compareTo(selectedName) < 0;
    }

    private static String buildRoutingKey(String issueCategory, String priority) {
        return normalizeKeyPart(issueCategory) + KEY_SEPARATOR + normalizeKeyPart(priority);
    }

    private static String normalizeKeyPart(String value) {
        return String.isBlank(value) ? '' : value.trim().toLowerCase();
    }
}
