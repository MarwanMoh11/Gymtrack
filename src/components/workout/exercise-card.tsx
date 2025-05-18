
'use client';

import { useState, useEffect, useMemo, useCallback } from 'react';
import { Card, CardHeader, CardTitle, CardContent, CardDescription, CardFooter } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Wand2, CheckCircle, XCircle, Edit, Save, ArrowUpCircle, Sparkles, RotateCcw } from 'lucide-react'; // Added Sparkles, RotateCcw
import type { Exercise, LoggedExerciseData, LoggedSetData, SetData } from '@/types/workout';
import SetLogger from './set-logger';
import AIRecommendationModal from './ai-recommendation-modal';
import { getPreviousSetPerformance } from '@/lib/workout-utils'; // Added getPreviousSetPerformance
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
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
} from "@/components/ui/alert-dialog"


// Helper function to parse target reps (handles numbers, strings like '8-10', '10+')
const parseMaxTargetReps = (target: string | number): number | null => {
    if (typeof target === 'number') {
        return target;
    }
    if (typeof target === 'string') {
        // Check for range like "8-10"
        const rangeMatch = target.match(/(\d+)\s*-\s*(\d+)/);
        if (rangeMatch) {
            return Math.max(parseInt(rangeMatch[1], 10), parseInt(rangeMatch[2], 10));
        }
        // Check for minimum like "10+"
        const minMatch = target.match(/(\d+)\+/);
        if (minMatch) {
            // Treat the minimum as the target to exceed for now
            return parseInt(minMatch[1], 10);
        }
        // Check for simple number string
        const numMatch = target.match(/^(\d+)$/);
        if (numMatch) {
            return parseInt(numMatch[1], 10);
        }
        // 'to failure' or other text -> cannot determine max target numerically
        if (target.toLowerCase().includes('failure') || target.toLowerCase().includes('min') || target.toLowerCase().includes('—')) {
             return null; // Cannot suggest increase based on this
        }
    }
    // Try parsing as a simple number if other formats fail
    const parsed = parseInt(String(target), 10);
    return isNaN(parsed) ? null : parsed;
};


interface ExerciseCardProps {
  exercise: Exercise;
  effectiveTargetWeight?: string; // User's current planned target (from localStorage or default)
  onLogSet: (exerciseId: string, setId: string, log: LoggedSetData) => void;
  loggedData?: LoggedExerciseData;
  onUpdateEffectiveTargetWeight: (exerciseId: string, newWeight: string) => void;
  triggerRepReset: (exerciseId: string) => void; // Callback to trigger rep reset in parent
  onClearExerciseLog: (exerciseId: string) => void; // Callback to clear log for this exercise
}

