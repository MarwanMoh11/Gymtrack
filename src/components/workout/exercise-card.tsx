
'use client';

import { useState } from 'react';
import { Card, CardHeader, CardTitle, CardContent, CardDescription, CardFooter } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Wand2, ArrowRight, TrendingUp, Loader2 } from 'lucide-react';
import type { Exercise, SetData, LoggedExerciseData, LoggedSetData } from '@/types/workout';
import SetLogger from './set-logger';
import AIRecommendationModal from './ai-recommendation-modal';
import type { NextSessionRecommendationOutput } from '@/ai/flows/next-session-recommendation';
import { parseWeightToNumber } from '@/lib/workout-utils';

interface ExerciseCardProps {
  exercise: Exercise;
  onLogSet: (exerciseId: string, setId: string, log: LoggedSetData) => void;
  loggedData?: LoggedExerciseData;
  aiSuggestionForToday?: NextSessionRecommendationOutput | null;
  isLoadingAISuggestion?: boolean;
}

export default function ExerciseCard({ 
  exercise, 
  onLogSet, 
  loggedData, 
  aiSuggestionForToday,
  isLoadingAISuggestion 
}: ExerciseCardProps) {
  const [isAIRecModalOpen, setIsAIRecModalOpen] = useState(false);

  const handleLogSet = (setId: string, log: LoggedSetData) => {
    onLogSet(exercise.id, setId, log);
  };

  const isSpecialActivity = exercise.isActivity || exercise.isConditioning || exercise.isWarmup || exercise.isMatch || exercise.isStretch || exercise.isFoamRoll || exercise.isRecovery;
  const canShowAIButton = !isSpecialActivity && !exercise.isCore;

  const allSetsCompleted = exercise.sets.every(set => loggedData?.[set.id]?.isCompleted);

  const renderAISuggestion = () => {
    if (isLoadingAISuggestion) {
      return <p className="text-xs text-primary/80 flex items-center"><Loader2 className="h-3 w-3 animate-spin mr-1" /> Checking AI...</p>;
    }
    if (!aiSuggestionForToday) return null;

    const planWeightNum = parseWeightToNumber(exercise.targetWeight, exercise.name);
    const aiWeightNum = parseWeightToNumber(aiSuggestionForToday.suggestedWeight, exercise.name);
    const diff = aiWeightNum - planWeightNum;

    return (
      <div className="mt-1 text-xs text-primary flex items-center">
        <TrendingUp className="h-4 w-4 mr-1" />
        AI Suggests: {aiSuggestionForToday.suggestedWeight}
        {diff !== 0 && planWeightNum > 0 && (
          <span className={`ml-1 ${diff > 0 ? 'text-green-400' : 'text-red-400'}`}>
            ({diff > 0 ? '+' : ''}{diff.toFixed(1)}kg)
          </span>
        )}
        {` for ${aiSuggestionForToday.suggestedReps}`}
      </div>
    );
  };

  return (
    <Card className="mb-6 shadow-md hover:shadow-lg transition-shadow duration-300">
      <CardHeader className="pb-3">
        <div className="flex justify-between items-start">
          <div>
            <CardTitle className="text-xl font-semibold text-foreground">
              {exercise.name}
            </CardTitle>
            {exercise.targetWeight && (
              <CardDescription className="text-sm text-muted-foreground">
                Plan Target: {exercise.targetWeight}
              </CardDescription>
            )}
            {!isSpecialActivity && renderAISuggestion()}
          </div>
          {exercise.notes && (
            <Badge variant="secondary" className="whitespace-nowrap ml-2 shrink-0">{exercise.notes}</Badge>
          )}
        </div>
      </CardHeader>
      <CardContent className="p-0">
        {exercise.sets.map((set, index) => (
          <SetLogger
            key={set.id}
            setNumber={index + 1}
            setData={set}
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
            className="bg-primary/10 hover:bg-primary/20 text-primary border-primary/30"
            >
            <Wand2 className="mr-2 h-4 w-4" />
            Get AI Advice (Next Workout)
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
