
// src/app/exercises/[exerciseId]/page.tsx
'use client';

import { use, useState, useEffect, useCallback, useMemo } from 'react'; 
import Link from 'next/link';
import { useSearchParams, useRouter } from 'next/navigation';
// Import service functions
import { getExerciseById as getBaseExerciseByIdFromService, getActiveNamedWorkoutPlan, getPlanById } from '@/lib/workout-plan-service';
import { getAllExercisesFromPlan as getAllExercisesForAutocompleteGlobal, getWorkoutByDayFromPlan } from '@/data/workout-data'; // For modal

import type { Exercise as ExerciseType, SetData, LoggedSetData, DailyLog, WorkoutDay, LoggedExerciseData, WeeklyPlan } from '@/types/workout';
import { Card, CardContent, CardDescription, CardHeader, CardTitle, CardFooter } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Separator } from '@/components/ui/separator';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { ArrowLeft, Dumbbell, Sparkles, CheckCircle, Edit, Save, XCircle, XSquare, Undo2, Lock, Info, ArrowUpCircle, Pencil } from 'lucide-react'; 
import SetLogger from '@/components/workout/set-logger';
import AIRecommendationModal from '@/components/workout/ai-recommendation-modal';
import AddExerciseModal from '@/components/workout-plan/add-exercise-modal'; 
import { getUserTargetWeight, setTargetWeightOverride } from '@/lib/user-settings';
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


const getCurrentDateString = (): string => {
  return new Date().toISOString().split('T')[0];
};

function getDailyLogLocalStorageKey(dayId: string, date: string): string {
  // Potentially include activePlanId if logs are strictly plan-specific
  // const activePlan = getActiveNamedWorkoutPlan();
  // const planPrefix = activePlan ? `${activePlan.id}_` : '';
  return `gymtrack_log_${dayId}_${date}`;
}

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
  params: { 
    exerciseId: string;
  };
};

