
'use client';

import { useState, useEffect, useCallback } from 'react';
import type { WorkoutDay, DailyLog, LoggedSetData, Exercise } from '@/types/workout';
import ExerciseCard from './exercise-card';
import DayProgress from './day-progress';
import { Button } from '@/components/ui/button';
import { useToast } from '@/hooks/use-toast';
import { Card, CardDescription, CardHeader, CardTitle } from '../ui/card';
// Removed AI imports: nextSessionRecommendation, NextSessionRecommendationInput, NextSessionRecommendationOutput
// Removed AI related utility: transformHistoricalDataForAI
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
  // Removed AI State: aiSuggestionsForToday, isLoadingAISuggestions
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

  // Removed fetchAISuggestionsForToday function and related useEffect

  // Handle logging a single set
  const handleLogSet = useCallback((exerciseId: string, setId: string, log: LoggedSetData) => {
    setDailyLog(prevLog => {
        const newExerciseLog = {
            ...(prevLog[exerciseId] || {}),
            [setId]: log,
        };
        // Check if this exercise log is now effectively empty (only contains non-completed sets)
        const isEmpty = Object.values(newExerciseLog).every(l => !l.isCompleted);
        
        if (isEmpty) {
             // Remove the exercise entry entirely if all its sets are marked incomplete
            const { [exerciseId]: _, ...restLog } = prevLog;
            return restLog;
        } else {
            // Otherwise, update the exercise log
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
             // Keep the weight if previously logged, but reset reps and mark incomplete
            updatedExerciseLog[setDef.id] = {
                weight: exerciseLog[setDef.id]?.weight, // Keep existing logged weight if any
                reps: '', // Set reps to empty string for placeholder
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
        const effectiveTargetWeight = getUserTargetWeight(exercise.id, exercise.targetWeight);

        return (
          <ExerciseCard
            key={`${exercise.id}-${effectiveTargetWeightsKey}`} // Add key to force re-render on target weight changes
            exercise={exercise}
            effectiveTargetWeight={effectiveTargetWeight} // Pass down the effective weight
            onLogSet={handleLogSet}
            loggedData={dailyLog[exercise.id]}
            // Removed AI suggestion props
            onUpdateEffectiveTargetWeight={handleUpdateEffectiveTargetWeight}
            triggerRepReset={triggerRepReset} // Pass down the reset function
          />
        );
      })}
    </div>
  );
}
