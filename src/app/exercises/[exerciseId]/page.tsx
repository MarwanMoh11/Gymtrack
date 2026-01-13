// src/app/exercises/[exerciseId]/page.tsx
'use client';

import { use, useState, useEffect, useMemo, useCallback } from 'react';
import Link from 'next/link';
import { useSearchParams, useRouter } from 'next/navigation';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useAuth } from '@/context/auth-context';
import { produce } from 'immer';

import type { Exercise as ExerciseType, ExerciseLogData, DailyLog, SetData, UserData, NamedWorkoutPlan, WorkoutDay } from '../../../types/workout';
import { Card, CardContent, CardDescription, CardHeader, CardTitle, CardFooter } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Separator } from '@/components/ui/separator';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { ArrowLeft, Dumbbell, CheckCircle, Edit, Save, XCircle, XSquare, Undo2, Lock, Info, ArrowUpCircle, Pencil, Loader2, Sparkles, ChevronDown, ChevronUp, PlayCircle } from 'lucide-react';
import SetLogger from '@/components/workout/set-logger';
import AddExerciseModal from '@/components/workout-plan/add-exercise-modal';
import { useToast } from '@/hooks/use-toast';
import LoadingExercisePage from './loading';
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "@/components/ui/collapsible";
import { getPreviousSetPerformance } from '@/lib/workout-utils';
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogTrigger,
} from "@/components/ui/alert-dialog";
import { cn } from '@/lib/utils';
import { getUserData, saveUserData } from '@/lib/firestore-workout-plan-service';
import { getDailyLog, saveDailyLog } from '@/lib/firestore-log-service';
import { getTargetWeightOverrides, setTargetWeightOverride as saveTargetWeightOverride } from '@/lib/firestore-settings-service';

const getCurrentDateString = (): string => {
  return new Date().toISOString().split('T')[0];
};

const parseMaxTargetReps = (target: string | number): number | null => {
  if (typeof target === 'number') return target;
  if (typeof target === 'string') {
    const rangeMatch = target.match(/(\d+)\s*-\s*(\d+)/);
    if (rangeMatch) return Math.max(parseInt(rangeMatch[1], 10), parseInt(rangeMatch[2], 10));
    const minMatch = target.match(/(\d+)\+/);
    if (minMatch) return parseInt(minMatch[1], 10);
    const numMatch = target.match(/^(\d+)$/);
    if (numMatch) return parseInt(numMatch[1], 10);
    if (target.toLowerCase().includes('failure') || target.toLowerCase().includes('min') || target.toLowerCase().includes('—')) return null;
  }
  const parsed = parseInt(String(target), 10);
  return isNaN(parsed) ? null : parsed;
};

interface ExercisePageProps {
  params: Promise<{ exerciseId: string; }>;
}

