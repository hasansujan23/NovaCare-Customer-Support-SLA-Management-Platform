// Presentation-layer controller for the NovaCare Case Support Console.
// SLA state is owned by SLAService / SLAMonitoringService; this class only reads it.
// Security: "with sharing" enforces record access, and Security.stripInaccessible removes
// any field the running user cannot read, so hidden fields degrade to empty values
// instead of failing the whole console.
public with sharing class CaseSupportConsoleController {
    @TestVisible private static final String LOAD_ERROR_MESSAGE = 'Unable to load Case Support Console.';
    @TestVisible private static final String FIRST_RESPONSE_ERROR_MESSAGE = 'Unable to record the first response.';
    @TestVisible private static final String FIRST_RESPONSE_PERMISSION_MESSAGE =
        'You do not have permission to record a first response on this case.';
    @TestVisible private static final String FIRST_RESPONSE_CLOSED_MESSAGE =
        'A first response cannot be recorded on a closed case.';
    @TestVisible private static final String FIRST_RESPONSE_EXISTS_MESSAGE =
        'A first response has already been recorded for this case.';
    @TestVisible private static final Integer HISTORY_LIMIT = 10;

    private static final String OWNER_TYPE_USER = 'User';
    private static final String OWNER_TYPE_QUEUE = 'Queue';

    @AuraEnabled(cacheable=true)
    public static CaseSupportConsoleDTO getConsoleData(Id caseId) {
        try {
            if (!isCaseId(caseId) || !Schema.sObjectType.Case.isAccessible()) {
                throw controlledError(LOAD_ERROR_MESSAGE);
            }

            Case supportCase = queryReadableCase(caseId);
            if (supportCase == null) {
                throw controlledError(LOAD_ERROR_MESSAGE);
            }
            return buildConsoleData(supportCase);
        } catch (AuraHandledException controlled) {
            throw controlled;
        } catch (Exception unexpected) {
            System.debug(LoggingLevel.ERROR, 'Case Support Console load failed: ' + unexpected.getMessage());
            throw controlledError(LOAD_ERROR_MESSAGE);
        }
    }

    // Records the agent's first response using server time. It intentionally does not touch
    // SLA Status, SLA Breached or Escalation Level; SLAMonitoringService evaluates the response.
    @AuraEnabled
    public static Datetime markFirstResponse(Id caseId) {
        try {
            if (!isCaseId(caseId)) {
                throw controlledError(FIRST_RESPONSE_ERROR_MESSAGE);
            }
            if (!canUpdateFirstResponseField()) {
                throw controlledError(FIRST_RESPONSE_PERMISSION_MESSAGE);
            }

            List<Case> cases = [
                SELECT Id, IsClosed, First_Responded_At__c
                FROM Case
                WHERE Id = :caseId
                LIMIT 1
                FOR UPDATE
            ];
            if (cases.isEmpty()) {
                throw controlledError(FIRST_RESPONSE_ERROR_MESSAGE);
            }
            if (!hasEditAccess(caseId)) {
                throw controlledError(FIRST_RESPONSE_PERMISSION_MESSAGE);
            }
            if (cases[0].IsClosed) {
                throw controlledError(FIRST_RESPONSE_CLOSED_MESSAGE);
            }
            if (cases[0].First_Responded_At__c != null) {
                throw controlledError(FIRST_RESPONSE_EXISTS_MESSAGE);
            }

            Datetime respondedAt = System.now();
            update new Case(Id = caseId, First_Responded_At__c = respondedAt);
            return respondedAt;
        } catch (AuraHandledException controlled) {
            throw controlled;
        } catch (Exception unexpected) {
            System.debug(LoggingLevel.ERROR, 'Case Support Console first response failed: ' + unexpected.getMessage());
            throw controlledError(FIRST_RESPONSE_ERROR_MESSAGE);
        }
    }

    private static Case queryReadableCase(Id caseId) {
        List<Case> cases = [
            SELECT Id, CaseNumber, Subject, Status, IsClosed, ClosedDate, Priority, Issue_Category__c, CreatedDate,
                AccountId, Account.Name, ContactId, Contact.Name, AssetId, Asset.Name, OwnerId, Owner.Name,
                Support_Subscription__c, Support_Subscription__r.Name, Support_Subscription__r.Support_Plan__c,
                Support_Subscription__r.Status__c, Support_Subscription__r.Start_Date__c,
                Support_Subscription__r.End_Date__c, Support_Subscription__r.X24x7_Support__c,
                SLA_Status__c, SLA_Breached__c, Escalation_Level__c, Escalated_At__c,
                First_Response_Due__c, First_Responded_At__c, Resolution_Due__c
            FROM Case
            WHERE Id = :caseId
            LIMIT 1
        ];
        if (cases.isEmpty()) {
            return null;
        }
        return (Case) Security.stripInaccessible(AccessType.READABLE, cases).getRecords()[0];
    }

    private static CaseSupportConsoleDTO buildConsoleData(Case supportCase) {
        CaseSupportConsoleDTO dto = new CaseSupportConsoleDTO();
        dto.caseInfo = buildCaseInfo(supportCase);
        dto.customer = buildCustomer(supportCase);
        dto.assignment = buildAssignment(supportCase);
        dto.sla = buildSla(supportCase);

        dto.subscriptionAccessible = Schema.sObjectType.Support_Subscription__c.isAccessible()
            && Schema.sObjectType.Case.fields.Support_Subscription__c.isAccessible();
        if (dto.subscriptionAccessible) {
            dto.subscription = buildSubscription(parentOf(supportCase, 'Support_Subscription__r'));
        }

        dto.historyAccessible = canReadHistory();
        if (dto.historyAccessible) {
            dto.history = loadHistory(supportCase.Id);
        }

        dto.canMarkFirstResponse = dto.caseInfo.isClosed == false
            && Schema.sObjectType.Case.fields.First_Responded_At__c.isAccessible()
            && dto.sla.firstRespondedAt == null
            && canUpdateFirstResponseField()
            && hasEditAccess(supportCase.Id);
        return dto;
    }

    private static CaseSupportConsoleDTO.CaseInfo buildCaseInfo(Case supportCase) {
        CaseSupportConsoleDTO.CaseInfo info = new CaseSupportConsoleDTO.CaseInfo();
        info.caseId = supportCase.Id;
        info.caseNumber = (String) valueOf(supportCase, 'CaseNumber');
        info.subject = (String) valueOf(supportCase, 'Subject');
        info.status = (String) valueOf(supportCase, 'Status');
        info.isClosed = valueOf(supportCase, 'IsClosed') == true;
        info.closedDate = (Datetime) valueOf(supportCase, 'ClosedDate');
        info.priority = (String) valueOf(supportCase, 'Priority');
        info.issueCategory = (String) valueOf(supportCase, 'Issue_Category__c');
        info.createdDate = (Datetime) valueOf(supportCase, 'CreatedDate');
        return info;
    }

    private static CaseSupportConsoleDTO.CustomerInfo buildCustomer(Case supportCase) {
        CaseSupportConsoleDTO.CustomerInfo customer = new CaseSupportConsoleDTO.CustomerInfo();
        customer.accountId = (Id) valueOf(supportCase, 'AccountId');
        customer.accountName = (String) valueOf(parentOf(supportCase, 'Account'), 'Name');
        customer.contactId = (Id) valueOf(supportCase, 'ContactId');
        customer.contactName = (String) valueOf(parentOf(supportCase, 'Contact'), 'Name');
        customer.assetId = (Id) valueOf(supportCase, 'AssetId');
        customer.assetName = (String) valueOf(parentOf(supportCase, 'Asset'), 'Name');
        return customer;
    }

    private static CaseSupportConsoleDTO.AssignmentInfo buildAssignment(Case supportCase) {
        CaseSupportConsoleDTO.AssignmentInfo assignment = new CaseSupportConsoleDTO.AssignmentInfo();
        assignment.ownerId = (Id) valueOf(supportCase, 'OwnerId');
        assignment.ownerName = (String) valueOf(parentOf(supportCase, 'Owner'), 'Name');
        if (assignment.ownerId != null) {
            // Case ownership is polymorphic: the owner is either a User or a Queue (Group).
            assignment.ownerType = assignment.ownerId.getSObjectType() == Group.SObjectType
                ? OWNER_TYPE_QUEUE
                : OWNER_TYPE_USER;
            if (assignment.ownerType == OWNER_TYPE_QUEUE && assignment.ownerName == null) {
                assignment.ownerName = queueName(assignment.ownerId);
            }
        }
        return assignment;
    }

    // stripInaccessible removes the polymorphic Owner.Name for queues because Group is not a
    // describable CRUD object for most users. The queue name is shown on the standard Case page
    // to anyone who can read OwnerId, so it is resolved only after OwnerId passed the FLS check.
    private static String queueName(Id queueId) {
        List<Group> queues = [SELECT Name FROM Group WHERE Id = :queueId AND Type = 'Queue' LIMIT 1];
        return queues.isEmpty() ? null : queues[0].Name;
    }

    private static CaseSupportConsoleDTO.SubscriptionInfo buildSubscription(SObject subscriptionRecord) {
        if (subscriptionRecord == null) {
            return null;
        }
        CaseSupportConsoleDTO.SubscriptionInfo subscription = new CaseSupportConsoleDTO.SubscriptionInfo();
        subscription.subscriptionId = subscriptionRecord.Id;
        subscription.subscriptionName = (String) valueOf(subscriptionRecord, 'Name');
        subscription.supportPlan = (String) valueOf(subscriptionRecord, 'Support_Plan__c');
        subscription.subscriptionStatus = (String) valueOf(subscriptionRecord, 'Status__c');
        subscription.startDate = (Date) valueOf(subscriptionRecord, 'Start_Date__c');
        subscription.endDate = (Date) valueOf(subscriptionRecord, 'End_Date__c');
        subscription.support24x7 = (Boolean) valueOf(subscriptionRecord, 'X24x7_Support__c');
        return subscription;
    }

    private static CaseSupportConsoleDTO.SlaInfo buildSla(Case supportCase) {
        CaseSupportConsoleDTO.SlaInfo sla = new CaseSupportConsoleDTO.SlaInfo();
        sla.slaStatus = (String) valueOf(supportCase, 'SLA_Status__c');
        sla.slaBreached = (Boolean) valueOf(supportCase, 'SLA_Breached__c');
        sla.escalationLevel = (String) valueOf(supportCase, 'Escalation_Level__c');
        sla.escalatedAt = (Datetime) valueOf(supportCase, 'Escalated_At__c');
        sla.firstResponseDue = (Datetime) valueOf(supportCase, 'First_Response_Due__c');
        sla.firstRespondedAt = (Datetime) valueOf(supportCase, 'First_Responded_At__c');
        sla.resolutionDue = (Datetime) valueOf(supportCase, 'Resolution_Due__c');
        return sla;
    }

    private static List<CaseSupportConsoleDTO.EscalationHistoryItem> loadHistory(Id caseId) {
        List<SLA_Escalation_History__c> records = [
            SELECT Id, Name, Escalated_At__c, Escalation_Level__c, Previous_SLA_Status__c,
                New_SLA_Status__c, SLA_Type__c, SLA_Due_At__c, Reason__c
            FROM SLA_Escalation_History__c
            WHERE Case__c = :caseId
            ORDER BY Escalated_At__c DESC NULLS LAST, CreatedDate DESC, Id DESC
            LIMIT :HISTORY_LIMIT
        ];

        List<CaseSupportConsoleDTO.EscalationHistoryItem> items = new List<CaseSupportConsoleDTO.EscalationHistoryItem>();
        for (SObject record : Security.stripInaccessible(AccessType.READABLE, records).getRecords()) {
            CaseSupportConsoleDTO.EscalationHistoryItem item = new CaseSupportConsoleDTO.EscalationHistoryItem();
            item.historyId = record.Id;
            item.name = (String) valueOf(record, 'Name');
            item.escalatedAt = (Datetime) valueOf(record, 'Escalated_At__c');
            item.escalationLevel = (String) valueOf(record, 'Escalation_Level__c');
            item.previousSlaStatus = (String) valueOf(record, 'Previous_SLA_Status__c');
            item.newSlaStatus = (String) valueOf(record, 'New_SLA_Status__c');
            item.slaType = (String) valueOf(record, 'SLA_Type__c');
            item.slaDueAt = (Datetime) valueOf(record, 'SLA_Due_At__c');
            item.reason = (String) valueOf(record, 'Reason__c');
            items.add(item);
        }
        return items;
    }

    // The timeline is only meaningful when the user can read the history object, its Case
    // link and its timestamp; otherwise the UI shows a permissions message, not "no escalations".
    private static Boolean canReadHistory() {
        Schema.DescribeSObjectResult historyDescribe = Schema.sObjectType.SLA_Escalation_History__c;
        return historyDescribe.isAccessible()
            && historyDescribe.fields.getMap().get('Case__c').getDescribe().isAccessible()
            && historyDescribe.fields.getMap().get('Escalated_At__c').getDescribe().isAccessible();
    }

    private static Boolean canUpdateFirstResponseField() {
        return Schema.sObjectType.Case.isUpdateable()
            && Schema.sObjectType.Case.fields.First_Responded_At__c.isUpdateable();
    }

    private static Boolean hasEditAccess(Id caseId) {
        List<UserRecordAccess> access = [
            SELECT RecordId, HasEditAccess
            FROM UserRecordAccess
            WHERE UserId = :UserInfo.getUserId()
            AND RecordId = :caseId
            LIMIT 1
        ];
        return !access.isEmpty() && access[0].HasEditAccess;
    }

    private static Boolean isCaseId(Id recordId) {
        return recordId != null && recordId.getSObjectType() == Case.SObjectType;
    }

    // Fields removed by stripInaccessible must not be read directly (that throws), so every
    // read goes through the populated-field map.
    private static Object valueOf(SObject record, String fieldName) {
        return record == null ? null : record.getPopulatedFieldsAsMap().get(fieldName);
    }

    private static SObject parentOf(SObject record, String relationshipName) {
        Object parent = valueOf(record, relationshipName);
        return parent instanceof SObject ? (SObject) parent : null;
    }

    private static AuraHandledException controlledError(String message) {
        AuraHandledException error = new AuraHandledException(message);
        error.setMessage(message);
        return error;
    }
}
