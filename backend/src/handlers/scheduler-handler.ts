import { BatchResponse } from 'firebase-admin/messaging';

import { logger } from '../lib/logger.js';
import { adminMessaging } from '../services/firebase-admin.js';
import {
  fetchDueReminders,
  listUserFcmTokens,
  markReminderFired,
} from '../services/tool-executor.js';

type ApiResponse = {
  statusCode: number;
  headers?: Record<string, string>;
  body: string;
};

const json = (statusCode: number, payload: Record<string, unknown>): ApiResponse => ({
  statusCode,
  headers: { 'content-type': 'application/json' },
  body: JSON.stringify(payload),
});

const sendReminderNotification = async (
  userId: string,
  reminderId: string,
  data: Record<string, unknown>,
): Promise<BatchResponse | null> => {
  const tokens = await listUserFcmTokens(userId);
  if (tokens.length === 0) {
    return null;
  }

  return adminMessaging().sendEachForMulticast({
    tokens,
    notification: {
      title: 'Juno Reminder',
      body: typeof data.message === 'string' ? data.message : 'Reminder due now',
    },
    data: {
      type: 'reminder',
      reminder_id: reminderId,
      user_id: userId,
      created_via:
        typeof data.created_via === 'string' ? data.created_via : 'scheduler',
    },
    android: {
      priority: 'high',
    },
    apns: {
      payload: {
        aps: {
          sound: 'default',
          category: 'JUNO_REMINDER',
        },
      },
    },
  });
};

export const handleSchedulerTick = async (): Promise<ApiResponse> => {
  try {
    const reminders = await fetchDueReminders();
    let delivered = 0;

    for (const reminder of reminders) {
      const result = await sendReminderNotification(
        reminder.userId,
        reminder.reminderId,
        reminder.data,
      );
      if (result && result.successCount > 0) {
        delivered += 1;
        await markReminderFired(reminder.userId, reminder.reminderId);
      }
    }

    return json(200, {
      scanned: reminders.length,
      delivered,
    });
  } catch (error) {
    logger.error('handleSchedulerTick failed', {
      error: error instanceof Error ? error.message : String(error),
    });
    return json(500, {
      error: 'Scheduler execution failed.',
    });
  }
};
