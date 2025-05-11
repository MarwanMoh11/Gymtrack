// src/app/dashboard/progressive-overload/page.tsx
'use client';
import { useState, useEffect, useMemo, useCallback } from 'react';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { ProgressChart, type ChartDataPoint } from '@/components/dashboard/progress-chart';
import { NextUpWidget } from '@/components/dashboard/next-up-widget';
import { weeklyPlan } from '@/data/workout-data';
import type { DailyLog, LoggedSetData, Exercise as ExerciseType } from '@/types/workout';
import { LineChart as LucideLineChart, History } from 'lucide-react';
import { Skeleton } from '@/components/ui/skeleton';

const getAllExercises = (): Array<{ id: string; name: string }> => {
  const exercisesMap = new Map<string, string>();
  weeklyPlan.forEach(day => {
    day.exercises.forEach(ex => {
      // Filter out non-progressing items like warmups, conditioning for this specific dashboard
      if (!ex.isWarmup && !ex.isConditioning && !ex.isStretch && !ex.isFoamRoll && !ex.isActivity && !ex.isMatch && !ex.isRecovery) {
        if (!exercisesMap.has(ex.id)) {
          exercisesMap.set(ex.id, ex.name);
        }
      }
    });
  });
  return Array.from(exercisesMap, ([id, name]) => ({ id, name })).sort((a,b) => a.name.localeCompare(b.name));
};

// Enhanced function to parse weight string to number
const parseWeightToNumber = (weightString: string | number | undefined, exerciseName?: string): number => {
    if (typeof weightString === 'number') return weightString;
    if (typeof weightString !== 'string') return 0;

    const lowerWeightString = weightString.toLowerCase();
    
    if (lowerWeightString.includes('bodyweight') || lowerWeightString.includes('bw')) {
        // Approx bodyweight, could be dynamic based on user profile in future
        // For now, a placeholder. If "+5kg" etc. is present, extract that.
        const bodyweightBase = 70; // Example placeholder for BW in kg
        const match = lowerWeightString.match(/bodyweight\s*\+\s*([\d.]+)\s*kg/i) || lowerWeightString.match(/bw\s*\+\s*([\d.]+)\s*kg/i);
        if (match && match[1]) {
            return bodyweightBase + parseFloat(match[1]);
        }
        return bodyweightBase;
    }
    
    // Match numbers, potentially with "kg" or "lbs" or "stack"
    const numericMatch = lowerWeightString.match(/([\d.]+)/);
    if (numericMatch && numericMatch[1]) {
        let value = parseFloat(numericMatch[1]);
        // Rudimentary stack conversion - highly dependent on machine
        if (lowerWeightString.includes('stack')) {
             // Example: "1st stack", "2nd stack". Assume ~5kg or 10lb increment per stack position.
             // This is a very rough heuristic and ideally needs machine-specific data.
             value = value * 5; // e.g., 5th stack = 25kg
        } else if (lowerWeightString.includes('each side')) {
            value = value * 2; // For barbells, e.g., "7.5kg each side"
        }
        // Add more specific parsing if needed, e.g. for "plates"
        return value;
    }
    return 0; 
};


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
            const exerciseLog = dayLog[exerciseId]; // LoggedExerciseData
            let maxWeightForDay = 0;
            let repsForMaxWeight: string | number | undefined = undefined;

            Object.values(exerciseLog).forEach((loggedSet: LoggedSetData) => {
              if (loggedSet.isCompleted && (loggedSet.weight !== undefined || exerciseName)) { // Ensure weight is meaningful
                const currentWeightNumber = parseWeightToNumber(loggedSet.weight, exerciseName);
                if (currentWeightNumber > maxWeightForDay) {
                  maxWeightForDay = currentWeightNumber;
                  repsForMaxWeight = loggedSet.reps;
                }
              }
            });

            if (maxWeightForDay > 0) {
              collectedData.push({ dateStr, dailyMaxWeight: maxWeightForDay, reps: repsForMaxWeight });
            }
          }
        } catch (error) {
          console.error(`Error parsing localStorage item ${key}:`, error);
        }
      }
    }
  }

  // Sort by date
  collectedData.sort((a, b) => new Date(a.dateStr).getTime() - new Date(b.dateStr).getTime());

  // Calculate PRs and format for chart
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


