
// src/app/exercises/[exerciseId]/page.tsx
'use client';

import { use, useState, useEffect, useMemo, useCallback } from 'react';
import Link from 'next/link';
import { useSearchParams, useRouter } from 'next/navigation';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useAuth } from '@/context/auth-context';
import { produce } from 'immer';

import type { Exercise as ExerciseType, LoggedExerciseData, WorkoutDay, NamedWorkoutPlan, SetData, UserData } from '@/types/workout';
import { Card, CardContent, CardDescription, CardHeader, CardTitle, CardFooter } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Separator } from '@/components/ui/separator';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { ArrowLeft, Dumbbell, Sparkles, CheckCircle, Edit, Save, XCircle, XSquare, Undo2, Lock, Info, ArrowUpCircle, Pencil, Loader2 } from 'lucide-react'; 
import SetLogger from '@/components/workout/set-logger';
import AIRecommendationModal from '@/components/workout/ai-recommendation-modal';
import AddExerciseModal from '@/components/workout-plan/add-exercise-modal'; 
import { useToast } from '@/hooks/use-toast';
import LoadingExercisePage from './loading';
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
import { getAllExercisesFromPlan as getAllExercisesForAutocompleteGlobal } from '@/data/workout-data';

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

type ExercisePageProps = {
  params: { exerciseId: string; };
};

