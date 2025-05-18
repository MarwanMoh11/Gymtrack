
// src/app/exercises/[exerciseId]/page.tsx
'use client';

import { useState, useEffect, useCallback, useMemo } from 'react';
import Link from 'next/link';
import { useSearchParams, useRouter } from 'next/navigation';
import { getExerciseById as getBaseExerciseById, getWorkoutByDay } from '@/data/workout-data';
import type { Exercise as ExerciseType, SetData, LoggedSetData, DailyLog, WorkoutDay, LoggedExerciseData } from '@/types/workout';
import { Card, CardContent, CardDescription, CardHeader, CardTitle, CardFooter } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Separator } from '@/components/ui/separator';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { ArrowLeft, Dumbbell, Wand2, Sparkles, CheckCircle, Edit, Save, XCircle, XSquare, Undo2, Lock, Info } from 'lucide-react';
import SetLogger from '@/components/workout/set-logger';
import AIRecommendationModal from '@/components/workout/ai-recommendation-modal';
import { getUserTargetWeight, setTargetWeightOverride } from '@/lib/user-settings';
import { useToast } from '@/hooks/use-toast';
import LoadingExercisePage from './loading'; // Reuse loading page for structure
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
  return `gymtrack_log_${dayId}_${date}`;
}

// Helper to parse target reps from ExerciseCard, adapted for this page
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

