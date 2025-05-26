
// src/app/dashboard/today/page.tsx
'use client';

import { useState, useEffect, useCallback, useMemo } from 'react';
import Link from 'next/link';
import { getWorkoutByDay as getWorkoutByDayFromActivePlan, getActiveWorkoutPlan } from '@/lib/workout-plan-service'; // Updated import
import type { WorkoutDay, DailyLog, Exercise as ExerciseType } from '@/types/workout';
import LoadingWorkoutPage from '@/app/workout/[day]/loading'; 
import { Card, CardContent, CardHeader, CardTitle, CardDescription, CardFooter } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import DayProgress from '@/components/workout/day-progress';
import { useToast } from '@/hooks/use-toast';
import { AlertTriangle, CheckSquare, ArrowRight, Info } from 'lucide-react';
import { getUserTargetWeight } from '@/lib/user-settings'; 

const days = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"];

const getCurrentDateString = (): string => {
  return new Date().toISOString().split('T')[0];
};

function getLocalStorageKey(dayId: string, date: string): string {
  // Append active plan ID to localStorage key to separate logs for different plans
  // This part needs activePlanId to be available. For now, assuming a simpler key or needs rework if planId is part of key.
  // For simplicity, let's assume dayId and date is enough if logs are not plan-specific or active plan is global for logs.
  // If logs MUST be plan-specific, this key generation needs active plan context.
  // const activePlan = getActiveNamedWorkoutPlan(); // This might be too much for a simple key function
  // const planPrefix = activePlan ? `${activePlan.id}_` : '';
  return `gymtrack_log_${dayId}_${date}`;
}

const calculateWorkoutProgress = (workoutDay: WorkoutDay | null, dailyLog: DailyLog) => {
  if (!workoutDay) return { completedSets: 0, totalSets: 0, score: 0 };

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


export default function TodaysWorkoutDashboardPage() {
  const [workoutDay, setWorkoutDay] = useState<WorkoutDay | null | undefined>(undefined);
  const [currentDayId, setCurrentDayId] = useState<string | null>(null);
  const [dailyLog, setDailyLog] = useState<DailyLog>({});
  const [isClient, setIsClient] = useState(false);
  const [currentDate, setCurrentDate] = useState('');
  const { toast } = useToast();

  useEffect(() => {
    setIsClient(true);
    const date = new Date();
    const dayId = days[date.getDay()];
    setCurrentDayId(dayId);
    
    // Fetch workout day from the *active* plan
    const fetchedWorkoutDay = getWorkoutByDayFromActivePlan(dayId);
    setWorkoutDay(fetchedWorkoutDay);

    const dateStr = getCurrentDateString();
    setCurrentDate(dateStr);

    if (typeof window !== 'undefined' && fetchedWorkoutDay) {
      const key = getLocalStorageKey(fetchedWorkoutDay.id, dateStr); // Key might need active plan ID
      const storedLog = localStorage.getItem(key);
      if (storedLog) {
        try {
          setDailyLog(JSON.parse(storedLog));
        } catch (error) {
          console.error("Failed to parse stored log for today:", error);
          setDailyLog({});
        }
      } else {
        setDailyLog({});
      }
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []); 

  useEffect(() => {
    if (typeof window !== 'undefined' && workoutDay && currentDate) {
      const key = getLocalStorageKey(workoutDay.id, currentDate);
      const storedLog = localStorage.getItem(key);
      if (storedLog) {
        try {
          const parsedLog = JSON.parse(storedLog);
          if (JSON.stringify(parsedLog) !== JSON.stringify(dailyLog)) {
            setDailyLog(parsedLog);
          }
        } catch (error) {
          console.error("Failed to parse stored log on update:", error);
        }
      } else {
        if (Object.keys(dailyLog).length > 0) { 
          setDailyLog({});
        }
      }
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [workoutDay, currentDate]); 


  const handleClearDayLog = useCallback(() => {
    if (!workoutDay || !currentDate) return;
    setDailyLog({});
    if (typeof window !== 'undefined') {
      localStorage.removeItem(getLocalStorageKey(workoutDay.id, currentDate));
    }
    toast({
      title: "Log Cleared",
      description: `Log for ${workoutDay.dayName} (${currentDate}) has been cleared.`,
    });
  }, [workoutDay, currentDate, toast]);
  
  const { completedSets, totalSets, score } = useMemo(
    () => calculateWorkoutProgress(workoutDay, dailyLog),
    [workoutDay, dailyLog]
  );

  if (!isClient || workoutDay === undefined) {
    return <LoadingWorkoutPage />;
  }

  if (!workoutDay) {
    return (
      <div className="container mx-auto px-4 py-8">
        <Card className="border-destructive">
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-destructive">
              <AlertTriangle /> Workout Not Found for Today
            </CardTitle>
          </CardHeader>
          <CardContent>
            <p>No workout plan found for {currentDayId || 'today'} in the active plan. Enjoy your rest day or check your plan!</p>
            <Button asChild variant="link" className="mt-2">
                <Link href="/workout-plan">Manage Workout Plans</Link>
            </Button>
          </CardContent>
        </Card>
      </div>
    );
  }
  
  const isExerciseCompleted = (exercise: ExerciseType): boolean => {
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

      <div className="space-y-4">
        <h2 className="text-xl font-semibold text-foreground mb-3">Exercises for Today:</h2>
        {workoutDay.exercises.map((exercise) => {
          const effectiveWeight = getUserTargetWeight(exercise.id, exercise.targetWeight);
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
                    {effectiveWeight && effectiveWeight !== exercise.targetWeight && ` | Today: ${effectiveWeight}`}
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
