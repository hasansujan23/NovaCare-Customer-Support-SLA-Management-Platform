import { LightningElement, api } from 'lwc';
import { buildTimelineItems } from 'c/novacareSlaUtils';

export default class NovacareEscalationTimeline extends LightningElement {
    @api history = [];
    @api accessible = false;

    get items() {
        return buildTimelineItems(this.history);
    }

    get hasItems() {
        return this.accessible && this.items.length > 0;
    }

    get isEmpty() {
        return this.accessible && this.items.length === 0;
    }
}