export default function ExerciseDetailPage({ params: paramsFromProps }: ExercisePageProps) {
  const resolvedParams = use(paramsFromProps);
  const exerciseId = resolvedParams.exerciseId;
  const { user } = useAuth();
  const queryClient = useQueryClient();
  const router = useRouter();
  const searchParams = useSearchParams();
  const dayIdFromQuery = searchParams.get('dayId');
  const planIdFromQuery = searchParams.get('planId');
  const { toast } = useToast();

  const [sessionTargetWeight, setSessionTargetWeight] = useState('');
  const [manualTargetWeightInput, setManualTargetWeightInput] = useState('');
  const [isEditingTarget, setIsEditingTarget] = useState(false);
  const [isEditExerciseModalOpen, setIsEditExerciseModalOpen] = useState(false);

  const currentDate = getCurrentDateString();

  // --- Data Fetching with React Query ---
  const { data: userData, isLoading: isLoadingUserData } = useQuery({
    queryKey: ['userData', user?.uid],
    queryFn: () => getUserData(user!.uid),
    enabled: !!user,
  });

  const { data: weightOverrides, isLoading: isLoadingOverrides } = useQuery({
    queryKey: ['weightOverrides', user?.uid],
    queryFn: () => getTargetWeightOverrides(user!.uid),
    enabled: !!user,
  });

  const { data: dailyLog, isLoading: isLoadingLog } = useQuery({
    queryKey: ['dailyLog', user?.uid, currentDate],
    queryFn: () => getDailyLog(user!.uid, currentDate),
    enabled: !!user && !!dayIdFromQuery, // Only enable if we're on a specific workout day
  });


  // --- Memos to derive state from queries ---
  const { baseExercise, currentWorkoutDay, exerciseForLogging, activePlan } = useMemo(() => {
    if (!userData) return { baseExercise: undefined, currentWorkoutDay: undefined, exerciseForLogging: undefined, activePlan: undefined };
    const plan = planIdFromQuery ? userData.plans.find((p: NamedWorkoutPlan) => p.id === planIdFromQuery) : userData.plans.find((p: NamedWorkoutPlan) => p.isActive);
    if (!plan) return { baseExercise: undefined, currentWorkoutDay: undefined, exerciseForLogging: undefined, activePlan: undefined };

    let baseEx, workoutDay, exerciseForLog;

    for (const day of plan.plan) {
      const found = day.exercises.find((ex: ExerciseType) => ex.id === exerciseId);
      if (found) {
        baseEx = found;
        if (day.id === dayIdFromQuery) {
          workoutDay = day;
          exerciseForLog = found;
        }
      }
    }
    return { baseExercise: baseEx, currentWorkoutDay: workoutDay, exerciseForLogging: exerciseForLog, activePlan: plan };
  }, [userData, planIdFromQuery, dayIdFromQuery, exerciseId]);

  const loggedExerciseData = useMemo(() => (dailyLog?.[exerciseId] || {}) as ExerciseLogData, [dailyLog, exerciseId]);

  // --- Effects to sync state with fetched data ---
  useEffect(() => {
    if (exerciseForLogging && weightOverrides) {
      const initialEffectiveWeight = weightOverrides[exerciseId] ?? exerciseForLogging.targetWeight ?? '';
      setSessionTargetWeight(initialEffectiveWeight);
      setManualTargetWeightInput(initialEffectiveWeight);
    }
  }, [exerciseForLogging, weightOverrides, exerciseId]);

  // --- Mutations ---
  const saveLogMutation = useMutation({
    mutationFn: (newLog: ExerciseLogData) => {
      if (!user) throw new Error("User not authenticated");
      const newDailyLog = { ...(dailyLog || {}), [exerciseId]: newLog };
      return saveDailyLog(user.uid, currentDate, newDailyLog);
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['dailyLog', user?.uid, currentDate] });
    },
    onError: () => {
      toast({ variant: 'destructive', title: "Save Error", description: "Could not save your log." });
    }
  });

  const saveWeightOverrideMutation = useMutation({
    mutationFn: (newWeight: string) => saveTargetWeightOverride(user!.uid, exerciseId, newWeight),
    onSuccess: (data, newWeight) => {
      queryClient.invalidateQueries({ queryKey: ['weightOverrides', user?.uid] });
      queryClient.setQueryData(['dailyLog', user?.uid, currentDate], (oldData: DailyLog | undefined) => {
        if (!oldData) return { [exerciseId]: {} };
        const { [exerciseId]: _, ...rest } = oldData;
        return rest;
      });
      setSessionTargetWeight(newWeight);
      toast({ title: "Target Weight Updated", description: `New weight for ${baseExercise?.name} is ${newWeight}. Sets reset.` });
      setIsEditingTarget(false);
    },
    onError: () => {
      toast({ variant: 'destructive', title: "Save Error", description: "Could not save weight override." });
    }
  });

  const saveEditedExerciseMutation = useMutation({
    mutationFn: (updatedExercise: ExerciseType) => {
      if (!userData || !activePlan || !dayIdFromQuery) throw new Error("No active plan or day to update");
      const newPlans = produce(userData.plans, (draft: NamedWorkoutPlan[]) => {
        const plan = draft.find(p => p.id === activePlan.id);
        if (!plan) return;
        const day = plan.plan.find((d: WorkoutDay) => d.id === dayIdFromQuery);
        if (!day) return;
        const exIndex = day.exercises.findIndex((ex: ExerciseType) => ex.id === updatedExercise.id);
        if (exIndex === -1) throw new Error("Exercise not found in day");
        day.exercises[exIndex] = updatedExercise;
      });
      return saveUserData(user!.uid, { ...userData, plans: newPlans });
    },
    onSuccess: (data, updatedExercise) => {
      queryClient.invalidateQueries({ queryKey: ['userData', user?.uid] });
      toast({ title: "Exercise Updated", description: `${updatedExercise.name} has been updated in your plan.` });
      setIsEditExerciseModalOpen(false);
    },
    onError: (error) => {
      toast({ variant: 'destructive', title: "Save Error", description: `Could not save exercise changes. ${error.message}` });
    }
  });

  // --- Event Handlers ---
  const handleLogSet = (setId: string, logData: { reps: string; isCompleted: boolean; }) => {
    const newLogEntry = { ...logData, weight: sessionTargetWeight };
    const newLoggedExerciseData = { ...loggedExerciseData, [setId]: newLogEntry };
    saveLogMutation.mutate(newLoggedExerciseData);
  };

  const handleSkipExercise = () => {
    if (!exerciseForLogging) return;
    const skippedLog: ExerciseLogData = {};
    exerciseForLogging.sets.forEach((set: SetData) => {
      skippedLog[set.id] = { id: set.id, reps: loggedExerciseData[set.id]?.reps || 0, weight: loggedExerciseData[set.id]?.weight, isCompleted: false };
    });
    saveLogMutation.mutate(skippedLog);
    toast({ variant: "default", title: "Exercise Skipped", description: `"${baseExercise?.name}" marked as skipped.` });
  };

  const handleUnskipExercise = () => {
    saveLogMutation.mutate({}); // Passing empty object resets the log for this exercise
    toast({ title: "Exercise Unskipped", description: `"${baseExercise?.name}" is no longer skipped.` });
  };

  const handleSaveManualTarget = () => {
    if (manualTargetWeightInput !== sessionTargetWeight) {
      saveWeightOverrideMutation.mutate(manualTargetWeightInput);
    } else {
      setIsEditingTarget(false);
    }
  };

  const handleCancelEditTarget = () => {
    setIsEditingTarget(false);
    setManualTargetWeightInput(sessionTargetWeight);
  };

  const handleEditClick = () => {
    setManualTargetWeightInput(sessionTargetWeight);
    setIsEditingTarget(true);
  }

  const isSkipped = useMemo(() => {
    if (!exerciseForLogging || exerciseForLogging.sets.length === 0 || !dayIdFromQuery) return false;
    return exerciseForLogging.sets.every((set: SetData) => loggedExerciseData[set.id]?.isCompleted === false) && Object.keys(loggedExerciseData).length >= exerciseForLogging.sets.length;
  }, [exerciseForLogging, loggedExerciseData, dayIdFromQuery]);

  const isLoading = isLoadingUserData || isLoadingLog || isLoadingOverrides;

  if (isLoading) {
    return <LoadingExercisePage />;
  }

  if (!baseExercise) {
    return (
      <div className="container mx-auto px-4 py-8 flex flex-col items-center text-center">
        <Dumbbell className="h-16 w-16 text-destructive mb-4" />
        <h1 className="text-2xl font-bold text-destructive mb-2">Exercise Not Found</h1>
        <p className="text-muted-foreground mb-6">
          The exercise with ID "{exerciseId}" could not be found.
        </p>
        <Button asChild variant="outline" onClick={() => router.back()}>
          <span><ArrowLeft className="mr-2 h-4 w-4" /> Go Back</span>
        </Button>
      </div>
    );
  }

  if (dayIdFromQuery && !exerciseForLogging && currentWorkoutDay) {
    return (
      <div className="container mx-auto px-4 py-8 flex flex-col items-center text-center">
        <Dumbbell className="h-16 w-16 text-destructive mb-4" />
        <h1 className="text-2xl font-bold text-destructive mb-2">Exercise Not in Day's Plan</h1>
        <p className="text-muted-foreground mb-6">
          "{baseExercise.name}" (ID: {exerciseId}) is not part of the plan for "{currentWorkoutDay?.title || dayIdFromQuery}".
        </p>
        <Button asChild variant="outline" onClick={() => router.push('/dashboard/today')}>
          <span><ArrowLeft className="mr-2 h-4 w-4" /> Back to Today's Workout</span>
        </Button>
      </div>
    );
  }

  const displayExercise = exerciseForLogging || baseExercise;
  const hasVideo = displayExercise.videoUrl && displayExercise.videoUrl.includes('youtube.com/embed');
  const allSetsCompletedCheck = dayIdFromQuery && exerciseForLogging?.sets.every((set: SetData) => loggedExerciseData?.[set.id]?.isCompleted);

  const isSpecialActivity = ['cardio', 'mobility', 'warmup', 'cooldown'].includes(displayExercise.category as string);
  const canShowAISuggestionButton = dayIdFromQuery && !isSpecialActivity && displayExercise.category !== 'core' && !isSkipped;

  return (
    <div className="w-full space-y-8 pb-20 animate-in fade-in duration-700">
      {/* Navigation & Status Header */}
      <div className="flex items-center justify-between">
        <Button
          variant="ghost"
          size="sm"
          onClick={() => dayIdFromQuery ? router.push('/dashboard/today') : router.back()}
          className="h-10 rounded-xl hover:bg-white/5 text-muted-foreground hover:text-foreground transition-all flex items-center gap-2 group -ml-2"
        >
          <ArrowLeft className="h-4 w-4 group-hover:-translate-x-1 transition-transform" />
          <span className="text-[10px] font-bold uppercase tracking-widest">Return to Training</span>
        </Button>

        {isSkipped && dayIdFromQuery && (
          <div className="px-3 py-1 rounded-full bg-destructive/10 border border-destructive/20 flex items-center gap-2">
            <Lock className="h-3 w-3 text-destructive" />
            <span className="text-[9px] font-bold uppercase tracking-widest text-destructive">Protocol Suspended</span>
          </div>
        )}
      </div>

      {/* Main Exercise Branding Card */}
      <div className="relative overflow-hidden rounded-[2.5rem] glass-panel border-none p-5 sm:p-8 md:p-10 shadow-2xl">
        <div className="relative z-10 flex flex-col md:flex-row md:items-center justify-between gap-8">
          <div className="flex items-start gap-6">
            <div className="w-16 h-16 rounded-[2rem] bg-primary flex items-center justify-center border border-primary/20 shadow-xl shadow-primary/20 -rotate-3 group-hover:rotate-0 transition-transform duration-500 flex-shrink-0">
              <Dumbbell className="h-8 w-8 text-background" />
            </div>
            <div className="space-y-1">
              <h1 className="text-3xl md:text-4xl font-black tracking-tighter leading-none">{displayExercise.name}</h1>
              <div className="flex flex-wrap gap-2 pt-2">
                {displayExercise.muscleGroups?.map((group: string) => (
                  <span key={group} className="text-[9px] font-black uppercase tracking-widest px-2 py-0.5 rounded-md bg-white/5 border border-white/5 text-foreground/40 italic">
                    {group}
                  </span>
                ))}
              </div>
            </div>
          </div>

          <div className="flex items-center gap-3">
            {dayIdFromQuery && exerciseForLogging && (
              <Button
                variant="outline"
                onClick={() => setIsEditExerciseModalOpen(true)}
                className="h-12 w-12 rounded-xl border-white/10 hover:bg-white/5 flex items-center justify-center interactive-scale p-0"
              >
                <Pencil className="h-4 w-4" />
              </Button>
            )}
          </div>
        </div>

        {/* Decorative Background Glows */}
        <div className="absolute -top-24 -left-24 w-64 h-64 bg-primary/10 rounded-full blur-[100px] pointer-events-none" />
        <div className="absolute -bottom-24 -right-24 w-64 h-64 bg-primary/5 rounded-full blur-[100px] pointer-events-none" />
      </div>

      {/* Collapsible Info Section */}
      <Collapsible className="glass-panel border-none rounded-[2rem] overflow-hidden">
        <CollapsibleTrigger className="w-full p-5 sm:p-6 flex items-center justify-between group">
          <div className="flex items-center gap-3">
            <div className="w-8 h-8 rounded-lg bg-white/5 flex items-center justify-center">
              <Info className="h-4 w-4 text-primary" />
            </div>
            <span className="text-[10px] font-black uppercase tracking-[0.2em] text-foreground/60">Execution & Methodology</span>
          </div>
          <ChevronDown className="h-4 w-4 text-foreground/40 group-data-[state=open]:rotate-180 transition-transform" />
        </CollapsibleTrigger>
        <CollapsibleContent className="px-5 sm:px-6 pb-8 space-y-8 animate-in slide-in-from-top-2 duration-300">
          {displayExercise.description && (
            <div className="space-y-3">
              <div className="h-[1px] w-full bg-white/5" />
              <p className="text-sm leading-relaxed text-muted-foreground font-medium italic">
                {displayExercise.description}
              </p>
            </div>
          )}

          {displayExercise.videoUrl && (
            <div className="space-y-4">
              <div className="flex items-center gap-2">
                <PlayCircle className="h-4 w-4 text-primary" />
                <h3 className="text-[10px] font-black uppercase tracking-widest">Visual Guidance</h3>
              </div>
              {hasVideo ? (
                <div className="aspect-video rounded-[1.5rem] overflow-hidden border border-white/5 shadow-2xl relative group">
                  <iframe
                    width="100%"
                    height="100%"
                    src={displayExercise.videoUrl}
                    title={`Video for ${displayExercise.name}`}
                    frameBorder="0"
                    allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share"
                    allowFullScreen
                    className="bg-black/50"
                  ></iframe>
                </div>
              ) : (
                <a
                  href={displayExercise.videoUrl}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="flex items-center justify-between p-4 rounded-xl bg-white/5 border border-white/5 hover:bg-white/10 transition-colors"
                >
                  <span className="text-xs font-bold text-primary">Open External Demonstration</span>
                  <ArrowUpCircle className="h-4 w-4 text-primary rotate-45" />
                </a>
              )}
            </div>
          )}
        </CollapsibleContent>
      </Collapsible>

      {/* Core Protocol Logging Section */}
      {exerciseForLogging && dayIdFromQuery && (
        <div className={cn(
          "relative glass-panel border-none rounded-[2.5rem] p-5 sm:p-8 md:p-10 shadow-2xl transition-all duration-500",
          isSkipped && "opacity-40 grayscale pointer-events-none scale-[0.98]"
        )}>
          {/* Section Header */}
          <div className="flex justify-between items-center mb-10">
            <div className="flex items-center gap-3">
              <div className="w-10 h-10 rounded-xl bg-primary/20 flex items-center justify-center border border-primary/20">
                <Edit className="h-5 w-5 text-primary" />
              </div>
              <h2 className="text-2xl font-black tracking-tight uppercase italic">Active Protocol</h2>
            </div>

            {!isSkipped ? (
              <AlertDialog>
                <AlertDialogTrigger asChild>
                  <Button variant="ghost" size="sm" className="h-10 rounded-xl text-destructive hover:bg-destructive/10 text-[10px] font-bold uppercase tracking-widest px-4">
                    Suspend Protocol
                  </Button>
                </AlertDialogTrigger>
                <AlertDialogContent className="glass-panel border-none rounded-[2.5rem] p-10">
                  <AlertDialogHeader>
                    <AlertDialogTitle className="text-2xl font-black tracking-tight">Suspend: {displayExercise.name}?</AlertDialogTitle>
                    <AlertDialogDescription className="text-muted-foreground font-medium pt-2">
                      Marking this protocol as suspended will impact your session score. This should only be done for essential recovery or fatigue management.
                    </AlertDialogDescription>
                  </AlertDialogHeader>
                  <AlertDialogFooter className="pt-6 gap-4">
                    <AlertDialogCancel className="h-12 rounded-xl border-white/10 hover:bg-white/5 font-bold uppercase tracking-widest text-[10px]">Resume Execution</AlertDialogCancel>
                    <AlertDialogAction onClick={handleSkipExercise} className="h-12 rounded-xl bg-destructive hover:bg-destructive/90 text-background font-bold uppercase tracking-widest text-[10px] shadow-xl shadow-destructive/20">
                      Confirm Suspension
                    </AlertDialogAction>
                  </AlertDialogFooter>
                </AlertDialogContent>
              </AlertDialog>
            ) : (
              <Button variant="outline" size="sm" onClick={handleUnskipExercise} className="h-10 rounded-xl border-primary/20 text-primary hover:bg-primary/5 text-[10px] font-bold uppercase tracking-widest px-4">
                <Undo2 className="mr-2 h-4 w-4" /> Reactivate Protocol
              </Button>
            )}
          </div>

          {/* Target Weight Setting */}
          {!(isSpecialActivity || displayExercise.category === 'core' || isSkipped) && (
            <div className="mb-10 p-6 rounded-[1.5rem] bg-white/5 border border-white/5 relative group overflow-hidden">
              <div className="relative z-10 flex flex-col sm:flex-row sm:items-center justify-between gap-6">
                <div>
                  <Label className="text-[10px] font-black uppercase tracking-[0.2em] text-foreground/40 mb-2 block">Planned Intensity</Label>
                  {isEditingTarget ? (
                    <div className="flex items-center gap-3">
                      <div className="relative flex-grow">
                        <Input
                          type="text"
                          value={manualTargetWeightInput}
                          onChange={(e) => setManualTargetWeightInput(e.target.value)}
                          className="h-12 bg-white/5 border-white/10 rounded-xl font-black text-lg focus-visible:ring-primary/50"
                          placeholder="e.g. 100 kg"
                          disabled={saveWeightOverrideMutation.isPending}
                        />
                        <div className="absolute right-3 top-1/2 -translate-y-1/2 text-[9px] font-black uppercase tracking-widest opacity-30">WEIGHT</div>
                      </div>
                      <Button onClick={handleSaveManualTarget} disabled={saveWeightOverrideMutation.isPending} className="h-12 w-12 rounded-xl bg-primary text-background flex-shrink-0 shadow-lg shadow-primary/20">
                        {saveWeightOverrideMutation.isPending ? <Loader2 className="h-5 w-5 animate-spin" /> : <Save className="h-5 w-5" />}
                      </Button>
                      <Button variant="ghost" onClick={handleCancelEditTarget} disabled={saveWeightOverrideMutation.isPending} className="h-12 w-12 rounded-xl bg-white/5 flex-shrink-0">
                        <XCircle className="h-5 w-5" />
                      </Button>
                    </div>
                  ) : (
                    <div className="flex items-center gap-4 group/weight cursor-pointer" onClick={handleEditClick}>
                      <span className="text-3xl font-black tracking-tighter text-primary">{sessionTargetWeight || 'N/A'}</span>
                      <div className="h-8 w-8 rounded-lg bg-primary/10 flex items-center justify-center opacity-0 group-hover/weight:opacity-100 transition-opacity">
                        <Pencil className="h-3 w-3 text-primary" />
                      </div>
                    </div>
                  )}
                </div>

                <div className="flex flex-col items-end">
                  <span className="text-[9px] font-black uppercase tracking-widest opacity-20 mb-1">Methodology</span>
                  <span className="text-xs font-black tracking-tight">{displayExercise.sets.length} High Tension Sets</span>
                </div>
              </div>
              {/* Decorative accent */}
              <div className="absolute top-0 right-0 w-32 h-32 bg-primary/5 rounded-full -mr-16 -mt-16 blur-2xl opacity-50" />
            </div>
          )}

          {/* Set List */}
          <div className="space-y-2">
            {exerciseForLogging.sets.map((set: SetData, index: number) => (
              <SetLogger
                key={set.id}
                setNumber={index + 1}
                setData={set}
                loggedSetData={loggedExerciseData?.[set.id]}
                onLogSet={(logData) => handleLogSet(set.id, logData)}
                exerciseUnit={exerciseForLogging.unit || baseExercise.unit}
                isSimpleLog={isSpecialActivity}
                isEditingInitially={!loggedExerciseData?.[set.id]?.isCompleted}
                effectiveTargetWeight={sessionTargetWeight}
                activePlan={activePlan}
              />
            ))}
          </div>
        </div>
      )}

      {exerciseForLogging && dayIdFromQuery && userData && (
        <AddExerciseModal
          isOpen={isEditExerciseModalOpen}
          onOpenChange={setIsEditExerciseModalOpen}
          onSave={(exercise) => saveEditedExerciseMutation.mutate(exercise)}
          dayId={dayIdFromQuery}
          initialData={exerciseForLogging}
        />
      )}
    </div>
  );
}
