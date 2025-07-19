// src/lib/firestore-log-service.ts
'use server';
import { db } from '@/lib/firebase';
import { collection, doc, getDoc, getDocs, setDoc, deleteDoc, writeBatch, query, where } from 'firebase/firestore';
import type { DailyLog } from '@/types/workout';

// --- Public Functions ---

/**
 * Fetches the daily workout log for a specific user and date.
 * @param userId The ID of the user.
 * @param date The date string in YYYY-MM-DD format.
 * @returns The DailyLog object or null if not found.
 */
export async function getDailyLog(userId: string, date: string): Promise<DailyLog | null> {
  if (!userId || !date) return null;
  const logDocRef = doc(db, 'users', userId, 'dailyLogs', date);
  try {
    const docSnap = await getDoc(logDocRef);
    return docSnap.exists() ? (docSnap.data() as DailyLog) : null;
  } catch (error) {
    console.error(`Error getting daily log for user ${userId} on ${date}:`, error);
    throw new Error('Failed to fetch daily log.');
  }
}

/**
 * Saves a daily workout log for a specific user.
 * @param userId The ID of the user.
 * @param date The date string in YYYY-MM-DD format.
 * @param dailyLog The DailyLog object to save.
 */
export async function saveDailyLog(userId: string, date: string, dailyLog: DailyLog): Promise<void> {
  if (!userId || !date) return;
  const logDocRef = doc(db, 'users', userId, 'dailyLogs', date);
  try {
    await setDoc(logDocRef, dailyLog, { merge: true });
  } catch (error) {
    console.error(`Error saving daily log for user ${userId} on ${date}:`, error);
    throw new Error('Failed to save daily log.');
  }
}

/**
 * Deletes the entire log for a specific user and date.
 * @param userId The ID of the user.
 * @param date The date string in YYYY-MM-DD format.
 */
export async function deleteDailyLog(userId: string, date: string): Promise<void> {
  if (!userId || !date) return;
  const logDocRef = doc(db, 'users', userId, 'dailyLogs', date);
  try {
    await deleteDoc(logDocRef);
  } catch (error) {
    console.error(`Error deleting daily log for user ${userId} on ${date}:`, error);
    throw new Error('Failed to delete daily log.');
  }
}

/**
 * Fetches all workout logs for a given user.
 * Used for populating calendar and charts.
 * @param userId The ID of the user.
 * @returns A map of date strings to DailyLog objects.
 */
export async function getAllUserLogs(userId: string): Promise<Map<string, DailyLog>> {
  if (!userId) return new Map();
  const logsCollectionRef = collection(db, 'users', userId, 'dailyLogs');
  const logsMap = new Map<string, DailyLog>();
  try {
    const querySnapshot = await getDocs(logsCollectionRef);
    querySnapshot.forEach((doc) => {
      logsMap.set(doc.id, doc.data() as DailyLog);
    });
    return logsMap;
  } catch (error) {
    console.error(`Error fetching all logs for user ${userId}:`, error);
    throw new Error('Failed to fetch user logs.');
  }
}


// --- Migration Logic ---

/**
 * Checks for and migrates daily logs from localStorage to Firestore.
 * This should be called once when a user logs in.
 * @param userId The ID of the user.
 */
export async function migrateLocalStorageLogsToFirestore(userId: string): Promise<void> {
  if (typeof window === 'undefined' || !userId) return;

  const logsToMigrate: { [key: string]: DailyLog } = {};
  const keysToRemove: string[] = [];

  for (let i = 0; i < localStorage.length; i++) {
    const key = localStorage.key(i);
    if (key && key.startsWith('gymtrack_log_')) {
      const logContent = localStorage.getItem(key);
      const match = key.match(/_(\d{4}-\d{2}-\d{2})$/);
      if (logContent && match && match[1]) {
        const dateStr = match[1];
        try {
          const parsedLog = JSON.parse(logContent);
          // Simple validation to ensure it's not an empty object
          if (Object.keys(parsedLog).length > 0) {
            logsToMigrate[dateStr] = parsedLog;
          }
          keysToRemove.push(key);
        } catch (e) {
          console.error(`Failed to parse legacy log for key ${key}, skipping.`, e);
          keysToRemove.push(key); // Remove corrupted data
        }
      }
    }
  }

  if (Object.keys(logsToMigrate).length === 0) {
    console.log("No legacy logs to migrate.");
    // Still clean up any keys that were marked for removal (e.g., corrupted ones)
    keysToRemove.forEach(key => localStorage.removeItem(key));
    return;
  }

  console.log(`Migrating ${Object.keys(logsToMigrate).length} daily logs to Firestore...`);

  try {
    const batch = writeBatch(db);
    for (const dateStr in logsToMigrate) {
      const logData = logsToMigrate[dateStr];
      const logDocRef = doc(db, 'users', userId, 'dailyLogs', dateStr);
      batch.set(logDocRef, logData, { merge: true }); // Merge to avoid overwriting newer data
    }
    await batch.commit();

    // After successful migration, remove from localStorage
    keysToRemove.forEach(key => localStorage.removeItem(key));
    console.log("Successfully migrated and cleared legacy logs.");
  } catch (error) {
    console.error("Error migrating logs to Firestore:", error);
    // Do not remove from localStorage if migration fails, to allow for retry
  }
}
