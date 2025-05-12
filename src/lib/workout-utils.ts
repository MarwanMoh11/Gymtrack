
import type { DailyLog, Exercise, WorkoutDay } from '@/types/workout';
import { weeklyPlan } from '@/data/workout-data';
import type { NextSessionRecommendationInput } from '@/ai/flows/next-session-recommendation';
import type { CoachingTipsInput } from '@/ai/flows/coaching-tips-flow';


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
        if (dateA && dateB) return new Date(dateA).getTime() - new Date(dateB).getTime();
        return 0;
    });

    for (const key of keysToSearch) {
        const match = key.match(/_(\d{4}-\d{2}-\d{2})$/);
        if (match) {
            const dateStr = match[1];
            try {
                const dailyLogString = localStorage.getItem(key);
                if (!dailyLogString) continue;
                const dailyLog: DailyLog = JSON.parse(dailyLogString);

                if (dailyLog[exerciseId] && exerciseDefinition) {
                    const exerciseLog = dailyLog[exerciseId];
                    const repsPerSet: string[] = [];
                    let sessionWeight: string | undefined;

                    exerciseDefinition.sets.forEach(setDef => {
                        const loggedSet = exerciseLog[setDef.id];
                        if (loggedSet && loggedSet.isCompleted) {
                            repsPerSet.push(String(loggedSet.reps || setDef.targetReps));
                            if (sessionWeight === undefined) {
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

  const sortedDates = dates.map(d => d.getTime()).sort((a, b) => a - b);

  let currentStreak = 1;
  let longestStreak = 1;
  const oneDayMillis = 24 * 60 * 60 * 1000;

  for (let i = 1; i < sortedDates.length; i++) {
    const diff = sortedDates[i] - sortedDates[i - 1];

    if (diff >= oneDayMillis - (3600 * 1000) && diff <= oneDayMillis + (3600 * 1000)) {
       const date1 = new Date(sortedDates[i-1]);
       const date2 = new Date(sortedDates[i]);
       const nextDay = new Date(date1);
       nextDay.setUTCDate(date1.getUTCDate() + 1);

       if (date2.getUTCFullYear() === nextDay.getUTCFullYear() &&
           date2.getUTCMonth() === nextDay.getUTCMonth() &&
           date2.getUTCDate() === nextDay.getUTCDate()) {
             currentStreak++;
           } else {
              longestStreak = Math.max(longestStreak, currentStreak);
              currentStreak = 1;
           }
    } else if (diff > oneDayMillis + (3600 * 1000)) {
      longestStreak = Math.max(longestStreak, currentStreak);
      currentStreak = 1;
    }
  }

  longestStreak = Math.max(longestStreak, currentStreak);

  const today = new Date();
  const lastLogDate = new Date(sortedDates[sortedDates.length - 1]);
  const todayStart = new Date(Date.UTC(today.getUTCFullYear(), today.getUTCMonth(), today.getUTCDate()));
  const yesterdayStart = new Date(todayStart.getTime() - oneDayMillis);
  const lastLogStart = new Date(Date.UTC(lastLogDate.getUTCFullYear(), lastLogDate.getUTCMonth(), lastLogDate.getUTCDate()));

  if (lastLogStart.getTime() < yesterdayStart.getTime()) {
      currentStreak = 0;
  }

  return { current: currentStreak, longest: longestStreak };
};


/**
 * Summarizes recent workout logs for AI coaching tips input.
 * Fetches logs from the last ~4 weeks (28 days).
 * @returns An array of LogSummary objects.
 */
export const summarizeRecentLogs = (): CoachingTipsInput['recentLogs'] => {
  if (typeof window === 'undefined') return [];

  const summaries: CoachingTipsInput['recentLogs'] = [];
  const fourWeeksAgo = new Date();
  fourWeeksAgo.setDate(fourWeeksAgo.getDate() - 28);
  const fourWeeksAgoTimestamp = fourWeeksAgo.getTime();

  const keysToSearch: string[] = [];
  for (let i = 0; i < localStorage.length; i++) {
    const key = localStorage.key(i);
    if (key && key.startsWith('gymtrack_log_')) {
      keysToSearch.push(key);
    }
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
    if (match) {
      const dateStr = match[1];
      const logDate = new Date(dateStr);
      logDate.setUTCHours(0, 0, 0, 0); // Normalize to UTC start of day

      if (logDate.getTime() >= fourWeeksAgoTimestamp) {
        try {
          const dailyLogString = localStorage.getItem(key);
          if (!dailyLogString) continue;
          const dailyLog: DailyLog = JSON.parse(dailyLogString);

          let exercisesCompleted = 0;
          let setsCompleted = 0;

          Object.values(dailyLog).forEach((exerciseLog) => {
            let exerciseHasCompletedSet = false;
            Object.values(exerciseLog).forEach((setLog) => {
              if (setLog.isCompleted) {
                setsCompleted++;
                exerciseHasCompletedSet = true;
              }
            });
            if (exerciseHasCompletedSet) {
              exercisesCompleted++;
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
        } catch (e) {
          console.error(`Error processing log summary for key ${key}:`, e);
        }
      } else {
        // Stop processing older logs once we go past the 4-week mark
        break;
      }
    }
  }

  // Return summaries sorted ascending by date for the AI
  return summaries.sort((a, b) => new Date(a.date).getTime() - new Date(b.date).getTime());
};