export default function ProgressiveOverloadDashboardPage() {
  const [allExercises, setAllExercises] = useState<Array<{ id: string; name: string }>>([]);
  const [selectedExerciseId, setSelectedExerciseId] = useState<string | undefined>(undefined);
  const [chartData, setChartData] = useState<ChartDataPoint[]>([]);
  const [targetProgressionData, setTargetProgressionData] = useState<ChartDataPoint[]>([]);
  const [isLoading, setIsLoading] = useState(true); // Start true for initial exercise list load
  const [isClient, setIsClient] = useState(false);


  useEffect(() => {
    setIsClient(true); // Indicate client-side rendering is active
    const exercises = getAllExercises();
    setAllExercises(exercises);
    if (exercises.length > 0 && !selectedExerciseId) {
      setSelectedExerciseId(exercises[0].id);
    } else if (exercises.length === 0) {
        setIsLoading(false); // No exercises, stop loading
    }
  }, [selectedExerciseId]);

  const selectedExerciseName = useMemo(() => {
    return allExercises.find(ex => ex.id === selectedExerciseId)?.name || '';
  }, [selectedExerciseId, allExercises]);

  const fetchDataForExercise = useCallback(() => {
    if (selectedExerciseId && isClient) {
      setIsLoading(true);
      const historicalData = getHistoricalDataForExercise(selectedExerciseId, selectedExerciseName);
      setChartData(historicalData);

      if (historicalData.length > 0) {
        const firstPoint = historicalData[0];
        const lastPointDate = new Date(historicalData[historicalData.length - 1].date);
        
        const simulatedTarget: ChartDataPoint[] = [];
        let currentTargetWeight = firstPoint.weight;
        const incrementPerWeek = 0.5; // Target: +0.5kg per week from start (very conservative)

        // Project target for 12 weeks from the first data point or up to 4 weeks beyond last data point
        const projectionEndDate = new Date(lastPointDate);
        projectionEndDate.setDate(projectionEndDate.getDate() + (4 * 7)); // 4 weeks beyond last data

        for (let d = new Date(firstPoint.date); d <= projectionEndDate; d.setDate(d.getDate() + 7)) {
            simulatedTarget.push({ date: new Date(d).toISOString().split('T')[0], weight: parseFloat(currentTargetWeight.toFixed(1)), type: 'target' });
            currentTargetWeight += incrementPerWeek;
        }
        setTargetProgressionData(simulatedTarget);
      } else {
        setTargetProgressionData([]);
      }
      setIsLoading(false);
    } else if (!selectedExerciseId && isClient) {
        setChartData([]);
        setTargetProgressionData([]);
        setIsLoading(false);
    }
  }, [selectedExerciseId, isClient, selectedExerciseName]);


  useEffect(() => {
    fetchDataForExercise();
  }, [fetchDataForExercise]);

  if (!isClient) {
    // Render skeleton or minimal loading state during SSR or before client hydration
    return <LoadingProgressiveOverloadDashboard />;
  }

  return (
    <div className="container mx-auto py-8 px-4 md:px-6 space-y-8">
      <header className="flex flex-col sm:flex-row justify-between items-center gap-4">
        <h1 className="text-3xl font-bold text-primary flex items-center">
          <LucideLineChart className="mr-3 h-8 w-8" />
          Progressive Overload Dashboard
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
        <>
          <ProgressChart 
            actualData={chartData} 
            targetData={targetProgressionData} 
            exerciseName={selectedExerciseName} 
          />
          <NextUpWidget 
            exerciseId={selectedExerciseId} 
            exerciseName={selectedExerciseName}
            historicalData={chartData} // Pass processed chart data for context
          />
        </>
      )}
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

// Minimal Loading component for SSR / initial client render before hydration
function LoadingProgressiveOverloadDashboard() {
  return (
    <div className="container mx-auto py-8 px-4 md:px-6 space-y-8">
      <div className="flex flex-col sm:flex-row justify-between items-center gap-4">
        <Skeleton className="h-10 w-1/2 sm:w-1/3 bg-muted/50" />
        <Skeleton className="h-10 w-full sm:w-1/4 bg-muted/50" />
      </div>
      <Skeleton className="h-80 w-full bg-muted/50 rounded-2xl" />
      <Skeleton className="h-40 w-full bg-muted/50 rounded-2xl" />
    </div>
  );
}
