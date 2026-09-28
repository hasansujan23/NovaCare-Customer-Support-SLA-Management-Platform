public with sharing class SLAMonitorScheduler implements Schedulable {
    public static final Integer BATCH_SIZE = 100;

    public void execute(SchedulableContext context) {
        Database.executeBatch(new SLAMonitorBatch(), BATCH_SIZE);
    }
}