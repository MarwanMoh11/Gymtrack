
import type { ChartDataPoint } from '@/components/dashboard/progress-chart';
import { weeklyPlan } from '@/data/workout-data';
import type { NextSessionRecommendationInput } from '@/ai/flows/next-session-recommendation';
import type { DailyLog, Exercise } from '@/types/workout';

export const getAllExercises = (): Array<{ id: string; name: string }> => {
  const exercisesMap = new Map<string, string>();
  weeklyPlan.forEach(day => {
    day.exercises.forEach(ex => {
      if (!ex.isWarmup && !ex.isConditioning && !ex.isStretch && !ex.isFoamRoll && !ex.isActivity && !ex.isMatch && !ex.isRecovery) {
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

    if (lowerWeightString.includes('bodyweight') || lowerWeightString.includes('bw') || lowerWeightString === '0 kg (bodyweight)' || lowerWeightString === 'bodyweight or added' || lowerWeightString === '0') {
        const bodyweightBase = 70; // Example placeholder for BW in kg
        const addMatch = lowerWeightString.match(/(?:bw|bodyweight)\s*\+\s*([\d.]+)\s*kg/i);
        if (addMatch && addMatch[1]) {
            return bodyweightBase + parseFloat(addMatch[1]);
        }
        // If "bodyweight or added" and no explicit addition, default to bodyweight or 0 if that makes more sense.
        // For "0 kg (bodyweight)", it's effectively 0 if it's an external load, or bodyweight if it's the exercise itself.
        // Given the context, if "bodyweight" is mentioned, it implies body as resistance.
        // If it's "0 kg", it means no ADDED weight.
        if (lowerWeightString.includes('0 kg') && lowerWeightString.includes('bodyweight')) return 0; // e.g. Dips with no added weight
        if (lowerWeightString === '0') return 0;
        return bodyweightBase; // Default for "bodyweight"
    }
    
    // Handle "Xth stack" or "X stack"
    const stackMatch = lowerWeightString.match(/([\d.]+)(?:st|nd|rd|th)?\s*stack/i);
    if (stackMatch && stackMatch[1]) {
        const stackPosition = parseFloat(stackMatch[1]);
        // Assuming each stack plate is ~5kg. This is a rough heuristic.
        return stackPosition * 5; 
    }
    
    // Handle "X kg each side"
    const eachSideMatch = lowerWeightString.match(/([\d.]+)\s*kg\s*each\s*side/i);
    if (eachSideMatch && eachSideMatch[1]) {
        return parseFloat(eachSideMatch[1]) * 2;
    }

    // General numeric match (e.g., "22.5 kg", "65", "12 lbs")
    // Also handles "Maintain at 80 kg" -> 80
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

    const keysToSearch: string[] = [];
    for (let i = 0; i < localStorage.length; i++) {
        const key = localStorage.key(i);
        if (key && key.startsWith('gymtrack_log_')) {
            keysToSearch.push(key);
        }
    }
    
    keysToSearch.sort((a, b) => {
        const dateA = a.match(/_(\d{4}-\d{2}-\d{2})$/)?.[1];
        const dateB = b.match(/_(\d{4}-\d{2}-\d{2})$/)?.[1];
        if (dateA && dateB) return new Date(dateA).getTime() - new Date(dateB).getTime();
        return 0;
    });

    let originalExercise: Exercise | undefined;
    for (const day of weeklyPlan) {
        originalExercise = day.exercises.find(ex => ex.id === exerciseId);
        if (originalExercise) break;
    }

    for (const key of keysToSearch) {
        const match = key.match(/gymtrack_log_([a-zA-Z0-9-]+)_(\d{4}-\d{2}-\d{2})$/);
        if (match) {
            const dateStr = match[2];
            try {
                const dailyLogString = localStorage.getItem(key);
                if (!dailyLogString) continue;
                const dailyLog: DailyLog = JSON.parse(dailyLogString);

                if (dailyLog[exerciseId]) {
                    const exerciseLog = dailyLog[exerciseId];
                    const repsPerSet: string[] = [];
                    let currentWeight: string | undefined;
                    
                    if (originalExercise) {
                        // Ensure sets are processed in their defined order
                        originalExercise.sets.forEach(setDef => {
                            const loggedSet = exerciseLog[setDef.id];
                            if (loggedSet && loggedSet.isCompleted) {
                                repsPerSet.push(String(loggedSet.reps || setDef.targetReps));
                                // Capture weight from the first completed set of that day for consistency
                                if (currentWeight === undefined) {
                                    currentWeight = String(loggedSet.weight || setDef.targetWeight || originalExercise?.targetWeight || 'bodyweight');
                                }
                            }
                        });
                    }

                    if (repsPerSet.length > 0 && currentWeight !== undefined) {
                       relevantLogs.push({
                           date: dateStr,
                           weight: currentWeight,
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
