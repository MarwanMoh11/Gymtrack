
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
import { CheckSquare, TrendingUp } from 'lucide-react';

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
    totalSets += exercise.sets.length;
    const exerciseLog = dailyLog[exercise.id];
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
      setIsInitialized(true);
    } else {
        setIsInitialized(true);
    }
  }, [workoutDay.id]);

  // Save log to localStorage whenever it changes
  useEffect(() => {
    if (isInitialized && typeof window !== 'undefined' && currentDate) {
      const key = getLocalStorageKey(workoutDay.id, currentDate);
      if (Object.keys(dailyLog).length > 0) {
        localStorage.setItem(key, JSON.stringify(dailyLog));
      } else {
        if (localStorage.getItem(key)) {
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
        const isEmpty = Object.values(newExerciseLog).every(l => !l.isCompleted);

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

  const handleClearDayLog = useCallback(() => {
    setDailyLog({});
    toast({
      title: "Log Cleared",
      description: `Log for ${workoutDay.dayName} (${currentDate}) has been cleared.`,
    });
    setEffectiveTargetWeightsKey(prev => prev + 1);
  }, [workoutDay.dayName, currentDate, toast]);

  const handleUpdateEffectiveTargetWeight = useCallback((exerciseId: string, newWeight: string) => {
    const exerciseName = workoutDay.exercises.find(e => e.id === exerciseId)?.name || 'exercise';
    setTargetWeightOverride(exerciseId, newWeight);
    setEffectiveTargetWeightsKey(prev => prev + 1);
    toast({
      title: "Plan Updated",
      description: `Target weight for ${exerciseName} updated to ${newWeight}.`,
    });
  }, [toast, workoutDay.exercises]);

  const triggerRepReset = useCallback((exerciseId: string) => {
    setDailyLog(prevLog => {
        const exerciseLog = prevLog[exerciseId];
        if (!exerciseLog) return prevLog;

        const updatedExerciseLog: LoggedExerciseData = {};
        const exerciseDefinition = workoutDay.exercises.find(e => e.id === exerciseId);

        exerciseDefinition?.sets.forEach(setDef => {
            updatedExerciseLog[setDef.id] = {
                weight: exerciseLog[setDef.id]?.weight,
                reps: '',
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

  const handleClearExerciseLog = useCallback((exerciseIdToClear: string) => {
    setDailyLog(prevLog => {
      const exerciseLog = prevLog[exerciseIdToClear];
      if (!exerciseLog) return prevLog; // No log to clear for this exercise

      const updatedExerciseLog: LoggedExerciseData = {};
      const exerciseDefinition = workoutDay.exercises.find(e => e.id === exerciseIdToClear);

      exerciseDefinition?.sets.forEach(setDef => {
        // Keep existing logged weight/reps but mark as incomplete
        updatedExerciseLog[setDef.id] = {
          reps: exerciseLog[setDef.id]?.reps || '', // Keep reps if they were entered
          weight: exerciseLog[setDef.id]?.weight, // Keep weight
          isCompleted: false // Mark as not completed
        };
      });
      
      // Check if the exercise log is now effectively empty (all sets incomplete and no actual data)
      // This logic might need refinement based on how "empty" is defined
      const isNowEffectivelyEmpty = Object.values(updatedExerciseLog).every(
        log => !log.isCompleted && (log.reps === '' || log.reps === undefined)
      );

      if (isNowEffectivelyEmpty) {
        // If clearing made it empty, remove the exercise entry from the daily log
        const { [exerciseIdToClear]: _, ...restLog } = prevLog;
        return restLog;
      } else {
        // Otherwise, update the exercise log with all sets marked incomplete
        return {
          ...prevLog,
          [exerciseIdToClear]: updatedExerciseLog,
        };
      }
    });
    toast({
      variant: "default",
      title: "Exercise Progress Cleared",
      description: `Progress for ${workoutDay.exercises.find(e => e.id === exerciseIdToClear)?.name || 'exercise'} has been cleared for today. You can log it again if needed.`,
    });
  }, [workoutDay.exercises, toast]);


  const { completedSets, totalSets, score } = useMemo(
    () => calculateWorkoutProgress(workoutDay, dailyLog),
    [workoutDay, dailyLog]
  );

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
        return (
          <ExerciseCard
            key={`${exercise.id}-${effectiveTargetWeightsKey}`}
            exercise={exercise}
            effectiveTargetWeight={effectiveTargetWeight}
            onLogSet={handleLogSet}
            loggedData={dailyLog[exercise.id]}
            onUpdateEffectiveTargetWeight={handleUpdateEffectiveTargetWeight}
            triggerRepReset={triggerRepReset}
            onClearExerciseLog={handleClearExerciseLog}
          />
        );
      })}
    </div>
  );
}
