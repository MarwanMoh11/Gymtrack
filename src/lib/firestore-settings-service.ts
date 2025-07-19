// src/lib/firestore-settings-service.ts
'use server';
import { db } from '@/lib/firebase';
import { doc, getDoc, setDoc, updateDoc } from 'firebase/firestore';

// --- Types ---
type UserSettings = {
  targetWeightOverrides?: Record<string, string>;
  sessionOverride?: {
    dayId: string;
    date: string; // YYYY-MM-DD
  };
};

// --- Private Functions ---

/**
 * Fetches the entire settings document for a user.
 * @param userId The ID of the user.
 * @returns The user's settings document or an empty object.
 */
async function getUserSettings(userId: string): Promise<UserSettings> {
  if (!userId) return {};
  const settingsDocRef = doc(db, 'users', userId, 'settings', 'userSettings');
  try {
    const docSnap = await getDoc(settingsDocRef);
    return docSnap.exists() ? (docSnap.data() as UserSettings) : {};
  } catch (error) {
    console.error(`Error getting user settings for ${userId}:`, error);
    throw new Error("Failed to fetch user settings.");
  }
}

// --- Public Functions for Target Weight Overrides ---

export async function getTargetWeightOverrides(userId: string): Promise<Record<string, string>> {
  const settings = await getUserSettings(userId);
  return settings.targetWeightOverrides || {};
}

export async function setTargetWeightOverride(userId: string, exerciseId: string, targetWeight: string): Promise<void> {
  if (!userId || !exerciseId) return;
  const settingsDocRef = doc(db, 'users', userId, 'settings', 'userSettings');
  try {
    // Use dot notation to update a specific field in the map
    await setDoc(settingsDocRef, {
      targetWeightOverrides: {
        [exerciseId]: targetWeight
      }
    }, { merge: true });
  } catch (error) {
    console.error(`Error setting weight override for user ${userId}:`, error);
    throw new Error("Failed to save weight override.");
  }
}

// --- Public Functions for Session Override ---

export async function setTodayWorkoutOverride(userId: string, dayId: string): Promise<void> {
  if (!userId || !dayId) return;
  const settingsDocRef = doc(db, 'users', userId, 'settings', 'userSettings');
  const today = new Date().toISOString().split('T')[0];
  try {
    await setDoc(settingsDocRef, {
      sessionOverride: { dayId, date: today }
    }, { merge: true });
  } catch (error) {
    console.error(`Error setting session override for user ${userId}:`, error);
    throw new Error("Failed to save session override.");
  }
}

export async function getTodayWorkoutOverride(userId: string): Promise<string | null> {
  const settings = await getUserSettings(userId);
  const today = new Date().toISOString().split('T')[0];
  if (settings.sessionOverride && settings.sessionOverride.date === today) {
    return settings.sessionOverride.dayId;
  }
  return null;
}

export async function clearTodayWorkoutOverride(userId: string): Promise<void> {
  if (!userId) return;
  const settingsDocRef = doc(db, 'users', userId, 'settings', 'userSettings');
  try {
    // To "delete" a field, we can merge with an empty object,
    // though setting it to null or an empty value works well too.
    await setDoc(settingsDocRef, {
        sessionOverride: null
    }, { merge: true });
  } catch (error) {
    console.error(`Error clearing session override for user ${userId}:`, error);
    throw new Error("Failed to clear session override.");
  }
}


// --- Migration Logic ---

/**
 * Migrates session and weight overrides from localStorage to Firestore.
 * @param userId The ID of the user.
 */
export async function migrateLocalStorageSettingsToFirestore(userId: string): Promise<void> {
  if (typeof window === 'undefined' || !userId) return;

  const USER_TARGET_WEIGHT_OVERRIDES_KEY = 'gymtrack_user_target_weights';
  const legacyWeightsStr = localStorage.getItem(USER_TARGET_WEIGHT_OVERRIDES_KEY);
  const legacySessionKey = `gymtrack_today_override_${new Date().toISOString().split('T')[0]}`;
  const legacySessionDayId = localStorage.getItem(legacySessionKey);

  let settingsToMigrate: UserSettings = {};
  let needsMigration = false;

  if (legacyWeightsStr) {
    try {
      const parsedWeights = JSON.parse(legacyWeightsStr);
      if (Object.keys(parsedWeights).length > 0) {
        settingsToMigrate.targetWeightOverrides = parsedWeights;
        needsMigration = true;
      }
    } catch (e) {
      console.error("Failed to parse legacy weight overrides, skipping.", e);
    }
  }

  if (legacySessionDayId) {
    settingsToMigrate.sessionOverride = {
      dayId: legacySessionDayId,
      date: new Date().toISOString().split('T')[0],
    };
    needsMigration = true;
  }

  if (!needsMigration) {
    console.log("No legacy settings to migrate.");
    return;
  }

  console.log("Migrating legacy settings to Firestore...", settingsToMigrate);
  const settingsDocRef = doc(db, 'users', userId, 'settings', 'userSettings');

  try {
    // Merge to ensure we don't overwrite any newer data if migration runs twice
    await setDoc(settingsDocRef, settingsToMigrate, { merge: true });
    
    // Clear legacy data on success
    if (legacyWeightsStr) localStorage.removeItem(USER_TARGET_WEIGHT_OVERRIDES_KEY);
    if (legacySessionDayId) localStorage.removeItem(legacySessionKey);
    console.log("Successfully migrated and cleared legacy settings.");
  } catch (error) {
    console.error("Error migrating settings to Firestore:", error);
  }
}