export default function ExerciseDetailPage({ params: paramsFromProps }: ExercisePageProps) {
  const resolvedParams = use(paramsFromProps as any);
  const { exerciseId } = resolvedParams;
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
  const [isAIRecModalOpen, setIsAIRecModalOpen] = useState(false);
  const [canSuggestWeightIncrease, setCanSuggestWeightIncrease] = useState(false);
  
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
  
  const { data: allExercisesForModal, isLoading: isLoadingAllExercises } = useQuery({
      queryKey: ['allExercisesForAutocomplete'],
      queryFn: getAllExercisesForAutocompleteGlobal,
  });

  // --- Memos to derive state from queries ---
  const { baseExercise, currentWorkoutDay, exerciseForLogging, activePlan } = useMemo(() => {
    if (!userData) return { baseExercise: undefined, currentWorkoutDay: undefined, exerciseForLogging: undefined, activePlan: undefined };
    const plan = planIdFromQuery ? userData.plans.find(p => p.id === planIdFromQuery) : userData.plans.find(p => p.isActive);
    if (!plan) return { baseExercise: undefined, currentWorkoutDay: undefined, exerciseForLogging: undefined, activePlan: undefined };
    
    let baseEx, workoutDay, exerciseForLog;

    for(const day of plan.plan) {
        const found = day.exercises.find(ex => ex.id === exerciseId);
        if (found) {
            baseEx = found;
            if (day.id === dayIdFromQuery) {
                workoutDay = day;
                exerciseForLog = found;
            }
        }
    }
    if (!baseEx) baseEx = allExercisesForModal?.find(ex => ex.id === exerciseId);

    return { baseExercise: baseEx, currentWorkoutDay: workoutDay, exerciseForLogging: exerciseForLog, activePlan: plan };
  }, [userData, planIdFromQuery, dayIdFromQuery, exerciseId, allExercisesForModal]);
  
  const loggedExerciseData = useMemo(() => (dailyLog?.[exerciseId] || {}) as LoggedExerciseData, [dailyLog, exerciseId]);

  // --- Effects to sync state with fetched data ---
  useEffect(() => {
    if (exerciseForLogging && weightOverrides) {
        const initialEffectiveWeight = weightOverrides[exerciseId] ?? exerciseForLogging.targetWeight ?? '';
        setSessionTargetWeight(initialEffectiveWeight);
        setManualTargetWeightInput(initialEffectiveWeight);
    }
  }, [exerciseForLogging, weightOverrides, exerciseId]);
  
  const checkCompletionAndPlanReps = useCallback((currentLogData?: LoggedExerciseData) => {
    if (!currentLogData || !exerciseForLogging || exerciseForLogging.sets.length === 0) return false;
    const allSetsCompleted = exerciseForLogging.sets.every(set => currentLogData[set.id]?.isCompleted);
    if (!allSetsCompleted) return false;

    for (const set of exerciseForLogging.sets) {
      const loggedSet = currentLogData[set.id];
      const maxTarget = parseMaxTargetReps(set.targetReps);
      const loggedRepsNum = loggedSet?.reps !== undefined ? parseInt(String(loggedSet.reps), 10) : NaN;
      if (maxTarget === null) continue;
      if (isNaN(loggedRepsNum) || loggedRepsNum < maxTarget) return false;
    }
    return true;
  }, [exerciseForLogging]);

  useEffect(() => {
    setCanSuggestWeightIncrease(checkCompletionAndPlanReps(loggedExerciseData));
  }, [loggedExerciseData, checkCompletionAndPlanReps]);
  
  // --- Mutations ---
  const saveLogMutation = useMutation({
    mutationFn: (newLog: LoggedExerciseData) => {
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
      queryClient.invalidateQueries({ queryKey: ['weightOverrides', user?.uid]});
      queryClient.setQueryData(['dailyLog', user?.uid, currentDate], (oldData: DailyLog | undefined) => {
          if (!oldData) return { [exerciseId]: {} };
          const { [exerciseId]: _, ...rest } = oldData;
          return rest;
      });
      setSessionTargetWeight(newWeight);
      setCanSuggestWeightIncrease(false);
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
        const newPlans = produce(userData.plans, draft => {
            const plan = draft.find(p => p.id === activePlan.id);
            if (!plan) return;
            const day = plan.plan.find(d => d.id === dayIdFromQuery);
            if (!day) return;
            const exIndex = day.exercises.findIndex(ex => ex.id === updatedExercise.id);
            if (exIndex === -1) throw new Error("Exercise not found in day");
            day.exercises[exIndex] = updatedExercise;
        });
        return saveUserData(user!.uid, { ...userData, plans: newPlans });
    },
    onSuccess: (data, updatedExercise) => {
        queryClient.invalidateQueries({ queryKey: ['userData', user?.uid] });
        toast({ title: "Exercise Updated", description: `${updatedExercise.name} has been updated in your plan.`});
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
    const skippedLog: LoggedExerciseData = {};
    exerciseForLogging.sets.forEach(set => {
      skippedLog[set.id] = { reps: loggedExerciseData[set.id]?.reps || '', weight: loggedExerciseData[set.id]?.weight, isCompleted: false };
    });
    saveLogMutation.mutate(skippedLog);
    toast({ variant: "default", title: "Exercise Skipped", description: `"${baseExercise?.name}" marked as skipped.`});
  };

  const handleUnskipExercise = () => {
    saveLogMutation.mutate({}); // Passing empty object resets the log for this exercise
    toast({ title: "Exercise Unskipped", description: `"${baseExercise?.name}" is no longer skipped.`});
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
    return exerciseForLogging.sets.every(set => loggedExerciseData[set.id]?.isCompleted === false) && Object.keys(loggedExerciseData).length >= exerciseForLogging.sets.length;
  }, [exerciseForLogging, loggedExerciseData, dayIdFromQuery]);

  const isLoading = isLoadingUserData || isLoadingLog || isLoadingOverrides || isLoadingAllExercises;

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
  const allSetsCompletedCheck = dayIdFromQuery && exerciseForLogging?.sets.every(set => loggedExerciseData?.[set.id]?.isCompleted);
  
  const isSpecialActivity = displayExercise.isActivity || displayExercise.isConditioning || displayExercise.isWarmup || displayExercise.isMatch || displayExercise.isStretch || displayExercise.isFoamRoll || displayExercise.isRecovery || displayExercise.isSkill || displayExercise.isMobility;
  const canShowAISuggestionButton = dayIdFromQuery && !isSpecialActivity && !displayExercise.isCore && !isSkipped;

  return (
    <div className="container mx-auto max-w-3xl px-2 sm:px-4 py-8 space-y-6">
      <div className="flex items-center justify-between">
        <Button variant="ghost" size="sm" onClick={() => dayIdFromQuery ? router.push('/dashboard/today') : router.back()} className="mr-auto">
            <ArrowLeft className="mr-2 h-4 w-4" /> Back to {dayIdFromQuery ? "Workout" : "Previous"}
        </Button>
        {isSkipped && dayIdFromQuery && (
            <Badge variant="destructive" className="text-xs font-normal">
                <Lock className="h-3 w-3 mr-1" /> Skipped
            </Badge>
        )}
      </div>

      <Card className="shadow-lg rounded-2xl">
        <CardHeader>
          <div className="flex justify-between items-start">
            <CardTitle className="text-2xl font-bold text-primary flex items-center">
               <Dumbbell className="mr-3 h-7 w-7" />
               {displayExercise.name}
            </CardTitle>
            {dayIdFromQuery && exerciseForLogging && ( 
              <Button variant="ghost" size="icon" onClick={() => setIsEditExerciseModalOpen(true)} className="shrink-0">
                <Pencil className="h-4 w-4" />
                <span className="sr-only">Edit Exercise Details</span>
              </Button>
            )}
          </div>
          {displayExercise.notes && !isSkipped &&(
            <Badge variant="secondary" className="text-xs mt-1 w-fit">{displayExercise.notes}</Badge>
          )}
        </CardHeader>
        <CardContent className="space-y-4">
          {displayExercise.description && (
            <div>
              <h3 className="text-md font-semibold mb-1 text-foreground">Description</h3>
              <p className="text-sm text-muted-foreground whitespace-pre-line">{displayExercise.description}</p>
            </div>
          )}

          {displayExercise.muscleGroups && displayExercise.muscleGroups.length > 0 && (
            <div>
              <h3 className="text-md font-semibold mb-1 text-foreground">Primary Muscle Groups</h3>
              <div className="flex flex-wrap gap-1">
                {displayExercise.muscleGroups.map((group) => (
                  <Badge key={group} variant="outline" className="text-xs">{group}</Badge>
                ))}
              </div>
            </div>
          )}
          
          <Separator />

          {displayExercise.videoUrl && (
            <div>
              <h3 className="text-md font-semibold mb-2 text-foreground">Instructional Video</h3>
              {hasVideo ? (
                <div className="aspect-video rounded-lg overflow-hidden border border-border">
                  <iframe
                    width="100%"
                    height="100%"
                    src={displayExercise.videoUrl}
                    title={`Video for ${displayExercise.name}`}
                    frameBorder="0"
                    allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share"
                    allowFullScreen
                    className="bg-muted"
                  ></iframe>
                </div>
              ) : (
                <p className="text-sm text-muted-foreground">
                  Video link: <a href={displayExercise.videoUrl} target="_blank" rel="noopener noreferrer" className="text-primary hover:underline">{displayExercise.videoUrl}</a>
                </p>
              )}
            </div>
          )}
        </CardContent>
      </Card>

      {exerciseForLogging && dayIdFromQuery && (
        <Card className={cn("shadow-lg rounded-2xl", isSkipped && "bg-card/60")}>
          <CardHeader className="pb-3">
            <div className="flex justify-between items-center">
                <CardTitle className="text-xl">Log Your Sets</CardTitle>
                {isSkipped ? (
                    <Button variant="outline" size="sm" onClick={handleUnskipExercise}><Undo2 className="mr-2 h-4 w-4" />Unskip</Button>
                ) : (
                    <AlertDialog>
                        <AlertDialogTrigger asChild>
                            <Button variant="ghost" size="sm" className="text-destructive hover:text-destructive hover:bg-destructive/10"><XSquare className="mr-2 h-4 w-4" />Skip Exercise</Button>
                        </AlertDialogTrigger>
                        <AlertDialogContent>
                            <AlertDialogHeader>
                            <AlertDialogTitle>Skip: {displayExercise.name}?</AlertDialogTitle>
                            <AlertDialogDescription>
                                This marks all sets as not completed for today, affecting your score. You can log sets later if you unskip.
                            </AlertDialogDescription>
                            </AlertDialogHeader>
                            <AlertDialogFooter>
                            <AlertDialogCancel>Cancel</AlertDialogCancel>
                            <AlertDialogAction onClick={handleSkipExercise} className="bg-destructive hover:bg-destructive/90 text-destructive-foreground">
                                Skip Exercise
                            </AlertDialogAction>
                            </AlertDialogFooter>
                        </AlertDialogContent>
                    </AlertDialog>
                )}
            </div>
            {!(isSpecialActivity || displayExercise.isCore || isSkipped) && (
              <div className="mt-3 p-3 bg-secondary/30 rounded-md border border-secondary/50">
                <Label className="text-xs font-medium text-muted-foreground">Planned Weight for Today</Label>
                {isEditingTarget ? (
                  <div className="flex items-center gap-2 mt-1">
                    <Input
                      type="text"
                      value={manualTargetWeightInput}
                      onChange={(e) => setManualTargetWeightInput(e.target.value)}
                      className="h-8 text-sm flex-grow"
                      placeholder="e.g. 80 kg or Bodyweight"
                      aria-label="Edit target weight"
                      disabled={saveWeightOverrideMutation.isPending}
                    />
                    <Button size="icon" variant="ghost" onClick={handleSaveManualTarget} className="h-8 w-8 text-primary shrink-0" aria-label="Save weight" disabled={saveWeightOverrideMutation.isPending}>
                        {saveWeightOverrideMutation.isPending ? <Loader2 className="h-4 w-4 animate-spin"/> : <Save className="h-4 w-4" />}
                    </Button>
                    <Button size="icon" variant="ghost" onClick={handleCancelEditTarget} className="h-8 w-8 shrink-0" aria-label="Cancel edit weight" disabled={saveWeightOverrideMutation.isPending}><XCircle className="h-4 w-4" /></Button>
                  </div>
                ) : (
                  <div className="flex items-center justify-between mt-1">
                    <div className="flex items-center gap-2">
                        <p className="text-sm font-semibold text-foreground">{sessionTargetWeight || 'Not set'}</p>
                        {canSuggestWeightIncrease && (
                           <Badge variant="default" className="px-1.5 py-0.5 text-xs bg-green-600 hover:bg-green-700 text-white">
                              <ArrowUpCircle className="h-3 w-3 mr-0.5" /> Suggest Inc.
                           </Badge>
                        )}
                    </div>
                    <Button size="icon" variant="ghost" onClick={handleEditClick} className="h-8 w-8 shrink-0" aria-label="Edit weight"><Edit className="h-4 w-4" /></Button>
                  </div>
                )}
              </div>
            )}
          </CardHeader>
          <CardContent className={cn("p-0", isSkipped && "opacity-40 pointer-events-none")}>
            {exerciseForLogging.sets.map((set, index) => (
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
                />
              ))}
          </CardContent>
          {canShowAISuggestionButton && (
            <CardFooter className="pt-4 justify-end">
              <Button
                variant="outline"
                size="sm"
                onClick={() => setIsAIRecModalOpen(true)}
                disabled={!allSetsCompletedCheck}
                 className="bg-accent/20 hover:bg-accent/30 text-accent-foreground border-accent/50"
              >
                <Sparkles className="mr-2 h-4 w-4" />
                AI Weight Advice
              </Button>
            </CardFooter>
          )}
        </Card>
      )}
      {canShowAISuggestionButton && exerciseForLogging && dayIdFromQuery && (
         <AIRecommendationModal
            exercise={exerciseForLogging}
            isOpen={isAIRecModalOpen}
            onOpenChange={setIsAIRecModalOpen}
        />
      )}
      {exerciseForLogging && dayIdFromQuery && allExercisesForModal && userData && (
        <AddExerciseModal
          isOpen={isEditExerciseModalOpen}
          onOpenChange={setIsEditExerciseModalOpen}
          onSave={(exercise) => saveEditedExerciseMutation.mutate(exercise)}
          allExercises={allExercisesForModal}
          dayId={dayIdFromQuery}
          initialData={exerciseForLogging} 
        />
      )}
    </div>
  );
}
