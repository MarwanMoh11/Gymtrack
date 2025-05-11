
// src/components/dashboard/next-up-widget.tsx
'use client';

import { useEffect, useState } from 'react';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Loader2, Wand2, RefreshCw } from 'lucide-react';
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert';
import type { NextSessionRecommendationOutput, NextSessionRecommendationInput } from '@/ai/flows/next-session-recommendation';
import { transformHistoricalDataForAI } from '@/lib/workout-utils'; // Import from new location

interface NextUpWidgetProps {
  exerciseId: string | null;
  exerciseName: string;
  aiSuggestion: NextSessionRecommendationOutput | null; // Accept suggestion as prop
  onRefreshNeeded: () => void; // Callback to request parent to refresh data (and AI suggestion)
}

export function NextUpWidget({ exerciseId, exerciseName, aiSuggestion, onRefreshNeeded }: NextUpWidgetProps) {
  const [isLoading, setIsLoading] = useState(false); // For the refresh button's own loading state
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    // When aiSuggestion prop changes, update local states
    if (aiSuggestion) {
      setError(null);
    } else if (exerciseId && !aiSuggestion && !isLoading) {
      // If an exercise is selected, but no suggestion is provided (e.g. AI fetch failed at parent)
      // Check if we should show a specific message for this widget
      const recentPerformance = transformHistoricalDataForAI(exerciseId);
      if(recentPerformance.length === 0) {
        setError(`Not enough recent logged data for ${exerciseName} to generate a recommendation.`);
      } else {
        setError(null); // Parent might be handling the error display
      }
    }
  }, [aiSuggestion, exerciseId, exerciseName, isLoading]);


  const handleRefresh = async () => {
    setIsLoading(true);
    setError(null);
    onRefreshNeeded(); // Ask parent to refresh data and AI suggestion
    // A small delay to allow parent to fetch and update prop
    setTimeout(() => setIsLoading(false), 1500); 
  };
  
  return (
    <Card className="shadow-xl rounded-2xl">
      <CardHeader>
        <div className="flex justify-between items-center">
          <CardTitle className="text-2xl font-bold text-primary">Next Up: {exerciseName || 'Select Exercise'}</CardTitle>
          <Button variant="ghost" size="icon" onClick={handleRefresh} disabled={isLoading || !exerciseId} className="rounded-full text-primary hover:bg-primary/10">
            {isLoading ? <Loader2 className="h-5 w-5 animate-spin" /> : <RefreshCw className="h-5 w-5" />}
            <span className="sr-only">Refresh Recommendation</span>
          </Button>
        </div>
        <CardDescription>AI-powered suggestion for your next session.</CardDescription>
      </CardHeader>
      <CardContent>
        {isLoading && ( // This isLoading is local to the refresh button click
          <div className="flex items-center justify-center py-8">
            <Loader2 className="h-8 w-8 animate-spin text-primary mr-3" />
            <span className="text-muted-foreground">Refreshing recommendation...</span>
          </div>
        )}
        {error && !isLoading && (
          <Alert variant="destructive">
            <AlertTitle>Info</AlertTitle>
            <AlertDescription>{error}</AlertDescription>
          </Alert>
        )}
        {!isLoading && !error && aiSuggestion && (
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
            <p className="text-muted-foreground">Click the <Wand2 className="inline h-4 w-4 text-primary" /> refresh button to get/update the recommendation for {exerciseName}.</p>
            <p className="text-xs text-muted-foreground/70 mt-1">Ensure you have logged recent sessions for this exercise.</p>
          </div>
        )}
         {!isLoading && !error && !aiSuggestion && !exerciseId && (
          <div className="text-center py-8">
            <p className="text-muted-foreground">Please select an exercise to get a recommendation.</p>
          </div>
        )}
      </CardContent>
    </Card>
  );
}
