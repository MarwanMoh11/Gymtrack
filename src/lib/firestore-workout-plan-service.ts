// src/lib/firestore-workout-plan-service.ts
'use server';

import type { NamedWorkoutPlan } from '@/types/workout';
import { defaultNamedPlans } from '@/data/workout-data';

const WORKOUT_PLANS_STORAGE_KEY = 'gymtrack_workout_plans';

// --- Public Functions ---

/**
 * Fetches all workout plans from localStorage.
 * If no plans are found, it initializes them with the default plans.
 * @returns A promise that resolves to an array of NamedWorkoutPlan.
 */
export async function getAllUserWorkoutPlans(): Promise<NamedWorkoutPlan[]> {
  console.log('[LocalStorageService] Getting all workout plans.');
  if (typeof window === 'undefined') {
    // Return default plans in SSR/server-side context, won't be active.
    return defaultNamedPlans.map(p => ({ ...p, isActive: false }));
  }

  const plansJson = window.localStorage.getItem(WORKOUT_PLANS_STORAGE_KEY);

  if (!plansJson) {
    console.log('[LocalStorageService] No plans found, initializing with defaults.');
    const plansToSave = defaultNamedPlans.map(p => ({ ...p, isActive: false }));
    await saveAllUserWorkoutPlans(plansToSave);
    return plansToSave;
  }

  try {
    const plans = JSON.parse(plansJson) as NamedWorkoutPlan[];
    console.log(`[LocalStorageService] Successfully fetched ${plans.length} plans.`);
    return plans;
  } catch (error) {
    console.error('[LocalStorageService] Error parsing plans from localStorage:', error);
    // If parsing fails, reset to default
    const plansToSave = defaultNamedPlans.map(p => ({ ...p, isActive: false }));
    await saveAllUserWorkoutPlans(plansToSave);
    return plansToSave;
  }
}

/**
 * Saves all workout plans to localStorage.
 * @param plans The array of plans to save.
 */
export async function saveAllUserWorkoutPlans(plans: NamedWorkoutPlan[]): Promise<void> {
  console.log(`[LocalStorageService] Attempting to save ${plans.length} plans.`);
   if (typeof window === 'undefined') return;

  try {
    window.localStorage.setItem(WORKOUT_PLANS_STORAGE_KEY, JSON.stringify(plans));
    console.log(`[LocalStorageService] Successfully saved all workout plans.`);
  } catch (error) {
    console.error(`[LocalStorageService] Error saving workout plans:`, error);
    throw new Error("Failed to save workout plans to localStorage.");
  }
}

/**
 * Saves a single workout plan.
 * @param plan The plan to save.
 */
export async function saveUserWorkoutPlan(plan: NamedWorkoutPlan): Promise<void> {
    console.log(`[LocalStorageService] Attempting to save plan '${plan.id}'.`);
    try {
        const allPlans = await getAllUserWorkoutPlans();
        const planIndex = allPlans.findIndex(p => p.id === plan.id);

        if (planIndex > -1) {
            allPlans[planIndex] = plan;
        } else {
            allPlans.push(plan);
        }

        await saveAllUserWorkoutPlans(allPlans);
        console.log(`[LocalStorageService] Successfully saved plan '${plan.id}'.`);
    } catch (error) {
        console.error(`[LocalStorageService] Error saving plan ${plan.id}:`, error);
        throw new Error("Failed to save workout plan.");
    }
}
