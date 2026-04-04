import { randomUUID } from 'node:crypto';

import { FieldPath, Timestamp } from 'firebase-admin/firestore';
import { calendar_v3, google } from 'googleapis';

import { env } from '../config/env.js';
import { logger } from '../lib/logger.js';
import { adminFirestore } from './firebase-admin.js';

type ToolResult = Record<string, unknown>;

type ReminderStatus = 'pending' | 'fired' | 'dismissed' | 'snoozed';
type MemoryCategory = 'preferences' | 'facts' | 'habits' | 'health' | 'routines';

export class ToolExecutor {
  constructor(private readonly userId: string) {}

  async execute(toolName: string, input: Record<string, unknown>): Promise<ToolResult> {
    switch (toolName) {
      case 'set_reminder':
        return this.setReminder(input);
      case 'list_reminders':
        return this.listReminders(input);
      case 'cancel_reminder':
        return this.cancelReminder(input);
      case 'create_calendar_event':
        return this.createCalendarEvent(input);
      case 'get_upcoming_events':
        return this.getUpcomingEvents(input);
      case 'store_memory':
        return this.storeMemory(input);
      case 'query_memory':
        return this.queryMemory(input);
      case 'analyze_nutrition':
        return this.analyzeNutrition(input);
      case 'get_user_context':
        return this.getUserContext(input);
      default:
        throw new Error(`Unsupported tool: ${toolName}`);
    }
  }

  private userRef() {
    return adminFirestore().collection('users').doc(this.userId);
  }

  private remindersRef() {
    return this.userRef().collection('reminders');
  }

  private memoriesRef() {
    return this.userRef().collection('memories');
  }

  private nutritionLogsRef() {
    return this.userRef().collection('nutrition_logs');
  }

  private async setReminder(input: Record<string, unknown>): Promise<ToolResult> {
    const message = String(input.message ?? '').trim();
    const delayMinutes = Number(input.delay_minutes ?? 0);
    const priority = String(input.priority ?? 'normal');

    if (!message || !Number.isFinite(delayMinutes) || delayMinutes <= 0) {
      throw new Error('set_reminder requires a message and a positive delay_minutes.');
    }

    const id = randomUUID();
    const triggerAt = new Date(Date.now() + delayMinutes * 60_000);
    await this.remindersRef().doc(id).set({
      message,
      trigger_at: triggerAt.toISOString(),
      status: 'pending',
      priority,
      created_via: 'voice',
      snooze_count: 0,
      created_at: new Date().toISOString(),
    });

    return {
      reminder_id: id,
      message,
      trigger_at: triggerAt.toISOString(),
      status: 'pending',
      priority,
    };
  }

  private async listReminders(input: Record<string, unknown>): Promise<ToolResult> {
    const statusFilter = String(input.status_filter ?? 'pending') as
      | 'pending'
      | 'fired'
      | 'all';

    let query:
      | FirebaseFirestore.Query<FirebaseFirestore.DocumentData>
      | FirebaseFirestore.CollectionReference<FirebaseFirestore.DocumentData> =
      this.remindersRef().orderBy('trigger_at');

    if (statusFilter !== 'all') {
      query = query.where('status', '==', statusFilter);
    }

    const snapshot = await query.get();
    return {
      reminders: snapshot.docs.map((doc) => ({
        reminder_id: doc.id,
        ...doc.data(),
      })),
    };
  }

  private async cancelReminder(input: Record<string, unknown>): Promise<ToolResult> {
    const reminderId = String(input.reminder_id ?? '').trim();
    if (!reminderId) {
      throw new Error('cancel_reminder requires reminder_id.');
    }

    await this.remindersRef().doc(reminderId).update({
      status: 'dismissed',
      dismissed_at: new Date().toISOString(),
    });

    return {
      reminder_id: reminderId,
      status: 'dismissed',
    };
  }

  private async storeMemory(input: Record<string, unknown>): Promise<ToolResult> {
    const key = String(input.key ?? '').trim();
    const value = String(input.value ?? '').trim();
    const category = String(input.category ?? 'facts') as MemoryCategory;

    if (!key || !value) {
      throw new Error('store_memory requires key and value.');
    }

    const existing = await this.memoriesRef().where('key', '==', key).limit(1).get();
    const id = existing.docs[0]?.id ?? randomUUID();
    const now = new Date().toISOString();

    await this.memoriesRef().doc(id).set(
      {
        key,
        value,
        category,
        source: 'voice',
        created_at: existing.docs[0]?.get('created_at') ?? now,
        updated_at: now,
      },
      { merge: true },
    );

    return {
      memory_id: id,
      key,
      value,
      category,
    };
  }

