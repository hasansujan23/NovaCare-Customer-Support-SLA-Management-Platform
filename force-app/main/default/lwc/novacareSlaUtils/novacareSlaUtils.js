/**
 * Display-only helpers for the NovaCare Case Support Console.
 *
 * Nothing in this module decides official SLA state. SLA Status, SLA Breached and
 * Escalation Level are owned by SLAService / SLAMonitoringService and are only read here.
 * Countdown values are presentation aids and may run ahead of the next monitoring batch.
 */

export const EMPTY_VALUE = '—';
export const COUNTDOWN_INTERVAL_MS = 60000;

const MS_PER_MINUTE = 60000;
const MINUTES_PER_HOUR = 60;
const MINUTES_PER_DAY = 1440;

const SLA_STATUS_META = {
    'Not Started': { label: 'Not Started', icon: 'utility:clock', iconAlt: 'Not started', tone: 'neutral' },
    'On Track': { label: 'On Track', icon: 'utility:success', iconAlt: 'On track', tone: 'success' },
    'At Risk': { label: 'At Risk', icon: 'utility:warning', iconAlt: 'Warning', tone: 'warning' },
    Breached: { label: 'Breached', icon: 'utility:error', iconAlt: 'Breached', tone: 'error' },
    Completed: { label: 'Completed', icon: 'utility:check', iconAlt: 'Completed', tone: 'info' }
};

const ESCALATION_TONES = {
    None: 'neutral',
    'Level 1': 'warning',
    'Level 2': 'error',
    Management: 'error'
};

const PRIORITY_TONES = {
    Critical: 'error',
    High: 'warning',
    Medium: 'info',
    Low: 'neutral'
};

export function hasValue(value) {
    return value !== null && value !== undefined && value !== '';
}

export function displayValue(value) {
    return hasValue(value) ? String(value) : EMPTY_VALUE;
}

export function toTimestamp(value) {
    if (!hasValue(value)) {
        return null;
    }
    const timestamp = value instanceof Date ? value.getTime() : new Date(value).getTime();
    return Number.isNaN(timestamp) ? null : timestamp;
}

/**
 * Whole minutes from `now` until `deadline` (negative when overdue), truncated toward zero
 * so that anything under a minute either side of the deadline counts as "due now".
 */
export function minutesUntil(deadline, now = Date.now()) {
    const due = toTimestamp(deadline);
    const current = toTimestamp(now);
    if (due === null || current === null) {
        return null;
    }
    return Math.trunc((due - current) / MS_PER_MINUTE);
}

/** 125 → "2h 5m", 30 → "30m", 120 → "2h", 1500 → "1d 1h". */
export function formatDuration(totalMinutes) {
    if (totalMinutes === null || totalMinutes === undefined || Number.isNaN(totalMinutes)) {
        return EMPTY_VALUE;
    }
    const minutes = Math.abs(Math.trunc(totalMinutes));
    const days = Math.floor(minutes / MINUTES_PER_DAY);
    const hours = Math.floor((minutes % MINUTES_PER_DAY) / MINUTES_PER_HOUR);
    const remainder = minutes % MINUTES_PER_HOUR;

    if (days > 0) {
        return hours > 0 ? `${days}d ${hours}h` : `${days}d`;
    }
    if (hours > 0) {
        return remainder > 0 ? `${hours}h ${remainder}m` : `${hours}h`;
    }
    return `${remainder}m`;
}

/** "2h 5m remaining", "Due now", "1h 15m overdue", or "—" when there is no deadline. */
export function formatCountdown(deadline, now = Date.now()) {
    const minutes = minutesUntil(deadline, now);
    if (minutes === null) {
        return EMPTY_VALUE;
    }
    if (minutes === 0) {
        return 'Due now';
    }
    const duration = formatDuration(minutes);
    return minutes > 0 ? `${duration} remaining` : `${duration} overdue`;
}

export function getSlaStatusMeta(status) {
    if (!hasValue(status)) {
        return { label: 'No SLA', icon: 'utility:clock', iconAlt: 'No SLA applied', tone: 'neutral' };
    }
    return SLA_STATUS_META[status] || { label: status, icon: 'utility:info', iconAlt: status, tone: 'neutral' };
}

export function getEscalationTone(level) {
    return ESCALATION_TONES[level] || 'neutral';
}

export function getPriorityTone(priority) {
    return PRIORITY_TONES[priority] || 'neutral';
}

export function toneClass(base, tone) {
    return `${base} ${base}_${tone || 'neutral'}`;
}

