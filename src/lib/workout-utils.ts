// src/lib/workout-utils.ts
import type { DailyLog, NamedWorkoutPlan, SetData, LoggedSetData, Exercise, WorkoutDay, PlanExercise } from '../types/workout';



export const getAllExercises = (allPlans: NamedWorkoutPlan[]): Array<{ id: string; name: string }> => {
  const exercisesMap = new Map<string, string>();
  allPlans?.forEach((namedPlan: NamedWorkoutPlan) => {
    namedPlan.plan.forEach((day: WorkoutDay) => {
      day.exercises.forEach((ex: PlanExercise) => {
        const isSpecialCategory = ['cardio', 'mobility', 'warmup', 'cooldown'].includes(ex.category as string);
        if (!isSpecialCategory && ex.category !== 'core' && ex.unit === 'reps') {
          if (!exercisesMap.has(ex.id)) {
            exercisesMap.set(ex.id, ex.name);
          }
        }
      });
    });
  });
  return Array.from(exercisesMap, ([id, name]) => ({ id, name })).sort((a, b) => a.name.localeCompare(b.name));
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

  const sortedDates = Array.from(allLogs.keys()).sort((a, b) => new Date(a).getTime() - new Date(b).getTime());

  sortedDates.forEach(dateStr => {
    const dailyLog = allLogs.get(dateStr);
    if (!dailyLog) return;
    const exerciseLog = dailyLog[exerciseId];

    if (exerciseLog && typeof exerciseLog === 'object' && Object.keys(exerciseLog).length > 0) {
      const repsPerSet: string[] = [];
      let sessionWeight: string | undefined;

      // Find the first completed set to determine the session's weight
      for (const setId in exerciseLog) {
        const loggedSet = exerciseLog[setId] as LoggedSetData;
        if (loggedSet.isCompleted && loggedSet.weight) {
          sessionWeight = String(loggedSet.weight);
          break;
        }
      }
      if (sessionWeight === undefined) return;

      Object.values(exerciseLog).forEach((loggedSet: any) => {
        const s = loggedSet as LoggedSetData;
        if (s.isCompleted) {
          repsPerSet.push(String(s.reps ?? '0'));
        }
      });

      if (repsPerSet.length > 0) {
        relevantLogs.push({ date: dateStr, weightStr: sessionWeight, repsPerSet });
      }
    }
  });

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
  activePlan: NamedWorkoutPlan | undefined,
  currentDayLog?: DailyLog
): LoggedSetData | undefined => {
  if (!activePlan) return undefined;

  let currentExercise: Exercise | undefined;
  for (const day of activePlan.plan) {
    const found = day.exercises.find((ex: PlanExercise) => ex.id === exerciseId);
    if (found) {
      currentExercise = found;
      break;
    }
  }

  if (!currentExercise) return undefined;

  const allSetIdsForExercise = currentExercise.sets.map((s: SetData) => s.id);
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
    // We should not look at today's log for *historical* data, only previous days.
    // The check for previous sets *within* today's session is handled above.
    if (dateStr === todayStr) continue;

    const dailyLog = allLogs.get(dateStr);
    if (!dailyLog) continue;

    const historicalExerciseLog = dailyLog[exerciseId];
    if (historicalExerciseLog) {
      // Find the performance for the corresponding set from the last session this exercise was performed.
      // We look at the set with the same index.
      if (currentSetIndex !== -1) {
        const correspondingSetId = allSetIdsForExercise[currentSetIndex];
        const historicalSet = historicalExerciseLog[correspondingSetId];
        if (historicalSet?.isCompleted) {
          return historicalSet;
        }
      }
      // Fallback: If set IDs don't match (e.g., plan changed), find the last completed set from that day's log for the exercise.
      const lastCompletedSet = Object.values(historicalExerciseLog).reverse().find(s => s.isCompleted);
      if (lastCompletedSet) {
        return lastCompletedSet;
      }
    }
  }

  return undefined;
};


// New function for Muscle Heatmap
export const getVolumeForMuscleGroups = (
  dates: string[],
  allLogs: Map<string, DailyLog>,
  allPlans: NamedWorkoutPlan[]
): { [muscle: string]: number } => {
  const muscleVolumes: { [muscle: string]: number } = {};
  const exerciseCache = new Map<string, Exercise>();

  // Pre-populate exercise cache from all plans
  allPlans.forEach((p: NamedWorkoutPlan) => p.plan.forEach((d: WorkoutDay) => d.exercises.forEach((e: PlanExercise) => exerciseCache.set(e.id, e))));

  dates.forEach(dateStr => {
    const log = allLogs.get(dateStr);
    if (log) {
      for (const exerciseId in log) {
        const exerciseLog = log[exerciseId];
        const exerciseDef = exerciseCache.get(exerciseId);

        if (exerciseDef && exerciseDef.muscleGroups) {
          const completedSets = Object.values(exerciseLog).filter((set: any) => (set as LoggedSetData).isCompleted).length;
          if (completedSets > 0) {
            exerciseDef.muscleGroups.forEach((muscle: string) => {
              // **THE FIX**: Use += to accumulate volume instead of overwriting it.
              muscleVolumes[muscle] = (muscleVolumes[muscle] || 0) + completedSets;
            });
          }
        }
      }
    }
  });

  return muscleVolumes;
};
