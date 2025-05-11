// src/components/dashboard/next-up-widget.tsx
'use client';

import { useEffect, useState } from 'react';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Loader2, Wand2, RefreshCw } from 'lucide-react';
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert';
import { nextSessionRecommendation, NextSessionRecommendationInput, NextSessionRecommendationOutput } from '@/ai/flows/next-session-recommendation';
import type { ChartDataPoint } from './progress-chart'; // Assuming this is where LoggedSetData might be defined or similar
import type { DailyLog, LoggedSetData, Exercise } from '@/types/workout'; // For PerformanceEntrySchema
import { weeklyPlan } from '@/data/workout-data';


interface NextUpWidgetProps {
  exerciseId: string | null;
  exerciseName: string;
  historicalData: ChartDataPoint[]; // Simplified, might need more detailed data for AI
}

// Helper to transform ChartDataPoint to PerformanceEntry for AI
const transformForAI = (exerciseId: string, historicalData: ChartDataPoint[]): NextSessionRecommendationInput['recentPerformance'] => {
    if (typeof window === 'undefined') return [];
    
    const performanceEntries: NextSessionRecommendationInput['recentPerformance'] = [];
    const relevantLogs: Array<{ date: string, weight: string, repsPerSet: string[] }> = [];

    // Iterate localStorage to find detailed set data
    const keysToSearch: string[] = [];
    for (let i = 0; i < localStorage.length; i++) {
        const key = localStorage.key(i);
        if (key && key.startsWith('gymtrack_log_')) {
            keysToSearch.push(key);
        }
    }
    // Sort keys by date part to process in chronological order for recent N workouts
    keysToSearch.sort((a, b) => {
        const dateA = a.match(/_(\d{4}-\d{2}-\d{2})$/)?.[1];
        const dateB = b.match(/_(\d{4}-\d{2}-\d{2})$/)?.[1];
        if (dateA && dateB) return new Date(dateA).getTime() - new Date(dateB).getTime();
        return 0;
    });


    for (const key of keysToSearch) {
        const match = key.match(/gymtrack_log_([a-zA-Z0-9-]+)_(\d{4}-\d{2}-\d{2})$/);
        if (match) {
            const dateStr = match[2];
            try {
                const dailyLogString = localStorage.getItem(key);
                if (!dailyLogString) continue;
                const dailyLog: DailyLog = JSON.parse(dailyLogString);

                if (dailyLog[exerciseId]) {
                    const exerciseLog = dailyLog[exerciseId];
                    const repsPerSet: string[] = [];
                    let currentWeight: string = 'N/A';
                    
                    // Find the original exercise definition to get set IDs in order
                    let originalExercise: Exercise | undefined;
                    for (const day of weeklyPlan) {
                        originalExercise = day.exercises.find(ex => ex.id === exerciseId);
                        if (originalExercise) break;
                    }

                    if (originalExercise) {
                        originalExercise.sets.forEach(setDef => {
                            const loggedSet = exerciseLog[setDef.id];
                            if (loggedSet && loggedSet.isCompleted) {
                                repsPerSet.push(String(loggedSet.reps || setDef.targetReps));
                                if (loggedSet.weight) currentWeight = String(loggedSet.weight);
                                else if (setDef.targetWeight) currentWeight = String(setDef.targetWeight);
                                else if (originalExercise?.targetWeight) currentWeight = String(originalExercise.targetWeight);
                            }
                        });
                    }


                    if (repsPerSet.length > 0) {
                       relevantLogs.push({
                           date: dateStr,
                           weight: currentWeight !== 'N/A' ? currentWeight : (originalExercise?.targetWeight || 'bodyweight'),
                           repsPerSet: repsPerSet,
                       });
                    }
                }
            } catch (e) {
                console.error(`Error processing log for key ${key}:`, e);
            }
        }
    }
    // Return the most recent ~8 entries
    return relevantLogs.slice(-8);
};


