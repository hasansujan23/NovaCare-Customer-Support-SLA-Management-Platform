@IsTest
private class SLAMonitorSchedulerTest {
    @IsTest
    static void schedulerLaunchesMonitoringBatch() {
        String jobName = 'SLA Monitor Scheduler Test';

        Test.startTest();
        Id scheduledJobId = System.schedule(jobName, '0 0 0 1 1 ? 2099', new SLAMonitorScheduler());
        CronTrigger scheduledJob = [
            SELECT CronJobDetail.Name, CronExpression, State
            FROM CronTrigger
            WHERE Id = :scheduledJobId
        ];
        System.assertEquals(jobName, scheduledJob.CronJobDetail.Name);
        System.assertEquals('0 0 0 1 1 ? 2099', scheduledJob.CronExpression);
        Test.stopTest();

        List<AsyncApexJob> launchedBatches = [
            SELECT Id, JobType, ApexClass.Name, Status
            FROM AsyncApexJob
            WHERE ApexClass.Name = 'SLAMonitorBatch'
        ];
        System.assertEquals(1, launchedBatches.size(), 'The scheduled execution must launch the SLA batch.');
        System.assertEquals('BatchApex', launchedBatches[0].JobType);
    }
}