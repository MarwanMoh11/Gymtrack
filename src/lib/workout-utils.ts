
import type { DailyLog, Exercise, WorkoutDay, LoggedExerciseData, SetData } from '@/types/workout';
import { weeklyPlan } from '@/data/workout-data';
import type { NextSessionRecommendationInput } from '@/ai/flows/next-session-recommendation';


export const getAllExercises = (): Array<{ id: string; name: string }> => {
  const exercisesMap = new Map<string, string>();
  weeklyPlan.forEach(day => {
    day.exercises.forEach(ex => {
      // Include only exercises likely to be tracked for progressive overload
      if (!ex.isWarmup && !ex.isConditioning && !ex.isStretch && !ex.isFoamRoll && !ex.isActivity && !ex.isMatch && !ex.isRecovery && !ex.isCore) {
        if (!exercisesMap.has(ex.id)) {
          exercisesMap.set(ex.id, ex.name);
        }
      }
    });
  });
  return Array.from(exercisesMap, ([id, name]) => ({ id, name })).sort((a,b) => a.name.localeCompare(b.name));
};

export const parseWeightToNumber = (weightString: string | number | undefined, exerciseName?: string): number => {
    if (typeof weightString === 'number') return weightString;
    if (typeof weightString !== 'string' || !weightString.trim()) return 0;

    const lowerWeightString = weightString.toLowerCase();

    // Handle specific bodyweight strings first
    if (['bodyweight', 'bw', '0 kg (bodyweight)', 'bodyweight or added', '0'].includes(lowerWeightString)) {
        const bodyweightBase = 70; // Example placeholder for BW in kg
        const addMatch = lowerWeightString.match(/(?:bw|bodyweight)\s*\+\s*([\d.]+)\s*kg/i);
        if (addMatch && addMatch[1]) {
            return bodyweightBase + parseFloat(addMatch[1]);
        }
        if (lowerWeightString.includes('0 kg') && lowerWeightString.includes('bodyweight')) return 0;
        if (lowerWeightString === '0') return 0;
        return bodyweightBase; // Default for "bodyweight" alone
    }

    // Handle "Xth stack" or "X stack"
    const stackMatch = lowerWeightString.match(/([\d.]+)(?:st|nd|rd|th)?\s*stack/i);
    if (stackMatch && stackMatch[1]) {
        const stackPosition = parseFloat(stackMatch[1]);
        return stackPosition * 5; // Rough heuristic: 5kg per stack plate
    }

    // Handle "X kg each side"
    const eachSideMatch = lowerWeightString.match(/([\d.]+)\s*kg\s*each\s*side/i);
    if (eachSideMatch && eachSideMatch[1]) {
        // Assumes standard 20kg olympic bar unless specified otherwise
        const barWeight = exerciseName?.toLowerCase().includes('barbell') ? 20 : 0;
        return (parseFloat(eachSideMatch[1]) * 2) + barWeight;
    }

    // General numeric match (e.g., "22.5 kg", "65", "12 lbs", "Maintain at 80 kg")
    const numericMatch = lowerWeightString.match(/([\d.]+)/);
    if (numericMatch && numericMatch[1]) {
        return parseFloat(numericMatch[1]);
    }

    console.warn(`Could not parse weight string: "${weightString}" for exercise "${exerciseName}". Defaulting to 0.`);
    return 0;
};


export const transformHistoricalDataForAI = (exerciseId: string): NextSessionRecommendationInput['recentPerformance'] => {
    if (typeof window === 'undefined') return [];

    const relevantLogs: Array<{ date: string, weight: string, repsPerSet: string[] }> = [];
    const exerciseDefinition = weeklyPlan.flatMap(day => day.exercises).find(ex => ex.id === exerciseId);

    const keysToSearch: string[] = [];
    try {
        for (let i = 0; i < localStorage.length; i++) {
            const key = localStorage.key(i);
            if (key && key.startsWith('gymtrack_log_')) {
                keysToSearch.push(key);
            }
        }
    } catch (error) {
        console.error("Error accessing localStorage keys:", error);
        return []; // Return empty if localStorage is inaccessible
    }


    // Sort keys by date ascending
    keysToSearch.sort((a, b) => {
        const dateA = a.match(/_(\d{4}-\d{2}-\d{2})$/)?.[1];
        const dateB = b.match(/_(\d{4}-\d{2}-\d{2})$/)?.[1];
        if (dateA && dateB) return new Date(dateA).getTime() - new Date(dateB).getTime();
        return 0;
    });

    for (const key of keysToSearch) {
        const match = key.match(/_(\d{4}-\d{2}-\d{2})$/);
        if (match && match[1]) { // Ensure match and dateString exist
            const dateStr = match[1];
            try {
                const dailyLogString = localStorage.getItem(key);
                if (!dailyLogString) continue;
                const dailyLog: DailyLog = JSON.parse(dailyLogString);

                const exerciseLog = dailyLog[exerciseId];
                if (exerciseLog && exerciseDefinition && typeof exerciseLog === 'object') {
                    const repsPerSet: string[] = [];
                    let sessionWeight: string | undefined;

                    exerciseDefinition.sets.forEach(setDef => {
                        const loggedSet = exerciseLog[setDef.id];
                        // Check if loggedSet is valid and completed
                        if (loggedSet && typeof loggedSet === 'object' && loggedSet.isCompleted) {
                            repsPerSet.push(String(loggedSet.reps ?? setDef.targetReps)); // Use logged or target reps
                            if (sessionWeight === undefined) {
                                // Use the weight logged with the set, fallback to definition
                                sessionWeight = String(loggedSet.weight ?? exerciseDefinition.targetWeight ?? 'bodyweight');
                            }
                        }
                    });

                    if (repsPerSet.length > 0 && sessionWeight !== undefined) {
                       relevantLogs.push({
                           date: dateStr,
                           weight: sessionWeight,
                           repsPerSet: repsPerSet,
                       });
                    }
                }
            } catch (e) {
                console.error(`Error processing log for key ${key}:`, e);
            }
        }
    }
    // Return only the last 8 relevant workout logs for the AI context
    return relevantLogs.slice(-8);
};

