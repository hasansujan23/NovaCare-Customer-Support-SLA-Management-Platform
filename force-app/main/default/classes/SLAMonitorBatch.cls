public with sharing class SLAMonitorBatch implements Database.Batchable<SObject> {
    public Database.QueryLocator start(Database.BatchableContext context) {
        return Database.getQueryLocator([
            SELECT Id, IsClosed, Priority, Support_Subscription__c,
                First_Response_Due__c, Resolution_Due__c, First_Responded_At__c,
                SLA_Status__c, SLA_Breached__c, Escalation_Level__c, Escalated_At__c
            FROM Case
            WHERE SLA_Status__c IN ('On Track', 'At Risk', 'Breached')
        ]);
    }

    public void execute(Database.BatchableContext context, List<SObject> scope) {
        List<Case> supportCases = new List<Case>();
        for (SObject record : scope) {
            supportCases.add((Case) record);
        }
        SLAMonitoringService.process(supportCases);
    }

    public void finish(Database.BatchableContext context) {
    }
}