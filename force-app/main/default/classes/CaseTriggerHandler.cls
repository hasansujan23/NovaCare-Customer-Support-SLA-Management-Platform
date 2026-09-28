public with sharing class CaseTriggerHandler {
    public static void beforeInsert(List<Case> newCases) {
        SLAService.applyInitialSla(newCases);
        CaseRoutingService.routeCases(newCases);
    }
}