export default function ExerciseDetailPage({ params: paramsFromProps }: ExercisePageProps) {
  const resolvedParams = use(paramsFromProps as any);
  const { exerciseId } = resolvedParams;

  const router = useRouter();
  const searchParams = useSearchParams();
  const dayIdFromQuery = searchParams.get('dayId');
  const planIdFromQuery = searchParams.get('planId'); // For context if not using global active plan
  
  const [baseExercise, setBaseExercise] = useState<ExerciseType | null | undefined>(undefined);
  const [currentWorkoutDay, setCurrentWorkoutDay] = useState<WorkoutDay | null | undefined>(undefined);
  const [exerciseForLogging, setExerciseForLogging] = useState<ExerciseType | null | undefined>(undefined);
  
  const [loggedExerciseData, setLoggedExerciseData] = useState<LoggedExerciseData>({});
  const [isClient, setIsClient] = useState(false);
  const [currentDate, setCurrentDate] = useState('');
  
  const [isAIRecModalOpen, setIsAIRecModalOpen] = useState(false);
  const [isEditingTarget, setIsEditingTarget] = useState(false);
  const [manualTargetWeight, setManualTargetWeight] = useState('');
  const [forceSetEditKey, setForceSetEditKey] = useState(0);
  const [canSuggestWeightIncrease, setCanSuggestWeightIncrease] = useState(false);

  const [isEditExerciseModalOpen, setIsEditExerciseModalOpen] = useState(false);
  const [allExercisesForModal, setAllExercisesForModal] = useState<ExerciseType[]>([]);

  const { toast } = useToast();

  useEffect(() => {
    setIsClient(true);
    const dateStr = getCurrentDateString();
    setCurrentDate(dateStr);

    // Fetch base exercise details (globally or from specified plan)
    const fetchedBaseExercise = getBaseExerciseByIdFromService(exerciseId, planIdFromQuery ? getPlanById(planIdFromQuery)?.plan : undefined);
    setBaseExercise(fetchedBaseExercise);
    setAllExercisesForModal(getAllExercisesForAutocompleteGlobal()); // For modal autocomplete

    if (dayIdFromQuery) {
      // Determine the plan to use: specific if planId is in query, otherwise active plan
      const planToUse = planIdFromQuery ? getPlanById(planIdFromQuery)?.plan : getActiveNamedWorkoutPlan()?.plan;

      if (planToUse) {
          const fetchedWorkoutDay = getWorkoutByDayFromPlan(planToUse, dayIdFromQuery);
          setCurrentWorkoutDay(fetchedWorkoutDay);
          if (fetchedWorkoutDay) {
            const specificExerciseFromDay = fetchedWorkoutDay.exercises.find(ex => ex.id === exerciseId);
            setExerciseForLogging(specificExerciseFromDay);
            
            const initialEffectiveWeight = getUserTargetWeight(exerciseId, specificExerciseFromDay?.targetWeight || fetchedBaseExercise?.targetWeight);
            setManualTargetWeight(initialEffectiveWeight || '');

            if (typeof window !== 'undefined') {
              const dailyLogKey = getDailyLogLocalStorageKey(dayIdFromQuery, dateStr); // Key might need planId if logs are plan-specific
              const storedDailyLog = localStorage.getItem(dailyLogKey);
              if (storedDailyLog) {
                try {
                  const dailyLog: DailyLog = JSON.parse(storedDailyLog);
                  setLoggedExerciseData(dailyLog[exerciseId] || {});
                } catch (e) {
                  console.error("Failed to parse daily log for exercise detail:", e);
                  setLoggedExerciseData({});
                }
              } else {
                setLoggedExerciseData({});
              }
            }
          } else {
             setExerciseForLogging(null); // Exercise not found in this day's plan
          }
      } else {
         setCurrentWorkoutDay(null); // Plan not found
         setExerciseForLogging(null);
      }
    } else {
        // If no dayId, this page is likely for viewing library exercise, not logging
        setExerciseForLogging(fetchedBaseExercise); // Show base exercise, no logging context
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [exerciseId, dayIdFromQuery, planIdFromQuery]);

  const updateFullDailyLog = (updatedExerciseLog: LoggedExerciseData | null) => {
    if (typeof window === 'undefined' || !dayIdFromQuery || !currentDate) return;
    const dailyLogKey = getDailyLogLocalStorageKey(dayIdFromQuery, currentDate);
    let currentDailyLog: DailyLog = {};
    const storedLog = localStorage.getItem(dailyLogKey);
    if (storedLog) {
      try {
        currentDailyLog = JSON.parse(storedLog);
      } catch (e) { /* ignore parsing error, start fresh */ }
    }

    if (updatedExerciseLog === null || Object.keys(updatedExerciseLog).length === 0) {
      const { [exerciseId]: _, ...restDailyLog } = currentDailyLog;
      if (Object.keys(restDailyLog).length === 0) {
        localStorage.removeItem(dailyLogKey);
      } else {
        localStorage.setItem(dailyLogKey, JSON.stringify(restDailyLog));
      }
    } else {
      const newDailyLog = { ...currentDailyLog, [exerciseId]: updatedExerciseLog };
      localStorage.setItem(dailyLogKey, JSON.stringify(newDailyLog));
    }
  };

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
  
  const handleLogSet = (setId: string, log: LoggedSetData) => {
    const effectiveWeightForLog = manualTargetWeight || exerciseForLogging?.targetWeight || baseExercise?.targetWeight || 'N/A';
    const newLogEntry = { ...log, weight: effectiveWeightForLog };
    
    setLoggedExerciseData(prev => {
      const updatedLog = { ...prev, [setId]: newLogEntry };
      updateFullDailyLog(updatedLog);
      return updatedLog;
    });
  };
  
  const effectiveTargetWeightDisplay = useMemo(() => {
     return getUserTargetWeight(exerciseId, exerciseForLogging?.targetWeight || baseExercise?.targetWeight);
  }, [exerciseId, exerciseForLogging, baseExercise]);


  useEffect(() => {
    if (!isEditingTarget) {
        setManualTargetWeight(effectiveTargetWeightDisplay || '');
    }
  }, [effectiveTargetWeightDisplay, isEditingTarget]);


  const handleSaveManualTarget = () => {
    const currentWeight = getUserTargetWeight(exerciseId, exerciseForLogging?.targetWeight || baseExercise?.targetWeight);
    if (manualTargetWeight !== (currentWeight || '')) {
      setTargetWeightOverride(exerciseId, manualTargetWeight);
      
      const resetExerciseLog: LoggedExerciseData = {};
      exerciseForLogging?.sets.forEach(setDef => {
        resetExerciseLog[setDef.id] = {
          weight: manualTargetWeight,
          reps: '', 
          isCompleted: false
        };
      });
      setLoggedExerciseData(resetExerciseLog);
      updateFullDailyLog(resetExerciseLog);
      setForceSetEditKey(prev => prev + 1);
      setCanSuggestWeightIncrease(false); 
      toast({
        title: "Target Weight Updated",
        description: `New weight for ${baseExercise?.name} is ${manualTargetWeight}. Your sets for this session have been reset.`,
      });
    }
    setIsEditingTarget(false);
  };

  const handleCancelEditTarget = () => {
    setIsEditingTarget(false);
    const currentWeight = getUserTargetWeight(exerciseId, exerciseForLogging?.targetWeight || baseExercise?.targetWeight);
    setManualTargetWeight(currentWeight || '');
  };

  const isSkipped = useMemo(() => {
    if (!exerciseForLogging || exerciseForLogging.sets.length === 0 || !dayIdFromQuery) return false; // Skipping only relevant in logging context
    return exerciseForLogging.sets.every(set => loggedExerciseData[set.id]?.isCompleted === false) && Object.keys(loggedExerciseData).length > 0;
  }, [exerciseForLogging, loggedExerciseData, dayIdFromQuery]);

  const handleSkipExercise = () => {
    if (!exerciseForLogging) return;
    const skippedLog: LoggedExerciseData = {};
    exerciseForLogging.sets.forEach(set => {
      skippedLog[set.id] = { reps: loggedExerciseData[set.id]?.reps || '', weight: loggedExerciseData[set.id]?.weight, isCompleted: false };
    });
    setLoggedExerciseData(skippedLog);
    updateFullDailyLog(skippedLog);
    setIsEditingTarget(false);
    setCanSuggestWeightIncrease(false);
    setForceSetEditKey(prev => prev + 1);
    toast({ variant: "default", title: "Exercise Skipped", description: `"${baseExercise?.name}" marked as skipped.`});
  };

  const handleUnskipExercise = () => {
    setLoggedExerciseData({});
    updateFullDailyLog(null);
    setIsEditingTarget(false);
    setForceSetEditKey(prev => prev + 1);
    toast({ title: "Exercise Unskipped", description: `"${baseExercise?.name}" is no longer skipped.`});
  };

  const handleSaveEditedExercise = (updatedExercise: ExerciseType) => {
    // This function is now more complex as it needs to update the plan in workout-plan-service
    // For now, it will update the local view. Persisting plan changes is a larger task.
    setExerciseForLogging(updatedExercise);
    if (baseExercise && baseExercise.id === updatedExercise.id) {
      setBaseExercise(updatedExercise);
    }
    // TODO: Integrate with workout-plan-service to update the exercise definition in the active plan
    toast({
      title: "Exercise Updated (View)",
      description: `${updatedExercise.name} details updated for this view. For plan-wide changes, use 'Manage Workout Plans'.`,
    });
    setIsEditExerciseModalOpen(false);
  };


  if (!isClient || baseExercise === undefined || (dayIdFromQuery && exerciseForLogging === undefined && currentWorkoutDay !== null /* check if day was actually loaded */)) {
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
  
  if (dayIdFromQuery && !exerciseForLogging && currentWorkoutDay) { // currentWorkoutDay exists but exercise not found in it
     return (
      <div className="container mx-auto px-4 py-8 flex flex-col items-center text-center">
        <Dumbbell className="h-16 w-16 text-destructive mb-4" />
        <h1 className="text-2xl font-bold text-destructive mb-2">Exercise Not in Day's Plan</h1>
        <p className="text-muted-foreground mb-6">
          "{baseExercise.name}" (ID: {exerciseId}) is not part of the plan for "{currentWorkoutDay?.dayName || dayIdFromQuery}".
        </p>
         <Button asChild variant="outline" onClick={() => router.push('/dashboard/today')}>
           <span><ArrowLeft className="mr-2 h-4 w-4" /> Back to Today's Workout</span>
        </Button>
      </div>
    );
  }
  
  const displayExercise = exerciseForLogging || baseExercise; // Fallback to base if no specific logging context
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

      {exerciseForLogging && dayIdFromQuery && ( // Only show logging if in context of a workout day
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
                      value={manualTargetWeight}
                      onChange={(e) => setManualTargetWeight(e.target.value)}
                      className="h-8 text-sm flex-grow"
                      placeholder="e.g. 80 kg"
                      aria-label="Edit target weight"
                    />
                    <Button size="icon" variant="ghost" onClick={handleSaveManualTarget} className="h-8 w-8 text-primary shrink-0" aria-label="Save weight"><Save className="h-4 w-4" /></Button>
                    <Button size="icon" variant="ghost" onClick={handleCancelEditTarget} className="h-8 w-8 shrink-0" aria-label="Cancel edit weight"><XCircle className="h-4 w-4" /></Button>
                  </div>
                ) : (
                  <div className="flex items-center justify-between mt-1">
                    <div className="flex items-center gap-2">
                        <p className="text-sm font-semibold text-foreground">{manualTargetWeight || 'Not set'}</p>
                        {canSuggestWeightIncrease && (
                           <Badge variant="default" className="px-1.5 py-0.5 text-xs bg-green-600 hover:bg-green-700 text-white">
                              <ArrowUpCircle className="h-3 w-3 mr-0.5" /> Suggest Inc.
                           </Badge>
                        )}
                    </div>
                    <Button size="icon" variant="ghost" onClick={() => setIsEditingTarget(true)} className="h-8 w-8 shrink-0" aria-label="Edit weight"><Edit className="h-4 w-4" /></Button>
                  </div>
                )}
              </div>
            )}
          </CardHeader>
          <CardContent className={cn("p-0", isSkipped && "opacity-40 pointer-events-none")}>
            {exerciseForLogging.sets.map((set, index) => {
              const lastSessionSetPerformance = getPreviousSetPerformance(exerciseId, set.id, exerciseForLogging.sets);
              return (
                <SetLogger
                  key={`${set.id}-${forceSetEditKey}`}
                  setNumber={index + 1}
                  setData={set}
                  loggedSetData={loggedExerciseData?.[set.id]}
                  lastSessionSetPerformance={lastSessionSetPerformance}
                  effectiveTargetWeight={manualTargetWeight}
                  onLogSet={(logData) => handleLogSet(set.id, logData)}
                  exerciseUnit={exerciseForLogging.unit || baseExercise.unit}
                  isSimpleLog={isSpecialActivity}
                  isEditingInitially={!loggedExerciseData?.[set.id]?.isCompleted || (forceSetEditKey > 0 && !!loggedExerciseData?.[set.id]?.isCompleted)}
                />
              );
            })}
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
            loggedExerciseData={loggedExerciseData}
            isOpen={isAIRecModalOpen}
            onOpenChange={setIsAIRecModalOpen}
        />
      )}
      {exerciseForLogging && dayIdFromQuery && ( // Only allow editing if in context of a day's plan
        <AddExerciseModal
          isOpen={isEditExerciseModalOpen}
          onOpenChange={setIsEditExerciseModalOpen}
          onSave={handleSaveEditedExercise}
          allExercises={allExercisesForModal}
          dayId={dayIdFromQuery} // This is crucial
          initialData={exerciseForLogging} 
        />
      )}
    </div>
  );
}
