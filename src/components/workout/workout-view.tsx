
'use client';

import { useState, useEffect, useCallback } from 'react';
import type { WorkoutDay, DailyLog, LoggedSetData, Exercise } from '@/types/workout';
import ExerciseCard from './exercise-card';
import DayProgress from './day-progress';
import { Button } from '@/components/ui/button';
import { useToast } from '@/hooks/use-toast';
import { Card, CardDescription, CardHeader, CardTitle } from '../ui/card';
import { nextSessionRecommendation, NextSessionRecommendationInput, NextSessionRecommendationOutput } from '@/ai/flows/next-session-recommendation';
import { transformHistoricalDataForAI } from '@/lib/workout-utils';
import { getUserTargetWeight, setTargetWeightOverride } from '@/lib/user-settings';
import LoadingWorkoutPage from '@/app/workout/[day]/loading'; // Import loading component

interface WorkoutViewProps {
  workoutDay: WorkoutDay;
}

const getCurrentDateString = (): string => {
  return new Date().toISOString().split('T')[0];
};

function getLocalStorageKey(dayId: string, date: string): string {
  return `gymtrack_log_${dayId}_${date}`;
}

export default function WorkoutView({ workoutDay }: WorkoutViewProps) {
  const [dailyLog, setDailyLog] = useState<DailyLog>({});
  const [isInitialized, setIsInitialized] = useState(false);
  const [currentDate, setCurrentDate] = useState('');
  const [aiSuggestionsForToday, setAiSuggestionsForToday] = useState<Map<string, NextSessionRecommendationOutput | null>>(new Map());
  const [isLoadingAISuggestions, setIsLoadingAISuggestions] = useState(false);
  // State to trigger re-render when effective target weights change via user settings
  const [effectiveTargetWeightsKey, setEffectiveTargetWeightsKey] = useState(0); 
  const { toast } = useToast();

  // Initialize date and load log from localStorage
  useEffect(() => {
    const dateStr = getCurrentDateString();
    setCurrentDate(dateStr);

    if (typeof window !== 'undefined') {
      const key = getLocalStorageKey(workoutDay.id, dateStr);
      const storedLog = localStorage.getItem(key);
      if (storedLog) {
        try {
          setDailyLog(JSON.parse(storedLog));
        } catch (error) {
          console.error("Failed to parse stored log:", error);
          localStorage.removeItem(key); 
          setDailyLog({});
        }
      } else {
        setDailyLog({});
      }
      setIsInitialized(true); // Mark as initialized after loading attempt
    } else {
        setIsInitialized(true); // Mark initialized even if window is undefined (SSR/initial)
    }
  }, [workoutDay.id]); // Only depends on workoutDay.id

  // Save log to localStorage whenever it changes
  useEffect(() => {
    if (isInitialized && typeof window !== 'undefined' && currentDate) {
      const key = getLocalStorageKey(workoutDay.id, currentDate);
      if (Object.keys(dailyLog).length > 0) {
        localStorage.setItem(key, JSON.stringify(dailyLog));
      } else {
        // Only remove if the key actually exists to avoid unnecessary writes
        if (localStorage.getItem(key)) {
            localStorage.removeItem(key);
        }
      }
    }
  }, [dailyLog, workoutDay.id, isInitialized, currentDate]);

  // Fetch AI suggestions for today's workout
  const fetchAISuggestionsForToday = useCallback(async () => {
    if (!isInitialized || !currentDate || typeof window === 'undefined') return; // Need localstorage access

    setIsLoadingAISuggestions(true);
    const suggestions = new Map<string, NextSessionRecommendationOutput | null>();
    
    for (const exercise of workoutDay.exercises) {
      // Only fetch for main lifts, not accessories/activities
      if (!exercise.isWarmup && !exercise.isConditioning && !exercise.isStretch && !exercise.isFoamRoll && !exercise.isActivity && !exercise.isMatch && !exercise.isRecovery && !exercise.isCore) {
        const recentPerformance = transformHistoricalDataForAI(exercise.id); // Needs localStorage
        if (recentPerformance.length > 0) {
          try {
            const input: NextSessionRecommendationInput = {
              exerciseName: exercise.name,
              recentPerformance,
              userGoal: 'Progressive overload for strength and hypertrophy',
            };
            const suggestion = await nextSessionRecommendation(input);
            suggestions.set(exercise.id, suggestion);
          } catch (e) {
            console.error(`AI Suggestion Error for ${exercise.name}:`, e);
            suggestions.set(exercise.id, null); // Store null on error
          }
        } else {
          suggestions.set(exercise.id, null); // Store null if no history
        }
      } else {
        suggestions.set(exercise.id, null); // No suggestion needed for these types
      }
    }
    setAiSuggestionsForToday(suggestions);
    setIsLoadingAISuggestions(false);
  }, [workoutDay.exercises, isInitialized, currentDate]);

  // Trigger AI fetch after initialization
  useEffect(() => {
    if(isInitialized && currentDate) { 
       fetchAISuggestionsForToday();
    }
  }, [fetchAISuggestionsForToday, isInitialized, currentDate]);


  // Handle logging a single set
  const handleLogSet = useCallback((exerciseId: string, setId: string, log: LoggedSetData) => {
    setDailyLog(prevLog => {
        const newExerciseLog = {
            ...(prevLog[exerciseId] || {}),
            [setId]: log,
        };
        // If all sets are now completed, remove the entry if empty, otherwise update
        const isEmpty = Object.values(newExerciseLog).every(l => !l.isCompleted && !l.reps && !l.weight);
        if (isEmpty) {
            const { [exerciseId]: _, ...restLog } = prevLog;
            return restLog;
        } else {
            return {
                ...prevLog,
                [exerciseId]: newExerciseLog,
            };
        }
    });
  }, []);

  // Clear the entire log for the current day
  const handleClearDayLog = useCallback(() => {
    setDailyLog({});
    toast({
      title: "Log Cleared",
      description: `Log for ${workoutDay.dayName} (${currentDate}) has been cleared.`,
    });
     // Also force refresh of effective weights display if needed
    setEffectiveTargetWeightsKey(prev => prev + 1);
  }, [workoutDay.dayName, currentDate, toast]);

  // Update the target weight override and trigger UI refresh
  const handleUpdateEffectiveTargetWeight = useCallback((exerciseId: string, newWeight: string) => {
    const exerciseName = workoutDay.exercises.find(e => e.id === exerciseId)?.name || 'exercise';
    setTargetWeightOverride(exerciseId, newWeight);
    setEffectiveTargetWeightsKey(prev => prev + 1); // Force re-render to show updated target weight
    toast({
      title: "Plan Updated",
      description: `Target weight for ${exerciseName} updated to ${newWeight}.`,
    });
  }, [toast, workoutDay.exercises]);

  // Reset logged reps for a specific exercise (called when weight changes)
  const triggerRepReset = useCallback((exerciseId: string) => {
    setDailyLog(prevLog => {
        const exerciseLog = prevLog[exerciseId];
        if (!exerciseLog) return prevLog; // No log exists for this exercise yet

        const updatedExerciseLog: LoggedExerciseData = {};
        const exerciseDefinition = workoutDay.exercises.find(e => e.id === exerciseId);

        exerciseDefinition?.sets.forEach(setDef => {
            // Reset reps to '8' and mark as incomplete
            updatedExerciseLog[setDef.id] = { 
                ...exerciseLog[setDef.id], // Keep original weight if logged, but it will be overwritten on next log
                reps: '8', 
                isCompleted: false 
            };
        });

        return {
            ...prevLog,
            [exerciseId]: updatedExerciseLog,
        };
    });
     toast({
        variant: "default",
        title: "Reps Reset",
        description: `Logged reps for ${workoutDay.exercises.find(e=>e.id===exerciseId)?.name || 'exercise'} reset due to weight change. Please re-log your sets.`,
     });
  }, [workoutDay.exercises, toast]);


  // Show loading state until initialized
  if (!isInitialized) {
    // Use the dedicated loading component if available, otherwise simple text
    return typeof LoadingWorkoutPage === 'function' ? <LoadingWorkoutPage /> : <div>Loading workout...</div>;
  }

  return (
    <div className="container mx-auto max-w-3xl px-2 sm:px-4 py-8">
      <Card className="mb-8 bg-card shadow-lg border-none">
        <CardHeader>
          <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-2">
            <div>
              <CardTitle className="text-3xl font-bold text-primary mb-1">{workoutDay.dayName}</CardTitle>
              <CardDescription className="text-lg text-muted-foreground">{workoutDay.title} - {currentDate}</CardDescription>
            </div>
             <Button variant="outline" onClick={handleClearDayLog} size="sm" className="rounded-full shrink-0">
              Clear Today's Log
            </Button>
          </div>
          {workoutDay.notes && (
            <p className="mt-3 text-sm text-foreground/80 p-3 bg-secondary/50 rounded-md">{workoutDay.notes}</p>
          )}
        </CardHeader>
      </Card>
      
      <DayProgress workoutDay={workoutDay} dailyLog={dailyLog} />

      {workoutDay.exercises.map((exercise: Exercise) => {
        // Get the potentially overridden target weight for display and logging
        const effectiveTargetWeight = getUserTargetWeight(exercise.id, exercise.targetWeight);
        
        return (
          <ExerciseCard
            key={`${exercise.id}-${effectiveTargetWeightsKey}`} // Add key to force re-render on target weight changes
            exercise={exercise}
            effectiveTargetWeight={effectiveTargetWeight} // Pass down the effective weight
            onLogSet={handleLogSet}
            loggedData={dailyLog[exercise.id]}
            aiSuggestionForToday={aiSuggestionsForToday.get(exercise.id)}
            isLoadingAISuggestion={isLoadingAISuggestions && !aiSuggestionsForToday.has(exercise.id)}
            onUpdateEffectiveTargetWeight={handleUpdateEffectiveTargetWeight}
            triggerRepReset={triggerRepReset} // Pass down the reset function
          />
        );
      })}
    </div>
  );
}
