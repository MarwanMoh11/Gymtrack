
// src/components/workout/workout-view.tsx
// This component is being phased out for the main /dashboard/today view.
// Its core logic is moving to /dashboard/today/page.tsx and /exercises/[exerciseId]/page.tsx.
// For now, it can remain for the /workout/[day] pages, but those will be inconsistent
// with the new logging flow until they are also updated.

'use client';

import { useState, useEffect, useCallback } from 'react';
import Link from 'next/link'; // Added import for Link
import type { WorkoutDay, DailyLog, LoggedSetData, Exercise } from '@/types/workout';
// ExerciseCard is no longer used here for the primary logging view.
// import ExerciseCard from './exercise-card'; 
import DayProgress from './day-progress';
import { Button } from '@/components/ui/button';
import { useToast } from '@/hooks/use-toast';
import { Card, CardDescription, CardHeader, CardTitle, CardFooter } from '../ui/card';
// Target weight logic might still be relevant if this page is kept for other days.
// import { getUserTargetWeight, setTargetWeightOverride } from '@/lib/user-settings';
import LoadingWorkoutPage from '@/app/workout/[day]/loading';
import { CheckSquare, AlertTriangle, ArrowRight } from 'lucide-react'; // Added ArrowRight

interface WorkoutViewProps {
  workoutDay: WorkoutDay;
}

const getCurrentDateString = (): string => {
  return new Date().toISOString().split('T')[0];
};

function getLocalStorageKey(dayId: string, date: string): string {
  return `gymtrack_log_${dayId}_${date}`;
}

// Simplified progress calculation, as detailed logging is elsewhere
const calculateWorkoutProgress = (workoutDay: WorkoutDay, dailyLog: DailyLog) => {
  let totalSets = 0;
  let completedSets = 0;

  workoutDay.exercises.forEach(exercise => {
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
  // const [effectiveTargetWeightsKey, setEffectiveTargetWeightsKey] = useState(0); 
  const { toast } = useToast();

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

  // This component no longer directly handles logging sets. 
  // It only displays progress based on localStorage.

  const handleClearDayLog = useCallback(() => {
    setDailyLog({});
    if (typeof window !== 'undefined') {
        localStorage.removeItem(getLocalStorageKey(workoutDay.id, currentDate));
    }
    toast({
      title: "Log Cleared",
      description: `Log for ${workoutDay.dayName} (${currentDate}) has been cleared.`,
    });
    // setEffectiveTargetWeightsKey(prev => prev + 1);
  }, [workoutDay.id, workoutDay.dayName, currentDate, toast]);
  
  const { completedSets, totalSets, score } = calculateWorkoutProgress(workoutDay, dailyLog);

  if (!isInitialized) {
    return <LoadingWorkoutPage />;
  }
  
  const isExerciseCompleted = (exercise: Exercise): boolean => {
    const exerciseLog = dailyLog[exercise.id];
    if (!exerciseLog) return false;
    return exercise.sets.every(set => exerciseLog[set.id]?.isCompleted);
  };


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
              Clear Full Log
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

       <div className="space-y-4">
        <h2 className="text-xl font-semibold text-foreground mb-3">Exercises for {workoutDay.dayName}:</h2>
        {workoutDay.exercises.map((exercise) => {
           const exerciseCompleted = isExerciseCompleted(exercise);
           const exerciseLog = dailyLog[exercise.id];
           const isSkipped = exerciseLog && exercise.sets.length > 0 && exercise.sets.every(set => exerciseLog[set.id]?.isCompleted === false);

          return (
            <Card key={exercise.id} className="shadow-md hover:shadow-lg transition-shadow duration-300">
              <CardHeader className="flex flex-row justify-between items-center pb-3">
                <div>
                  <CardTitle className="text-lg font-semibold text-foreground">{exercise.name}</CardTitle>
                  <CardDescription className="text-xs text-muted-foreground">
                    {exercise.sets.length} sets
                    {exercise.targetWeight && ` | Plan: ${exercise.targetWeight}`}
                  </CardDescription>
                </div>
                <div className="flex items-center gap-2">
                    {isSkipped && (
                        <span className="text-xs text-destructive font-medium">(Skipped)</span>
                    )}
                    {exerciseCompleted && !isSkipped && (
                        <CheckSquare className="h-5 w-5 text-primary" />
                    )}
                    <Button asChild variant="ghost" size="sm">
                        {/* Link to the exercise detail page, passing the current workoutDay.id */}
                        <Link href={`/exercises/${exercise.id}?dayId=${workoutDay.id}`}>
                            Log / View <ArrowRight className="ml-2 h-4 w-4" />
                        </Link>
                    </Button>
                </div>
              </CardHeader>
              {exercise.notes && (
                <CardContent className="pb-3 pt-0">
                    <p className="text-xs italic text-muted-foreground bg-secondary/30 p-2 rounded-md">{exercise.notes}</p>
                </CardContent>
              )}
            </Card>
          );
        })}
      </div>
    </div>
  );
}
    