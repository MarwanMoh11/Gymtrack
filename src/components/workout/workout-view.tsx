
'use client';

import { useState, useEffect, useCallback, useMemo } from 'react';
import type { WorkoutDay, DailyLog, LoggedSetData, Exercise, LoggedExerciseData } from '@/types/workout';
import ExerciseCard from './exercise-card';
import DayProgress from './day-progress';
import { Button } from '@/components/ui/button';
import { useToast } from '@/hooks/use-toast';
import { Card, CardDescription, CardHeader, CardTitle, CardFooter } from '../ui/card';
import { getUserTargetWeight, setTargetWeightOverride } from '@/lib/user-settings';
import LoadingWorkoutPage from '@/app/workout/[day]/loading';
import { CheckSquare } from 'lucide-react';

interface WorkoutViewProps {
  workoutDay: WorkoutDay;
}

const getCurrentDateString = (): string => {
  return new Date().toISOString().split('T')[0];
};

function getLocalStorageKey(dayId: string, date: string): string {
  return `gymtrack_log_${dayId}_${date}`;
}

// Helper function to calculate progress, moved outside for reusability if needed
const calculateWorkoutProgress = (workoutDay: WorkoutDay, dailyLog: DailyLog) => {
  let totalSets = 0;
  let completedSets = 0;

  workoutDay.exercises.forEach(exercise => {
    // Only count sets for exercises that are not considered "skipped" for totalSets
    const exerciseLog = dailyLog[exercise.id];
    const isSkipped = exerciseLog && exercise.sets.length > 0 && exercise.sets.every(set => exerciseLog[set.id]?.isCompleted === false);

    if (!isSkipped) {
        exercise.sets.forEach(() => {
            totalSets++;
        });
    }
    
    if (exerciseLog) {
      exercise.sets.forEach(set => {
        if (exerciseLog[set.id]?.isCompleted) {
          completedSets++;
        }
      });
    }
  });
  const score = totalSets > 0 ? Math.round((completedSets / totalSets) * 100) : 0;
  return { completedSets, totalSets, score };
};


