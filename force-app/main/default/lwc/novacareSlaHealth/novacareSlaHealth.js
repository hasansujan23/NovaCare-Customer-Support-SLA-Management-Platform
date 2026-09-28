import { LightningElement, api } from 'lwc';
import {
    COUNTDOWN_INTERVAL_MS,
    buildFirstResponseView,
    buildResolutionView,
    getMonitoredObligation,
    getSlaStatusMeta,
    hasValue,
    toneClass
} from 'c/novacareSlaUtils';

/**
 * Renders the First Response and Resolution SLA cards.
 * The countdown is display-only: it ticks once a minute on the client and never calls Apex.
 * Official SLA Status is shown exactly as maintained by SLAMonitoringService.
 */
export default class NovacareSlaHealth extends LightningElement {
    @api caseInfo;
    @api canMarkFirstResponse = false;
    @api isMarking = false;

    now = Date.now();
    _sla;
    _timerId = null;

    @api
    get sla() {
        return this._sla;
    }
    set sla(value) {
        this._sla = value;
        // New server data (initial load or refresh) recomputes the countdown immediately.
        this.now = Date.now();
    }

    connectedCallback() {
        this.now = Date.now();
        this.syncTimer();
    }

    renderedCallback() {
        this.syncTimer();
    }

    disconnectedCallback() {
        this.stopTimer();
    }

    get isClosed() {
        return this.caseInfo?.isClosed === true;
    }

    // A closed case, or one without open deadlines, has nothing to count down.
    get needsCountdown() {
        if (this.isClosed || !this._sla) {
            return false;
        }
        const awaitingFirstResponse = hasValue(this._sla.firstResponseDue) && !hasValue(this._sla.firstRespondedAt);
        return awaitingFirstResponse || hasValue(this._sla.resolutionDue);
    }

    syncTimer() {
        if (this.needsCountdown) {
            this.startTimer();
        } else {
            this.stopTimer();
        }
    }

    startTimer() {
        if (this._timerId) {
            return;
        }
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._timerId = setInterval(() => {
            this.now = Date.now();
        }, COUNTDOWN_INTERVAL_MS);
    }

    stopTimer() {
        if (this._timerId) {
            clearInterval(this._timerId);
            this._timerId = null;
        }
    }

    get monitoredObligation() {
        return getMonitoredObligation(this._sla, this.isClosed);
    }

    get officialStatus() {
        return getSlaStatusMeta(this._sla?.slaStatus);
    }

    get officialStatusClass() {
        return toneClass('nc-pill', this.officialStatus.tone);
    }

    get firstResponse() {
        const cardView = buildFirstResponseView(this._sla, this.isClosed, this.now);
        return this.decorate(cardView, this.monitoredObligation === 'firstResponse');
    }

    get resolution() {
        const cardView = buildResolutionView(this._sla, this.isClosed, this.now);
        return this.decorate(cardView, this.monitoredObligation === 'resolution');
    }

    decorate(cardView, isMonitored) {
        return {
            ...cardView,
            isMonitored,
            cardClass: toneClass('sla-card', cardView.tone),
            stateClass: toneClass('sla-card__state', cardView.tone),
            detailClass: cardView.isOverdue ? 'sla-card__detail sla-card__detail_overdue' : 'sla-card__detail',
            outcomeClass: toneClass('nc-pill', cardView.tone)
        };
    }

    get hasFirstResponseDue() {
        return hasValue(this._sla?.firstResponseDue);
    }
    get hasFirstRespondedAt() {
        return hasValue(this._sla?.firstRespondedAt);
    }
    get hasResolutionDue() {
        return hasValue(this._sla?.resolutionDue);
    }
    get hasClosedDate() {
        return this.isClosed && hasValue(this.caseInfo?.closedDate);
    }
    get showMarkFirstResponse() {
        return this.canMarkFirstResponse && !this.isClosed && !this.hasFirstRespondedAt;
    }
    handleMarkFirstResponse() {
        this.dispatchEvent(new CustomEvent('markfirstresponse'));
    }
}
