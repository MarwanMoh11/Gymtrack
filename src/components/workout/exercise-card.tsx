
'use client';

import { useState, useEffect } from 'react';
import { Card, CardHeader, CardTitle, CardContent, CardDescription, CardFooter } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Wand2, CheckCircle, XCircle, Edit, Save, Loader2 } from 'lucide-react';
import type { Exercise, LoggedExerciseData, LoggedSetData } from '@/types/workout';
import SetLogger from './set-logger';
import AIRecommendationModal from './ai-recommendation-modal';
import type { NextSessionRecommendationOutput } from '@/ai/flows/next-session-recommendation';
import { parseWeightToNumber } from '@/lib/workout-utils';
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


interface ExerciseCardProps {
  exercise: Exercise;
  effectiveTargetWeight?: string; // User's current planned target (from localStorage or default)
  onLogSet: (exerciseId: string, setId: string, log: LoggedSetData) => void;
  loggedData?: LoggedExerciseData;
  aiSuggestionForToday?: NextSessionRecommendationOutput | null;
  isLoadingAISuggestion?: boolean;
  onUpdateEffectiveTargetWeight: (exerciseId: string, newWeight: string) => void;
  triggerRepReset: (exerciseId: string) => void; // Callback to trigger rep reset in parent
}

export default function ExerciseCard({ 
  exercise, 
  effectiveTargetWeight,
  onLogSet, 
  loggedData, 
  aiSuggestionForToday,
  isLoadingAISuggestion,
  onUpdateEffectiveTargetWeight,
  triggerRepReset
}: ExerciseCardProps) {
  const [isAIRecModalOpen, setIsAIRecModalOpen] = useState(false);
  const [isEditingTarget, setIsEditingTarget] = useState(false);
  const [manualTargetWeight, setManualTargetWeight] = useState(effectiveTargetWeight || exercise.targetWeight || '');
  // State to manage forced edit state for SetLoggers after weight change
  const [forceSetEditKey, setForceSetEditKey] = useState(0); 

  useEffect(() => {
    // Update local manual input if the effective target changes externally (e.g., AI accept)
    setManualTargetWeight(effectiveTargetWeight || exercise.targetWeight || '');
  }, [effectiveTargetWeight, exercise.targetWeight]);


  const handleLogSet = (setId: string, log: LoggedSetData) => {
    // Ensure the log includes the weight used for the exercise at the time of logging
    const weightToLog = effectiveTargetWeight || exercise.targetWeight || 'N/A';
    onLogSet(exercise.id, setId, { ...log, weight: weightToLog });
  };

  const handleAcceptAISuggestion = () => {
    if (aiSuggestionForToday?.suggestedWeight) {
      const newWeight = aiSuggestionForToday.suggestedWeight;
      onUpdateEffectiveTargetWeight(exercise.id, newWeight); // Update in localStorage/parent state
      setManualTargetWeight(newWeight); // Update local input field state
      setIsEditingTarget(false);
      triggerRepReset(exercise.id); // Ask parent to reset reps in dailyLog
      setForceSetEditKey(prev => prev + 1); // Force SetLoggers to re-evaluate initial edit state
    }
  };

  const handleSaveManualTarget = () => {
    const currentWeight = effectiveTargetWeight || exercise.targetWeight || '';
    // Only trigger reset if the weight actually changed
    if (manualTargetWeight !== currentWeight) {
      onUpdateEffectiveTargetWeight(exercise.id, manualTargetWeight);
      triggerRepReset(exercise.id); // Ask parent to reset reps in dailyLog
      setForceSetEditKey(prev => prev + 1); // Force SetLoggers to re-evaluate initial edit state
    }
    setIsEditingTarget(false);
  };

  const handleCancelEdit = () => {
    setIsEditingTarget(false);
    setManualTargetWeight(effectiveTargetWeight || exercise.targetWeight || ''); // Reset input to current effective weight
  };

  const isSpecialActivity = exercise.isActivity || exercise.isConditioning || exercise.isWarmup || exercise.isMatch || exercise.isStretch || exercise.isFoamRoll || exercise.isRecovery;
  const canShowAIButton = !isSpecialActivity && !exercise.isCore;
  const allSetsCompleted = exercise.sets.every(set => loggedData?.[set.id]?.isCompleted);

  const currentPlanTargetToDisplay = effectiveTargetWeight || exercise.targetWeight;

  const renderTargetWeightControls = () => {
    if (isSpecialActivity || exercise.isCore) return null; // No target editing for these

    const aiSuggestsDifferent = aiSuggestionForToday?.suggestedWeight && 
                                parseWeightToNumber(aiSuggestionForToday.suggestedWeight, exercise.name) !== parseWeightToNumber(currentPlanTargetToDisplay, exercise.name);

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
            <p className="text-sm font-semibold text-foreground">{currentPlanTargetToDisplay || 'Not set'}</p>
            <Button size="icon" variant="ghost" onClick={() => setIsEditingTarget(true)} className="h-8 w-8 shrink-0" aria-label="Edit weight">
              <Edit className="h-4 w-4" />
            </Button>
          </div>
        )}

        {isLoadingAISuggestion && !isEditingTarget && (
           <p className="text-xs text-primary/80 flex items-center mt-1"><Loader2 className="h-3 w-3 animate-spin mr-1" /> Checking AI for today...</p>
        )}

        {aiSuggestionForToday?.suggestedWeight && !isEditingTarget && (
          <div className="mt-2 pt-2 border-t border-secondary">
             <p className="text-xs text-muted-foreground mb-1">AI Suggestion for Today:</p>
            <div className="flex items-center justify-between gap-2">
              <span className={`text-sm font-semibold ${aiSuggestsDifferent ? 'text-primary' : 'text-foreground'}`}>
                {aiSuggestionForToday.suggestedWeight} for {aiSuggestionForToday.suggestedReps}
              </span>
              {aiSuggestsDifferent && (
                <AlertDialog>
                  <AlertDialogTrigger asChild>
                    <Button size="sm" variant="outline" className="text-xs h-7 border-primary text-primary hover:bg-primary/10 shrink-0">
                      <CheckCircle className="h-3 w-3 mr-1" /> Use AI
                    </Button>
                  </AlertDialogTrigger>
                  <AlertDialogContent>
                    <AlertDialogHeader>
                      <AlertDialogTitle>Confirm Target Update</AlertDialogTitle>
                      <AlertDialogDescription>
                        Set today's planned weight for {exercise.name} to {aiSuggestionForToday.suggestedWeight}? This will reset the logged reps for today's sets, requiring you to re-log them with the new weight.
                      </AlertDialogDescription>
                    </AlertDialogHeader>
                    <AlertDialogFooter>
                      <AlertDialogCancel>Cancel</AlertDialogCancel>
                      <AlertDialogAction onClick={handleAcceptAISuggestion}>Confirm & Reset Reps</AlertDialogAction>
                    </AlertDialogFooter>
                  </AlertDialogContent>
                </AlertDialog>
              )}
            </div>
            <p className="text-xs text-muted-foreground italic mt-0.5">{aiSuggestionForToday.reasoning}</p>
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
            {!(isSpecialActivity || exercise.isCore) && exercise.targetWeight && !currentPlanTargetToDisplay && ( // Show base plan if no override
                <CardDescription className="text-xs text-muted-foreground/70">
                    Base Plan: {exercise.targetWeight}
                </CardDescription>
            )}
          </div>
          {exercise.notes && (
            <Badge variant="secondary" className="whitespace-nowrap ml-2 shrink-0 text-xs">{exercise.notes}</Badge>
          )}
        </div>
        {renderTargetWeightControls()}
      </CardHeader>
      <CardContent className="p-0">
        {exercise.sets.map((set, index) => {
          const previousSetId = index > 0 ? exercise.sets[index - 1].id : undefined;
          const previousLoggedReps = previousSetId ? loggedData?.[previousSetId]?.reps : undefined;
          const currentLoggedSetData = loggedData?.[set.id];
          // Determine if the set logger should be in editing mode
          // It should be editing if not completed, OR if the forceSetEditKey has changed (meaning weight was updated)
          const isEditingInitially = !currentLoggedSetData?.isCompleted || (forceSetEditKey > 0 && currentLoggedSetData?.isCompleted);

          return (
            <SetLogger
              key={`${set.id}-${forceSetEditKey}`} // Include key to force re-render on weight change
              setNumber={index + 1}
              setData={set} // Pass the original set definition
              loggedSetData={currentLoggedSetData}
              previousLoggedReps={previousLoggedReps}
              effectiveTargetWeight={currentPlanTargetToDisplay} // Pass the effective weight for logging
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
            disabled={!allSetsCompleted} // Keep disabled logic based on completion status before potential reset
            className="bg-accent/20 hover:bg-accent/30 text-accent-foreground border-accent/50"
            >
            <Wand2 className="mr-2 h-4 w-4" />
            AI Advice for Next Workout
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