export default function WorkoutView({ workoutDay }: WorkoutViewProps) {
  const [dailyLog, setDailyLog] = useState<DailyLog>({});
  const [isInitialized, setIsInitialized] = useState(false);
  const [currentDate, setCurrentDate] = useState('');
  const [effectiveTargetWeightsKey, setEffectiveTargetWeightsKey] = useState(0); // Used to force re-render ExerciseCards
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
          localStorage.removeItem(key); // Clear corrupted data
          setDailyLog({});
        }
      } else {
        setDailyLog({}); // No log for today yet
      }
      setIsInitialized(true);
    } else {
        // Handle server-side or environment where localStorage is not available
        setIsInitialized(true); // Still need to set this true to allow rendering
    }
  }, [workoutDay.id]); // Only re-run if workoutDay.id changes (e.g., navigating to a different day's plan)

  // Save log to localStorage whenever it changes
  useEffect(() => {
    if (isInitialized && typeof window !== 'undefined' && currentDate) {
      const key = getLocalStorageKey(workoutDay.id, currentDate);
      if (Object.keys(dailyLog).length > 0) {
        localStorage.setItem(key, JSON.stringify(dailyLog));
      } else {
        // If dailyLog becomes empty, remove its key from localStorage
        if (localStorage.getItem(key)) { // Check if it exists before removing
            localStorage.removeItem(key);
        }
      }
    }
  }, [dailyLog, workoutDay.id, isInitialized, currentDate]);


  const handleLogSet = useCallback((exerciseId: string, setId: string, log: LoggedSetData) => {
    setDailyLog(prevLog => {
        const newExerciseLog = {
            ...(prevLog[exerciseId] || {}),
            [setId]: log,
        };
        // Check if all sets for this exercise are now marked as not completed
        const exerciseDef = workoutDay.exercises.find(e => e.id === exerciseId);
        const allDefinedSetsMarkedNotCompleted = exerciseDef?.sets.every(setDef => newExerciseLog[setDef.id]?.isCompleted === false);

        if (exerciseDef && exerciseDef.sets.length > 0 && allDefinedSetsMarkedNotCompleted) {
            // If all defined sets are marked incomplete, keep the exercise log (as it represents a "skipped" state)
            return {
                ...prevLog,
                [exerciseId]: newExerciseLog,
            };
        } else if (Object.values(newExerciseLog).every(l => !l.isCompleted && (l.reps === '' || l.reps === undefined ))) {
             // If all logged sets are incomplete AND have no reps (i.e. cleared/reset)
            const { [exerciseId]: _, ...restLog } = prevLog;
            return restLog;
        }
        else {
            return {
                ...prevLog,
                [exerciseId]: newExerciseLog,
            };
        }
    });
  }, [workoutDay.exercises]);

  const handleClearDayLog = useCallback(() => {
    setDailyLog({});
    toast({
      title: "Log Cleared",
      description: `Log for ${workoutDay.dayName} (${currentDate}) has been cleared.`,
    });
    // Force re-render of ExerciseCards so their internal states (like isEditingTarget) can reset
    setEffectiveTargetWeightsKey(prev => prev + 1);
  }, [workoutDay.dayName, currentDate, toast]);

  const handleUpdateEffectiveTargetWeight = useCallback((exerciseId: string, newWeight: string) => {
    const exerciseName = workoutDay.exercises.find(e => e.id === exerciseId)?.name || 'exercise';
    setTargetWeightOverride(exerciseId, newWeight);
    setEffectiveTargetWeightsKey(prev => prev + 1); // Force re-render to reflect new effective weight
    toast({
      title: "Plan Updated",
      description: `Target weight for ${exerciseName} updated to ${newWeight}. Reps for this exercise have been reset.`,
    });
  }, [toast, workoutDay.exercises]);

  // Callback to reset reps for a specific exercise (e.g., when weight changes)
  const triggerRepReset = useCallback((exerciseId: string) => {
    setDailyLog(prevLog => {
        const exerciseLog = prevLog[exerciseId];
        if (!exerciseLog) return prevLog; // No log for this exercise to reset

        const updatedExerciseLog: LoggedExerciseData = {};
        const exerciseDefinition = workoutDay.exercises.find(e => e.id === exerciseId);

        exerciseDefinition?.sets.forEach(setDef => {
            // Keep the existing weight from the log if available, otherwise from plan
            // Reset reps and mark as incomplete
            updatedExerciseLog[setDef.id] = {
                weight: exerciseLog[setDef.id]?.weight, // Keep previously logged/derived weight for the set
                reps: '', // Reset reps
                isCompleted: false // Mark as not completed
            };
        });

        return {
            ...prevLog,
            [exerciseId]: updatedExerciseLog,
        };
    });
     // Toast message is now handled in onUpdateEffectiveTargetWeight for better context
  }, [workoutDay.exercises]);

  const handleSkipExercise = useCallback((exerciseIdToSkip: string) => {
    setDailyLog(prevLog => {
      const exerciseDefinition = workoutDay.exercises.find(e => e.id === exerciseIdToSkip);
      if (!exerciseDefinition || exerciseDefinition.sets.length === 0) return prevLog; // Cannot skip exercises without sets

      const updatedExerciseLog: LoggedExerciseData = { ...(prevLog[exerciseIdToSkip] || {}) };

      exerciseDefinition.sets.forEach(setDef => {
        updatedExerciseLog[setDef.id] = {
          reps: prevLog[exerciseIdToSkip]?.[setDef.id]?.reps || '', // Keep reps if they were entered
          weight: prevLog[exerciseIdToSkip]?.[setDef.id]?.weight, // Keep weight
          isCompleted: false // Mark as not completed
        };
      });
      
      return {
          ...prevLog,
          [exerciseIdToSkip]: updatedExerciseLog,
      };
    });
    toast({
      variant: "default",
      title: "Exercise Skipped",
      description: `"${workoutDay.exercises.find(e => e.id === exerciseIdToSkip)?.name || 'Exercise'}" has been marked as skipped for today. Your workout score will be affected.`,
    });
  }, [workoutDay.exercises, toast]);

  const handleUnskipExercise = useCallback((exerciseIdToUnskip: string) => {
    setDailyLog(prevLog => {
      const { [exerciseIdToUnskip]: _, ...restLog } = prevLog;
      return restLog;
    });
    setEffectiveTargetWeightsKey(prev => prev + 1); // Force re-render of ExerciseCards
    toast({
      title: "Exercise Unskipped",
      description: `"${workoutDay.exercises.find(e => e.id === exerciseIdToUnskip)?.name || 'Exercise'}" is no longer skipped. You can now log sets.`,
    });
  }, [workoutDay.exercises, toast]);


  const { completedSets, totalSets, score } = useMemo(
    () => calculateWorkoutProgress(workoutDay, dailyLog),
    [workoutDay, dailyLog]
  );

  if (!isInitialized) {
    // Ensure LoadingWorkoutPage is a valid component or provide a fallback
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
              Clear Today's Full Log
            </Button>
          </div>
          {workoutDay.notes && (
            <p className="mt-3 text-sm text-foreground/80 p-3 bg-secondary/50 rounded-md">{workoutDay.notes}</p>
          )}
        </CardHeader>
        <CardFooter className="flex flex-col sm:flex-row justify-between items-center pt-3 pb-4 px-6 gap-4">
             <div className="w-full sm:w-auto">
                <h3 className="text-sm font-medium text-muted-foreground flex items-center">
                    <CheckSquare className="h-4 w-4 mr-1.5 text-primary/80" />
                    Session Score
                </h3>
                <p className="text-2xl font-bold text-primary">{score}%</p>
                <p className="text-xs text-muted-foreground">{completedSets} of {totalSets} sets completed</p>
             </div>
             <div className="w-full sm:w-auto flex-grow max-w-xs">
                 <DayProgress completedSets={completedSets} totalSets={totalSets} />
             </div>
        </CardFooter>
      </Card>

      {workoutDay.exercises.map((exercise: Exercise) => {
        const effectiveTargetWeight = getUserTargetWeight(exercise.id, exercise.targetWeight);
        const exerciseLog = dailyLog[exercise.id];
        const isSkipped = exerciseLog && 
                          exercise.sets.length > 0 && 
                          exercise.sets.every(set => exerciseLog[set.id]?.isCompleted === false);
        
        return (
          <ExerciseCard
            key={`${exercise.id}-${effectiveTargetWeightsKey}`} 
            exercise={exercise}
            effectiveTargetWeight={effectiveTargetWeight}
            onLogSet={handleLogSet}
            loggedData={dailyLog[exercise.id]}
            onUpdateEffectiveTargetWeight={handleUpdateEffectiveTargetWeight}
            triggerRepReset={triggerRepReset}
            onSkipExercise={handleSkipExercise}
            onUnskipExercise={handleUnskipExercise}
            isSkipped={isSkipped}
          />
        );
      })}
    </div>
  );
}

