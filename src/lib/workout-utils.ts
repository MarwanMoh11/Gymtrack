
import type { DailyLog, Exercise, WorkoutDay, LoggedExerciseData, SetData } from '@/types/workout';
import { getActiveWorkoutPlan, getExerciseById } from '@/lib/workout-plan-service';
import type { NextSessionRecommendationInput } from '@/ai/flows/next-session-recommendation';


export const getAllExercises = (): Array<{ id: string; name: string }> => {
  const activePlan = getActiveWorkoutPlan();
  if (!activePlan) return [];
  
  const exercisesMap = new Map<string, string>();
  activePlan.forEach(day => {
    day.exercises.forEach(ex => {
      // Include only exercises likely to be tracked for progressive overload
      if (!ex.isWarmup && !ex.isConditioning && !ex.isStretch && !ex.isFoamRoll && !ex.isActivity && !ex.isMatch && !ex.isRecovery && !ex.isCore && ex.unit === 'reps') {
        if (!exercisesMap.has(ex.id)) {
          exercisesMap.set(ex.id, ex.name);
        }
      }
    });
  });
  return Array.from(exercisesMap, ([id, name]) => ({ id, name })).sort((a,b) => a.name.localeCompare(b.name));
};

export const parseWeightToNumber = (weightString: string | number | undefined): number => {
    if (typeof weightString === 'number') return weightString;
    if (typeof weightString !== 'string' || !weightString.trim()) return 0;

    const lowerWeightString = weightString.toLowerCase();
    
    // Handle specific keywords that mean 0 weight
    if (['bodyweight', 'bw', '0', '0 kg', 'n/a'].includes(lowerWeightString)) {
        return 0;
    }
    
    // Handle "bodyweight + 5kg"
    const addMatch = lowerWeightString.match(/(?:bw|bodyweight)\s*\+\s*([\d.]+)/i);
    if (addMatch && addMatch[1]) {
        // Here we can't know the user's bodyweight, so we represent this as just the added weight.
        // A more complex implementation could ask for user's bodyweight. For charting, this is a reasonable simplification.
        return parseFloat(addMatch[1]);
    }

    // Handle "5th stack" or "5 stack"
    const stackMatch = lowerWeightString.match(/([\d.]+)(?:st|nd|rd|th)?\s*stack/i);
    if (stackMatch && stackMatch[1]) {
        return parseFloat(stackMatch[1]) * 5; // Rough heuristic: 5kg per stack plate
    }

    // Handle "15 kg each side"
    const eachSideMatch = lowerWeightString.match(/([\d.]+)\s*kg\s*each\s*side/i);
    if (eachSideMatch && eachSideMatch[1]) {
        // Assuming standard 20kg olympic bar for exercises that might use this wording
        const barWeight = 20; 
        return (parseFloat(eachSideMatch[1]) * 2) + barWeight;
    }

    // General numeric match (e.g., "22.5 kg", "65", "Maintain at 80 kg")
    const numericMatch = lowerWeightString.match(/([\d.]+)/);
    if (numericMatch && numericMatch[1]) {
        return parseFloat(numericMatch[1]);
    }

    console.warn(`Could not parse weight string: "${weightString}". Defaulting to 0.`);
    return 0;
};

export type ChartData = {
  date: string;
  weight: number;
  reps: string;
  isPR: boolean;
};

export const calculateProgressDataForChart = (exerciseId: string): ChartData[] => {
    if (typeof window === 'undefined') return [];

    const relevantLogs: Array<{ date: string, weightStr: string, repsPerSet: string[] }> = [];

    // This logic is similar to transformHistoricalDataForAI but simplified for chart needs
    try {
        for (let i = 0; i < localStorage.length; i++) {
            const key = localStorage.key(i);
            if (!key || !key.startsWith('gymtrack_log_')) continue;

            const match = key.match(/_(\d{4}-\d{2}-\d{2})$/);
            if (!match || !match[1]) continue;
            
            const dateStr = match[1];
            const dailyLogString = localStorage.getItem(key);
            if (!dailyLogString) continue;

            const dailyLog: DailyLog = JSON.parse(dailyLogString);
            const exerciseLog = dailyLog[exerciseId];

            if (exerciseLog && typeof exerciseLog === 'object' && Object.keys(exerciseLog).length > 0) {
                 const repsPerSet: string[] = [];
                 let sessionWeight: string | undefined;

                 // Use first completed set to determine the weight for the session
                 for (const setId in exerciseLog) {
                    const loggedSet = exerciseLog[setId];
                    if (loggedSet.isCompleted && loggedSet.weight) {
                        sessionWeight = loggedSet.weight;
                        break;
                    }
                 }
                 // If no weight on a set, fallback to exercise definition (less accurate)
                 if (!sessionWeight) {
                    const exerciseDef = getExerciseById(exerciseId);
                    sessionWeight = exerciseDef?.targetWeight ?? '0';
                 }

                 Object.values(exerciseLog).forEach(loggedSet => {
                     if (loggedSet.isCompleted) {
                         repsPerSet.push(String(loggedSet.reps ?? '0'));
                     }
                 });

                 if (repsPerSet.length > 0 && sessionWeight !== undefined) {
                    relevantLogs.push({ date: dateStr, weightStr: sessionWeight, repsPerSet });
                 }
            }
        }
    } catch (e) {
        console.error("Error processing logs for chart data:", e);
        return [];
    }

    // Sort by date ascending
    relevantLogs.sort((a, b) => new Date(a.date).getTime() - new Date(b.date).getTime());
    
    let maxWeight = -1;
    const chartData: ChartData[] = relevantLogs.map(log => {
        const weight = parseWeightToNumber(log.weightStr);
        let isPR = false;
        if (weight > maxWeight) {
            isPR = true;
            maxWeight = weight;
        }
        return {
            date: log.date,
            weight: weight,
            reps: log.repsPerSet.join(', '),
            isPR,
        };
    });

    return chartData;
};


