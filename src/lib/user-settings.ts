
// src/lib/user-settings.ts
'use client';

const USER_TARGET_WEIGHT_OVERRIDES_KEY = 'gymtrack_user_target_weights';

/**
 * Retrieves all target weight overrides from localStorage.
 * @returns A record of exerciseId to overridden targetWeight.
 */
export function getTargetWeightOverrides(): Record<string, string> {
  if (typeof window === 'undefined') {
    return {};
  }
  const storedOverrides = localStorage.getItem(USER_TARGET_WEIGHT_OVERRIDES_KEY);
  if (storedOverrides) {
    try {
      return JSON.parse(storedOverrides);
    } catch (e) {
      console.error("Failed to parse target weight overrides from localStorage", e);
      localStorage.removeItem(USER_TARGET_WEIGHT_OVERRIDES_KEY); // Clear corrupted data
      return {};
    }
  }
  return {};
}

/**
 * Sets or updates a target weight override for a specific exercise in localStorage.
 * @param exerciseId The ID of the exercise.
 * @param targetWeight The new target weight string.
 */
export function setTargetWeightOverride(exerciseId: string, targetWeight: string): void {
  if (typeof window === 'undefined') {
    return;
  }
  const overrides = getTargetWeightOverrides();
  overrides[exerciseId] = targetWeight;
  localStorage.setItem(USER_TARGET_WEIGHT_OVERRIDES_KEY, JSON.stringify(overrides));
}

/**
 * Gets the user's target weight for an exercise, checking overrides first.
 * @param exerciseId The ID of the exercise.
 * @param defaultTargetWeight The default target weight from the base plan.
 * @returns The overridden target weight if available, otherwise the default.
 */
export function getUserTargetWeight(exerciseId: string, defaultTargetWeight?: string): string | undefined {
  const overrides = getTargetWeightOverrides();
  return overrides[exerciseId] !== undefined ? overrides[exerciseId] : defaultTargetWeight;
}
