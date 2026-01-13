// src/components/workout/workout-view.tsx
'use client';

import { useState, useEffect, useCallback, useMemo } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useAuth } from '@/context/auth-context';
import { useUser } from '@/context/user-context';
import { getDailyLog, deleteDailyLog } from '@/lib/firestore-log-service';
import { getTodayWorkoutOverride, clearTodayWorkoutOverride as clearOverrideService } from '@/lib/firestore-settings-service';
import type { WorkoutDay, DailyLog, Exercise as ExerciseType, LoggedSetData, SetData, PlanExercise, NamedWorkoutPlan } from '../../types/workout';
import LoadingWorkoutPage from '@/app/workout/[day]/loading';
import { Card, CardContent, CardHeader, CardTitle, CardDescription, CardFooter } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import DayProgress from '@/components/workout/day-progress';
import { useToast } from '@/hooks/use-toast';
import { AlertTriangle, CheckSquare, ArrowRight, RefreshCcw, ShieldAlert, Dumbbell } from 'lucide-react';
import { getTargetWeightOverrides } from '@/lib/firestore-settings-service';
import { cn } from '@/lib/utils';

const days = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"];

const getCurrentDateString = (): string => {
  return new Date().toISOString().split('T')[0];
};

const calculateWorkoutProgress = (workoutDay: WorkoutDay | null, dailyLog: DailyLog) => {
  if (!workoutDay) return { completedSets: 0, totalSets: 0, score: 0 };
  let totalSets = 0;
  let completedSets = 0;
  workoutDay.exercises.forEach((exercise: PlanExercise) => {
    const exerciseLog = dailyLog[exercise.id];
    const isSkipped = exerciseLog && exercise.sets.length > 0 && Object.values(exerciseLog).length >= exercise.sets.length && exercise.sets.every((set: SetData) => (exerciseLog[set.id] as LoggedSetData)?.isCompleted === false);
    if (!isSkipped) {
      exercise.sets.forEach(() => { totalSets++; });
    }
    if (exerciseLog) {
      exercise.sets.forEach((set: SetData) => {
        if ((exerciseLog[set.id] as LoggedSetData)?.isCompleted) {
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
  const { user } = useAuth();
  const queryClient = useQueryClient();
  const { toast } = useToast();
  const router = useRouter();

  const [workoutDay, setWorkoutDay] = useState<WorkoutDay | null | undefined>(undefined);
  const [currentDate, setCurrentDate] = useState('');
  const [isOverrideActive, setIsOverrideActive] = useState(false);

  const { userData, isLoading: isLoadingUserData } = useUser();

  const { data: weightOverrides, isLoading: isLoadingOverrides } = useQuery({
    queryKey: ['weightOverrides', user?.uid],
    queryFn: () => getTargetWeightOverrides(user!.uid),
    enabled: !!user,
  });

  const { data: overrideIdFromDB, isLoading: isLoadingOverrideId } = useQuery({
    queryKey: ['todayOverride', user?.uid],
    queryFn: () => getTodayWorkoutOverride(user!.uid),
    enabled: !!user && dayIdFromProps === null,
  });

  useEffect(() => {
    const dateStr = getCurrentDateString();
    const displayDate = new Date().toLocaleDateString('en-US', { weekday: 'long', month: 'short', day: 'numeric' });
    setCurrentDate(displayDate);
  }, []);

  const loadWorkoutForDisplay = useCallback(() => {
    if (!userData) {
      setWorkoutDay(undefined);
      return;
    }

    const date = new Date();
    const activePlan = userData.plans.find((p: NamedWorkoutPlan) => p.isActive);

    if (!activePlan) {
      setWorkoutDay(null);
      return;
    }

    let dayToSet: WorkoutDay | undefined | null = null;

    if (dayIdFromProps === null) {
      const finalOverrideId = overrideIdFromDB || null;
      setIsOverrideActive(!!finalOverrideId);
      if (finalOverrideId) {
        dayToSet = activePlan.plan.find((d: WorkoutDay) => d.id === finalOverrideId);
      } else {
        const todayNumeric = date.getDay();
        dayToSet = activePlan.plan.find((d: WorkoutDay) => d.mapsToActualDayOfWeek === todayNumeric);
      }
    } else {
      dayToSet = activePlan.plan.find((d: WorkoutDay) => d.id === dayIdFromProps);
      setIsOverrideActive(false);
    }
    setWorkoutDay(dayToSet || null);
  }, [userData, overrideIdFromDB, dayIdFromProps]);

  useEffect(() => {
    if (!isLoadingUserData && !isLoadingOverrideId) {
      loadWorkoutForDisplay();
    }
  }, [isLoadingUserData, isLoadingOverrideId, loadWorkoutForDisplay]);


  const clearLogMutation = useMutation({
    mutationFn: () => {
      const dateStr = new Date().toISOString().split('T')[0];
      if (!user) throw new Error("User not available");
      return deleteDailyLog(user.uid, dateStr)
    },
    onSuccess: () => {
      const dateStr = new Date().toISOString().split('T')[0];
      queryClient.invalidateQueries({ queryKey: ['dailyLog', user?.uid, dateStr] });
      toast({ title: "Session Reset", description: "Your daily log for this session has been cleared." });
    },
    onError: () => {
      toast({ variant: 'destructive', title: "Error", description: "Could not reset the daily session." });
    },
  });

  const clearOverrideMutation = useMutation({
    mutationFn: () => {
      if (!user) throw new Error("User not authenticated.");
      return clearOverrideService(user.uid);
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['todayOverride', user?.uid] });
      setIsOverrideActive(false);
      toast({ title: "Protocol Reverted", description: "Returning to regularly scheduled training." });
    }
  });

  const { data: dailyLog, isLoading: isLoadingLog } = useQuery({
    queryKey: ['dailyLog', user?.uid, new Date().toISOString().split('T')[0]],
    queryFn: () => getDailyLog(user!.uid, new Date().toISOString().split('T')[0]),
    enabled: !!user && (dayIdFromProps === null),
    initialData: {},
  });

  const { completedSets, totalSets, score } = useMemo(
    () => (dayIdFromProps === null) ? calculateWorkoutProgress(workoutDay ?? null, dailyLog || {}) : { completedSets: 0, totalSets: 0, score: 0 },
    [workoutDay, dailyLog, dayIdFromProps]
  );

  const isLoading = workoutDay === undefined || isLoadingUserData || isLoadingLog || isLoadingOverrides || (dayIdFromProps === null && isLoadingOverrideId);

  if (isLoading) {
    return <LoadingWorkoutPage />;
  }

  if (!workoutDay) {
    return (
      <div className="w-full">
        <Card className="glass-panel border-none rounded-[2.5rem] p-12 text-center overflow-hidden relative">
          <div className="relative z-10 flex flex-col items-center">
            <div className="w-20 h-20 rounded-3xl bg-primary/10 flex items-center justify-center mb-8 border border-primary/20 rotate-3 animate-pulse">
              <AlertTriangle className="h-10 w-10 text-primary" />
            </div>
            <CardTitle className="text-3xl font-bold mb-4 font-heading tracking-tight">Active Rest Day</CardTitle>
            <p className="text-muted-foreground mb-8 max-w-sm mx-auto font-medium leading-relaxed">
              No protocol detected for today. Recovery is where the transformation happens.
            </p>
            <div className="flex flex-col sm:flex-row gap-4 w-full justify-center">
              {isOverrideActive && (
                <Button onClick={() => clearOverrideMutation.mutate()} variant="outline" className="h-12 rounded-xl border-white/10 hover:bg-white/5 font-bold uppercase tracking-widest text-[10px]">
                  <RefreshCcw className="mr-2 h-4 w-4" /> Clear Override
                </Button>
              )}
              <Button asChild size="lg" className="h-14 rounded-2xl bg-primary hover:bg-primary/90 font-bold uppercase tracking-widest text-xs px-10 shadow-xl shadow-primary/20 interactive-scale">
                <Link href="/workout-plan">Explore Full Plan</Link>
              </Button>
            </div>
          </div>
          <div className="absolute -bottom-12 -right-12 w-48 h-48 bg-primary/5 rounded-full blur-[80px]" />
        </Card>
      </div>
    );
  }

  const isExerciseCompleted = (exercise: PlanExercise): boolean => {
    if (!dailyLog) return false;
    const exerciseLog = dailyLog[exercise.id];
    if (!exerciseLog) return false;
    return exercise.sets.every((set: SetData) => (exerciseLog[set.id] as any)?.isCompleted);
  };

  return (
    <div className="w-full space-y-10 animate-in fade-in slide-in-from-bottom-4 duration-700">
      {isOverrideActive && dayIdFromProps === null && (
        <div className="p-4 rounded-2xl bg-primary/10 border border-primary/20 flex items-center justify-between group animate-in slide-in-from-top-4 duration-500">
          <div className="flex items-center gap-3">
            <ShieldAlert className="h-5 w-5 text-primary" />
            <span className="text-[10px] font-bold uppercase tracking-widest text-primary/80">Manual Override Active</span>
          </div>
          <Button variant="ghost" size="sm" onClick={() => clearOverrideMutation.mutate()} className="h-8 rounded-lg text-primary hover:bg-primary/20 text-[9px] font-bold uppercase tracking-tighter">
            <RefreshCcw className="mr-1.5 h-3 w-3" /> Revert
          </Button>
        </div>
      )}

      {/* Main Focus Card */}
      <div className="relative overflow-hidden rounded-[2.5Rem] glass-panel border-none p-8 md:p-10 shadow-2xl group animate-in zoom-in-98 duration-1000">
        <div className="relative z-10 flex flex-col md:flex-row md:items-end justify-between gap-8">
          <div className="space-y-4">
            <div className="flex items-center gap-3">
              <div className="w-12 h-12 rounded-2xl bg-primary flex items-center justify-center border border-primary shadow-lg shadow-primary/20 -rotate-3 group-hover:rotate-0 transition-transform duration-500">
                <Dumbbell className="h-6 w-6 text-background" />
              </div>
              <div>
                <h2 className="text-3xl md:text-4xl font-bold tracking-tight font-heading">{workoutDay.dayName}</h2>
                <p className="text-primary font-bold uppercase tracking-[0.2em] text-[10px] opacity-80">{currentDate}</p>
              </div>
            </div>
            <p className="text-muted-foreground text-xl md:text-2xl font-medium max-w-md leading-tight">
              {workoutDay.title}
            </p>
            {workoutDay.notes && (
              <div className="inline-block p-4 rounded-2xl bg-white/5 border border-white/5 text-sm font-medium text-foreground/80 max-w-sm italic">
                {workoutDay.notes}
              </div>
            )}
          </div>

          {dayIdFromProps === null && (
            <div className="flex flex-col items-center md:items-end gap-3 min-w-[200px]">
              <div className="flex items-baseline gap-1">
                <span className="text-5xl font-bold tracking-tighter text-primary">{score}</span>
                <span className="text-sm font-bold opacity-30">%</span>
              </div>
              <div className="w-full h-2 bg-white/5 rounded-full overflow-hidden border border-white/5">
                <div
                  className="h-full bg-primary rounded-full transition-all duration-1000 ease-out"
                  style={{ width: `${score}%` }}
                />
              </div>
              <div className="flex gap-4 items-center mt-2">
                <div className="text-center">
                  <p className="text-[9px] uppercase tracking-widest font-bold opacity-40">Sets</p>
                  <p className="text-sm font-bold">{completedSets}/{totalSets}</p>
                </div>
                <div className="h-6 w-[1px] bg-white/10" />
                <Button variant="ghost" size="sm" onClick={() => clearLogMutation.mutate()} className="h-8 rounded-lg text-muted-foreground hover:bg-white/5 text-[9px] font-bold uppercase tracking-widest px-4">
                  Reset Session
                </Button>
              </div>
            </div>
          )}
        </div>

        {/* Decorative Elements */}
        <div className="absolute -top-12 -left-12 w-48 h-48 bg-primary/10 rounded-full blur-[100px] pointer-events-none" />
        <div className="absolute -bottom-12 -right-12 w-64 h-64 bg-primary/5 rounded-full blur-[100px] pointer-events-none" />
      </div>

      {/* Exercise List */}
      <div className="space-y-6">
        <div className="flex items-center justify-between px-2">
          <h2 className="text-sm font-bold uppercase tracking-[0.2em] opacity-50">Assigned Movements</h2>
          <div className="flex items-center gap-2">
            <div className="w-2 h-2 rounded-full bg-primary animate-pulse" />
            <span className="text-[10px] font-bold uppercase tracking-widest text-primary">Active Session</span>
          </div>
        </div>

        <div className="grid grid-cols-1 gap-4">
          {workoutDay.exercises.map((exercise: PlanExercise, index: number) => {
            const effectiveWeight = weightOverrides?.[exercise.id] ?? exercise.targetWeight;
            const exerciseCompleted = (dayIdFromProps === null) ? isExerciseCompleted(exercise) : false;
            const exerciseLog = dailyLog ? dailyLog[exercise.id] : undefined;
            const isSkipped = dayIdFromProps === null && exerciseLog && exercise.sets.length > 0 && Object.values(exerciseLog).length >= exercise.sets.length && exercise.sets.every((set: SetData) => (exerciseLog[set.id] as any)?.isCompleted === false);

            return (
              <Link
                key={exercise.id}
                href={`/exercises/${exercise.id}?dayId=${workoutDay.id}`}
                className="group block"
                style={{ animationDelay: `${index * 100}ms` }}
              >
                <div className={cn(
                  "glass-panel border-none p-6 md:p-8 rounded-[2rem] transition-all duration-300 relative overflow-hidden flex items-center justify-between gap-6 interactive-scale",
                  exerciseCompleted ? "opacity-60 grayscale-[0.5]" : "hover:bg-white/10"
                )}>
                  <div className="flex items-center gap-6 flex-1 min-w-0">
                    <div className={cn(
                      "w-14 h-14 rounded-2xl flex items-center justify-center border transition-all duration-500 flex-shrink-0 group-hover:scale-110",
                      exerciseCompleted
                        ? "bg-primary/20 border-primary text-primary"
                        : isSkipped
                          ? "bg-destructive/10 border-destructive/20 text-destructive"
                          : "bg-white/5 border-white/10 text-foreground/50 group-hover:border-primary/50 group-hover:text-primary"
                    )}>
                      {exerciseCompleted ? <CheckSquare className="h-6 w-6" /> : <Dumbbell className="h-6 w-6" />}
                    </div>

                    <div className="min-w-0 flex-1">
                      <h3 className="text-xl font-bold tracking-tight truncate leading-tight group-hover:text-primary transition-colors">{exercise.name}</h3>
                      <div className="flex flex-wrap items-center gap-x-4 gap-y-1 mt-1">
                        <div className="flex items-center gap-1">
                          <span className="text-[10px] font-bold uppercase tracking-widest opacity-40">Protocol:</span>
                          <span className="text-xs font-bold">{exercise.sets.length} Premium Sets</span>
                        </div>
                        {(exercise.targetWeight || effectiveWeight) && (
                          <div className="flex items-center gap-1">
                            <span className="text-[10px] font-bold uppercase tracking-widest opacity-40">Target:</span>
                            <span className="text-xs font-bold text-primary">{effectiveWeight || exercise.targetWeight}</span>
                          </div>
                        )}
                      </div>
                    </div>
                  </div>

                  <div className="flex items-center gap-4 flex-shrink-0">
                    {isSkipped && (
                      <div className="px-3 py-1 rounded-full bg-destructive/10 border border-destructive/20">
                        <span className="text-[9px] font-bold uppercase tracking-widest text-destructive">Skipped</span>
                      </div>
                    )}
                    <div className="w-10 h-10 rounded-full bg-white/5 flex items-center justify-center opacity-0 group-hover:opacity-100 group-hover:bg-primary/20 transition-all duration-300">
                      <ArrowRight className="h-5 w-5 text-primary group-hover:translate-x-1 transition-transform" />
                    </div>
                  </div>

                  {/* Decorative Progress indicator inside the card */}
                  {exerciseCompleted && (
                    <div className="absolute top-0 bottom-0 left-0 w-1 bg-primary" />
                  )}
                </div>
              </Link>
            );
          })}
        </div>
      </div>
    </div>
  );
}
