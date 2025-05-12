
// src/app/dashboard/progressive-overload/page.tsx
'use client';
import { useState, useEffect, useMemo, useCallback } from 'react';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { ProgressChart, type ChartDataPoint } from '@/components/dashboard/progress-chart';
import { NextUpWidget } from '@/components/dashboard/next-up-widget';
import { weeklyPlan } from '@/data/workout-data';
import type { DailyLog, LoggedSetData, Exercise as ExerciseType } from '@/types/workout';
import { LineChart as LucideLineChart, History, Loader2, CalendarDays } from 'lucide-react';
import LoadingProgressiveOverloadDashboard from './loading'; // Use the dedicated loading component
import { getAllExercises, parseWeightToNumber, transformHistoricalDataForAI } from '@/lib/workout-utils';
import { nextSessionRecommendation, NextSessionRecommendationInput, NextSessionRecommendationOutput } from '@/ai/flows/next-session-recommendation';
import { useToast } from '@/hooks/use-toast';
import { Calendar } from '@/components/ui/calendar';

const getHistoricalDataForExercise = (exerciseId: string, exerciseName?: string): ChartDataPoint[] => {
  if (typeof window === 'undefined') return [];
  
  const collectedData: Array<{ dateStr: string, dailyMaxWeight: number, reps?: string | number }> = [];
  
  for (let i = 0; i < localStorage.length; i++) {
    const key = localStorage.key(i);
    if (!key) continue;

    const match = key.match(/^gymtrack_log_([a-zA-Z0-9-]+)_(\d{4}-\d{2}-\d{2})$/);
    if (match) {
      const dateStr = match[2];
      const dayLogString = localStorage.getItem(key);
      if (dayLogString) {
        try {
          const dayLog: DailyLog = JSON.parse(dayLogString);
          if (dayLog[exerciseId]) {
            const exerciseLog = dayLog[exerciseId]; 
            let maxWeightForDay = 0;
            let repsForMaxWeight: string | number | undefined = undefined;

            Object.values(exerciseLog).forEach((loggedSet: LoggedSetData) => {
              if (loggedSet.isCompleted && (loggedSet.weight !== undefined || exerciseName)) { 
                const currentWeightNumber = parseWeightToNumber(loggedSet.weight, exerciseName);
                if (currentWeightNumber > maxWeightForDay) {
                  maxWeightForDay = currentWeightNumber;
                  repsForMaxWeight = loggedSet.reps;
                }
              }
            });

            if (maxWeightForDay > 0 || (parseWeightToNumber(exerciseName) > 0 && exerciseName?.toLowerCase().includes("bodyweight")) ) { // Also chart bodyweight exercises if they have entries
              collectedData.push({ dateStr, dailyMaxWeight: maxWeightForDay, reps: repsForMaxWeight });
            }
          }
        } catch (error) {
          console.error(`Error parsing localStorage item ${key}:`, error);
        }
      }
    }
  }

  collectedData.sort((a, b) => new Date(a.dateStr).getTime() - new Date(b.dateStr).getTime());

  let currentMaxWeightEver = 0;
  return collectedData.map(item => {
    const isPR = item.dailyMaxWeight > currentMaxWeightEver;
    if (isPR) {
      currentMaxWeightEver = item.dailyMaxWeight;
    }
    return {
      date: item.dateStr,
      weight: item.dailyMaxWeight,
      type: 'actual',
      isPR,
      reps: item.reps,
    };
  });
};

const getLoggedDays = (): Date[] => {
  if (typeof window === 'undefined') return [];
  const loggedDates = new Set<string>();
  for (let i = 0; i < localStorage.length; i++) {
    const key = localStorage.key(i);
    if (!key) continue;
    const match = key.match(/^gymtrack_log_[a-zA-Z0-9-]+_(\d{4}-\d{2}-\d{2})$/);
    if (match) {
      loggedDates.add(match[1]);
    }
  }
  // Convert string dates to Date objects, handling potential timezone issues
  return Array.from(loggedDates).map(dateStr => {
    const [year, month, day] = dateStr.split('-').map(Number);
    return new Date(year, month - 1, day); // Use UTC or local time consistently
  });
}

