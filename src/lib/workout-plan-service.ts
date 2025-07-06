
// src/lib/workout-plan-service.ts
'use client';

import type { NamedWorkoutPlan, WeeklyPlan, WorkoutDay, Exercise } from '@/types/workout';
import { defaultNamedPlans, getWorkoutByDayFromPlan as getWorkoutByDayFromPlanData, getAllExercisesFromPlan as getAllExercisesFromPlanData, getExerciseById as getExerciseByIdData } from '@/data/workout-data';
import { produce } from 'immer'; // Using immer for easier immutable updates

const WORKOUT_PLANS_STORAGE_KEY = 'gymtrack_workout_plans';
const OPTIMIZED_PLAN_ID = 'jeff-nippard-plan'; // ID of the new default plan

let clientSidePlans: NamedWorkoutPlan[] | null = null;

function deepClone<T>(obj: T): T {
  if (obj === null || typeof obj !== 'object') {
    return obj;
  }
  // Handle Date objects
  if (obj instanceof Date) {
    return new Date(obj.getTime()) as any;
  }
  // Handle Arrays
  if (Array.isArray(obj)) {
    return obj.map(item => deepClone(item)) as any;
  }
  // Handle Objects
  const clonedObj: any = {};
  for (const key in obj) {
    if (Object.prototype.hasOwnProperty.call(obj, key)) {
      clonedObj[key] = deepClone(obj[key]);
    }
  }
  return clonedObj;
}

export function loadWorkoutPlans(): NamedWorkoutPlan[] {
  if (typeof window === 'undefined') {
    // Server-side rendering or no window context, return a fresh copy of defaults
    // Ensure the optimized plan is active here as well for SSR consistency if ever needed
    const plans = deepClone(defaultNamedPlans);
    let optimizedPlanIsActive = false;
    plans.forEach(p => {
        if (p.id === OPTIMIZED_PLAN_ID) {
            p.isActive = true;
            optimizedPlanIsActive = true;
        } else {
            p.isActive = false;
        }
    });
    // Fallback if optimized plan somehow wasn't in defaults or ID mismatch
    if (!optimizedPlanIsActive && plans.length > 0) {
        plans[0].isActive = true;
    }
    return plans;
  }

  if (clientSidePlans === null) { // Check if already loaded in this session
    let loadedUserPlans: NamedWorkoutPlan[] = [];
    const storedPlansString = localStorage.getItem(WORKOUT_PLANS_STORAGE_KEY);

    if (storedPlansString) {
      try {
        loadedUserPlans = JSON.parse(storedPlansString);
      } catch (e) {
        console.error("Failed to parse workout plans from localStorage", e);
        localStorage.removeItem(WORKOUT_PLANS_STORAGE_KEY); // Clear corrupted data
        // Fallback to defaults if parsing fails
        loadedUserPlans = [];
      }
    }
    
    let finalPlans: NamedWorkoutPlan[] = deepClone(loadedUserPlans);
    const existingPlanIds = new Set(finalPlans.map(p => p.id));

    // Add any default plans that are missing from the user's stored plans
    defaultNamedPlans.forEach(defaultPlan => {
      if (!existingPlanIds.has(defaultPlan.id)) {
        finalPlans.push(deepClone(defaultPlan)); // Add if new
        existingPlanIds.add(defaultPlan.id); // Add to set to track it's now included
      } else {
        // Optional: Update existing default plans if they change in code?
        // For now, we don't overwrite user's version of a default plan if they have it.
        // However, we MUST ensure the `isActive` status is correctly managed for the OPTIMIZED_PLAN_ID.
      }
    });
    
    let optimizedPlanExists = false;
    finalPlans.forEach(p => {
      if (p.id === OPTIMIZED_PLAN_ID) {
        p.isActive = true;
        optimizedPlanExists = true;
      } else {
        p.isActive = false;
      }
    });

    // If the optimized plan (by its ID) wasn't found in the final list (e.g. user deleted it),
    // re-add it from defaults and make it active.
    if (!optimizedPlanExists) {
        const optimizedPlanFromDefaults = defaultNamedPlans.find(dp => dp.id === OPTIMIZED_PLAN_ID);
        if (optimizedPlanFromDefaults) {
            finalPlans.push(deepClone(optimizedPlanFromDefaults)); // This will have isActive true from defaults
            // Ensure all others are inactive again
             finalPlans.forEach(p => {
                p.isActive = (p.id === OPTIMIZED_PLAN_ID);
            });
        }
    }
    
    // Fallback: if after all merging, no plan is active (edge case), make the first one active.
    if (finalPlans.length > 0 && !finalPlans.some(p => p.isActive)) {
      finalPlans[0].isActive = true;
    }
    
    clientSidePlans = finalPlans;
    saveWorkoutPlans(clientSidePlans); // Save the potentially merged/updated list
  }
  return deepClone(clientSidePlans); // Return a clone to prevent direct mutation
}


export function saveWorkoutPlans(plans: NamedWorkoutPlan[]): void {
  clientSidePlans = deepClone(plans); // Update the in-memory cache
  if (typeof window !== 'undefined') {
    localStorage.setItem(WORKOUT_PLANS_STORAGE_KEY, JSON.stringify(plans));
  }
}

