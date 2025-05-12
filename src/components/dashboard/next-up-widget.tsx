
// src/components/dashboard/next-up-widget.tsx
'use client';

import { useEffect, useState } from 'react';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Loader2, Wand2, RefreshCw, Activity } from 'lucide-react'; // Added Activity import
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert';
import type { NextSessionRecommendationOutput } from '@/ai/flows/next-session-recommendation';
import { transformHistoricalDataForAI } from '@/lib/workout-utils'; 

interface NextUpWidgetProps {
  exerciseId: string | undefined;
  exerciseName: string;
  aiSuggestion: NextSessionRecommendationOutput | null;
  onRefreshNeeded: () => void; 
  isLoading: boolean; // Receive loading state from parent
}

export function NextUpWidget({ exerciseId, exerciseName, aiSuggestion, onRefreshNeeded, isLoading }: NextUpWidgetProps) {
  const [isRefreshing, setIsRefreshing] = useState(false); // Local state for refresh button animation
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    // Update error message based on suggestion and loading state
    if (!isLoading && exerciseId) {
        const recentPerformance = transformHistoricalDataForAI(exerciseId);
        if (aiSuggestion) {
            setError(null); // Clear error if suggestion is present
        } else if (recentPerformance.length === 0) {
            // No suggestion because no data
            setError(`Not enough recent logged data for ${exerciseName} to generate a recommendation.`);
        } else {
            // No suggestion, but data exists - could be AI error or just no progression needed
            setError(null); // Let the component show the 'no suggestion/prompt refresh' message instead of an error
        }
    } else if (!exerciseId) {
        setError(null); // Clear error if no exercise selected
    }
    // Reset refresh button state if loading finishes
    if (!isLoading) {
        setIsRefreshing(false);
    }
  }, [aiSuggestion, exerciseId, exerciseName, isLoading]);


  const handleRefresh = async () => {
    setIsRefreshing(true); // Show spinner on button
    setError(null);
    onRefreshNeeded(); // Ask parent to refresh AI suggestion
    // Parent now controls the main isLoading state, isRefreshing is just for the button visual
  };
  
  return (
    <Card className="shadow-xl rounded-2xl">
      <CardHeader>
        <div className="flex justify-between items-center">
          <CardTitle className="text-xl font-bold text-primary">AI Insight: {exerciseName || 'Select Exercise'}</CardTitle>
          <Button variant="ghost" size="icon" onClick={handleRefresh} disabled={isLoading || isRefreshing || !exerciseId} className="rounded-full text-primary hover:bg-primary/10">
            {isLoading || isRefreshing ? <Loader2 className="h-5 w-5 animate-spin" /> : <RefreshCw className="h-5 w-5" />}
            <span className="sr-only">Refresh Recommendation</span>
          </Button>
        </div>
        <CardDescription>AI suggestion for your next session with this exercise.</CardDescription>
      </CardHeader>
      <CardContent>
        {isLoading && ( // Show main loading indicator from parent
          <div className="flex items-center justify-center py-8">
            <Loader2 className="h-8 w-8 animate-spin text-primary mr-3" />
            <span className="text-muted-foreground">Loading AI suggestion...</span>
          </div>
        )}
        {error && !isLoading && exerciseId && ( 
          <Alert variant="destructive">
            <AlertTitle>Info</AlertTitle>
            <AlertDescription>{error}</AlertDescription>
          </Alert>
        )}
        {!isLoading && !error && aiSuggestion && exerciseId && ( 
          <div className="space-y-3">
            <div>
              <h4 className="font-semibold text-lg">Suggested Weight:</h4>
              <p className="text-primary text-xl font-bold">{aiSuggestion.suggestedWeight}</p>
            </div>
            <div>
              <h4 className="font-semibold text-lg">Suggested Reps:</h4>
              <p className="text-primary text-xl font-bold">{aiSuggestion.suggestedReps}</p>
            </div>
            <div>
              <h4 className="font-semibold text-lg">Reasoning:</h4>
              <p className="text-sm text-muted-foreground italic">{aiSuggestion.reasoning}</p>
            </div>
          </div>
        )}
        {!isLoading && !error && !aiSuggestion && exerciseId && ( 
          <div className="text-center py-8">
            <Wand2 className="mx-auto h-10 w-10 text-muted-foreground/50 mb-3" />
            <p className="text-muted-foreground">No specific suggestion from AI for the next session.</p>
            <p className="text-xs text-muted-foreground/70 mt-1">This might mean maintaining current weight/reps is advised, or there isn't enough recent data. Click refresh to try again.</p>
             
          </div>
        )}
         {!isLoading && !exerciseId && ( // Show prompt to select exercise if none is selected
          <div className="text-center py-8">
             <Activity className="mx-auto h-10 w-10 text-muted-foreground/50 mb-3" />
            <p className="text-muted-foreground">Select an exercise above to get AI insights.</p>
          </div>
        )}
      </CardContent>
    </Card>
  );
}