  private async queryMemory(input: Record<string, unknown>): Promise<ToolResult> {
    const queryText = String(input.query ?? '').trim().toLowerCase();
    const categoryFilter = String(input.category_filter ?? 'all');
    if (!queryText) {
      throw new Error('query_memory requires query.');
    }

    let query:
      | FirebaseFirestore.Query<FirebaseFirestore.DocumentData>
      | FirebaseFirestore.CollectionReference<FirebaseFirestore.DocumentData> =
      this.memoriesRef().orderBy(FieldPath.documentId());

    if (categoryFilter !== 'all') {
      query = query.where('category', '==', categoryFilter);
    }

    const snapshot = await query.get();
    const allMemories = snapshot.docs
      .map((doc) => ({
        memory_id: doc.id,
        ...doc.data(),
      }));

    const matches = (queryText
      ? allMemories.filter((memory) => {
        const haystack = `${String(memory.key)} ${String(memory.value)}`.toLowerCase();
        return haystack.includes(queryText);
      })
      : allMemories)
      .slice(0, 10);

    return { matches };
  }

  private async createCalendarEvent(input: Record<string, unknown>): Promise<ToolResult> {
    const title = String(input.title ?? '').trim();
    const startTime = String(input.start_time ?? '').trim();
    const endTime = input.end_time ? String(input.end_time) : undefined;

    if (!title || !startTime) {
      throw new Error('create_calendar_event requires title and start_time.');
    }

    const calendar = await this.getCalendarClient();
    if (!calendar) {
      return {
        configured: false,
        message: 'Google Calendar is not configured for this user.',
      };
    }

    const response = await calendar.events.insert({
      calendarId: 'primary',
      requestBody: {
        summary: title,
        description: input.description ? String(input.description) : undefined,
        location: input.location ? String(input.location) : undefined,
        start: {
          dateTime: startTime,
        },
        end: {
          dateTime: endTime ?? new Date(new Date(startTime).getTime() + 30 * 60_000).toISOString(),
        },
      },
    });

    return {
      configured: true,
      event_id: response.data.id,
      html_link: response.data.htmlLink,
      status: response.data.status,
    };
  }

  private async getUpcomingEvents(input: Record<string, unknown>): Promise<ToolResult> {
    const hoursAhead = Number(input.hours_ahead ?? 24);
    const calendar = await this.getCalendarClient();
    if (!calendar) {
      return {
        configured: false,
        events: [],
      };
    }

    const now = new Date();
    const end = new Date(now.getTime() + hoursAhead * 60 * 60_000);
    const response = await calendar.events.list({
      calendarId: 'primary',
      timeMin: now.toISOString(),
      timeMax: end.toISOString(),
      singleEvents: true,
      orderBy: 'startTime',
      maxResults: 20,
    });

    return {
      configured: true,
      events: (response.data.items ?? []).map((event) => ({
        id: event.id,
        title: event.summary,
        start_time: event.start?.dateTime ?? event.start?.date,
        end_time: event.end?.dateTime ?? event.end?.date,
        location: event.location,
      })),
    };
  }

  private async analyzeNutrition(input: Record<string, unknown>): Promise<ToolResult> {
    const ocrText = String(input.ocr_text ?? '').trim();
    if (!ocrText) {
      throw new Error('analyze_nutrition requires ocr_text.');
    }

    const extractNumber = (pattern: RegExp): number | null => {
      const match = pattern.exec(ocrText);
      if (!match) return null;
      return Number(match[1]);
    };

    const calories = extractNumber(/calories\s+(\d+)/i);
    const protein = extractNumber(/protein\s+(\d+)/i);
    const sugar = extractNumber(/sugars?\s+(\d+)/i);
    const sodium = extractNumber(/sodium\s+(\d+)/i);
    const quantity = typeof input.quantity === 'number' ? input.quantity : 1;

    const concerns = [
      if ((sugar ?? 0) * quantity >= 20) 'high sugar',
      if ((sodium ?? 0) * quantity >= 600) 'high sodium',
      if ((protein ?? 0) * quantity <= 5) 'low protein',
    ];

    const recommendation =
        concerns.contains('high sugar') || concerns.contains('high sodium')
          ? 'moderate'
          : 'eat';

    const logId = randomUUID();
    await this.nutritionLogsRef().doc(logId).set({
      ocr_text: ocrText,
      occasion: input.occasion ?? null,
      quantity,
      is_cheat_meal: input.is_cheat_meal ?? null,
      analysis: `Calories: ${calories ?? 'unknown'}, protein: ${protein ?? 'unknown'}g, sugar: ${sugar ?? 'unknown'}g, sodium: ${sodium ?? 'unknown'}mg.`,
      recommendation,
      timestamp: new Date().toISOString(),
    });

    return {
      nutrition_log_id: logId,
      calories,
      protein_grams: protein,
      sugar_grams: sugar,
      sodium_mg: sodium,
      quantity,
      concerns,
      recommendation,
    };
  }