/**
 * The official SLA Status describes the obligation currently being monitored: first response
 * until one is recorded, then resolution. Used only to label which card the badge refers to.
 */
export function getMonitoredObligation(sla, isClosed) {
    if (isClosed || !sla) {
        return null;
    }
    return hasValue(sla.firstRespondedAt) ? 'resolution' : 'firstResponse';
}

function view(stateLabel, icon, iconAlt, tone, extra = {}) {
    return { stateLabel, icon, iconAlt, tone, detail: null, outcome: null, isOverdue: false, ...extra };
}

export function buildFirstResponseView(sla, isClosed, now = Date.now()) {
    const due = toTimestamp(sla && sla.firstResponseDue);
    const respondedAt = toTimestamp(sla && sla.firstRespondedAt);

    if (respondedAt !== null) {
        if (due === null) {
            return view('Responded', 'utility:success', 'Responded', 'neutral');
        }
        if (respondedAt <= due) {
            return view('Responded', 'utility:success', 'Responded', 'success', { outcome: 'Met SLA' });
        }
        const lateBy = formatDuration(Math.max(1, Math.trunc((respondedAt - due) / MS_PER_MINUTE)));
        return view('Responded Late', 'utility:error', 'Responded late', 'error', {
            outcome: 'SLA Missed',
            detail: `${lateBy} after the deadline`
        });
    }

    if (isClosed) {
        return view('Not Recorded', 'utility:ban', 'Not recorded', 'neutral', {
            detail: 'Case closed without a recorded first response.'
        });
    }
    if (due === null) {
        return view('No SLA Target', 'utility:clock', 'No SLA target', 'neutral', {
            detail: 'No first response target applies to this case.'
        });
    }

    const minutes = minutesUntil(due, now);
    if (minutes < 0) {
        return view('Response Overdue', 'utility:error', 'Response overdue', 'error', {
            detail: formatCountdown(due, now),
            isOverdue: true
        });
    }
    return view('Awaiting Response', 'utility:clock', 'Awaiting response', 'info', {
        detail: formatCountdown(due, now)
    });
}

export function buildResolutionView(sla, isClosed, now = Date.now()) {
    if (isClosed) {
        return view('Completed', 'utility:check', 'Completed', 'success', { outcome: 'Case closed' });
    }

    const due = toTimestamp(sla && sla.resolutionDue);
    if (due === null) {
        return view('No SLA Target', 'utility:clock', 'No SLA target', 'neutral', {
            detail: 'No resolution target applies to this case.'
        });
    }

    const minutes = minutesUntil(due, now);
    if (minutes < 0) {
        return view('Overdue', 'utility:error', 'Overdue', 'error', {
            detail: formatCountdown(due, now),
            isOverdue: true
        });
    }
    return view('In Progress', 'utility:clock', 'In progress', 'info', { detail: formatCountdown(due, now) });
}

function describeTransition(slaType, newStatus) {
    const subject = hasValue(slaType) ? `${slaType} SLA` : 'SLA';
    if (newStatus === 'At Risk') {
        return `${subject} entered At Risk`;
    }
    if (newStatus === 'Breached') {
        return `${subject} breached`;
    }
    return hasValue(newStatus) ? `${subject} changed to ${newStatus}` : `${subject} escalated`;
}

export function buildTimelineItems(history) {
    if (!Array.isArray(history)) {
        return [];
    }
    return history.map((entry, index) => {
        const statusMeta = getSlaStatusMeta(entry.newSlaStatus);
        const hasTransition = hasValue(entry.previousSlaStatus) && hasValue(entry.newSlaStatus);
        return {
            key: entry.historyId || `history-${index}`,
            escalatedAt: entry.escalatedAt,
            hasEscalatedAt: hasValue(entry.escalatedAt),
            title: describeTransition(entry.slaType, entry.newSlaStatus),
            icon: statusMeta.icon,
            iconAlt: statusMeta.iconAlt,
            markerClass: toneClass('timeline__marker', statusMeta.tone),
            hasLevel: hasValue(entry.escalationLevel),
            levelLabel: hasValue(entry.escalationLevel) ? `Escalated to ${entry.escalationLevel}` : null,
            levelClass: toneClass('nc-pill', getEscalationTone(entry.escalationLevel)),
            hasTransition,
            transition: hasTransition ? `${entry.previousSlaStatus} → ${entry.newSlaStatus}` : null,
            hasReason: hasValue(entry.reason),
            reason: entry.reason,
            hasSlaDueAt: hasValue(entry.slaDueAt),
            slaDueAt: entry.slaDueAt,
            showConnector: index < history.length - 1
        };
    });
}