/**
 * Calculates the current and longest workout streaks from a list of dates.
 * Dates should represent logged workout days (UTC normalized Date objects).
 * @param dates - An array of Date objects representing logged workout days (normalized to UTC midnight).
 * @returns An object with `current` and `longest` streak counts.
 */
export const calculateStreaks = (dates: Date[]): { current: number; longest: number } => {
  if (dates.length === 0) {
    return { current: 0, longest: 0 };
  }

  // Ensure dates are unique UTC timestamps at midnight and sorted
  const uniqueSortedTimestamps = Array.from(new Set(dates.map(d => d.getTime()))).sort((a, b) => a - b);

  if (uniqueSortedTimestamps.length === 0) {
    return { current: 0, longest: 0 };
  }

  let currentStreak = 0; // Start at 0, check the last day later
  let longestStreak = 0;
  const oneDayMillis = 24 * 60 * 60 * 1000;

  // Iterate through the sorted unique dates
  for (let i = 0; i < uniqueSortedTimestamps.length; i++) {
    if (i === 0) {
      // First date always starts a streak of 1
      currentStreak = 1;
    } else {
      const diff = uniqueSortedTimestamps[i] - uniqueSortedTimestamps[i - 1];
      // Check if the difference is exactly one day in milliseconds
      if (diff === oneDayMillis) {
        currentStreak++;
      } else {
        // Gap detected, update longest streak and reset current
        longestStreak = Math.max(longestStreak, currentStreak);
        currentStreak = 1; // Start a new streak
      }
    }
    // Update longest streak at each step
    longestStreak = Math.max(longestStreak, currentStreak);
  }


  // Final check for the current streak relative to today
  const today = new Date();
  const todayUTCStart = Date.UTC(today.getUTCFullYear(), today.getUTCMonth(), today.getUTCDate());
  const lastLogTimestamp = uniqueSortedTimestamps[uniqueSortedTimestamps.length - 1];

  // If the last log was not today or yesterday, the current streak is 0
  if (lastLogTimestamp < todayUTCStart - oneDayMillis) {
    currentStreak = 0;
  }

  return { current: currentStreak, longest: longestStreak };
};


/**
 * Retrieves the performance for a specific set of an exercise from the most recent *previous* session.
 * @param exerciseId The ID of the exercise.
 * @param currentSetId The ID of the set for which to find previous performance.
 * @param exerciseSetsDefinition The full list of set definitions for the current exercise.
 * @returns The LoggedSetData for that set from the last relevant session, or undefined.
 */
export const getPreviousSetPerformance = (
    exerciseId: string,
    currentSetId: string,
    exerciseSetsDefinition: SetData[]
): LoggedSetData | undefined => {
    if (typeof window === 'undefined') return undefined;

    const todayStr = new Date().toISOString().split('T')[0];
    const keysToSearch: string[] = [];
    try {
        for (let i = 0; i < localStorage.length; i++) {
            const key = localStorage.key(i);
            if (key && key.startsWith('gymtrack_log_')) {
                keysToSearch.push(key);
            }
        }
    } catch (error) {
        console.error("Error accessing localStorage keys for getPreviousSetPerformance:", error);
        return undefined;
    }

    // Sort keys by date descending to find the most recent previous log
    keysToSearch.sort((a, b) => {
        const dateA = a.match(/_(\d{4}-\d{2}-\d{2})$/)?.[1];
        const dateB = b.match(/_(\d{4}-\d{2}-\d{2})$/)?.[1];
        if (dateA && dateB) return new Date(dateB).getTime() - new Date(dateA).getTime(); // Descending
        return 0;
    });

    // Find the index of the current set in its definition
    const currentSetIndex = exerciseSetsDefinition.findIndex(set => set.id === currentSetId);
    if (currentSetIndex === -1) return undefined; // Should not happen if data is consistent

    for (const key of keysToSearch) {
        const match = key.match(/_(\d{4}-\d{2}-\d{2})$/);
        if (match && match[1]) {
            const dateStr = match[1];
            if (dateStr === todayStr) continue; // Skip today's log

            try {
                const dailyLogString = localStorage.getItem(key);
                if (!dailyLogString) continue;
                const dailyLog: DailyLog = JSON.parse(dailyLogString);

                const historicalExerciseLog = dailyLog[exerciseId];
                if (historicalExerciseLog && typeof historicalExerciseLog === 'object') {
                    // Attempt to find the historical set by its ID first (if plans are consistent)
                    // Or, fall back to matching by index if set IDs might change across plan versions
                    // For this implementation, we'll try finding a set at the same index.
                    
                    // Get all set IDs from the historical log for this exercise
                    const historicalSetIds = Object.keys(historicalExerciseLog);
                    if (historicalSetIds.length > currentSetIndex) {
                        // Assume the set at the same index is the corresponding one.
                        // This is a simplification. A more robust system might store historical set definitions.
                        const historicalSetKey = historicalSetIds[currentSetIndex]; // This relies on consistent ordering of sets in the log
                        const previousPerformance = historicalExerciseLog[historicalSetKey];
                        
                        if (previousPerformance && previousPerformance.isCompleted) {
                            return previousPerformance;
                        }
                    }
                }
            } catch (e) {
                console.error(`Error processing historical log for key ${key} in getPreviousSetPerformance:`, e);
            }
        }
    }
    return undefined;
};