export function NextUpWidget({ exerciseId, exerciseName, historicalData }: NextUpWidgetProps) {
  const [recommendation, setRecommendation] = useState<NextSessionRecommendationOutput | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const fetchRecommendation = async () => {
    if (!exerciseId || !exerciseName) {
      setError("Please select an exercise first.");
      return;
    }
    
    setIsLoading(true);
    setError(null);
    setRecommendation(null);

    const recentPerformance = transformForAI(exerciseId, historicalData);

    if (recentPerformance.length === 0) {
        setError(`Not enough recent logged data for ${exerciseName} to generate a recommendation. Please log more workouts.`);
        setIsLoading(false);
        return;
    }
    
    const input: NextSessionRecommendationInput = {
      exerciseName,
      recentPerformance, // Use transformed detailed data
      userGoal: 'Progressive overload for strength and hypertrophy', // Default or could be dynamic
    };

    try {
      const result = await nextSessionRecommendation(input);
      setRecommendation(result);
    } catch (e) {
      console.error('AI Recommendation Error (NextUp):', e);
      const errorMessage = e instanceof Error ? e.message : 'An unknown error occurred.';
      setError(`Failed to get recommendation: ${errorMessage}`);
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => {
    // Clear recommendation if exercise changes and no historical data, or on initial load without exercise
    if (!exerciseId || historicalData.length === 0) {
      setRecommendation(null);
      setError(null);
      setIsLoading(false);
    } else {
        // Optionally auto-fetch when exerciseId or data changes and is valid
        // fetchRecommendation(); 
        // For now, require manual click to reduce API calls during dev/interaction
         setRecommendation(null); // Clear old recommendation
         setError(null);
    }
  }, [exerciseId, historicalData]); // Removed exerciseName from deps as it's derived from exerciseId

  return (
    <Card className="shadow-xl rounded-2xl">
      <CardHeader>
        <div className="flex justify-between items-center">
          <CardTitle className="text-2xl font-bold text-primary">Next Up: {exerciseName || 'Select Exercise'}</CardTitle>
          <Button variant="ghost" size="icon" onClick={fetchRecommendation} disabled={isLoading || !exerciseId} className="rounded-full text-primary hover:bg-primary/10">
            {isLoading ? <Loader2 className="h-5 w-5 animate-spin" /> : <RefreshCw className="h-5 w-5" />}
            <span className="sr-only">Refresh Recommendation</span>
          </Button>
        </div>
        <CardDescription>AI-powered suggestion for your next session.</CardDescription>
      </CardHeader>
      <CardContent>
        {isLoading && (
          <div className="flex items-center justify-center py-8">
            <Loader2 className="h-8 w-8 animate-spin text-primary mr-3" />
            <span className="text-muted-foreground">Generating recommendation...</span>
          </div>
        )}
        {error && !isLoading && (
          <Alert variant="destructive">
            <AlertTitle>Error</AlertTitle>
            <AlertDescription>{error}</AlertDescription>
          </Alert>
        )}
        {!isLoading && !error && recommendation && (
          <div className="space-y-3">
            <div>
              <h4 className="font-semibold text-lg">Suggested Weight:</h4>
              <p className="text-primary text-xl font-bold">{recommendation.suggestedWeight}</p>
            </div>
            <div>
              <h4 className="font-semibold text-lg">Suggested Reps:</h4>
              <p className="text-primary text-xl font-bold">{recommendation.suggestedReps}</p>
            </div>
            <div>
              <h4 className="font-semibold text-lg">Reasoning:</h4>
              <p className="text-sm text-muted-foreground italic">{recommendation.reasoning}</p>
            </div>
          </div>
        )}
        {!isLoading && !error && !recommendation && exerciseId && (
          <div className="text-center py-8">
            <p className="text-muted-foreground">Click the <Wand2 className="inline h-4 w-4 text-primary" /> refresh button to get a recommendation for {exerciseName}.</p>
            <p className="text-xs text-muted-foreground/70 mt-1">Ensure you have logged recent sessions for this exercise.</p>
          </div>
        )}
         {!isLoading && !error && !recommendation && !exerciseId && (
          <div className="text-center py-8">
            <p className="text-muted-foreground">Please select an exercise to get a recommendation.</p>
          </div>
        )}
      </CardContent>
    </Card>
  );
}
