
import type { DailyLog, Exercise } from '@/types/workout';
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
    for (let i = 0; i < localStorage.length; i++) {
        const key = localStorage.key(i);
        if (key && key.startsWith('gymtrack_log_')) {
            keysToSearch.push(key);
        }
    }
    
    // Sort keys by date ascending
    keysToSearch.sort((a, b) => {
        const dateA = a.match(/_(\d{4}-\d{2}-\d{2})$/)?.[1];
        const dateB = b.match(/_(\d{4}-\d{2}-\d{2})$/)?.[1];
        // Ensure consistent date parsing (consider UTC if timezone is an issue)
        if (dateA && dateB) return new Date(dateA).getTime() - new Date(dateB).getTime();
        return 0;
    });

    for (const key of keysToSearch) {
        const match = key.match(/_(\d{4}-\d{2}-\d{2})$/);
        if (match) {
            const dateStr = match[1]; // Date is the first capture group now
            try {
                const dailyLogString = localStorage.getItem(key);
                if (!dailyLogString) continue;
                const dailyLog: DailyLog = JSON.parse(dailyLogString);

                if (dailyLog[exerciseId] && exerciseDefinition) {
                    const exerciseLog = dailyLog[exerciseId];
                    const repsPerSet: string[] = [];
                    let sessionWeight: string | undefined;
                    
                    // Process sets in the order defined in the plan
                    exerciseDefinition.sets.forEach(setDef => {
                        const loggedSet = exerciseLog[setDef.id];
                        if (loggedSet && loggedSet.isCompleted) {
                            repsPerSet.push(String(loggedSet.reps || setDef.targetReps)); 
                            // Capture weight from the first completed set of that day
                            if (sessionWeight === undefined) {
                                // Use logged weight if present, otherwise fall back to exercise target
                                sessionWeight = String(loggedSet.weight || exerciseDefinition.targetWeight || 'bodyweight');
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
    // Return the most recent ~8 entries for the AI model
    return relevantLogs.slice(-8);
};

/**
 * Calculates the current and longest workout streaks from a list of dates.
 * Dates should represent logged workout days.
 * Assumes dates are Date objects.
 * @param dates - An array of Date objects representing logged workout days.
 * @returns An object with `current` and `longest` streak counts.
 */
export const calculateStreaks = (dates: Date[]): { current: number; longest: number } => {
  if (dates.length === 0) {
    return { current: 0, longest: 0 };
  }

  // 1. Sort dates chronologically
  const sortedDates = dates.map(d => d.getTime()).sort((a, b) => a - b);

  // 2. Calculate differences and identify streaks
  let currentStreak = 1;
  let longestStreak = 1;
  const oneDayMillis = 24 * 60 * 60 * 1000;

  for (let i = 1; i < sortedDates.length; i++) {
    const diff = sortedDates[i] - sortedDates[i - 1];

    // Check if the difference is exactly one day
    // Allow for slight variations due to DST by checking within a range (e.g., 23-25 hours)
    if (diff >= oneDayMillis - (3600 * 1000) && diff <= oneDayMillis + (3600 * 1000)) {
       // Check if the calendar day is consecutive (handle month/year changes)
       const date1 = new Date(sortedDates[i-1]);
       const date2 = new Date(sortedDates[i]);
       const nextDay = new Date(date1);
       nextDay.setUTCDate(date1.getUTCDate() + 1); // Increment day using UTC

       if (date2.getUTCFullYear() === nextDay.getUTCFullYear() &&
           date2.getUTCMonth() === nextDay.getUTCMonth() &&
           date2.getUTCDate() === nextDay.getUTCDate()) {
             currentStreak++;
           } else {
              // Not consecutive days, reset streak
              longestStreak = Math.max(longestStreak, currentStreak);
              currentStreak = 1;
           }
    } else if (diff > oneDayMillis + (3600 * 1000)) {
      // Gap larger than ~1 day, reset streak
      longestStreak = Math.max(longestStreak, currentStreak);
      currentStreak = 1;
    } 
    // Ignore diffs less than ~23 hours (e.g. multiple logs same day)
  }

  // Final check for the last streak
  longestStreak = Math.max(longestStreak, currentStreak);

  // Check if the most recent logged date is yesterday or today to determine if current streak is active
  const today = new Date();
  const lastLogDate = new Date(sortedDates[sortedDates.length - 1]);

  const todayStart = new Date(Date.UTC(today.getUTCFullYear(), today.getUTCMonth(), today.getUTCDate()));
  const yesterdayStart = new Date(todayStart.getTime() - oneDayMillis);
  
  const lastLogStart = new Date(Date.UTC(lastLogDate.getUTCFullYear(), lastLogDate.getUTCMonth(), lastLogDate.getUTCDate()));


  if (lastLogStart.getTime() < yesterdayStart.getTime()) {
      // If the last log was before yesterday, the current streak is broken
      currentStreak = 0;
  }


  return { current: currentStreak, longest: longestStreak };
};

// Add any other utility functions needed below
