
// src/lib/workout-plan-service.ts
'use client';

import type { NamedWorkoutPlan, WeeklyPlan, WorkoutDay, Exercise } from '@/types/workout';
import { defaultNamedPlans, getWorkoutByDayFromPlan as getWorkoutByDayFromPlanData, getAllExercisesFromPlan as getAllExercisesFromPlanData, getExerciseById as getExerciseByIdData } from '@/data/workout-data';
import { produce } from 'immer'; // Using immer for easier immutable updates

const WORKOUT_PLANS_STORAGE_KEY = 'gymtrack_workout_plans';

let clientSidePlans: NamedWorkoutPlan[] | null = null;

function deepClone<T>(obj: T): T {
  return JSON.parse(JSON.stringify(obj));
}

export function loadWorkoutPlans(): NamedWorkoutPlan[] {
  if (clientSidePlans) return deepClone(clientSidePlans);

  if (typeof window !== 'undefined') {
    const storedPlans = localStorage.getItem(WORKOUT_PLANS_STORAGE_KEY);
    if (storedPlans) {
      try {
        clientSidePlans = JSON.parse(storedPlans);
        // Ensure at least one plan is active if none are
        if (clientSidePlans && !clientSidePlans.some(p => p.isActive)) {
          clientSidePlans[0].isActive = true;
        }
        return deepClone(clientSidePlans!);
      } catch (e) {
        console.error("Failed to parse workout plans from localStorage", e);
        localStorage.removeItem(WORKOUT_PLANS_STORAGE_KEY); // Clear corrupted data
      }
    }
  }
  // If no stored plans or server-side rendering, use defaults
  clientSidePlans = deepClone(defaultNamedPlans);
  if (clientSidePlans.length > 0 && !clientSidePlans.some(p => p.isActive)) {
      clientSidePlans[0].isActive = true; // Ensure first plan is active by default
  }
  saveWorkoutPlans(clientSidePlans); // Save defaults to localStorage if it's the first load client-side
  return deepClone(clientSidePlans);
}

export function saveWorkoutPlans(plans: NamedWorkoutPlan[]): void {
  clientSidePlans = deepClone(plans);
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
  const currentPlans = loadWorkoutPlans();
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
        draft[0].isActive = true;
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

// Function to update the active plan (e.g., after editing)
export function updateActiveWorkoutPlan(updatedWeeklyPlan: WeeklyPlan): void {
    const currentPlans = loadWorkoutPlans();
    const activePlanIndex = currentPlans.findIndex(p => p.isActive);

    if (activePlanIndex === -1 && currentPlans.length > 0) {
        // If no active plan somehow, make the first one active and update it
        const updatedPlans = produce(currentPlans, draft => {
            draft[0].isActive = true;
            draft[0].plan = updatedWeeklyPlan;
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
        console.warn("No active plan found to update. This shouldn't happen if plans are loaded correctly.");
        // Optionally, create a new plan or set a default as active
    }
}


// Placeholder for creating a new plan - more UI needed for this
export function createNewWorkoutPlan(name: string, description?: string): NamedWorkoutPlan {
    const newPlanId = `custom-plan-${Date.now()}`;
    const newNamedPlan: NamedWorkoutPlan = {
        id: newPlanId,
        name: name,
        description: description || "A new custom workout plan.",
        plan: [], // Starts as an empty plan
        isActive: false, // Not active by default
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
