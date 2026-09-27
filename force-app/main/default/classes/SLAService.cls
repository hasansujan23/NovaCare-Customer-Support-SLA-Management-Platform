public with sharing class SLAService {
    private static final String ACTIVE_SUBSCRIPTION_STATUS = 'Active';
    private static final String SLA_STATUS_ON_TRACK = 'On Track';
    private static final String ESCALATION_LEVEL_NONE = 'None';
    private static final String POLICY_KEY_SEPARATOR = '|';

    public static void applyInitialSla(List<Case> newCases) {
        if (newCases == null || newCases.isEmpty()) {
            return;
        }

        Set<Id> subscriptionIds = collectSubscriptionIds(newCases);
        if (subscriptionIds.isEmpty()) {
            return;
        }

        Map<Id, Support_Subscription__c> activeSubscriptionsById = queryActiveSubscriptions(subscriptionIds);
        if (activeSubscriptionsById.isEmpty()) {
            return;
        }

        Map<String, Support_SLA_Policy__mdt> activePoliciesByKey = loadActivePolicies();
        if (activePoliciesByKey.isEmpty()) {
            return;
        }

        // CreatedDate is not reliably available in before insert, so use one transaction-level base time.
        Datetime baseTime = System.now();

        for (Case supportCase : newCases) {
            if (supportCase.Support_Subscription__c == null || String.isBlank(supportCase.Priority)) {
                continue;
            }

            Support_Subscription__c subscription = activeSubscriptionsById.get(supportCase.Support_Subscription__c);
            if (subscription == null || String.isBlank(subscription.Support_Plan__c)) {
                continue;
            }

            Support_SLA_Policy__mdt policy = activePoliciesByKey.get(buildPolicyKey(subscription.Support_Plan__c, supportCase.Priority));
            if (policy == null || policy.First_Response_Minutes__c == null || policy.Resolution_Minutes__c == null) {
                continue;
            }

            supportCase.First_Response_Due__c = baseTime.addMinutes(policy.First_Response_Minutes__c.intValue());
            supportCase.Resolution_Due__c = baseTime.addMinutes(policy.Resolution_Minutes__c.intValue());
            supportCase.SLA_Status__c = SLA_STATUS_ON_TRACK;
            supportCase.SLA_Breached__c = false;
            supportCase.Escalation_Level__c = ESCALATION_LEVEL_NONE;
        }
    }

    private static Set<Id> collectSubscriptionIds(List<Case> newCases) {
        Set<Id> subscriptionIds = new Set<Id>();
        for (Case supportCase : newCases) {
            if (supportCase.Support_Subscription__c != null) {
                subscriptionIds.add(supportCase.Support_Subscription__c);
            }
        }
        return subscriptionIds;
    }

    private static Map<Id, Support_Subscription__c> queryActiveSubscriptions(Set<Id> subscriptionIds) {
        return new Map<Id, Support_Subscription__c>([
            SELECT Id, Support_Plan__c, Status__c
            FROM Support_Subscription__c
            WHERE Id IN :subscriptionIds
            AND Status__c = :ACTIVE_SUBSCRIPTION_STATUS
        ]);
    }

    private static Map<String, Support_SLA_Policy__mdt> loadActivePolicies() {
        Map<String, Support_SLA_Policy__mdt> policiesByKey = new Map<String, Support_SLA_Policy__mdt>();
        for (Support_SLA_Policy__mdt policy : [
            SELECT Support_Plan__c, Priority__c, First_Response_Minutes__c, Resolution_Minutes__c
            FROM Support_SLA_Policy__mdt
            WHERE Active__c = true
        ]) {
            if (String.isBlank(policy.Support_Plan__c) || String.isBlank(policy.Priority__c)) {
                continue;
            }
            policiesByKey.put(buildPolicyKey(policy.Support_Plan__c, policy.Priority__c), policy);
        }
        return policiesByKey;
    }

    private static String buildPolicyKey(String supportPlan, String priority) {
        return supportPlan + POLICY_KEY_SEPARATOR + priority;
    }
}