export default function ExerciseDetailPage({ params }: ExercisePageProps) {
  const router = useRouter();
  const searchParams = useSearchParams();
  const dayIdFromQuery = searchParams.get('dayId');
  
  const [baseExercise, setBaseExercise] = useState<ExerciseType | null | undefined>(undefined);
  const [currentWorkoutDay, setCurrentWorkoutDay] = useState<WorkoutDay | null | undefined>(undefined);
  const [exerciseForLogging, setExerciseForLogging] = useState<ExerciseType | null | undefined>(undefined);
  
  const [loggedExerciseData, setLoggedExerciseData] = useState<LoggedExerciseData>({});
  const [isClient, setIsClient] = useState(false);
  const [currentDate, setCurrentDate] = useState('');
  
  const [isAIRecModalOpen, setIsAIRecModalOpen] = useState(false);
  const [isEditingTarget, setIsEditingTarget] = useState(false);
  const [manualTargetWeight, setManualTargetWeight] = useState('');
  const [forceSetEditKey, setForceSetEditKey] = useState(0); // To re-render SetLoggers
  const [canSuggestWeightIncrease, setCanSuggestWeightIncrease] = useState(false);

  const { toast } = useToast();

  // Initial data fetching and state setup
  useEffect(() => {
    setIsClient(true);
    const dateStr = getCurrentDateString();
    setCurrentDate(dateStr);

    const fetchedBaseExercise = getBaseExerciseById(params.exerciseId);
    setBaseExercise(fetchedBaseExercise);

    if (dayIdFromQuery) {
      const fetchedWorkoutDay = getWorkoutByDay(dayIdFromQuery);
      setCurrentWorkoutDay(fetchedWorkoutDay);
      if (fetchedWorkoutDay) {
        const specificExerciseFromDay = fetchedWorkoutDay.exercises.find(ex => ex.id === params.exerciseId);
        setExerciseForLogging(specificExerciseFromDay);
        
        const initialEffectiveWeight = getUserTargetWeight(params.exerciseId, specificExerciseFromDay?.targetWeight || fetchedBaseExercise?.targetWeight);
        setManualTargetWeight(initialEffectiveWeight || '');

        // Load log for this specific exercise from the daily log
        if (typeof window !== 'undefined') {
          const dailyLogKey = getDailyLogLocalStorageKey(dayIdFromQuery, dateStr);
          const storedDailyLog = localStorage.getItem(dailyLogKey);
          if (storedDailyLog) {
            try {
              const dailyLog: DailyLog = JSON.parse(storedDailyLog);
              setLoggedExerciseData(dailyLog[params.exerciseId] || {});
            } catch (e) {
              console.error("Failed to parse daily log for exercise detail:", e);
              setLoggedExerciseData({});
            }
          } else {
            setLoggedExerciseData({});
          }
        }
      }
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [params.exerciseId, dayIdFromQuery]);

  // Utility function to update the full daily log in localStorage
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
      // If exercise log is null or empty, remove it from daily log
      const { [params.exerciseId]: _, ...restDailyLog } = currentDailyLog;
      if (Object.keys(restDailyLog).length === 0) {
        localStorage.removeItem(dailyLogKey);
      } else {
        localStorage.setItem(dailyLogKey, JSON.stringify(restDailyLog));
      }
    } else {
      const newDailyLog = { ...currentDailyLog, [params.exerciseId]: updatedExerciseLog };
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
      updateFullDailyLog(updatedLog); // Save to localStorage
      return updatedLog;
    });
  };
  
  const effectiveTargetWeightDisplay = useMemo(() => {
     return getUserTargetWeight(params.exerciseId, exerciseForLogging?.targetWeight || baseExercise?.targetWeight);
  }, [params.exerciseId, exerciseForLogging, baseExercise, manualTargetWeight, isEditingTarget]);


  useEffect(() => {
    // Update manualTargetWeight input when effectiveTargetWeightDisplay changes (e.g. due to external override or initial load)
    // but only if not currently editing, to avoid overwriting user input.
    if (!isEditingTarget) {
        setManualTargetWeight(effectiveTargetWeightDisplay || '');
    }
  }, [effectiveTargetWeightDisplay, isEditingTarget]);


  const handleSaveManualTarget = () => {
    const currentWeight = getUserTargetWeight(params.exerciseId, exerciseForLogging?.targetWeight || baseExercise?.targetWeight);
    if (manualTargetWeight !== (currentWeight || '')) {
      setTargetWeightOverride(params.exerciseId, manualTargetWeight);
      
      // Reset reps for this exercise
      const resetExerciseLog: LoggedExerciseData = {};
      exerciseForLogging?.sets.forEach(setDef => {
        resetExerciseLog[setDef.id] = {
          weight: manualTargetWeight, // New weight for future logs
          reps: '',
          isCompleted: false
        };
      });
      setLoggedExerciseData(resetExerciseLog);
      updateFullDailyLog(resetExerciseLog);
      setForceSetEditKey(prev => prev + 1);
      setCanSuggestWeightIncrease(false);
      toast({
        title: "Plan Updated",
        description: `Target weight for ${baseExercise?.name} updated to ${manualTargetWeight}. Reps for this session have been reset.`,
      });
    }
    setIsEditingTarget(false);
  };

  const handleCancelEditTarget = () => {
    setIsEditingTarget(false);
    const currentWeight = getUserTargetWeight(params.exerciseId, exerciseForLogging?.targetWeight || baseExercise?.targetWeight);
    setManualTargetWeight(currentWeight || '');
  };

  const isSkipped = useMemo(() => {
    if (!exerciseForLogging || exerciseForLogging.sets.length === 0) return false;
    return exerciseForLogging.sets.every(set => loggedExerciseData[set.id]?.isCompleted === false) && Object.keys(loggedExerciseData).length > 0;
  }, [exerciseForLogging, loggedExerciseData]);

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
    setLoggedExerciseData({}); // Clear local log for this exercise
    updateFullDailyLog(null); // Signal to remove this exercise's log from the daily log
    setIsEditingTarget(false);
    setForceSetEditKey(prev => prev + 1);
    toast({ title: "Exercise Unskipped", description: `"${baseExercise?.name}" is no longer skipped.`});
  };

  if (!isClient || baseExercise === undefined || (dayIdFromQuery && exerciseForLogging === undefined)) {
    return <LoadingExercisePage />;
  }

  if (!baseExercise) {
    return (
      <div className="container mx-auto px-4 py-8 flex flex-col items-center text-center">
        <Dumbbell className="h-16 w-16 text-destructive mb-4" />
        <h1 className="text-2xl font-bold text-destructive mb-2">Exercise Not Found</h1>
        <p className="text-muted-foreground mb-6">
          The exercise with ID "{params.exerciseId}" could not be found in the base library.
        </p>
        <Button asChild variant="outline" onClick={() => router.back()}>
          <ArrowLeft className="mr-2 h-4 w-4" /> Go Back
        </Button>
      </div>
    );
  }
  
  if (dayIdFromQuery && !exerciseForLogging) {
     return (
      <div className="container mx-auto px-4 py-8 flex flex-col items-center text-center">
        <Dumbbell className="h-16 w-16 text-destructive mb-4" />
        <h1 className="text-2xl font-bold text-destructive mb-2">Exercise Not in Day's Plan</h1>
        <p className="text-muted-foreground mb-6">
          "{baseExercise.name}" (ID: {params.exerciseId}) is not part of the plan for "{dayIdFromQuery}".
        </p>
         <Button asChild variant="outline" onClick={() => router.push('/dashboard/today')}>
          <ArrowLeft className="mr-2 h-4 w-4" /> Back to Today's Workout
        </Button>
      </div>
    );
  }

  const displayExercise = exerciseForLogging || baseExercise; // Use day-specific if available for sets, else base for info
  const hasVideo = displayExercise.videoUrl && displayExercise.videoUrl.includes('youtube.com/embed');
  const allSetsCompletedCheck = exerciseForLogging?.sets.every(set => loggedExerciseData?.[set.id]?.isCompleted);
  
  const isSpecialActivity = displayExercise.isActivity || displayExercise.isConditioning || displayExercise.isWarmup || displayExercise.isMatch || displayExercise.isStretch || displayExercise.isFoamRoll || displayExercise.isRecovery;
  const canShowAISuggestionButton = !isSpecialActivity && !displayExercise.isCore && !isSkipped;

  return (
    <div className="container mx-auto max-w-3xl px-4 py-8 space-y-6">
      <div className="flex items-center justify-between">
        <Button asChild variant="ghost" size="sm" onClick={() => router.back()} className="mr-auto">
            <ArrowLeft className="mr-2 h-4 w-4" /> Back to Workout
        </Button>
        {isSkipped && (
            <Badge variant="destructive" className="text-xs font-normal">
                <Lock className="h-3 w-3 mr-1" /> Skipped
            </Badge>
        )}
      </div>

      <Card className="shadow-lg rounded-2xl">
        <CardHeader>
          <CardTitle className="text-2xl font-bold text-primary flex items-center">
             <Dumbbell className="mr-3 h-7 w-7" />
             {displayExercise.name}
          </CardTitle>
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

      {/* Logging Section */}
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
              // For previous set performance, we'd need more complex historical data lookup.
              // For now, pass undefined or a simplified version if available.
              // const lastSessionSetPerformance = getPreviousSetPerformance(exerciseForLogging.id, set.id, exerciseForLogging.sets);
              return (
                <SetLogger
                  key={`${set.id}-${forceSetEditKey}`}
                  setNumber={index + 1}
                  setData={set}
                  loggedSetData={loggedExerciseData?.[set.id]}
                  // lastSessionSetPerformance={lastSessionSetPerformance} // Needs robust implementation
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
      {canShowAISuggestionButton && exerciseForLogging && (
         <AIRecommendationModal
            exercise={exerciseForLogging}
            loggedExerciseData={loggedExerciseData}
            isOpen={isAIRecModalOpen}
            onOpenChange={setIsAIRecModalOpen}
        />
      )}
    </div>
  );
}
    