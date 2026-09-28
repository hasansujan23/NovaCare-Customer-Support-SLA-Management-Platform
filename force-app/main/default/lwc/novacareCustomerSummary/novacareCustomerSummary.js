import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { displayValue, getEscalationTone, getPriorityTone, hasValue, toneClass } from 'c/novacareSlaUtils';

const SUBSCRIPTION_STATUS_TONES = {
    Active: 'success',
    Draft: 'neutral',
    Expired: 'error',
    Cancelled: 'error'
};

export default class NovacareCustomerSummary extends NavigationMixin(LightningElement) {
    @api customer;
    @api subscription;
    @api subscriptionAccessible = false;
    @api assignment;
    @api caseInfo;
    @api sla;

    // Customer
    get accountName() {
        return displayValue(this.customer?.accountName);
    }
    get canOpenAccount() {
        return hasValue(this.customer?.accountId) && hasValue(this.customer?.accountName);
    }
    get contactName() {
        return displayValue(this.customer?.contactName);
    }
    get canOpenContact() {
        return hasValue(this.customer?.contactId) && hasValue(this.customer?.contactName);
    }
    get assetName() {
        return displayValue(this.customer?.assetName);
    }
    get canOpenAsset() {
        return hasValue(this.customer?.assetId) && hasValue(this.customer?.assetName);
    }

    // Support subscription
    get hasSubscription() {
        return this.subscriptionAccessible && !!this.subscription;
    }
    get subscriptionUnavailableMessage() {
        return this.subscriptionAccessible
            ? 'No support subscription is linked to this case.'
            : 'Subscription details are not available with your current permissions.';
    }
    get supportPlan() {
        return displayValue(this.subscription?.supportPlan);
    }
    get subscriptionStatus() {
        return displayValue(this.subscription?.subscriptionStatus);
    }
    get subscriptionStatusClass() {
        return toneClass('nc-pill', SUBSCRIPTION_STATUS_TONES[this.subscription?.subscriptionStatus]);
    }
    get subscriptionName() {
        return displayValue(this.subscription?.subscriptionName);
    }
    get hasCoverage() {
        return this.subscription?.support24x7 === true || this.subscription?.support24x7 === false;
    }
    get coverageLabel() {
        return this.subscription?.support24x7 ? '24×7 Coverage' : 'Standard Coverage';
    }
    get coverageClass() {
        return toneClass('nc-pill', this.subscription?.support24x7 ? 'info' : 'neutral');
    }
    get hasStartDate() {
        return hasValue(this.subscription?.startDate);
    }
    get hasEndDate() {
        return hasValue(this.subscription?.endDate);
    }

    // Assignment
    get ownerName() {
        return displayValue(this.assignment?.ownerName);
    }
    get isQueueOwner() {
        return this.assignment?.ownerType === 'Queue';
    }
    get ownerTypeLabel() {
        return this.isQueueOwner ? 'Queue' : 'User';
    }
    get hasOwnerType() {
        return hasValue(this.assignment?.ownerType);
    }
    get ownerIcon() {
        return this.isQueueOwner ? 'standard:groups' : 'standard:user';
    }
    // Queues have no standard record page for agents, so only User owners are navigable.
    get canOpenOwner() {
        return !this.isQueueOwner && hasValue(this.assignment?.ownerId) && hasValue(this.assignment?.ownerName);
    }
    get priority() {
        return displayValue(this.caseInfo?.priority);
    }
    get priorityClass() {
        return toneClass('nc-pill', getPriorityTone(this.caseInfo?.priority));
    }
    get issueCategory() {
        return displayValue(this.caseInfo?.issueCategory);
    }
    get escalationLevel() {
        return displayValue(this.sla?.escalationLevel);
    }
    get escalationClass() {
        return toneClass('nc-pill', getEscalationTone(this.sla?.escalationLevel));
    }

    handleNavigate(event) {
        const recordId = event.currentTarget.dataset.recordId;
        if (!recordId) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId, actionName: 'view' }
        });
    }
}
