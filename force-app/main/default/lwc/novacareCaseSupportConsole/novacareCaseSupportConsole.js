import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import getConsoleData from '@salesforce/apex/CaseSupportConsoleController.getConsoleData';
import markFirstResponse from '@salesforce/apex/CaseSupportConsoleController.markFirstResponse';
import { displayValue, getPriorityTone, getSlaStatusMeta, hasValue, toneClass } from 'c/novacareSlaUtils';

const LOAD_ERROR_TITLE = 'Unable to load Case Support Console.';
const FIRST_RESPONSE_ERROR = 'Unable to record the first response.';

/**
 * NovaCare Case Support Console: one consolidated, cacheable Apex read feeds every section.
 * The component never writes SLA Status, SLA Breached or Escalation Level; those remain owned
 * by the server-side SLA engine (SLAService / SLAMonitoringService).
 */
export default class NovacareCaseSupportConsole extends LightningElement {
    @api recordId;

    consoleData;
    hasLoadError = false;
    isRefreshing = false;
    isMarking = false;
    wiredConsoleResult;

    @wire(getConsoleData, { caseId: '$recordId' })
    wiredConsole(result) {
        this.wiredConsoleResult = result;
        if (result.data) {
            this.consoleData = result.data;
            this.hasLoadError = false;
        } else if (result.error) {
            // Server details are intentionally not surfaced; the UI shows a fixed message.
            this.consoleData = undefined;
            this.hasLoadError = true;
        }
    }

    // State model: loading -> success | error
    get isLoading() {
        return !this.consoleData && !this.hasLoadError;
    }
    get hasData() {
        return !!this.consoleData;
    }
    get showRefreshSpinner() {
        return this.hasData && (this.isRefreshing || this.isMarking);
    }
    get loadErrorTitle() {
        return LOAD_ERROR_TITLE;
    }

    get caseInfo() {
        return this.consoleData?.caseInfo;
    }
    get sla() {
        return this.consoleData?.sla;
    }

    // Header
    get caseNumberLabel() {
        return hasValue(this.caseInfo?.caseNumber) ? `Case #${this.caseInfo.caseNumber}` : 'Case';
    }
    get subject() {
        return hasValue(this.caseInfo?.subject) ? this.caseInfo.subject : 'No subject';
    }
    get caseStatus() {
        return displayValue(this.caseInfo?.status);
    }
    get priorityLabel() {
        return hasValue(this.caseInfo?.priority) ? `${this.caseInfo.priority} Priority` : 'No Priority';
    }
    get priorityClass() {
        return toneClass('nc-pill', getPriorityTone(this.caseInfo?.priority));
    }
    get issueCategory() {
        return displayValue(this.caseInfo?.issueCategory);
    }
    get slaStatus() {
        return getSlaStatusMeta(this.sla?.slaStatus);
    }
    get slaBadgeClass() {
        return toneClass('status-badge', this.slaStatus.tone);
    }
    get slaBadgeLabel() {
        return `SLA status: ${this.slaStatus.label}`;
    }
    // A breach is historical fact (Task 04) and stays visible even after the SLA recovers.
    get showBreachFlag() {
        return this.sla?.slaBreached === true && this.sla?.slaStatus !== 'Breached';
    }

    async handleRefresh() {
        if (!this.wiredConsoleResult || this.isRefreshing) {
            return;
        }
        this.isRefreshing = true;
        try {
            await refreshApex(this.wiredConsoleResult);
        } catch (error) {
            // The wire handler has already switched to the error state if the reload failed.
            this.hasLoadError = !this.consoleData;
        } finally {
            this.isRefreshing = false;
        }
    }

    async handleMarkFirstResponse() {
        if (this.isMarking || !this.recordId) {
            return;
        }
        this.isMarking = true;
        try {
            await markFirstResponse({ caseId: this.recordId });
        } catch (error) {
            this.isMarking = false;
            this.showToast(FIRST_RESPONSE_ERROR, this.reduceActionError(error), 'error');
            return;
        }

        this.showToast('First response recorded', 'The first response time was saved using server time.', 'success');
        try {
            await refreshApex(this.wiredConsoleResult);
            // Keep the standard record page (details, highlights panel) in sync.
            await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
        } catch (error) {
            this.hasLoadError = !this.consoleData;
        } finally {
            this.isMarking = false;
        }
    }

    // markFirstResponse only throws controlled AuraHandledException messages.
    reduceActionError(error) {
        const message = error?.body?.message;
        return typeof message === 'string' && message.length > 0 ? message : 'Please try again.';
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