export function getAllNamedWorkoutPlans(): NamedWorkoutPlan[] {
  return loadWorkoutPlans();
}

export function getActiveWorkoutPlan(): WeeklyPlan | null {
  const plans = loadWorkoutPlans();
  const activePlan = plans.find(p => p.isActive);
  return activePlan ? activePlan.plan : (plans.length > 0 ? plans[0].plan : null) ;
}

export function getActiveNamedWorkoutPlan(): NamedWorkoutPlan | null {
  const plans = loadWorkoutPlans();
  const activePlan = plans.find(p => p.isActive);
  return activePlan || (plans.length > 0 ? plans[0] : null);
}

export function setActiveWorkoutPlan(planId: string): void {
  const currentPlans = loadWorkoutPlans(); // Ensures we're working with the latest merged data
  const updatedPlans = produce(currentPlans, draft => {
    let foundNewActive = false;
    draft.forEach(p => {
      if (p.id === planId) {
        p.isActive = true;
        foundNewActive = true;
      } else {
        p.isActive = false;
      }
    });
    // If the planId wasn't found, or something went wrong, ensure at least one plan is active
    if (!foundNewActive && draft.length > 0) {
        const optPlan = draft.find(p => p.id === OPTIMIZED_PLAN_ID);
        if (optPlan) optPlan.isActive = true;
        else draft[0].isActive = true; // Fallback to first or optimized
    }
  });
  saveWorkoutPlans(updatedPlans);
}

export function getWorkoutByDay(dayId: string): WorkoutDay | undefined {
    const activePlan = getActiveWorkoutPlan();
    if (!activePlan) return undefined;
    return getWorkoutByDayFromPlanData(activePlan, dayId);
}

export function getAllExercisesFromCurrentPlan(): Exercise[] {
    const activePlan = getActiveWorkoutPlan();
    if (!activePlan) return getAllExercisesFromPlanData(); // Fallback to all known if no active plan
    return getAllExercisesFromPlanData(activePlan);
}

export function getExerciseById(exerciseId: string): Exercise | undefined {
    const activePlan = getActiveWorkoutPlan();
    // Try to find in active plan first, then fallback to global search
    if (activePlan) {
        for (const day of activePlan) {
            const found = day.exercises.find(ex => ex.id === exerciseId);
            if (found) return found;
        }
    }
    return getExerciseByIdData(exerciseId); // Fallback to global search from workout-data
}

export function updateActiveWorkoutPlan(updatedWeeklyPlan: WeeklyPlan): void {
    const currentPlans = loadWorkoutPlans();
    const activePlanIndex = currentPlans.findIndex(p => p.isActive);

    if (activePlanIndex === -1 && currentPlans.length > 0) {
        // If no active plan somehow, make the optimized one active and update it
        const optimizedPlanIndex = currentPlans.findIndex(p => p.id === OPTIMIZED_PLAN_ID);
        const targetIndex = optimizedPlanIndex !== -1 ? optimizedPlanIndex : 0;

        const updatedPlans = produce(currentPlans, draft => {
            draft.forEach((p,idx) => p.isActive = (idx === targetIndex) );
            draft[targetIndex].plan = updatedWeeklyPlan;
        });
        saveWorkoutPlans(updatedPlans);
        return;
    }
    
    if (activePlanIndex !== -1) {
        const updatedPlans = produce(currentPlans, draft => {
            draft[activePlanIndex].plan = updatedWeeklyPlan;
        });
        saveWorkoutPlans(updatedPlans);
    } else {
        console.warn("No active plan found to update. Creating a new plan with this data.");
        // This case implies no plans exist at all, which loadWorkoutPlans should prevent.
        // However, as a safeguard, create a new plan.
        const newPlan: NamedWorkoutPlan = {
            id: OPTIMIZED_PLAN_ID, // Or generate a new ID if optimized isn't appropriate
            name: "Updated Active Plan",
            description: "Automatically created or updated.",
            plan: updatedWeeklyPlan,
            isActive: true,
        };
        saveWorkoutPlans([newPlan, ...currentPlans.map(p => ({...p, isActive: false}))]);
    }
}


export function createNewWorkoutPlan(name: string, description?: string): NamedWorkoutPlan {
    const newPlanId = `custom-plan-${name.toLowerCase().replace(/\s+/g, '-')}-${Date.now()}`;
    const newNamedPlan: NamedWorkoutPlan = {
        id: newPlanId,
        name: name,
        description: description || "A new custom workout plan.",
        plan: [], 
        isActive: false, 
    };
    
    const currentPlans = loadWorkoutPlans();
    const updatedPlans = produce(currentPlans, draft => {
        draft.push(newNamedPlan);
    });
    saveWorkoutPlans(updatedPlans);
    return newNamedPlan;
}

export function getDays() {
    const activePlan = getActiveWorkoutPlan();
    if (!activePlan) return [];
    return activePlan.filter(day => day.id !== 'exercise-library').map(day => ({ id: day.id, dayName: day.dayName, title: day.title }));
}

export function getPlanById(planId: string): NamedWorkoutPlan | undefined {
    const plans = loadWorkoutPlans();
    return plans.find(p => p.id === planId);
}
