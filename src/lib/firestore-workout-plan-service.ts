// src/lib/firestore-workout-plan-service.ts
'use server';

import type { NamedWorkoutPlan } from '@/types/workout';
import { defaultNamedPlans } from '@/data/workout-data';

const WORKOUT_PLANS_STORAGE_KEY = 'gymtrack_workout_plans';

// --- Public Functions ---

/**
 * Initializes the default workout plans in localStorage for a new user.
 * This should be called once upon user signup.
 */
export async function initializeDefaultPlansForUser(): Promise<void> {
  console.log('[PlanService] Initializing default plans for a new user.');
  if (typeof window === 'undefined') {
    console.log('[PlanService] Cannot initialize on server. Aborting.');
    return;
  }
  // This ensures no plan is active by default for a new user
  const plansToSave = defaultNamedPlans.map(p => ({ ...p, isActive: false }));
  await saveAllUserWorkoutPlans(plansToSave);
  console.log('[PlanService] Default plans have been initialized in localStorage.');
}

/**
 * Fetches all workout plans from localStorage.
 * If no plans are found, it returns null, indicating that initialization is needed.
 * @returns A promise that resolves to an array of NamedWorkoutPlan or null.
 */
export async function getAllUserWorkoutPlans(): Promise<NamedWorkoutPlan[] | null> {
  console.log('[PlanService] Getting all workout plans from localStorage.');
  if (typeof window === 'undefined') {
    console.warn('[PlanService] SSR context: cannot access localStorage. Returning null.');
    return null;
  }

  const plansJson = window.localStorage.getItem(WORKOUT_PLANS_STORAGE_KEY);

  if (!plansJson) {
    console.log('[PlanService] No plans found in localStorage.');
    return null;
  }

  try {
    const plans = JSON.parse(plansJson) as NamedWorkoutPlan[];
    console.log(`[PlanService] Successfully fetched ${plans.length} plans from localStorage.`);
    return plans;
  } catch (error) {
    console.error('[PlanService] Error parsing plans from localStorage:', error);
    return null;
  }
}

/**
 * Saves all workout plans to localStorage.
 * @param plans The array of plans to save.
 */
export async function saveAllUserWorkoutPlans(plans: NamedWorkoutPlan[]): Promise<void> {
    console.log(`[PlanService] Attempting to save ${plans.length} plans to localStorage.`);
    if (typeof window === 'undefined') {
        console.warn('[PlanService] Attempted to save plans on the server. Operation skipped.');
        return;
    };

    try {
        window.localStorage.setItem(WORKOUT_PLANS_STORAGE_KEY, JSON.stringify(plans));
        console.log(`[PlanService] Successfully saved all workout plans.`);
    } catch (error) {
        console.error(`[PlanService] Error saving workout plans:`, error);
        throw new Error("Failed to save workout plans to localStorage.");
    }
}

/**
 * Saves a single workout plan.
 * @param plan The plan to save.
 */
export async function saveUserWorkoutPlan(plan: NamedWorkoutPlan): Promise<void> {
    console.log(`[PlanService] Attempting to save single plan '${plan.id}'.`);
    try {
        const allPlans = (await getAllUserWorkoutPlans()) || [];
        const planIndex = allPlans.findIndex(p => p.id === plan.id);

        if (planIndex > -1) {
            console.log(`[PlanService] Updating existing plan at index ${planIndex}.`);
            allPlans[planIndex] = plan;
        } else {
            console.log(`[PlanService] Adding new plan.`);
            allPlans.push(plan);
        }

        await saveAllUserWorkoutPlans(allPlans);
        console.log(`[PlanService] Successfully saved single plan '${plan.id}'.`);
    } catch (error) {
        console.error(`[PlanService] Error saving plan ${plan.id}:`, error);
        throw new Error("Failed to save workout plan.");
    }
}