  private async getUserContext(input: Record<string, unknown>): Promise<ToolResult> {
    const includeMemories = input.include_memories !== false;
    const includeReminders = input.include_reminders !== false;
    const includeEvents = input.include_events !== false;

    const [memories, reminders, events] = await Promise.all([
      includeMemories
        ? this.queryMemory({ query: '', category_filter: 'all' }).catch(() => ({ matches: [] }))
        : Promise.resolve({ matches: [] }),
      includeReminders ? this.listReminders({ status_filter: 'pending' }).catch(() => ({ reminders: [] })) : Promise.resolve({ reminders: [] }),
      includeEvents ? this.getUpcomingEvents({ hours_ahead: 24 }).catch(() => ({ events: [] })) : Promise.resolve({ events: [] }),
    ]);

    return {
      user_id: this.userId,
      memories: memories.matches ?? [],
      reminders: reminders.reminders ?? [],
      upcoming_events: events.events ?? [],
    };
  }

  private async getCalendarClient(): Promise<calendar_v3.Calendar | null> {
    if (!env.GOOGLE_CLIENT_ID || !env.GOOGLE_CLIENT_SECRET || !env.GOOGLE_REDIRECT_URI) {
      return null;
    }

    const tokensDoc = await this.userRef()
      .collection('integrations')
      .doc('google_calendar')
      .get();

    if (!tokensDoc.exists) {
      return null;
    }

    const tokens = tokensDoc.data();
    if (!tokens) {
      return null;
    }

    const auth = new google.auth.OAuth2(
      env.GOOGLE_CLIENT_ID,
      env.GOOGLE_CLIENT_SECRET,
      env.GOOGLE_REDIRECT_URI,
    );

    auth.setCredentials({
      access_token: typeof tokens.access_token === 'string' ? tokens.access_token : undefined,
      refresh_token: typeof tokens.refresh_token === 'string' ? tokens.refresh_token : undefined,
      expiry_date:
        typeof tokens.expiry_date === 'number'
          ? tokens.expiry_date
          : undefined,
    });

    return google.calendar({ version: 'v3', auth });
  }
}

export const fetchDueReminders = async (): Promise<
  Array<{ userId: string; reminderId: string; data: Record<string, unknown> }>
> => {
  const nowIso = new Date().toISOString();
  const snapshot = await adminFirestore()
    .collectionGroup('reminders')
    .where('status', '==', 'pending')
    .where('trigger_at', '<=', nowIso)
    .get();

  return snapshot.docs.map((doc) => {
    const userId = doc.ref.parent.parent?.id;
    if (!userId) {
      throw new Error(`Unable to resolve user for reminder ${doc.id}`);
    }
    return {
      userId,
      reminderId: doc.id,
      data: doc.data(),
    };
  });
};

export const markReminderFired = async (
  userId: string,
  reminderId: string,
): Promise<void> => {
  await adminFirestore()
    .collection('users')
    .doc(userId)
    .collection('reminders')
    .doc(reminderId)
    .update({
      status: 'fired' satisfies ReminderStatus,
      fired_at: Timestamp.now().toDate().toISOString(),
    });
};

export const listUserFcmTokens = async (userId: string): Promise<string[]> => {
  const userDoc = await adminFirestore().collection('users').doc(userId).get();
  const tokens = userDoc.get('fcm_tokens');
  if (!Array.isArray(tokens)) {
    return [];
  }
  return tokens.filter((value): value is string => typeof value === 'string');
};

export const logToolFailure = (toolName: string, error: unknown): void => {
  logger.error('Tool execution failed', {
    toolName,
    error: error instanceof Error ? error.message : String(error),
  });
};
