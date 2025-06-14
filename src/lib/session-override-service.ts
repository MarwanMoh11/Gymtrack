
// src/lib/session-override-service.ts
'use client';

const getOverrideStorageKey = (): string => {
  // Ensures the override is specific to the current day
  const today = new Date().toISOString().split('T')[0];
  return `gymtrack_today_override_${today}`;
};

/**
 * Sets the workout day ID to be used for today, overriding the schedule.
 * @param dayId The ID of the WorkoutDay to perform today.
 */
export function setTodayWorkoutOverride(dayId: string): void {
  if (typeof window === 'undefined') return;
  try {
    localStorage.setItem(getOverrideStorageKey(), dayId);
  } catch (error) {
    console.error("Error setting today's workout override in localStorage:", error);
  }
}

/**
 * Gets the ID of the workout day that has been set to override today's schedule.
 * @returns The WorkoutDay ID string if an override is set for today, otherwise null.
 */
export function getTodayWorkoutOverride(): string | null {
  if (typeof window === 'undefined') return null;
  try {
    return localStorage.getItem(getOverrideStorageKey());
  } catch (error) {
    console.error("Error getting today's workout override from localStorage:", error);
    return null;
  }
}

/**
 * Clears any workout override set for today.
 */
export function clearTodayWorkoutOverride(): void {
  if (typeof window === 'undefined') return;
  try {
    localStorage.removeItem(getOverrideStorageKey());
  } catch (error) {
    console.error("Error clearing today's workout override from localStorage:", error);
  }
}
