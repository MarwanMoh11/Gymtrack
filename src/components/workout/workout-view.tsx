// src/components/workout/workout-view.tsx
'use client';

import { useState, useEffect, useCallback, useMemo } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useAuth } from '@/context/auth-context';
import { getAllUserWorkoutPlans } from '@/lib/firestore-workout-plan-service';
import { getDailyLog, deleteDailyLog } from '@/lib/firestore-log-service';
import { getTodayWorkoutOverride, clearTodayWorkoutOverride as clearOverrideService } from '@/lib/firestore-settings-service';
import type { WorkoutDay, DailyLog, Exercise as ExerciseType } from '@/types/workout';
import LoadingWorkoutPage from '@/app/workout/[day]/loading';
import { Card, CardContent, CardHeader, CardTitle, CardDescription, CardFooter } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import DayProgress from '@/components/workout/day-progress';
import { useToast } from '@/hooks/use-toast';
import { AlertTriangle, CheckSquare, ArrowRight, RefreshCcw, ShieldAlert, Dumbbell } from 'lucide-react';
import { getTargetWeightOverrides } from '@/lib/firestore-settings-service';

const days = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"];

const getCurrentDateString = (): string => {
  return new Date().toISOString().split('T')[0];
};

const calculateWorkoutProgress = (workoutDay: WorkoutDay | null, dailyLog: DailyLog) => {
  if (!workoutDay) return { completedSets: 0, totalSets: 0, score: 0 };
  let totalSets = 0;
  let completedSets = 0;
  workoutDay.exercises.forEach(exercise => {
    const exerciseLog = dailyLog[exercise.id];
    const isSkipped = exerciseLog && exercise.sets.length > 0 && Object.values(exerciseLog).length >= exercise.sets.length && exercise.sets.every(set => set.isCompleted === false);
    if (!isSkipped) {
      exercise.sets.forEach(() => { totalSets++; });
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

interface WorkoutViewProps {
  dayId: string | null; // Use null for "Today's Session"
}

export default function WorkoutView({ dayId: dayIdFromProps }: WorkoutViewProps) {
  console.log('[WorkoutView] Component rendering...');
  const { user } = useAuth();
  const queryClient = useQueryClient();
  const { toast } = useToast();
  const router = useRouter();

  const [workoutDay, setWorkoutDay] = useState<WorkoutDay | null | undefined>(undefined);
  const [currentDate, setCurrentDate] = useState('');
  const [isOverrideActive, setIsOverrideActive] = useState(false);
  
  const { data: allPlans, isLoading: isLoadingPlans } = useQuery({
    queryKey: ['workoutPlans', user?.uid], // Re-fetch if user changes
    queryFn: () => {
      console.log('[WorkoutView] Querying for workout plans.');
      return getAllUserWorkoutPlans();
    },
    enabled: !!user,
  });
  
  const { data: weightOverrides, isLoading: isLoadingOverrides } = useQuery({
    queryKey: ['weightOverrides', user?.uid],
    queryFn: () => getTargetWeightOverrides(user!.uid),
    enabled: !!user,
  });

  const { data: overrideIdFromDB, isLoading: isLoadingOverrideId } = useQuery({
      queryKey: ['todayOverride', user?.uid],
      queryFn: () => {
        console.log('[WorkoutView] Querying for today\'s override.');
        return getTodayWorkoutOverride(user!.uid);
      },
      enabled: !!user && dayIdFromProps === null,
  });
  
  useEffect(() => {
    const dateStr = getCurrentDateString();
    console.log(`[WorkoutView] Setting current date: ${dateStr}`);
    setCurrentDate(dateStr);
  }, []);

  const { data: dailyLog, isLoading: isLoadingLog } = useQuery({
      queryKey: ['dailyLog', user?.uid, currentDate],
      queryFn: () => {
        console.log(`[WorkoutView] Querying for daily log for date: ${currentDate}`);
        return getDailyLog(user!.uid, currentDate);
      },
      enabled: !!user && !!currentDate && (dayIdFromProps === null),
      initialData: {},
  });

  const loadWorkoutForDisplay = useCallback(() => {
    console.log('[WorkoutView] Running loadWorkoutForDisplay...');
    if (!allPlans) {
        console.log('[WorkoutView] No plans loaded yet, exiting loadWorkoutForDisplay.');
        setWorkoutDay(undefined); // Explicitly set to loading state
        return;
    }

    const date = new Date();
    const activePlan = allPlans.find(p => p.isActive);

    if (!activePlan) {
      console.log('[WorkoutView] No active plan found. Setting workoutDay to null (no workout scheduled).');
      setWorkoutDay(null);
      return;
    }
    
    let dayToSet: WorkoutDay | undefined | null = null;
    
    if (dayIdFromProps === null) { // "Today's Session" page
      const finalOverrideId = overrideIdFromDB || null;
      console.log(`[WorkoutView] Today's session. Override ID from DB: ${finalOverrideId}`);
      setIsOverrideActive(!!finalOverrideId);
      if (finalOverrideId) {
        dayToSet = activePlan.plan.find(d => d.id === finalOverrideId);
        console.log(`[WorkoutView] Found overridden day:`, dayToSet?.dayName);
      } else {
        const todayNumeric = date.getDay();
        console.log(`[WorkoutView] No override. Today is numeric day ${todayNumeric}.`);
        dayToSet = activePlan.plan.find(d => d.mapsToActualDayOfWeek === todayNumeric);
        console.log(`[WorkoutView] Found scheduled day:`, dayToSet?.dayName);
      }
    } else { // Specific [day] page
        console.log(`[WorkoutView] Specific day page for dayId: ${dayIdFromProps}`);
        dayToSet = activePlan.plan.find(d => d.id === dayIdFromProps);
        setIsOverrideActive(false);
    }
    console.log('[WorkoutView] Setting workout day state to:', dayToSet?.dayName || 'null');
    setWorkoutDay(dayToSet || null);
  }, [allPlans, overrideIdFromDB, dayIdFromProps]);
  
  useEffect(() => {
    console.log('[WorkoutView] EFFECT triggered. Deps:', {allPlans, isLoadingPlans, isLoadingOverrideId});
    if(!isLoadingPlans && !isLoadingOverrideId) {
      console.log('[WorkoutView] EFFECT: Plans and override have loaded. Calling loadWorkoutForDisplay.');
      loadWorkoutForDisplay();
    }
  }, [allPlans, isLoadingPlans, isLoadingOverrideId, loadWorkoutForDisplay]);


  const clearLogMutation = useMutation({
    mutationFn: () => {
        if (!user || !currentDate) throw new Error("User or date not available");
        return deleteDailyLog(user.uid, currentDate)
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['dailyLog', user?.uid, currentDate] });
      toast({ title: "Log Cleared", description: `Log for ${workoutDay?.dayName} (${currentDate}) has been cleared.` });
    },
    onError: () => {
      toast({ variant: 'destructive', title: "Error", description: "Could not clear the log." });
    },
  });

  const clearOverrideMutation = useMutation({
    mutationFn: () => {
        if (!user) throw new Error("User not authenticated.");
        return clearOverrideService(user.uid);
    },
    onSuccess: () => {
        queryClient.invalidateQueries({ queryKey: ['todayOverride', user?.uid]});
        setIsOverrideActive(false);
        toast({ title: "Override Cleared", description: "Now showing your regularly scheduled workout."});
    }
  });
  
  const { completedSets, totalSets, score } = useMemo(
    () => (dayIdFromProps === null) ? calculateWorkoutProgress(workoutDay, dailyLog || {}) : { completedSets: 0, totalSets: 0, score: 0},
    [workoutDay, dailyLog, dayIdFromProps]
  );
  
  const isLoading = workoutDay === undefined || isLoadingPlans || isLoadingLog || isLoadingOverrides || (dayIdFromProps === null && isLoadingOverrideId);
  console.log('[WorkoutView] RENDER check. Final isLoading state:', isLoading);
  console.table({
      workoutDayIsUndefined: workoutDay === undefined,
      isLoadingPlans, 
      isLoadingLog,
      isLoadingOverrides,
      isLoadingOverrideId: (dayIdFromProps === null) ? isLoadingOverrideId : 'N/A'
  });

  if (isLoading) {
    console.log('[WorkoutView] Displaying LoadingWorkoutPage skeleton.');
    return <LoadingWorkoutPage />;
  }
  
  if (!workoutDay) {
    const scheduledDayName = days[new Date().getDay()];
    console.log('[WorkoutView] No workoutDay found. Displaying "Workout Not Found" message.');
    return (
      <div className="container mx-auto px-4 py-8">
        <Card className="border-destructive">
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-destructive">
              <AlertTriangle />
              {isOverrideActive ? `Overridden Workout Not Found` : `No Workout For Today`}
            </CardTitle>
          </CardHeader>
          <CardContent>
            <p>
              {isOverrideActive
                ? `Could not find the overridden workout. It might have been deleted from the plan.`
                : `No workout is scheduled for ${dayIdFromProps || scheduledDayName} in your active plan.`}
            </p>
             <p className="mt-2 text-sm text-muted-foreground">
                You can start any workout for today from the "Full Workout Plan" page.
             </p>
            {isOverrideActive && (
              <Button onClick={() => clearOverrideMutation.mutate()} variant="outline" className="mt-4 mr-2">
                <RefreshCcw className="mr-2 h-4 w-4" /> Clear Override
              </Button>
            )}
            <Button asChild variant="default" className="mt-4">
              <Link href="/workout-plan">Go to Workout Plan</Link>
            </Button>
          </CardContent>
        </Card>
      </div>
    );
  }
  
  const isExerciseCompleted = (exercise: ExerciseType): boolean => {
    if (!dailyLog) return false;
    const exerciseLog = dailyLog[exercise.id];
    if (!exerciseLog) return false;
    return exercise.sets.every(set => exerciseLog[set.id]?.isCompleted);
  };

  console.log(`[WorkoutView] Rendering content for workout day: ${workoutDay.dayName}`);
  return (
    <div className="container mx-auto max-w-3xl px-2 sm:px-4 py-8">
       {isOverrideActive && dayIdFromProps === null && (
        <Card className="mb-6 bg-accent/20 border-accent shadow-md">
          <CardHeader className="flex-row items-center justify-between pb-3 pt-3">
            <div className="flex items-center gap-2">
              <ShieldAlert className="h-5 w-5 text-accent-foreground" />
              <CardTitle className="text-base text-accent-foreground">Session Override Active</CardTitle>
            </div>
            <Button variant="ghost" size="sm" onClick={() => clearOverrideMutation.mutate()} className="text-accent-foreground hover:bg-accent/30">
              <RefreshCcw className="mr-1.5 h-4 w-4" /> Revert to Scheduled
            </Button>
          </CardHeader>
        </Card>
      )}

      <Card className="mb-8 bg-card shadow-lg border-none">
        <CardHeader>
          <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-2">
            <div>
              <CardTitle className="text-3xl font-bold text-primary mb-1 flex items-center gap-3">
                <Dumbbell className="h-8 w-8" />
                {workoutDay.dayName}
              </CardTitle>
              <CardDescription className="text-lg text-muted-foreground">{workoutDay.title} - {currentDate}</CardDescription>
            </div>
             {dayIdFromProps === null && (
              <Button variant="outline" onClick={() => clearLogMutation.mutate()} size="sm" className="rounded-full shrink-0">
                Clear Today's Full Log
              </Button>
            )}
          </div>
          {workoutDay.notes && (
            <p className="mt-3 text-sm text-foreground/80 p-3 bg-secondary/50 rounded-md">{workoutDay.notes}</p>
          )}
        </CardHeader>
        {dayIdFromProps === null && (
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
        )}
      </Card>

      <div className="space-y-4">
        <h2 className="text-xl font-semibold text-foreground mb-3">Exercises for Today:</h2>
        {workoutDay.exercises.map((exercise) => {
          const effectiveWeight = weightOverrides?.[exercise.id] ?? exercise.targetWeight;
          const exerciseCompleted = (dayIdFromProps === null) ? isExerciseCompleted(exercise) : false;
          const exerciseLog = dailyLog ? dailyLog[exercise.id] : undefined;
          const isSkipped = dayIdFromProps === null && exerciseLog && exercise.sets.length > 0 && Object.values(exerciseLog).length >= exercise.sets.length && exercise.sets.every(set => set.isCompleted === false);

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
