import { createElement } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import NovacareCaseSupportConsole from 'c/novacareCaseSupportConsole';
import getConsoleData from '@salesforce/apex/CaseSupportConsoleController.getConsoleData';

jest.mock(
    '@salesforce/apex/CaseSupportConsoleController.getConsoleData',
    () => {
        const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
        return { default: createApexTestWireAdapter(jest.fn()) };
    },
    { virtual: true }
);

jest.mock(
    '@salesforce/apex/CaseSupportConsoleController.markFirstResponse',
    () => ({ default: jest.fn(() => Promise.resolve('2026-09-28T10:00:00.000Z')) }),
    { virtual: true }
);

jest.mock(
    '@salesforce/apex',
    () => ({ refreshApex: jest.fn(() => Promise.resolve()) }),
    { virtual: true }
);

const minutesFromNow = (minutes) => new Date(Date.now() + minutes * 60000).toISOString();

function consoleData(overrides = {}) {
    return {
        caseInfo: {
            caseId: '500000000000001AAA',
            caseNumber: '00001234',
            subject: 'API Integration Authentication Failure',
            status: 'Working',
            isClosed: false,
            priority: 'Critical',
            issueCategory: 'Integration'
        },
        customer: {
            accountId: '001000000000001AAA',
            accountName: 'Acme Corporation',
            contactId: '003000000000001AAA',
            contactName: 'John Smith',
            assetId: null,
            assetName: null
        },
        assignment: { ownerId: '00G000000000001AAA', ownerName: 'Integration Support', ownerType: 'Queue' },
        subscription: {
            subscriptionId: 'a00000000000001AAA',
            subscriptionName: 'SN-000001',
            supportPlan: 'Enterprise',
            subscriptionStatus: 'Active',
            startDate: '2026-01-01',
            endDate: '2026-12-31',
            support24x7: true
        },
        subscriptionAccessible: true,
        sla: {
            slaStatus: 'At Risk',
            slaBreached: false,
            escalationLevel: 'Level 1',
            firstResponseDue: minutesFromNow(-60),
            firstRespondedAt: minutesFromNow(-70),
            resolutionDue: minutesFromNow(42)
        },
        history: [],
        historyAccessible: true,
        canMarkFirstResponse: false,
        ...overrides
    };
}

async function flushPromises() {
    return Promise.resolve();
}

function render() {
    const element = createElement('c-novacare-case-support-console', { is: NovacareCaseSupportConsole });
    element.recordId = '500000000000001AAA';
    document.body.appendChild(element);
    return element;
}

function textOf(root) {
    return root.textContent.replace(/\s+/g, ' ');
}

describe('c-novacare-case-support-console', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
        jest.useRealTimers();
    });

    it('shows a spinner while loading', () => {
        const element = render();
        const spinner = element.shadowRoot.querySelector('lightning-spinner');
        expect(spinner).not.toBeNull();
        expect(spinner.alternativeText).toBe('Loading Case Support Console');
    });

    it('renders the header, sections and SLA badge on success', async () => {
        const element = render();
        getConsoleData.emit(consoleData());
        await flushPromises();

        const text = textOf(element.shadowRoot);
        expect(text).toContain('Case #00001234');
        expect(text).toContain('API Integration Authentication Failure');
        expect(text).toContain('Critical Priority');
        expect(text).toContain('At Risk');
        expect(element.shadowRoot.querySelector('.status-badge_warning')).not.toBeNull();
        expect(element.shadowRoot.querySelector('c-novacare-customer-summary')).not.toBeNull();
        expect(element.shadowRoot.querySelector('c-novacare-sla-health')).not.toBeNull();
        expect(element.shadowRoot.querySelector('c-novacare-escalation-timeline')).not.toBeNull();
    });

    it.each([
        ['On Track', 'status-badge_success'],
        ['Breached', 'status-badge_error'],
        ['Completed', 'status-badge_info']
    ])('renders the %s badge with text and tone', async (status, badgeClass) => {
        const element = render();
        const data = consoleData();
        getConsoleData.emit({ ...data, sla: { ...data.sla, slaStatus: status } });
        await flushPromises();

        const badge = element.shadowRoot.querySelector(`.${badgeClass}`);
        expect(badge).not.toBeNull();
        expect(badge.textContent).toContain(status);
    });

    it('shows a generic error without server details', async () => {
        const element = render();
        getConsoleData.error({ message: 'List has no rows for assignment to SObject' });
        await flushPromises();

        const text = textOf(element.shadowRoot);
        expect(text).toContain('Unable to load Case Support Console.');
        expect(text).not.toContain('List has no rows');
    });

    it('never renders null or undefined for missing values', async () => {
        const element = render();
        getConsoleData.emit(consoleData());
        await flushPromises();

        const summary = element.shadowRoot.querySelector('c-novacare-customer-summary');
        const text = textOf(summary.shadowRoot);
        expect(text).toContain('—');
        expect(text).not.toMatch(/undefined|null/);
    });

    it('renders an empty timeline state', async () => {
        const element = render();
        getConsoleData.emit(consoleData());
        await flushPromises();

        const timeline = element.shadowRoot.querySelector('c-novacare-escalation-timeline');
        expect(textOf(timeline.shadowRoot)).toContain('No SLA escalations have occurred for this case.');
        expect(timeline.shadowRoot.querySelector('ol')).toBeNull();
    });

    it('renders escalation history newest first as provided by the server', async () => {
        const element = render();
        getConsoleData.emit(
            consoleData({
                history: [
                    { historyId: 'h2', escalatedAt: minutesFromNow(-5), slaType: 'Resolution', previousSlaStatus: 'At Risk', newSlaStatus: 'Breached', escalationLevel: 'Level 2' },
                    { historyId: 'h1', escalatedAt: minutesFromNow(-60), slaType: 'Resolution', previousSlaStatus: 'On Track', newSlaStatus: 'At Risk', escalationLevel: 'Level 1' }
                ]
            })
        );
        await flushPromises();

        const timeline = element.shadowRoot.querySelector('c-novacare-escalation-timeline');
        const titles = [...timeline.shadowRoot.querySelectorAll('.timeline__title')].map((node) => node.textContent);
        expect(titles).toHaveLength(2);
        expect(titles[0]).toContain('Resolution SLA breached');
        expect(titles[1]).toContain('Resolution SLA entered At Risk');
    });

    it('refreshes server data through refreshApex without reloading the page', async () => {
        const element = render();
        getConsoleData.emit(consoleData());
        await flushPromises();

        const refreshButton = [...element.shadowRoot.querySelectorAll('lightning-button')].find(
            (button) => button.label === 'Refresh'
        );
        refreshButton.click();
        await flushPromises();

        expect(refreshApex).toHaveBeenCalledTimes(1);
    });

    it('shows resolution countdown and first response outcome in the SLA cards', async () => {
        const element = render();
        getConsoleData.emit(consoleData());
        await flushPromises();

        const health = element.shadowRoot.querySelector('c-novacare-sla-health');
        const text = textOf(health.shadowRoot);
        expect(text).toContain('Responded');
        expect(text).toContain('Met SLA');
        expect(text).toMatch(/4[12]m remaining/);
    });

    it('clears the countdown interval when removed from the DOM', async () => {
        jest.useFakeTimers();
        const clearSpy = jest.spyOn(window, 'clearInterval');
        const element = render();
        getConsoleData.emit(consoleData());
        await flushPromises();

        document.body.removeChild(element);

        expect(clearSpy).toHaveBeenCalled();
        clearSpy.mockRestore();
    });
});
