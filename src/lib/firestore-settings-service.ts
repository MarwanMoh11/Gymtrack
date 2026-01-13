// src/lib/firestore-settings-service.ts


import { db } from '@/lib/firebase';
import { doc, getDoc, setDoc, updateDoc } from 'firebase/firestore';

// --- Types ---
type UserSettings = {
  targetWeightOverrides?: Record<string, string>;
  sessionOverride?: {
    dayId: string;
    date: string; // YYYY-MM-DD
  } | null; // Allow null for clearing
};

// --- Private Functions ---

/**
 * Fetches the entire settings document for a user.
 * @param userId The ID of the user.
 * @returns The user's settings document or an empty object.
 */
async function getUserSettings(userId: string): Promise<UserSettings> {
  console.log(`[FirestoreService-Settings] Fetching settings for user ${userId}`);
  if (!userId) return {};
  const settingsDocRef = doc(db, 'users', userId, 'settings', 'userSettings');
  try {
    const docSnap = await getDoc(settingsDocRef);
    if (docSnap.exists()) {
      console.log(`[FirestoreService-Settings] Found existing settings for user ${userId}.`);
      return docSnap.data() as UserSettings;
    } else {
      console.log(`[FirestoreService-Settings] No settings found for user ${userId}, returning empty object.`);
      return {};
    }
  } catch (error) {
    console.error(`[FirestoreService-Settings] Error getting user settings for ${userId}:`, error);
    throw new Error("Failed to fetch user settings.");
  }
}

// --- Public Functions for Target Weight Overrides ---

export async function getTargetWeightOverrides(userId: string): Promise<Record<string, string>> {
  console.log(`[FirestoreService-Settings] Getting target weight overrides for user ${userId}`);
  const settings = await getUserSettings(userId);
  return settings.targetWeightOverrides || {};
}

export async function setTargetWeightOverride(userId: string, exerciseId: string, targetWeight: string): Promise<void> {
  if (!userId || !exerciseId) return;
  const settingsDocRef = doc(db, 'users', userId, 'settings', 'userSettings');
  console.log(`[FirestoreService-Settings] Setting weight override for user ${userId}, exercise ${exerciseId} to '${targetWeight}'.`);
  try {
    // Use dot notation to update a specific field in the map
    await setDoc(settingsDocRef, {
      targetWeightOverrides: {
        [exerciseId]: targetWeight
      }
    }, { merge: true });
    console.log(`[FirestoreService-Settings] Successfully set weight override for user ${userId}, exercise ${exerciseId}.`);
  } catch (error) {
    console.error(`[FirestoreService-Settings] Error setting weight override for user ${userId}:`, error);
    throw new Error("Failed to save weight override.");
  }
}

// --- Public Functions for Session Override ---

export async function setTodayWorkoutOverride(userId: string, dayId: string): Promise<void> {
  if (!userId || !dayId) return;
  const settingsDocRef = doc(db, 'users', userId, 'settings', 'userSettings');
  const today = new Date().toISOString().split('T')[0];
  console.log(`[FirestoreService-Settings] Setting session override for user ${userId} to dayId '${dayId}'.`);
  try {
    await setDoc(settingsDocRef, {
      sessionOverride: { dayId, date: today }
    }, { merge: true });
    console.log(`[FirestoreService-Settings] Successfully set session override for user ${userId}.`);
  } catch (error) {
    console.error(`[FirestoreService-Settings] Error setting session override for user ${userId}:`, error);
    throw new Error("Failed to save session override.");
  }
}

export async function getTodayWorkoutOverride(userId: string): Promise<string | null> {
  console.log(`[FirestoreService-Settings] Getting today's workout override for user ${userId}`);
  const settings = await getUserSettings(userId);
  const today = new Date().toISOString().split('T')[0];
  if (settings.sessionOverride && settings.sessionOverride.date === today) {
    console.log(`[FirestoreService-Settings] Found override for today: ${settings.sessionOverride.dayId}`);
    return settings.sessionOverride.dayId;
  }
  console.log(`[FirestoreService-Settings] No override found for today.`);
  return null;
}

export async function clearTodayWorkoutOverride(userId: string): Promise<void> {
  if (!userId) return;
  const settingsDocRef = doc(db, 'users', userId, 'settings', 'userSettings');
  console.log(`[FirestoreService-Settings] Clearing session override for user ${userId}.`);
  try {
    // Setting the field to null is how we clear it in Firestore when merging.
    await setDoc(settingsDocRef, {
      sessionOverride: null
    }, { merge: true });
    console.log(`[FirestoreService-Settings] Successfully cleared session override for user ${userId}.`);
  } catch (error) {
    console.error(`[FirestoreService-Settings] Error clearing session override for user ${userId}:`, error);
    throw new Error("Failed to clear session override.");
  }
}