export default function ProgressiveOverloadDashboardPage() {
  const [allExercises, setAllExercises] = useState<Array<{ id: string; name: string }>>([]);
  const [selectedExerciseId, setSelectedExerciseId] = useState<string | undefined>(undefined);
  const [chartData, setChartData] = useState<ChartDataPoint[]>([]);
  const [aiNextSessionSuggestion, setAiNextSessionSuggestion] = useState<NextSessionRecommendationOutput | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [isClient, setIsClient] = useState(false);
  const [loggedDays, setLoggedDays] = useState<Date[]>([]);
  const { toast } = useToast();

  useEffect(() => {
    setIsClient(true);
    const exercises = getAllExercises();
    setAllExercises(exercises);
    setLoggedDays(getLoggedDays());
    if (exercises.length > 0 && !selectedExerciseId) {
      setSelectedExerciseId(exercises[0].id);
    } else if (exercises.length === 0) {
      setIsLoading(false);
    }
  }, []); // Run once on mount


  const selectedExercise = useMemo(() => {
    return weeklyPlan.flatMap(day => day.exercises).find(ex => ex.id === selectedExerciseId);
  }, [selectedExerciseId]);

  const selectedExerciseName = selectedExercise?.name || '';

  const fetchDashboardData = useCallback(async () => {
    if (selectedExerciseId && isClient) {
      setIsLoading(true);
      setAiNextSessionSuggestion(null); // Clear previous AI suggestion

      const historicalData = getHistoricalDataForExercise(selectedExerciseId, selectedExerciseName);
      setChartData(historicalData);
      setLoggedDays(getLoggedDays()); // Refresh logged days as well

      if (historicalData.length > 0) {
        const recentPerformanceForAI = transformHistoricalDataForAI(selectedExerciseId);
        if (recentPerformanceForAI.length > 0) {
          try {
            const input: NextSessionRecommendationInput = {
              exerciseName: selectedExerciseName,
              recentPerformance: recentPerformanceForAI,
              userGoal: 'Progressive overload for strength and hypertrophy',
            };
            const suggestion = await nextSessionRecommendation(input);
            setAiNextSessionSuggestion(suggestion);
          } catch (e) {
            console.error('AI Recommendation Error for chart target:', e);
            toast({ variant: "destructive", title: "AI Error", description: "Could not fetch AI suggestion for target line." });
            setAiNextSessionSuggestion(null);
          }
        } else {
           setAiNextSessionSuggestion(null); // Clear suggestion if no recent data for AI
        }
      } else {
         setAiNextSessionSuggestion(null); // Clear suggestion if no historical data
      }
      setIsLoading(false);
    } else if (!selectedExerciseId && isClient) {
      setChartData([]);
      setAiNextSessionSuggestion(null);
      setIsLoading(false);
    }
  }, [selectedExerciseId, isClient, selectedExerciseName, toast]);

  useEffect(() => {
    fetchDashboardData();
  }, [fetchDashboardData]);
  
  const targetProgressionData = useMemo((): ChartDataPoint[] => {
    if (!selectedExerciseId || !isClient) return [];

    const simulatedTarget: ChartDataPoint[] = [];
    const currentDate = new Date();
    const oneWeekMillis = 7 * 24 * 60 * 60 * 1000;

    if (chartData.length > 0) {
        const lastActualPoint = chartData[chartData.length - 1];
        let lastDate = new Date(lastActualPoint.date);
        let currentTargetWeight = lastActualPoint.weight;
        
        // Add the last actual point as the start of the target line
        simulatedTarget.push({ date: lastActualPoint.date, weight: currentTargetWeight, type: 'target' });

        if (aiNextSessionSuggestion) {
            const aiTargetWeight = parseWeightToNumber(aiNextSessionSuggestion.suggestedWeight, selectedExerciseName);
            const nextSessionDate = new Date(lastDate.getTime() + oneWeekMillis);
            simulatedTarget.push({ date: nextSessionDate.toISOString().split('T')[0], weight: aiTargetWeight, type: 'target' });
            
            currentTargetWeight = aiTargetWeight;
            lastDate = nextSessionDate;
        }
        
        // Project further 11 weeks (total 12 including the AI point or first week)
        // Use a minimum increment or AI suggested increment
        const weeklyIncrement = aiNextSessionSuggestion ? Math.max(0.5, (parseWeightToNumber(aiNextSessionSuggestion.suggestedWeight, selectedExerciseName) - lastActualPoint.weight)) : 0.5;
        
        for (let i = 0; i < 11; i++) {
            lastDate = new Date(lastDate.getTime() + oneWeekMillis);
            // Ensure some minimal progression even if AI suggests maintenance or small decrease
            currentTargetWeight += Math.max(0.25, weeklyIncrement); 
            simulatedTarget.push({ date: lastDate.toISOString().split('T')[0], weight: parseFloat(currentTargetWeight.toFixed(1)), type: 'target' });
        }

    } else if (selectedExercise) { // No historical data, but exercise is selected
        let currentTargetWeight = parseWeightToNumber(selectedExercise.targetWeight, selectedExercise.name);
        let dateToStart = currentDate;

        // If AI has a suggestion (e.g. based on plan if no history), use it
        if (aiNextSessionSuggestion) {
             const aiTargetWeight = parseWeightToNumber(aiNextSessionSuggestion.suggestedWeight, selectedExerciseName);
             simulatedTarget.push({ date: dateToStart.toISOString().split('T')[0], weight: aiTargetWeight, type: 'target'});
             currentTargetWeight = aiTargetWeight;
        } else {
            simulatedTarget.push({ date: dateToStart.toISOString().split('T')[0], weight: currentTargetWeight, type: 'target'});
        }

        for (let i = 0; i < 12; i++) {
            dateToStart = new Date(dateToStart.getTime() + oneWeekMillis);
            currentTargetWeight += 0.5; // Default conservative increment
            simulatedTarget.push({ date: dateToStart.toISOString().split('T')[0], weight: parseFloat(currentTargetWeight.toFixed(1)), type: 'target' });
        }
    }
    return simulatedTarget;
  }, [chartData, aiNextSessionSuggestion, selectedExerciseId, isClient, selectedExerciseName, selectedExercise]);


  if (!isClient || (isLoading && !selectedExerciseId && allExercises.length > 0) ) {
    return <LoadingProgressiveOverloadDashboard />;
  }

  return (
    <div className="container mx-auto py-8 px-4 md:px-6 space-y-8">
      <header className="flex flex-col sm:flex-row justify-between items-center gap-4">
        <h1 className="text-3xl font-bold text-primary flex items-center">
          <LucideLineChart className="mr-3 h-8 w-8" />
          Progress Dashboard
        </h1>
        {allExercises.length > 0 ? (
            <Select value={selectedExerciseId} onValueChange={setSelectedExerciseId}>
            <SelectTrigger className="w-full sm:w-[280px] rounded-full bg-card border-primary/50 focus:ring-primary">
                <SelectValue placeholder="Select an exercise" />
            </SelectTrigger>
            <SelectContent className="bg-card border-primary/50">
                {allExercises.map(ex => (
                <SelectItem key={ex.id} value={ex.id} className="focus:bg-primary/20">
                    {ex.name}
                </SelectItem>
                ))}
            </SelectContent>
            </Select>
        ) : (
            <p className="text-muted-foreground">No trackable exercises found in your plan.</p>
        )}
      </header>

      {isLoading && selectedExerciseId && <LoadingProgressiveOverloadDashboard />}

      {!isLoading && selectedExerciseId && (
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
          <div className="lg:col-span-2 space-y-8">
            <ProgressChart 
              actualData={chartData} 
              targetData={targetProgressionData} 
              exerciseName={selectedExerciseName} 
            />
            <NextUpWidget 
              exerciseId={selectedExerciseId} 
              exerciseName={selectedExerciseName}
              aiSuggestion={aiNextSessionSuggestion} // Pass down the fetched suggestion
              onRefreshNeeded={fetchDashboardData} // Allow widget to trigger a data refresh if needed
            />
          </div>
          <div className="lg:col-span-1">
             <Card className="shadow-lg rounded-2xl">
              <CardHeader>
                <CardTitle className="text-xl font-semibold flex items-center">
                  <CalendarDays className="mr-2 h-5 w-5 text-primary" />
                  Logged Days
                </CardTitle>
                <CardDescription>Calendar view of your logged workout days.</CardDescription>
              </CardHeader>
              <CardContent className="flex justify-center">
                <Calendar
                  mode="multiple" // Show multiple selections (logged days)
                  selected={loggedDays}
                  className="rounded-md border"
                   modifiers={{
                    logged: loggedDays, // Custom modifier for logged days
                  }}
                  modifiersStyles={{
                    logged: { 
                      backgroundColor: 'hsl(var(--primary) / 0.3)', // Highlight logged days
                      borderRadius: 'var(--radius)'
                    } 
                  }}
                  disabled={{ after: new Date() }} // Disable future dates
                  // Add more props like onSelect if interaction is needed
                />
              </CardContent>
            </Card>
          </div>
        </div>
      )}

      {/* Placeholder cards when no exercise is selected or data is loading */}
      {!selectedExerciseId && !isLoading && allExercises.length > 0 && (
        <Card className="shadow-lg rounded-2xl">
            <CardHeader>
                <CardTitle className="text-xl font-semibold">Welcome!</CardTitle>
            </CardHeader>
            <CardContent className="text-center py-12">
                <History className="mx-auto h-12 w-12 text-primary mb-4" />
                <p className="text-muted-foreground">Select an exercise above to view your progress and get AI recommendations.</p>
            </CardContent>
        </Card>
      )}
       {!selectedExerciseId && !isLoading && allExercises.length === 0 && (
        <Card className="shadow-lg rounded-2xl">
            <CardHeader>
                <CardTitle className="text-xl font-semibold">No Exercises</CardTitle>
            </CardHeader>
            <CardContent className="text-center py-12">
                 <p className="text-muted-foreground">No trackable exercises found in your current workout plan. Add some to start tracking progress!</p>
            </CardContent>
        </Card>
      )}
    </div>
  );
}
