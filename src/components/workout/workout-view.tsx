
'use client';

import { useState, useEffect, useCallback } from 'react';
import type { WorkoutDay, DailyLog, LoggedSetData, Exercise } from '@/types/workout';
import ExerciseCard from './exercise-card';
import DayProgress from './day-progress';
import { Button } from '@/components/ui/button';
import { useToast } from '@/hooks/use-toast';
import { Card, CardDescription, CardHeader, CardTitle } from '../ui/card';
import { nextSessionRecommendation, NextSessionRecommendationInput, NextSessionRecommendationOutput } from '@/ai/flows/next-session-recommendation';
import { transformHistoricalDataForAI, parseWeightToNumber } from '@/lib/workout-utils';
import { getUserTargetWeight, setTargetWeightOverride } from '@/lib/user-settings';

interface WorkoutViewProps {
  workoutDay: WorkoutDay;
}

const getCurrentDateString = (): string => {
  return new Date().toISOString().split('T')[0];
};

function getLocalStorageKey(dayId: string, date: string): string {
  return `gymtrack_log_${dayId}_${date}`;
}

export default function WorkoutView({ workoutDay }: WorkoutViewProps) {
  const [dailyLog, setDailyLog] = useState<DailyLog>({});
  const [isInitialized, setIsInitialized] = useState(false);
  const [currentDate, setCurrentDate] = useState('');
  const [aiSuggestionsForToday, setAiSuggestionsForToday] = useState<Map<string, NextSessionRecommendationOutput | null>>(new Map());
  const [isLoadingAISuggestions, setIsLoadingAISuggestions] = useState(false);
  // State to trigger re-render when effective target weights change
  const [effectiveTargetWeightsKey, setEffectiveTargetWeightsKey] = useState(0); 
  const { toast } = useToast();

  useEffect(() => {
    setCurrentDate(getCurrentDateString());
  }, []);

  useEffect(() => {
    if (typeof window !== 'undefined' && currentDate) {
      const key = getLocalStorageKey(workoutDay.id, currentDate);
      const storedLog = localStorage.getItem(key);
      if (storedLog) {
        try {
          setDailyLog(JSON.parse(storedLog));
        } catch (error) {
          console.error("Failed to parse stored log:", error);
          localStorage.removeItem(key); 
        }
      } else {
        setDailyLog({});
      }
      setIsInitialized(true);
    }
  }, [workoutDay.id, currentDate]);

  useEffect(() => {
    if (isInitialized && typeof window !== 'undefined' && currentDate) {
      const key = getLocalStorageKey(workoutDay.id, currentDate);
      if (Object.keys(dailyLog).length > 0) {
        localStorage.setItem(key, JSON.stringify(dailyLog));
      } else {
        localStorage.removeItem(key);
      }
    }
  }, [dailyLog, workoutDay.id, isInitialized, currentDate]);

  const fetchAISuggestionsForToday = useCallback(async () => {
    if (!isInitialized || !currentDate) return;

    setIsLoadingAISuggestions(true);
    const suggestions = new Map<string, NextSessionRecommendationOutput | null>();
    
    for (const exercise of workoutDay.exercises) {
      if (!exercise.isWarmup && !exercise.isConditioning && !exercise.isStretch && !exercise.isFoamRoll && !exercise.isActivity && !exercise.isMatch && !exercise.isRecovery && !exercise.isCore) {
        const recentPerformance = transformHistoricalDataForAI(exercise.id);
        if (recentPerformance.length > 0) {
          try {
            const input: NextSessionRecommendationInput = {
              exerciseName: exercise.name,
              recentPerformance,
              userGoal: 'Progressive overload for strength and hypertrophy',
            };
            const suggestion = await nextSessionRecommendation(input);
            suggestions.set(exercise.id, suggestion);
          } catch (e) {
            console.error(`AI Suggestion Error for ${exercise.name}:`, e);
            suggestions.set(exercise.id, null);
          }
        } else {
          suggestions.set(exercise.id, null); 
        }
      }
    }
    setAiSuggestionsForToday(suggestions);
    setIsLoadingAISuggestions(false);
  }, [workoutDay.exercises, isInitialized, currentDate]);

  useEffect(() => {
    if(isInitialized) { // Fetch AI suggestions only after initialization
       fetchAISuggestionsForToday();
    }
  }, [fetchAISuggestionsForToday, isInitialized]);


  const handleLogSet = (exerciseId: string, setId: string, log: LoggedSetData) => {
    setDailyLog(prevLog => ({
      ...prevLog,
      [exerciseId]: {
        ...(prevLog[exerciseId] || {}),
        [setId]: log,
      },
    }));
  };

  const handleClearDayLog = () => {
    setDailyLog({});
    toast({
      title: "Log Cleared",
      description: `Log for ${workoutDay.dayName} (${currentDate}) has been cleared.`,
    });
  };

  const handleUpdateEffectiveTargetWeight = (exerciseId: string, newWeight: string) => {
    setTargetWeightOverride(exerciseId, newWeight);
    setEffectiveTargetWeightsKey(prev => prev + 1); // Force re-render to reflect updated target weight
    toast({
      title: "Plan Updated",
      description: `Target weight for ${workoutDay.exercises.find(e => e.id === exerciseId)?.name || 'exercise'} updated to ${newWeight}.`,
    });
  };
  
  if (!isInitialized || !currentDate) {
    return (
      <div className="container mx-auto px-4 py-8">
        <div className="animate-pulse">
          <div className="h-8 bg-muted rounded w-1/4 mb-4"></div>
          <div className="h-4 bg-muted rounded w-1/2 mb-8"></div>
          <div className="space-y-6">
            {[1,2,3].map(i => (
              <div key={i} className="p-4 bg-card rounded-lg shadow-sm">
                <div className="h-6 bg-muted rounded w-3/4 mb-2"></div>
                <div className="h-4 bg-muted rounded w-1/2 mb-4"></div>
                <div className="space-y-2">
                  <div className="h-10 bg-muted/50 rounded"></div>
                  <div className="h-10 bg-muted/50 rounded"></div>
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="container mx-auto max-w-3xl px-2 sm:px-4 py-8">
      <Card className="mb-8 bg-card shadow-lg border-none">
        <CardHeader>
          <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center">
            <div>
              <CardTitle className="text-3xl font-bold text-primary mb-1">{workoutDay.dayName}</CardTitle>
              <CardDescription className="text-lg text-muted-foreground">{workoutDay.title} - {currentDate}</CardDescription>
            </div>
             <Button variant="outline" onClick={handleClearDayLog} size="sm" className="mt-2 sm:mt-0 rounded-full">
              Clear Today's Log
            </Button>
          </div>
          {workoutDay.notes && (
            <p className="mt-2 text-sm text-foreground/80 p-3 bg-secondary/50 rounded-md">{workoutDay.notes}</p>
          )}
        </CardHeader>
      </Card>
      
      <DayProgress workoutDay={workoutDay} dailyLog={dailyLog} />

      {workoutDay.exercises.map((exercise: Exercise) => {
        const effectiveTargetWeight = getUserTargetWeight(exercise.id, exercise.targetWeight);
        return (
          <ExerciseCard
            key={`${exercise.id}-${effectiveTargetWeightsKey}`} // Add key to force re-render on change
            exercise={exercise}
            effectiveTargetWeight={effectiveTargetWeight}
            onLogSet={handleLogSet}
            loggedData={dailyLog[exercise.id]}
            aiSuggestionForToday={aiSuggestionsForToday.get(exercise.id)}
            isLoadingAISuggestion={isLoadingAISuggestions && !aiSuggestionsForToday.has(exercise.id)}
            onUpdateEffectiveTargetWeight={handleUpdateEffectiveTargetWeight}
          />
        );
      })}
    </div>
  );
}
