@IsTest
private class SLAMonitorBatchTest {
    @TestSetup
    static void setupData() {
        Account account = new Account(Name = 'SLA Batch Account');
        insert account;
        Support_Subscription__c subscription = new Support_Subscription__c(
            Account__c = account.Id,
            Support_Plan__c = 'Enterprise',
            Status__c = 'Active',
            Start_Date__c = Date.today(),
            End_Date__c = Date.today().addYears(1),
            X24x7_Support__c = true
        );
        insert subscription;

        Case supportCase = new Case(
            Subject = 'Batch monitored Case',
            Status = 'New',
            Origin = 'Phone',
            Priority = 'Critical',
            Issue_Category__c = 'Technical',
            Support_Subscription__c = subscription.Id
        );
        insert supportCase;
        supportCase.First_Response_Due__c = System.now().addMinutes(-5);
        supportCase.Resolution_Due__c = System.now().addHours(2);
        supportCase.First_Responded_At__c = null;
        supportCase.SLA_Status__c = 'On Track';
        supportCase.SLA_Breached__c = false;
        supportCase.Escalation_Level__c = 'None';
        update supportCase;
    }

    @IsTest
    static void batchProcessesCandidateCasesAndCreatesHistory() {
        Test.startTest();
        Id jobId = Database.executeBatch(new SLAMonitorBatch(), 100);
        Test.stopTest();

        AsyncApexJob job = [
            SELECT Status, JobItemsProcessed, TotalJobItems, NumberOfErrors
            FROM AsyncApexJob
            WHERE Id = :jobId
        ];
        System.assertEquals('Completed', job.Status);
        System.assertEquals(0, job.NumberOfErrors);

        Case result = [
            SELECT Id, SLA_Status__c, SLA_Breached__c, Escalation_Level__c
            FROM Case
            WHERE Subject = 'Batch monitored Case'
            LIMIT 1
        ];
        System.assertEquals('Breached', result.SLA_Status__c);
        System.assertEquals(true, result.SLA_Breached__c);
        System.assertEquals('Level 2', result.Escalation_Level__c);
        System.assertEquals(1, [
            SELECT COUNT()
            FROM SLA_Escalation_History__c
            WHERE Case__c = :result.Id
        ]);
    }
}