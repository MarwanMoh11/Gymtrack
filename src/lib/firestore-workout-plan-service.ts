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


// --- Private & Initialization Functions ---

/**
 * Initializes the default workout plans for a new user.
 * Sets the 'isActive' flag to false for all plans, forcing the user through onboarding.
 * @param userId The ID of the user.
 * @returns The array of default plans that were just saved.
 */
async function initializeDefaultPlansForUser(userId: string): Promise<NamedWorkoutPlan[]> {
  // For new users, ensure no plan is active so they are directed to the onboarding flow.
  const plansToSave = defaultNamedPlans.map(p => ({ ...p, isActive: false }));
  await saveAllUserWorkoutPlans(userId, plansToSave);
  return plansToSave;
}
