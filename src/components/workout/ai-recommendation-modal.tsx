'use client';

import { useState, useEffect } from 'react';
import { useQuery } from '@tanstack/react-query';
import { useAuth } from '@/context/auth-context';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
  DialogFooter,
} from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Loader2, Wand2, ArrowRight } from 'lucide-react';
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert';
import type { Exercise, DailyLog } from '@/types/workout';
import { nextSessionRecommendation, NextSessionRecommendationOutput } from '@/ai/flows/next-session-recommendation';
import { useToast } from '@/hooks/use-toast';
import { transformHistoricalDataForAI } from '@/lib/workout-utils';
import { getAllUserLogs } from '@/lib/firestore-log-service';

interface AIRecommendationModalProps {
  exercise: Exercise;
  isOpen: boolean;
  onOpenChange: (open: boolean) => void;
}

export default function AIRecommendationModal({
  exercise,
  isOpen,
  onOpenChange,
}: AIRecommendationModalProps) {
  const { user } = useAuth();
  const [isLoading, setIsLoading] = useState(false);
  const [recommendation, setRecommendation] = useState<NextSessionRecommendationOutput | null>(null);
  const [error, setError] = useState<string | null>(null);
  const { toast } = useToast();
  
  const { data: allLogs, isLoading: isLoadingLogs } = useQuery({
    queryKey: ['allUserLogs', user?.uid],
    queryFn: () => getAllUserLogs(user!.uid),
    enabled: !!user && isOpen, // Only fetch when the modal is open
  });

  const handleGetRecommendation = async () => {
    if (!allLogs) {
      setError("Log data is not available yet. Please try again in a moment.");
      return;
    }
    
    setIsLoading(true);
    setError(null);
    setRecommendation(null);

    const historicalData = transformHistoricalDataForAI(exercise.id, allLogs);

    if (historicalData.length === 0) {
        setError("Not enough historical data for a meaningful recommendation. Log a few sessions first.");
        setIsLoading(false);
        return;
    }

    try {
      const result = await nextSessionRecommendation({
          exerciseName: exercise.name,
          recentPerformance: historicalData,
          userGoal: 'strength and hypertrophy',
      });
      setRecommendation(result);
    } catch (e) {
      console.error('AI Recommendation Error:', e);
      setError('Failed to get recommendation. The AI may be busy or an error occurred.');
      toast({
        variant: 'destructive',
        title: 'AI Error',
        description: 'Could not fetch recommendation from AI.',
      });
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => {
    if (isOpen) {
      setRecommendation(null);
      setError(null);
      setIsLoading(false);
    }
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
            Get AI-powered advice for your next session based on your performance trend.
          </DialogDescription>
        </DialogHeader>

        {error && (
          <Alert variant="destructive" className="my-4">
            <AlertTitle>Error</AlertTitle>
            <AlertDescription>{error}</AlertDescription>
          </Alert>
        )}

        {recommendation && !isLoading && (
          <div className="my-4 p-4 bg-accent/30 rounded-md border border-accent space-y-3 text-sm">
            <div>
              <h4 className="font-semibold text-foreground mb-1">Suggested Weight:</h4>
              <p className="p-2 bg-background/50 rounded-md text-base font-bold text-primary">{recommendation.suggestedWeight}</p>
            </div>
             <div>
              <h4 className="font-semibold text-foreground mb-1">Suggested Reps:</h4>
              <p className="p-2 bg-background/50 rounded-md">{recommendation.suggestedReps}</p>
            </div>
             <div>
              <h4 className="font-semibold text-foreground mb-1">Reasoning:</h4>
              <p className="text-foreground/80">{recommendation.reasoning}</p>
            </div>
          </div>
        )}
        
        {(isLoading || isLoadingLogs) && (
          <div className="flex justify-center items-center my-8">
            <Loader2 className="h-8 w-8 animate-spin text-primary" />
            <p className="ml-2">Analyzing your progress...</p>
          </div>
        )}

        {!recommendation && !isLoading && !error && !isLoadingLogs && (
             <div className="my-4 p-4 bg-secondary/50 rounded-md text-center">
                <p className="text-sm text-muted-foreground">Click "Get Recommendation" to see AI advice.</p>
            </div>
        )}

        <DialogFooter className="sm:justify-between gap-2">
           <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>
            Close
          </Button>
          <Button type="button" onClick={handleGetRecommendation} disabled={isLoading || isLoadingLogs}>
            {isLoading || isLoadingLogs ? (
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
