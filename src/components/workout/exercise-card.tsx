
'use client';

import { useState, useEffect } from 'react';
import { Card, CardHeader, CardTitle, CardContent, CardDescription, CardFooter } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Wand2, CheckCircle, XCircle, Edit, Save, MinusCircle, Loader2, TrendingUp } from 'lucide-react';
import type { Exercise, SetData, LoggedExerciseData, LoggedSetData } from '@/types/workout';
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
}

export default function ExerciseCard({ 
  exercise, 
  effectiveTargetWeight,
  onLogSet, 
  loggedData, 
  aiSuggestionForToday,
  isLoadingAISuggestion,
  onUpdateEffectiveTargetWeight
}: ExerciseCardProps) {
  const [isAIRecModalOpen, setIsAIRecModalOpen] = useState(false);
  const [isEditingTarget, setIsEditingTarget] = useState(false);
  const [manualTargetWeight, setManualTargetWeight] = useState(effectiveTargetWeight || exercise.targetWeight || '');
  
  useEffect(() => {
    setManualTargetWeight(effectiveTargetWeight || exercise.targetWeight || '');
  }, [effectiveTargetWeight, exercise.targetWeight]);

  const handleLogSet = (setId: string, log: LoggedSetData) => {
    onLogSet(exercise.id, setId, log);
  };

  const handleAcceptAISuggestion = () => {
    if (aiSuggestionForToday?.suggestedWeight) {
      onUpdateEffectiveTargetWeight(exercise.id, aiSuggestionForToday.suggestedWeight);
      setManualTargetWeight(aiSuggestionForToday.suggestedWeight); // also update local state for input field
      setIsEditingTarget(false);
    }
  };

  const handleSaveManualTarget = () => {
    onUpdateEffectiveTargetWeight(exercise.id, manualTargetWeight);
    setIsEditingTarget(false);
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
        <Label className="text-xs font-medium text-muted-foreground">Planned Target for Today</Label>
        {isEditingTarget ? (
          <div className="flex items-center gap-2 mt-1">
            <Input 
              type="text" 
              value={manualTargetWeight} 
              onChange={(e) => setManualTargetWeight(e.target.value)}
              className="h-8 text-sm flex-grow"
              placeholder="e.g. 80 kg or Bodyweight"
            />
            <Button size="icon" variant="ghost" onClick={handleSaveManualTarget} className="h-8 w-8 text-primary">
              <Save className="h-4 w-4" />
            </Button>
            <Button size="icon" variant="ghost" onClick={() => {setIsEditingTarget(false); setManualTargetWeight(currentPlanTargetToDisplay || '');}} className="h-8 w-8">
              <XCircle className="h-4 w-4" />
            </Button>
          </div>
        ) : (
          <div className="flex items-center justify-between mt-1">
            <p className="text-sm font-semibold text-foreground">{currentPlanTargetToDisplay || 'Not set'}</p>
            <Button size="icon" variant="ghost" onClick={() => setIsEditingTarget(true)} className="h-8 w-8">
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
            <div className="flex items-center justify-between">
              <span className={`text-sm font-semibold ${aiSuggestsDifferent ? 'text-primary' : 'text-foreground'}`}>
                {aiSuggestionForToday.suggestedWeight} for {aiSuggestionForToday.suggestedReps}
              </span>
              {aiSuggestsDifferent && (
                <AlertDialog>
                  <AlertDialogTrigger asChild>
                    <Button size="sm" variant="outline" className="text-xs h-7 border-primary text-primary hover:bg-primary/10">
                      <CheckCircle className="h-3 w-3 mr-1" /> Use AI Target
                    </Button>
                  </AlertDialogTrigger>
                  <AlertDialogContent>
                    <AlertDialogHeader>
                      <AlertDialogTitle>Confirm Target Update</AlertDialogTitle>
                      <AlertDialogDescription>
                        Set today's planned target for {exercise.name} to {aiSuggestionForToday.suggestedWeight} based on AI suggestion?
                        This will update your plan for future sessions as well.
                      </AlertDialogDescription>
                    </AlertDialogHeader>
                    <AlertDialogFooter>
                      <AlertDialogCancel>Cancel</AlertDialogCancel>
                      <AlertDialogAction onClick={handleAcceptAISuggestion}>Confirm</AlertDialogAction>
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
        {exercise.sets.map((set, index) => (
          <SetLogger
            key={set.id}
            setNumber={index + 1}
            setData={{...set, targetWeight: currentPlanTargetToDisplay || set.targetWeight}} // Pass effective target to set logger
            loggedSetData={loggedData?.[set.id]}
            onLogSet={(log) => handleLogSet(set.id, log)}
            exerciseUnit={exercise.unit}
            isSimpleLog={isSpecialActivity}
          />
        ))}
      </CardContent>
      {canShowAIButton && (
        <CardFooter className="pt-4 justify-end">
          <Button 
            variant="outline" 
            size="sm" 
            onClick={() => setIsAIRecModalOpen(true)}
            disabled={!allSetsCompleted}
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
