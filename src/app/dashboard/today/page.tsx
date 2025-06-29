// src/app/dashboard/today/page.tsx
'use client';

import { useState, useEffect, useCallback, useMemo } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { getWorkoutByDay as getWorkoutByDayFromActivePlan } from '@/lib/workout-plan-service';
import { getTodayWorkoutOverride, clearTodayWorkoutOverride } from '@/lib/session-override-service';
import type { WorkoutDay, DailyLog, Exercise as ExerciseType } from '@/types/workout';
import LoadingWorkoutPage from '@/app/workout/[day]/loading';
import { Card, CardContent, CardHeader, CardTitle, CardDescription, CardFooter } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import DayProgress from '@/components/workout/day-progress';
import { useToast } from '@/hooks/use-toast';
import { AlertTriangle, CheckSquare, ArrowRight, RefreshCcw, ShieldAlert } from 'lucide-react';
import { getUserTargetWeight } from '@/lib/user-settings';

const days = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"];

const getCurrentDateString = (): string => {
  return new Date().toISOString().split('T')[0];
};

function getLocalStorageKey(dayId: string, date: string): string {
  return `gymtrack_log_${dayId}_${date}`;
}

const calculateWorkoutProgress = (workoutDay: WorkoutDay | null, dailyLog: DailyLog) => {
  if (!workoutDay) return { completedSets: 0, totalSets: 0, score: 0 };

  let totalSets = 0;
  let completedSets = 0;

  workoutDay.exercises.forEach(exercise => {
    const exerciseLog = dailyLog[exercise.id];
    const isSkipped = exerciseLog && exercise.sets.length > 0 && Object.values(exerciseLog).length >= exercise.sets.length && exercise.sets.every(set => exerciseLog[set.id]?.isCompleted === false);

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
  const [isOverrideActive, setIsOverrideActive] = useState(false);
  const [overrideDayId, setOverrideDayId] = useState<string | null>(null);
  const { toast } = useToast();
  const router = useRouter();

  const loadWorkoutForDisplay = useCallback(() => {
    const date = new Date();
    const scheduledDayId = days[date.getDay()];
    setCurrentDayId(scheduledDayId);

    const overrideId = getTodayWorkoutOverride();
    let dayIdToLoad = scheduledDayId;

    if (overrideId) {
      const overriddenWorkoutDay = getWorkoutByDayFromActivePlan(overrideId);
      if (overriddenWorkoutDay) {
        setWorkoutDay(overriddenWorkoutDay);
        setIsOverrideActive(true);
        setOverrideDayId(overrideId);
        dayIdToLoad = overrideId;
      } else {
        clearTodayWorkoutOverride();
        setIsOverrideActive(false);
        setOverrideDayId(null);
        setWorkoutDay(getWorkoutByDayFromActivePlan(scheduledDayId));
        toast({ variant: "destructive", title: "Override Error", description: "Could not find the overridden workout. Loading scheduled session."});
      }
    } else {
      setIsOverrideActive(false);
      setOverrideDayId(null);
      setWorkoutDay(getWorkoutByDayFromActivePlan(scheduledDayId));
    }
    
    const dateStr = getCurrentDateString();
    setCurrentDate(dateStr);

    if (typeof window !== 'undefined') {
      const activeWorkoutForLog = getWorkoutByDayFromActivePlan(dayIdToLoad);
      if (activeWorkoutForLog) {
        const key = getLocalStorageKey(activeWorkoutForLog.id, dateStr);
        const storedLog = localStorage.getItem(key);
        setDailyLog(storedLog ? JSON.parse(storedLog) : {});
      } else {
         setDailyLog({});
      }
    }
  }, [toast]);

  useEffect(() => {
    setIsClient(true);
    loadWorkoutForDisplay();
  }, [loadWorkoutForDisplay]);

  useEffect(() => {
    if (typeof window !== 'undefined' && workoutDay && currentDate) {
      const key = getLocalStorageKey(workoutDay.id, currentDate);
      const storedLog = localStorage.getItem(key);
      const currentLog = storedLog ? JSON.parse(storedLog) : {};
      if (JSON.stringify(currentLog) !== JSON.stringify(dailyLog)) {
          setDailyLog(currentLog);
      }
    }
  }, [workoutDay, currentDate, dailyLog]);

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

  const handleClearOverride = () => {
    clearTodayWorkoutOverride();
    setIsOverrideActive(false);
    setOverrideDayId(null);
    loadWorkoutForDisplay();
    toast({ title: "Override Cleared", description: "Now showing your regularly scheduled workout."});
  };

  if (!isClient || workoutDay === undefined) {
    return <LoadingWorkoutPage />;
  }
  
  if (!workoutDay) {
    return (
      <div className="container mx-auto px-4 py-8">
        <Card className="border-destructive">
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-destructive">
              <AlertTriangle />
              {isOverrideActive && overrideDayId ? `Overridden Workout Not Found` : `Workout Not Found for Today`}
            </CardTitle>
          </CardHeader>
          <CardContent>
            <p>
              {isOverrideActive && overrideDayId
                ? `Could not find the overridden workout (ID: ${overrideDayId}). Try clearing the override.`
                : `No workout plan found for ${currentDayId || 'today'} in the active plan. Enjoy your rest day or check your plan!`}
            </p>
            {isOverrideActive && (
              <Button onClick={handleClearOverride} variant="outline" className="mt-4 mr-2">
                <RefreshCcw className="mr-2 h-4 w-4" /> Clear Override
              </Button>
            )}
            <Button asChild variant="link" className="mt-4">
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
      {isOverrideActive && (
        <Card className="mb-6 bg-accent/20 border-accent shadow-md">
          <CardHeader className="flex-row items-center justify-between pb-3 pt-3">
            <div className="flex items-center gap-2">
              <ShieldAlert className="h-5 w-5 text-accent-foreground" />
              <CardTitle className="text-base text-accent-foreground">Session Override Active</CardTitle>
            </div>
            <Button variant="ghost" size="sm" onClick={handleClearOverride} className="text-accent-foreground hover:bg-accent/30">
              <RefreshCcw className="mr-1.5 h-4 w-4" /> Revert to Scheduled
            </Button>
          </CardHeader>
        </Card>
      )}

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
          const isSkipped = exerciseLog && exercise.sets.length > 0 && Object.values(exerciseLog).length >= exercise.sets.length && exercise.sets.every(set => exerciseLog[set.id]?.isCompleted === false);

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
