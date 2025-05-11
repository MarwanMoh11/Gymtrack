'use client';

import { useState } from 'react';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
  DialogFooter,
} from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Loader2, Wand2 } from 'lucide-react';
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert';
import type { Exercise, LoggedExerciseData } from '@/types/workout';
import { adjustWeightRecommendation, AdjustWeightRecommendationInput } from '@/ai/flows/adjust-weight-recommendation';
import { useToast } from '@/hooks/use-toast';

interface AIRecommendationModalProps {
  exercise: Exercise;
  loggedExerciseData?: LoggedExerciseData;
  isOpen: boolean;
  onOpenChange: (open: boolean) => void;
}

export default function AIRecommendationModal({
  exercise,
  loggedExerciseData,
  isOpen,
  onOpenChange,
}: AIRecommendationModalProps) {
  const [isLoading, setIsLoading] = useState(false);
  const [recommendation, setRecommendation] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const { toast } = useToast();

  const getRepsString = (isLogged: boolean): string => {
    return exercise.sets
      .map(set => {
        if (isLogged) {
          return loggedExerciseData?.[set.id]?.reps?.toString() || set.targetReps.toString();
        }
        return set.targetReps.toString();
      })
      .join(', ');
  };

  const handleGetRecommendation = async () => {
    setIsLoading(true);
    setError(null);
    setRecommendation(null);

    if (!loggedExerciseData || Object.keys(loggedExerciseData).length === 0) {
        setError("Please log at least one set for this exercise to get a recommendation.");
        setIsLoading(false);
        return;
    }

    const loggedSetsCount = exercise.sets.filter(s => loggedExerciseData[s.id]?.isCompleted).length;
    if (loggedSetsCount === 0) {
        setError("Ensure you have marked sets as completed by logging them.");
        setIsLoading(false);
        return;
    }


    const input: AdjustWeightRecommendationInput = {
      exerciseName: exercise.name,
      previousWeight: exercise.targetWeight || 'N/A',
      previousReps: getRepsString(false), // Target reps
      currentReps: getRepsString(true),   // Logged reps
      userGoal: 'Achieve progressive overload for strength and hypertrophy.', // Example goal
    };

    try {
      const result = await adjustWeightRecommendation(input);
      setRecommendation(result.recommendation);
    } catch (e) {
      console.error('AI Recommendation Error:', e);
      setError('Failed to get recommendation. Please try again.');
      toast({
        variant: 'destructive',
        title: 'AI Error',
        description: 'Could not fetch recommendation from AI.',
      });
    } finally {
      setIsLoading(false);
    }
  };

  // Reset state when dialog is closed/opened
  useState(() => {
    if (isOpen) {
      setRecommendation(null);
      setError(null);
      setIsLoading(false);
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isOpen]);


  return (
    <Dialog open={isOpen} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle className="flex items-center">
            <Wand2 className="mr-2 h-5 w-5 text-primary" />
            AI Recommendation for {exercise.name}
          </DialogTitle>
          <DialogDescription>
            Get AI-powered advice to adjust your weight or reps for the next workout.
          </DialogDescription>
        </DialogHeader>

        {error && (
          <Alert variant="destructive" className="my-4">
            <AlertTitle>Error</AlertTitle>
            <AlertDescription>{error}</AlertDescription>
          </Alert>
        )}

        {recommendation && !isLoading && (
          <div className="my-4 p-4 bg-accent/30 rounded-md border border-accent">
            <h4 className="font-semibold mb-2 text-foreground">Suggestion for your next session:</h4>
            <p className="text-sm text-foreground/80">{recommendation}</p>
          </div>
        )}
        
        {isLoading && (
          <div className="flex justify-center items-center my-8">
            <Loader2 className="h-8 w-8 animate-spin text-primary" />
            <p className="ml-2">Getting your recommendation...</p>
          </div>
        )}

        {!recommendation && !isLoading && !error && (
             <div className="my-4 p-4 bg-secondary/50 rounded-md text-center">
                <p className="text-sm text-muted-foreground">Click "Get Recommendation" to see AI advice.</p>
            </div>
        )}


        <DialogFooter className="sm:justify-between gap-2">
           <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>
            Close
          </Button>
          <Button type="button" onClick={handleGetRecommendation} disabled={isLoading}>
            {isLoading ? (
              <Loader2 className="mr-2 h-4 w-4 animate-spin" />
            ) : (
              <Wand2 className="mr-2 h-4 w-4" />
            )}
            Get Recommendation
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
