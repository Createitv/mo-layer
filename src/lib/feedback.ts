export const feedbackStatuses = ['new', 'reviewing', 'planned', 'done', 'rejected'] as const;

export const feedbackTypes = ['feature', 'bug', 'privacy', 'sync', 'billing', 'other'] as const;

export type FeedbackStatus = (typeof feedbackStatuses)[number];
export type FeedbackType = (typeof feedbackTypes)[number];

export const feedbackStatusLabels: Record<FeedbackStatus, string> = {
  new: 'New',
  reviewing: 'Reviewing',
  planned: 'Planned',
  done: 'Done',
  rejected: 'Rejected'
};

export const feedbackTypeLabels: Record<FeedbackType, string> = {
  feature: 'Feature request',
  bug: 'Bug report',
  privacy: 'Privacy concern',
  sync: 'Sync or recovery',
  billing: 'Billing',
  other: 'Other'
};