export default function ExerciseCard({
  exercise,
  effectiveTargetWeight,
  onLogSet,
  loggedData,
  onUpdateEffectiveTargetWeight,
  triggerRepReset,
  onClearExerciseLog,
}: ExerciseCardProps) {
  const [isAIRecModalOpen, setIsAIRecModalOpen] = useState(false);
  const [isEditingTarget, setIsEditingTarget] = useState(false);
  const [manualTargetWeight, setManualTargetWeight] = useState(effectiveTargetWeight || exercise.targetWeight || '');
  const [forceSetEditKey, setForceSetEditKey] = useState(0);
  const [canSuggestWeightIncrease, setCanSuggestWeightIncrease] = useState(false);


  // Function to check if weight increase can be suggested based on PLAN targets
  const checkCompletionAndPlanReps = useCallback((currentLogData?: LoggedExerciseData) => {
    if (!currentLogData || exercise.sets.length === 0) return false;

    const allSetsCompleted = exercise.sets.every(set => currentLogData[set.id]?.isCompleted);
    if (!allSetsCompleted) return false;

    for (const set of exercise.sets) {
      const loggedSet = currentLogData[set.id];
      const maxTarget = parseMaxTargetReps(set.targetReps); // Plan's target reps
      const loggedRepsNum = loggedSet?.reps !== undefined ? parseInt(String(loggedSet.reps), 10) : NaN;

      if (maxTarget === null) continue;

      if (isNaN(loggedRepsNum) || loggedRepsNum < maxTarget) {
        return false;
      }
    }
    return true;
  }, [exercise.sets]);


  // Update suggestion state when loggedData changes
  useEffect(() => {
    setCanSuggestWeightIncrease(checkCompletionAndPlanReps(loggedData));
  }, [loggedData, checkCompletionAndPlanReps]);


  // Update local manual input if the effective target changes externally
  useEffect(() => {
    setManualTargetWeight(effectiveTargetWeight || exercise.targetWeight || '');
  }, [effectiveTargetWeight, exercise.targetWeight]);


  const handleLogSet = (setId: string, log: LoggedSetData) => {
    const weightToLog = effectiveTargetWeight || exercise.targetWeight || 'N/A';
    const newLog = { ...log, weight: weightToLog };
    onLogSet(exercise.id, setId, newLog);

    const nextLogState = {
        ...(loggedData || {}),
        [setId]: newLog
    };
    setCanSuggestWeightIncrease(checkCompletionAndPlanReps(nextLogState));
  };


  const handleSaveManualTarget = () => {
    const currentWeight = effectiveTargetWeight || exercise.targetWeight || '';
    if (manualTargetWeight !== currentWeight) {
      onUpdateEffectiveTargetWeight(exercise.id, manualTargetWeight);
      triggerRepReset(exercise.id);
      setForceSetEditKey(prev => prev + 1);
      setCanSuggestWeightIncrease(false);
    }
    setIsEditingTarget(false);
  };

  const handleCancelEdit = () => {
    setIsEditingTarget(false);
    setManualTargetWeight(effectiveTargetWeight || exercise.targetWeight || '');
  };

  const handleClearLogPress = () => {
    onClearExerciseLog(exercise.id);
    // Optionally, reset local UI states if needed, e.g., close editing mode
    setIsEditingTarget(false);
    setCanSuggestWeightIncrease(false); // Re-evaluate this after log clears
    setForceSetEditKey(prev => prev + 1); // Force re-render of set loggers
  };

  const isSpecialActivity = exercise.isActivity || exercise.isConditioning || exercise.isWarmup || exercise.isMatch || exercise.isStretch || exercise.isFoamRoll || exercise.isRecovery;
  const canShowAIButton = !isSpecialActivity && !exercise.isCore;
  const allSetsCompletedCheck = useMemo(() => {
     return exercise.sets.every(set => loggedData?.[set.id]?.isCompleted);
  }, [exercise.sets, loggedData]);


  const currentPlanTargetToDisplay = effectiveTargetWeight || exercise.targetWeight;

  const renderTargetWeightControls = () => {
    if (isSpecialActivity || exercise.isCore) return null;

    return (
      <div className="mt-2 mb-1 p-3 bg-secondary/30 rounded-md border border-secondary/50">
        <Label className="text-xs font-medium text-muted-foreground">Planned Weight for Today</Label>
        {isEditingTarget ? (
          <div className="flex items-center gap-2 mt-1">
            <Input
              type="text"
              value={manualTargetWeight}
              onChange={(e) => setManualTargetWeight(e.target.value)}
              className="h-8 text-sm flex-grow"
              placeholder="e.g. 80 kg or Bodyweight"
              aria-label="Edit target weight"
            />
            <Button size="icon" variant="ghost" onClick={handleSaveManualTarget} className="h-8 w-8 text-primary shrink-0" aria-label="Save weight">
              <Save className="h-4 w-4" />
            </Button>
            <Button size="icon" variant="ghost" onClick={handleCancelEdit} className="h-8 w-8 shrink-0" aria-label="Cancel edit weight">
              <XCircle className="h-4 w-4" />
            </Button>
          </div>
        ) : (
          <div className="flex items-center justify-between mt-1">
             <div className="flex items-center gap-2">
                <p className="text-sm font-semibold text-foreground">{currentPlanTargetToDisplay || 'Not set'}</p>
                {canSuggestWeightIncrease && (
                   <Badge variant="default" className="px-1.5 py-0.5 text-xs bg-green-600 hover:bg-green-700 text-white">
                      <ArrowUpCircle className="h-3 w-3 mr-0.5" /> Suggest Inc.
                   </Badge>
                )}
             </div>
            <Button size="icon" variant="ghost" onClick={() => setIsEditingTarget(true)} className="h-8 w-8 shrink-0" aria-label="Edit weight">
              <Edit className="h-4 w-4" />
            </Button>
          </div>
        )}
      </div>
    );
  };

  return (
    <Card className="mb-6 shadow-md hover:shadow-lg transition-shadow duration-300">
      <CardHeader className="pb-2">
        <div className="flex justify-between items-start">
          <div>
            <CardTitle className="text-xl font-semibold text-foreground">
              {exercise.name}
            </CardTitle>
            {!(isSpecialActivity || exercise.isCore) && exercise.targetWeight && !currentPlanTargetToDisplay && (
                <CardDescription className="text-xs text-muted-foreground/70">
                    Base Plan: {exercise.targetWeight}
                </CardDescription>
            )}
          </div>
          <div className="flex items-center gap-2">
            {exercise.notes && (
                <Badge variant="secondary" className="whitespace-nowrap ml-2 shrink-0 text-xs">{exercise.notes}</Badge>
            )}
            <AlertDialog>
                <AlertDialogTrigger asChild>
                    <Button variant="ghost" size="icon" className="h-7 w-7 text-muted-foreground hover:text-destructive shrink-0">
                        <RotateCcw className="h-4 w-4" />
                        <span className="sr-only">Clear Log for {exercise.name}</span>
                    </Button>
                </AlertDialogTrigger>
                <AlertDialogContent>
                    <AlertDialogHeader>
                    <AlertDialogTitle>Clear Exercise Log?</AlertDialogTitle>
                    <AlertDialogDescription>
                        This will mark all sets for "{exercise.name}" as incomplete for today.
                        Your logged reps/weight for individual sets will be kept if you decide to log them again.
                        Are you sure you want to clear progress for this exercise?
                    </AlertDialogDescription>
                    </AlertDialogHeader>
                    <AlertDialogFooter>
                    <AlertDialogCancel>Cancel</AlertDialogCancel>
                    <AlertDialogAction onClick={handleClearLogPress} className="bg-destructive hover:bg-destructive/90 text-destructive-foreground">
                        Clear Log
                    </AlertDialogAction>
                    </AlertDialogFooter>
                </AlertDialogContent>
            </AlertDialog>
          </div>
        </div>
        {renderTargetWeightControls()}
      </CardHeader>
      <CardContent className="p-0">
        {exercise.sets.map((set, index) => {
          const lastSessionSetPerformance = getPreviousSetPerformance(exercise.id, set.id, exercise.sets);
          const currentLoggedSetData = loggedData?.[set.id];
          // Determine initial edit state: if not completed, or if forceSetEditKey changed AND it was completed (to allow re-editing a completed set after weight change)
          const isEditingInitially = !currentLoggedSetData?.isCompleted || (forceSetEditKey > 0 && !!currentLoggedSetData?.isCompleted);


          return (
            <SetLogger
              key={`${set.id}-${forceSetEditKey}`}
              setNumber={index + 1}
              setData={set}
              loggedSetData={currentLoggedSetData}
              lastSessionSetPerformance={lastSessionSetPerformance} // Pass last session's data for this set
              effectiveTargetWeight={currentPlanTargetToDisplay}
              onLogSet={(log) => handleLogSet(set.id, log)}
              exerciseUnit={exercise.unit}
              isSimpleLog={isSpecialActivity}
              isEditingInitially={isEditingInitially}
            />
          );
        })}
      </CardContent>
      {canShowAIButton && (
        <CardFooter className="pt-4 justify-end">
          <Button
            variant="outline"
            size="sm"
            onClick={() => setIsAIRecModalOpen(true)}
            disabled={!allSetsCompletedCheck}
            className="bg-accent/20 hover:bg-accent/30 text-accent-foreground border-accent/50"
            >
            <Sparkles className="mr-2 h-4 w-4" /> {/* Changed Icon */}
            AI Weight Advice
          </Button>
        </CardFooter>
      )}
      {canShowAIButton && (
         <AIRecommendationModal
            exercise={exercise}
            loggedExerciseData={loggedData}
            isOpen={isAIRecModalOpen}
            onOpenChange={setIsAIRecModalOpen}
        />
      )}
    </Card>
  );
}

