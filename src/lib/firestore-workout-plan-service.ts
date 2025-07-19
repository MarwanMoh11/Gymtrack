// src/lib/firestore-workout-plan-service.ts
'use server';

import { db } from '@/lib/firebase';
import { collection, doc, getDocs, setDoc, writeBatch } from 'firebase/firestore';
import type { NamedWorkoutPlan } from '@/types/workout';
import { defaultNamedPlans } from '@/data/workout-data';

// --- Public Functions ---

/**
 * Fetches all workout plans for a given user.
 * If the user has no plans, it initializes them with the default plans.
 * @param userId The ID of the user.
 * @returns A promise that resolves to an array of NamedWorkoutPlan.
 */
export async function getAllUserWorkoutPlans(userId: string): Promise<NamedWorkoutPlan[]> {
  if (!userId) {
    throw new Error("User ID is required to fetch workout plans.");
  }
  const plansCollectionRef = collection(db, 'users', userId, 'workoutPlans');
  const querySnapshot = await getDocs(plansCollectionRef);

  if (querySnapshot.empty) {
    console.log(`No plans found for user ${userId}, initializing with defaults.`);
    return initializeDefaultPlansForUser(userId);
  }

  const plans: NamedWorkoutPlan[] = [];
  querySnapshot.forEach((doc) => {
    plans.push(doc.data() as NamedWorkoutPlan);
  });
  return plans;
}

/**
 * Saves all of a user's workout plans to Firestore.
 * This is useful for bulk updates like reordering or changing the active plan.
 * @param userId The ID of the user.
 * @param plans The array of plans to save.
 */
export async function saveAllUserWorkoutPlans(userId: string, plans: NamedWorkoutPlan[]): Promise<void> {
  if (!userId) return;
  const batch = writeBatch(db);
  const plansCollectionRef = collection(db, 'users', userId, 'workoutPlans');

  plans.forEach((plan) => {
    const planDocRef = doc(plansCollectionRef, plan.id);
    batch.set(planDocRef, plan);
  });

  try {
    await batch.commit();
  } catch (error) {
    console.error(`Error saving all workout plans for user ${userId}:`, error);
    throw new Error("Failed to save workout plans.");
  }
}

/**
 * Saves a single workout plan for a user.
 * @param userId The ID of the user.
 * @param plan The plan to save.
 */
export async function saveUserWorkoutPlan(userId: string, plan: NamedWorkoutPlan): Promise<void> {
    if (!userId) return;
    const planDocRef = doc(db, 'users', userId, 'workoutPlans', plan.id);
    try {
        await setDoc(planDocRef, plan);
    } catch (error) {
        console.error(`Error saving plan ${plan.id} for user ${userId}:`, error);
        throw new Error("Failed to save workout plan.");
    }
}


// --- Private & Migration Functions ---

/**
 * Initializes the default workout plans for a new user or a user with no plans.
 * @param userId The ID of the user.
 * @returns The array of default plans that were just saved.
 */
async function initializeDefaultPlansForUser(userId: string): Promise<NamedWorkoutPlan[]> {
  const plansToSave = defaultNamedPlans.map(p => ({ ...p })); // Create a copy
  await saveAllUserWorkoutPlans(userId, plansToSave);
  return plansToSave;
}


/**
 * Migrates workout plans from localStorage to Firestore.
 * This should be called once when a user logs in.
 * @param userId The ID of the user.
 */
export async function migrateLocalStoragePlansToFirestore(userId:string): Promise<void> {
  if (typeof window === 'undefined' || !userId) return;

  const WORKOUT_PLANS_STORAGE_KEY = 'gymtrack_workout_plans';
  const storedPlansString = localStorage.getItem(WORKOUT_PLANS_STORAGE_KEY);

  if (!storedPlansString) {
    console.log("No legacy workout plans to migrate.");
    return;
  }

  try {
    const legacyPlans: NamedWorkoutPlan[] = JSON.parse(storedPlansString);
    
    if (!Array.isArray(legacyPlans) || legacyPlans.length === 0) {
      localStorage.removeItem(WORKOUT_PLANS_STORAGE_KEY); // Clean up invalid data
      return;
    }
    
    console.log(`Migrating ${legacyPlans.length} legacy workout plans to Firestore...`);

    // Fetch existing plans to avoid overwriting newer data if migration runs multiple times
    const existingPlans = await getAllUserWorkoutPlans(userId);
    const existingPlanIds = new Set(existingPlans.map(p => p.id));

    const plansToSave = legacyPlans.filter(p => !existingPlanIds.has(p.id));

    if (plansToSave.length > 0) {
        // Here we just add the new plans. We assume that if a plan with the same ID exists,
        // the Firestore version is the source of truth. We don't merge.
        const batch = writeBatch(db);
        const plansCollectionRef = collection(db, 'users', userId, 'workoutPlans');
        plansToSave.forEach(plan => {
            const planDocRef = doc(plansCollectionRef, plan.id);
            batch.set(planDocRef, plan);
        });
        await batch.commit();
        console.log(`Successfully migrated ${plansToSave.length} plans.`);
    } else {
        console.log("No new plans from localStorage to migrate.");
    }

    // Clear legacy data after successful check/migration
    localStorage.removeItem(WORKOUT_PLANS_STORAGE_KEY);

  } catch (error) {
    console.error("Error migrating workout plans to Firestore:", error);
    // Do not remove from localStorage if migration fails
  }
}
