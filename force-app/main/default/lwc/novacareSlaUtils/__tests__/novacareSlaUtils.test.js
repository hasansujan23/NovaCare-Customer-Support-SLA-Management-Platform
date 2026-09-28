import {
    EMPTY_VALUE,
    buildFirstResponseView,
    buildResolutionView,
    buildTimelineItems,
    displayValue,
    formatCountdown,
    formatDuration,
    getMonitoredObligation,
    getSlaStatusMeta
} from 'c/novacareSlaUtils';

const NOW = new Date('2026-09-28T10:00:00.000Z').getTime();
const minutesFromNow = (minutes) => new Date(NOW + minutes * 60000).toISOString();

describe('formatDuration', () => {
    it.each([
        [125, '2h 5m'],
        [30, '30m'],
        [120, '2h'],
        [0, '0m'],
        [1500, '1d 1h'],
        [2880, '2d']
    ])('formats %i minutes as %s', (minutes, expected) => {
        expect(formatDuration(minutes)).toBe(expected);
    });

    it('returns the empty marker for missing input', () => {
        expect(formatDuration(null)).toBe(EMPTY_VALUE);
    });
});

describe('formatCountdown', () => {
    it('formats remaining time', () => {
        expect(formatCountdown(minutesFromNow(125), NOW)).toBe('2h 5m remaining');
        expect(formatCountdown(minutesFromNow(30), NOW)).toBe('30m remaining');
    });

    it('formats overdue time', () => {
        expect(formatCountdown(minutesFromNow(-75), NOW)).toBe('1h 15m overdue');
    });

    it('treats anything within a minute of the deadline as due now', () => {
        expect(formatCountdown(new Date(NOW + 30000).toISOString(), NOW)).toBe('Due now');
        expect(formatCountdown(new Date(NOW - 59000).toISOString(), NOW)).toBe('Due now');
        expect(formatCountdown(new Date(NOW - 60000).toISOString(), NOW)).toBe('1m overdue');
    });

    it('returns the empty marker without a deadline', () => {
        expect(formatCountdown(null, NOW)).toBe(EMPTY_VALUE);
        expect(formatCountdown('not-a-date', NOW)).toBe(EMPTY_VALUE);
    });
});

describe('displayValue and status metadata', () => {
    it('never renders null or undefined', () => {
        expect(displayValue(null)).toBe(EMPTY_VALUE);
        expect(displayValue(undefined)).toBe(EMPTY_VALUE);
        expect(displayValue('')).toBe(EMPTY_VALUE);
        expect(displayValue('Acme')).toBe('Acme');
    });

    it.each([
        ['On Track', 'success'],
        ['At Risk', 'warning'],
        ['Breached', 'error'],
        ['Completed', 'info'],
        ['Not Started', 'neutral']
    ])('maps %s to a labelled %s tone', (status, tone) => {
        const meta = getSlaStatusMeta(status);
        expect(meta.label).toBe(status);
        expect(meta.tone).toBe(tone);
        expect(meta.icon).toMatch(/^utility:/);
    });

    it('labels a missing status', () => {
        expect(getSlaStatusMeta(null).label).toBe('No SLA');
    });
});

describe('buildFirstResponseView', () => {
    it('shows awaiting response with remaining time', () => {
        const view = buildFirstResponseView({ firstResponseDue: minutesFromNow(42) }, false, NOW);
        expect(view.stateLabel).toBe('Awaiting Response');
        expect(view.detail).toBe('42m remaining');
    });

    it('shows met SLA when responded before the deadline', () => {
        const view = buildFirstResponseView(
            { firstResponseDue: minutesFromNow(-10), firstRespondedAt: minutesFromNow(-22) },
            false,
            NOW
        );
        expect(view.stateLabel).toBe('Responded');
        expect(view.outcome).toBe('Met SLA');
    });

    it('shows a late response as SLA missed', () => {
        const view = buildFirstResponseView(
            { firstResponseDue: minutesFromNow(-30), firstRespondedAt: minutesFromNow(-10) },
            false,
            NOW
        );
        expect(view.stateLabel).toBe('Responded Late');
        expect(view.outcome).toBe('SLA Missed');
        expect(view.detail).toBe('20m after the deadline');
    });

    it('shows response overdue when no response and deadline passed', () => {
        const view = buildFirstResponseView({ firstResponseDue: minutesFromNow(-75) }, false, NOW);
        expect(view.stateLabel).toBe('Response Overdue');
        expect(view.detail).toBe('1h 15m overdue');
        expect(view.isOverdue).toBe(true);
    });

    it('does not count down on a closed case', () => {
        const view = buildFirstResponseView({ firstResponseDue: minutesFromNow(-75) }, true, NOW);
        expect(view.stateLabel).toBe('Not Recorded');
    });
});

describe('buildResolutionView', () => {
    it('shows remaining time for an open case', () => {
        const view = buildResolutionView({ resolutionDue: minutesFromNow(102) }, false, NOW);
        expect(view.stateLabel).toBe('In Progress');
        expect(view.detail).toBe('1h 42m remaining');
    });

    it('shows overdue duration for an open case', () => {
        const view = buildResolutionView({ resolutionDue: minutesFromNow(-37) }, false, NOW);
        expect(view.stateLabel).toBe('Overdue');
        expect(view.detail).toBe('37m overdue');
    });

    it('shows completed without a countdown for a closed case', () => {
        const view = buildResolutionView({ resolutionDue: minutesFromNow(-37) }, true, NOW);
        expect(view.stateLabel).toBe('Completed');
        expect(view.detail).toBeNull();
    });
});

describe('getMonitoredObligation', () => {
    it('follows the obligation the official status describes', () => {
        expect(getMonitoredObligation({ firstRespondedAt: null }, false)).toBe('firstResponse');
        expect(getMonitoredObligation({ firstRespondedAt: minutesFromNow(-5) }, false)).toBe('resolution');
        expect(getMonitoredObligation({}, true)).toBeNull();
    });
});

describe('buildTimelineItems', () => {
    it('describes each escalation and omits the connector after the last item', () => {
        const items = buildTimelineItems([
            { historyId: 'a2', newSlaStatus: 'Breached', previousSlaStatus: 'At Risk', slaType: 'Resolution', escalationLevel: 'Level 2' },
            { historyId: 'a1', newSlaStatus: 'At Risk', previousSlaStatus: 'On Track', slaType: 'Resolution', escalationLevel: 'Level 1' }
        ]);
        expect(items[0].title).toBe('Resolution SLA breached');
        expect(items[0].levelLabel).toBe('Escalated to Level 2');
        expect(items[0].transition).toBe('At Risk → Breached');
        expect(items[1].title).toBe('Resolution SLA entered At Risk');
        expect(items[0].showConnector).toBe(true);
        expect(items[1].showConnector).toBe(false);
    });

    it('returns an empty list for missing history', () => {
        expect(buildTimelineItems(undefined)).toEqual([]);
    });
});
