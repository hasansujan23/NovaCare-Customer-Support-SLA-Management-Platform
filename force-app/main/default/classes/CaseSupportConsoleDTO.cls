// Read-only response contract for the NovaCare Case Support Console LWC.
// Values are populated only from fields the running user is permitted to read.
public with sharing class CaseSupportConsoleDTO {
    @AuraEnabled public CaseInfo caseInfo;
    @AuraEnabled public CustomerInfo customer;
    @AuraEnabled public AssignmentInfo assignment;
    @AuraEnabled public SubscriptionInfo subscription;
    @AuraEnabled public SlaInfo sla;
    @AuraEnabled public List<EscalationHistoryItem> history = new List<EscalationHistoryItem>();
    @AuraEnabled public Boolean subscriptionAccessible = false;
    @AuraEnabled public Boolean historyAccessible = false;
    @AuraEnabled public Boolean canMarkFirstResponse = false;

    public class CaseInfo {
        @AuraEnabled public Id caseId;
        @AuraEnabled public String caseNumber;
        @AuraEnabled public String subject;
        @AuraEnabled public String status;
        @AuraEnabled public Boolean isClosed;
        @AuraEnabled public Datetime closedDate;
        @AuraEnabled public String priority;
        @AuraEnabled public String issueCategory;
        @AuraEnabled public Datetime createdDate;
    }

    public class CustomerInfo {
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public Id contactId;
        @AuraEnabled public String contactName;
        @AuraEnabled public Id assetId;
        @AuraEnabled public String assetName;
    }

    public class AssignmentInfo {
        @AuraEnabled public Id ownerId;
        @AuraEnabled public String ownerName;
        @AuraEnabled public String ownerType;
    }

    public class SubscriptionInfo {
        @AuraEnabled public Id subscriptionId;
        @AuraEnabled public String subscriptionName;
        @AuraEnabled public String supportPlan;
        @AuraEnabled public String subscriptionStatus;
        @AuraEnabled public Date startDate;
        @AuraEnabled public Date endDate;
        @AuraEnabled public Boolean support24x7;
    }

    public class SlaInfo {
        @AuraEnabled public String slaStatus;
        @AuraEnabled public Boolean slaBreached;
        @AuraEnabled public String escalationLevel;
        @AuraEnabled public Datetime escalatedAt;
        @AuraEnabled public Datetime firstResponseDue;
        @AuraEnabled public Datetime firstRespondedAt;
        @AuraEnabled public Datetime resolutionDue;
    }

    public class EscalationHistoryItem {
        @AuraEnabled public Id historyId;
        @AuraEnabled public String name;
        @AuraEnabled public Datetime escalatedAt;
        @AuraEnabled public String escalationLevel;
        @AuraEnabled public String previousSlaStatus;
        @AuraEnabled public String newSlaStatus;
        @AuraEnabled public String slaType;
        @AuraEnabled public Datetime slaDueAt;
        @AuraEnabled public String reason;
    }
}
