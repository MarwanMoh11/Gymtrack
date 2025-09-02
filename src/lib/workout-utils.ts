

import type { DailyLog, Exercise, WorkoutDay, NamedWorkoutPlan, SetData, LoggedSetData } from '@/types/workout';
import { defaultNamedPlans } from '@/data/workout-data';
import type { NextSessionRecommendationInput } from '@/ai/flows/next-session-recommendation';


export const getAllExercises = (allPlans: NamedWorkoutPlan[]): Array<{ id: string; name: string }> => {
  const exercisesMap = new Map<string, string>();
  allPlans?.forEach(namedPlan => {
    namedPlan.plan.forEach(day => {
      day.exercises.forEach(ex => {
        if (!ex.isWarmup && !ex.isConditioning && !ex.stretch && !ex.isFoamRoll && !ex.isActivity && !ex.isMatch && !ex.isRecovery && !ex.isCore && ex.unit === 'reps') {
          if (!exercisesMap.has(ex.id)) {
            exercisesMap.set(ex.id, ex.name);
          }
        }
      });
    });
  });
  return Array.from(exercisesMap, ([id, name]) => ({ id, name })).sort((a,b) => a.name.localeCompare(b.name));
};

export const parseWeightToNumber = (weightString: string | number | undefined): number => {
    if (typeof weightString === 'number') return weightString;
    if (typeof weightString !== 'string' || !weightString.trim()) return 0;
    const lowerWeightString = weightString.toLowerCase();
    if (['bodyweight', 'bw', '0', '0 kg', 'n/a'].includes(lowerWeightString)) return 0;
    const addMatch = lowerWeightString.match(/(?:bw|bodyweight)\s*\+\s*([\d.]+)/i);
    if (addMatch && addMatch[1]) return parseFloat(addMatch[1]);
    const stackMatch = lowerWeightString.match(/([\d.]+)(?:st|nd|rd|th)?\s*stack/i);
    if (stackMatch && stackMatch[1]) return parseFloat(stackMatch[1]) * 5;
    const eachSideMatch = lowerWeightString.match(/([\d.]+)\s*kg\s*each\s*side/i);
    if (eachSideMatch && eachSideMatch[1]) return (parseFloat(eachSideMatch[1]) * 2) + 20;
    const numericMatch = lowerWeightString.match(/([\d.]+)/);
    if (numericMatch && numericMatch[1]) return parseFloat(numericMatch[1]);
    return 0;
};

export type ChartData = {
  date: string;
  weight: number;
  reps: string;
  isPR: boolean;
};

export const calculateProgressDataForChart = (exerciseId: string, allLogs: Map<string, DailyLog>): ChartData[] => {
    const relevantLogs: Array<{ date: string, weightStr: string, repsPerSet: string[] }> = [];

    allLogs.forEach((dailyLog, dateStr) => {
        const exerciseLog = dailyLog[exerciseId];
        if (exerciseLog && typeof exerciseLog === 'object' && Object.keys(exerciseLog).length > 0) {
            const repsPerSet: string[] = [];
            let sessionWeight: string | undefined;

            for (const setId in exerciseLog) {
                const loggedSet = exerciseLog[setId];
                if (loggedSet.isCompleted && loggedSet.weight) {
                    sessionWeight = loggedSet.weight;
                    break; 
                }
            }
            if (sessionWeight === undefined) return;

            Object.values(exerciseLog).forEach(loggedSet => {
                if (loggedSet.isCompleted) {
                    repsPerSet.push(String(loggedSet.reps ?? '0'));
                }
            });

            if (repsPerSet.length > 0) {
                relevantLogs.push({ date: dateStr, weightStr: sessionWeight, repsPerSet });
            }
        }
    });

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


export const transformHistoricalDataForAI = (exerciseId: string, allLogs: Map<string, DailyLog>): NextSessionRecommendationInput['recentPerformance'] => {
    const relevantLogs: Array<{ date: string, weight: string, repsPerSet: string[] }> = [];

    const sortedDates = Array.from(allLogs.keys()).sort((a,b) => new Date(a).getTime() - new Date(b).getTime());

    sortedDates.forEach(dateStr => {
        const dailyLog = allLogs.get(dateStr);
        if (!dailyLog) return;
        const exerciseLog = dailyLog[exerciseId];
        
        if (exerciseLog && typeof exerciseLog === 'object' && Object.keys(exerciseLog).length > 0) {
            const repsPerSet: string[] = [];
            let sessionWeight: string | undefined;

            for (const setId in exerciseLog) {
                const set = exerciseLog[setId];
                if (set.isCompleted && set.weight) {
                    sessionWeight = set.weight;
                    break;
                }
            }
            if (sessionWeight === undefined) return;

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
    });
    return relevantLogs.slice(-8);
};

export const calculateStreaks = (dates: Date[]): { current: number; longest: number } => {
  if (dates.length === 0) return { current: 0, longest: 0 };
  const uniqueSortedTimestamps = Array.from(new Set(dates.map(d => d.getTime()))).sort((a, b) => a - b);
  if (uniqueSortedTimestamps.length === 0) return { current: 0, longest: 0 };
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
    allLogs: Map<string, DailyLog>,
    currentDayLog?: DailyLog // Pass today's log to search within it
): LoggedSetData | undefined => {
    
    const allSetIdsForExercise = Object.keys(currentDayLog?.[exerciseId] ?? {});
    const currentSetIndex = allSetIdsForExercise.indexOf(currentSetId);

    // 1. Check previous sets in the CURRENT workout session first
    if (currentDayLog && currentSetIndex > 0) {
        for (let i = currentSetIndex - 1; i >= 0; i--) {
            const prevSetId = allSetIdsForExercise[i];
            const prevSetLog = currentDayLog[exerciseId]?.[prevSetId];
            if (prevSetLog?.isCompleted) {
                return prevSetLog;
            }
        }
    }

    // 2. If no prior set today, check historical logs
    const sortedDates = Array.from(allLogs.keys()).sort((a, b) => new Date(b).getTime() - new Date(a).getTime());
    const todayStr = new Date().toISOString().split('T')[0];

    for (const dateStr of sortedDates) {
        // We can look at today's log too, in case we're editing a later set after finishing an earlier one
        const dailyLog = allLogs.get(dateStr);
        if (!dailyLog) continue;

        const historicalExerciseLog = dailyLog[exerciseId];
        if (historicalExerciseLog) {
             // Find the last completed set from that day for the exercise
             const historicalSetIds = Object.keys(historicalExerciseLog).reverse();
             for (const setId of historicalSetIds) {
                 const historicalSet = historicalExerciseLog[setId];
                 if (historicalSet?.isCompleted) {
                     return historicalSet;
                 }
             }
        }
    }
    
    return undefined;
};
