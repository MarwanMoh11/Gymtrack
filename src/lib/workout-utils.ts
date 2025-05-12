
import type { DailyLog, Exercise, WorkoutDay, LoggedExerciseData } from '@/types/workout';
import { weeklyPlan } from '@/data/workout-data';
import type { NextSessionRecommendationInput } from '@/ai/flows/next-session-recommendation';
import type { CoachingTipsInput, LogSummarySchema } from '@/ai/flows/coaching-tips-flow'; // Import LogSummarySchema


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
 * Summarizes recent workout logs for AI coaching tips input.
 * Fetches logs from the last ~4 weeks (28 days).
 * @returns An array of LogSummary objects.
 */
export const summarizeRecentLogs = (): Array<LogSummarySchema> => { // Explicit return type
  if (typeof window === 'undefined') return [];

  const summaries: Array<LogSummarySchema> = []; // Explicit type
  const fourWeeksAgo = new Date();
  fourWeeksAgo.setUTCDate(fourWeeksAgo.getUTCDate() - 28); // Use UTC dates
  const fourWeeksAgoTimestamp = Date.UTC(fourWeeksAgo.getUTCFullYear(), fourWeeksAgo.getUTCMonth(), fourWeeksAgo.getUTCDate());


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

  // Sort keys by date descending to process recent ones first
  keysToSearch.sort((a, b) => {
    const dateA = a.match(/_(\d{4}-\d{2}-\d{2})$/)?.[1];
    const dateB = b.match(/_(\d{4}-\d{2}-\d{2})$/)?.[1];
    if (dateA && dateB) return new Date(dateB).getTime() - new Date(dateA).getTime(); // Descending
    return 0;
  });

  for (const key of keysToSearch) {
    const match = key.match(/_(\d{4}-\d{2}-\d{2})$/);
    if (match && match[1]) { // Ensure match and dateString exist
      const dateStr = match[1];
      try {
         // Create Date object from string parts using UTC
        const dateParts = dateStr.split('-').map(Number);
        if (dateParts.length === 3 && !dateParts.some(isNaN)) {
            const logDateTimestamp = Date.UTC(dateParts[0], dateParts[1] - 1, dateParts[2]);

            if (logDateTimestamp >= fourWeeksAgoTimestamp) {
                const dailyLogString = localStorage.getItem(key);
                if (!dailyLogString) continue;
                const dailyLog: DailyLog = JSON.parse(dailyLogString);

                let exercisesCompleted = 0;
                let setsCompleted = 0;

                Object.values(dailyLog).forEach((exerciseLog) => {
                  // Ensure exerciseLog is a valid object before iterating
                  if (exerciseLog && typeof exerciseLog === 'object') {
                    let exerciseHasCompletedSet = false;
                    Object.values(exerciseLog).forEach((setLog) => {
                      // Ensure setLog is valid and check isCompleted
                      if (setLog && typeof setLog === 'object' && setLog.isCompleted) {
                        setsCompleted++;
                        exerciseHasCompletedSet = true;
                      }
                    });
                    if (exerciseHasCompletedSet) {
                      exercisesCompleted++;
                    }
                  }
                });


                // Only add summary if at least one set was completed
                if (setsCompleted > 0) {
                    summaries.push({
                    date: dateStr,
                    exercisesCompleted: exercisesCompleted,
                    setsCompleted: setsCompleted,
                    });
                }

            } else {
                // Stop processing older logs once we go past the 4-week mark
                break;
            }
        } else {
             console.error(`Invalid date string format found in key: ${key}`);
        }

      } catch (e) {
        console.error(`Error processing log summary for key ${key}:`, e);
      }
    }
  }

  // Return summaries sorted ascending by date for the AI
  return summaries.sort((a, b) => new Date(a.date).getTime() - new Date(b.date).getTime());
};