export const transformHistoricalDataForAI = (exerciseId: string): NextSessionRecommendationInput['recentPerformance'] => {
    if (typeof window === 'undefined') return [];

    const relevantLogs: Array<{ date: string, weight: string, repsPerSet: string[] }> = [];

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
        return [];
    }


    keysToSearch.sort((a, b) => {
        const dateA = a.match(/_(\d{4}-\d{2}-\d{2})$/)?.[1];
        const dateB = b.match(/_(\d{4}-\d{2}-\d{2})$/)?.[1];
        if (dateA && dateB) return new Date(dateA).getTime() - new Date(dateB).getTime();
        return 0;
    });

    for (const key of keysToSearch) {
        const match = key.match(/_(\d{4}-\d{2}-\d{2})$/);
        if (match && match[1]) { 
            const dateStr = match[1];
            try {
                const dailyLogString = localStorage.getItem(key);
                if (!dailyLogString) continue;
                const dailyLog: DailyLog = JSON.parse(dailyLogString);

                const exerciseLog = dailyLog[exerciseId];
                
                if (exerciseLog && typeof exerciseLog === 'object' && Object.keys(exerciseLog).length > 0) {
                    const repsPerSet: string[] = [];
                    let sessionWeight: string | undefined;

                    // Find a representative weight from the logged sets for that day
                    for (const setId in exerciseLog) {
                        const set = exerciseLog[setId];
                        if (set.isCompleted && set.weight) {
                            sessionWeight = set.weight;
                            break;
                        }
                    }

                    // If no weight is found in any set, we can't form a valid entry
                    if (sessionWeight === undefined) continue;

                    // Collect all completed reps
                    Object.values(exerciseLog).forEach(set => {
                        if (set.isCompleted) {
                            repsPerSet.push(String(set.reps ?? '0'));
                        }
                    });

                    if (repsPerSet.length > 0) {
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

export const calculateStreaks = (dates: Date[]): { current: number; longest: number } => {
  if (dates.length === 0) {
    return { current: 0, longest: 0 };
  }

  const uniqueSortedTimestamps = Array.from(new Set(dates.map(d => d.getTime()))).sort((a, b) => a - b);

  if (uniqueSortedTimestamps.length === 0) {
    return { current: 0, longest: 0 };
  }

  let currentStreak = 0; 
  let longestStreak = 0;
  const oneDayMillis = 24 * 60 * 60 * 1000;

  for (let i = 0; i < uniqueSortedTimestamps.length; i++) {
    if (i === 0) {
      currentStreak = 1;
    } else {
      const diff = uniqueSortedTimestamps[i] - uniqueSortedTimestamps[i - 1];
      if (diff === oneDayMillis) {
        currentStreak++;
      } else {
        longestStreak = Math.max(longestStreak, currentStreak);
        currentStreak = 1;
      }
    }
    longestStreak = Math.max(longestStreak, currentStreak);
  }

  const today = new Date();
  const todayUTCStart = Date.UTC(today.getUTCFullYear(), today.getUTCMonth(), today.getUTCDate());
  const lastLogTimestamp = uniqueSortedTimestamps[uniqueSortedTimestamps.length - 1];

  if (lastLogTimestamp < todayUTCStart - oneDayMillis) {
    currentStreak = 0;
  }

  return { current: currentStreak, longest: longestStreak };
};

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

    keysToSearch.sort((a, b) => {
        const dateA = a.match(/_(\d{4}-\d{2}-\d{2})$/)?.[1];
        const dateB = b.match(/_(\d{4}-\d{2}-\d{2})$/)?.[1];
        if (dateA && dateB) return new Date(dateB).getTime() - new Date(dateA).getTime();
        return 0;
    });

    const currentSetIndex = exerciseSetsDefinition.findIndex(set => set.id === currentSetId);
    if (currentSetIndex === -1) return undefined;

    for (const key of keysToSearch) {
        const match = key.match(/_(\d{4}-\d{2}-\d{2})$/);
        if (match && match[1]) {
            const dateStr = match[1];
            if (dateStr === todayStr) continue;

            try {
                const dailyLogString = localStorage.getItem(key);
                if (!dailyLogString) continue;
                const dailyLog: DailyLog = JSON.parse(dailyLogString);

                const historicalExerciseLog = dailyLog[exerciseId];
                if (historicalExerciseLog && typeof historicalExerciseLog === 'object') {
                    const historicalSetIds = Object.keys(historicalExerciseLog);
                    if (historicalSetIds.length > currentSetIndex) {
                        const historicalSetKey = historicalSetIds[currentSetIndex];
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
