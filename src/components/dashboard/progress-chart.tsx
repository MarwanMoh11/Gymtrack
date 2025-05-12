
// src/app/dashboard/progressive-overload/page.tsx
'use client';
import { useState, useEffect, useMemo, useCallback } from 'react';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { NextUpWidget } from '@/components/dashboard/next-up-widget';
import { weeklyPlan, getWorkoutByDay } from '@/data/workout-data';
import type { DailyLog, WorkoutDay, Exercise as ExerciseType } from '@/types/workout';
import { History, Loader2, CalendarDays, Activity, Flame } from 'lucide-react';
import LoadingProgressiveOverloadDashboard from './loading';
import { getAllExercises, parseWeightToNumber, transformHistoricalDataForAI, calculateStreaks } from '@/lib/workout-utils';
import { nextSessionRecommendation, NextSessionRecommendationInput, NextSessionRecommendationOutput } from '@/ai/flows/next-session-recommendation';
import { useToast } from '@/hooks/use-toast';
import { Calendar } from '@/components/ui/calendar';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from '@/components/ui/dialog';
import PastWorkoutLogView from '@/components/dashboard/past-workout-log-view'; // New component to view past logs

// Function to get historical data (simplified, only needed for AI now)
const getHistoricalDataForExercise = (exerciseId: string): any[] => {
  if (typeof window === 'undefined') return [];
  
  const collectedData: any[] = [];
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
             // Basic check to see if there's *any* data logged for the exercise on this day
            if (Object.values(dayLog[exerciseId]).some(set => set.isCompleted)) {
              collectedData.push({ date: dateStr }); // Just need the date for checking length > 0
            }
          }
        } catch (error) {
          console.error(`Error parsing localStorage item ${key}:`, error);
        }
      }
    }
  }
  return collectedData;
};

const getLoggedDays = (): Date[] => {
  if (typeof window === 'undefined') return [];
  const loggedDates = new Set<string>();
  for (let i = 0; i < localStorage.length; i++) {
    const key = localStorage.key(i);
    if (!key) continue;
    const match = key.match(/^gymtrack_log_[a-zA-Z0-9-]+_(\d{4}-\d{2}-\d{2})$/);
    if (match) {
      // Ensure the log is not empty before adding the date
      const logContent = localStorage.getItem(key);
      if (logContent && logContent !== '{}') {
         try {
           const parsedLog = JSON.parse(logContent);
           // Check if there's at least one completed set in the log
           if (Object.values(parsedLog).some((exerciseLog: any) => 
               Object.values(exerciseLog).some((set: any) => set.isCompleted)
           )) {
               loggedDates.add(match[2]); // Use index 2 for the date YYYY-MM-DD
           }
         } catch (e) {
             console.error("Error parsing log for date check:", key, e);
         }
      }
    }
  }
  // Convert string dates to Date objects, handling potential timezone issues
  return Array.from(loggedDates).map(dateStr => {
    const [year, month, day] = dateStr.split('-').map(Number);
    return new Date(Date.UTC(year, month - 1, day)); // Use UTC to avoid timezone shifts
  });
};

// Helper to format date as YYYY-MM-DD in local timezone
const formatDateLocal = (date: Date): string => {
  const year = date.getFullYear();
  const month = (date.getMonth() + 1).toString().padStart(2, '0');
  const day = date.getDate().toString().padStart(2, '0');
  return `${year}-${month}-${day}`;
};

// Helper to get local storage key using local date
function getLocalStorageKey(dayId: string, date: Date): string {
  const dateStr = formatDateLocal(date);
  return `gymtrack_log_${dayId}_${dateStr}`;
}

export default function ProgressiveOverloadDashboardPage() {
  const [allExercises, setAllExercises] = useState<Array<{ id: string; name: string }>>([]);
  const [selectedExerciseId, setSelectedExerciseId] = useState<string | undefined>(undefined);
  const [aiNextSessionSuggestion, setAiNextSessionSuggestion] = useState<NextSessionRecommendationOutput | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [isClient, setIsClient] = useState(false);
  const [loggedDays, setLoggedDays] = useState<Date[]>([]);
  const [streaks, setStreaks] = useState<{ current: number; longest: number }>({ current: 0, longest: 0 });
  const [selectedDate, setSelectedDate] = useState<Date | undefined>(undefined);
  const [selectedDateLog, setSelectedDateLog] = useState<DailyLog | null>(null);
  const [selectedWorkoutDay, setSelectedWorkoutDay] = useState<WorkoutDay | null>(null);
  const [isLogModalOpen, setIsLogModalOpen] = useState(false);
  const { toast } = useToast();

  // Initial setup: get exercises, logged days, calculate streaks
  useEffect(() => {
    setIsClient(true);
    const exercises = getAllExercises();
    setAllExercises(exercises);
    const days = getLoggedDays();
    setLoggedDays(days);
    setStreaks(calculateStreaks(days)); // Calculate streaks

    if (exercises.length > 0 && !selectedExerciseId) {
      // Don't automatically select an exercise initially
      setIsLoading(false); 
    } else if (exercises.length === 0) {
      setIsLoading(false);
    }
  }, []); // Run once on mount

  const selectedExercise = useMemo(() => {
    return weeklyPlan.flatMap(day => day.exercises).find(ex => ex.id === selectedExerciseId);
  }, [selectedExerciseId]);

  const selectedExerciseName = selectedExercise?.name || '';

  // Fetch AI suggestion when exercise changes
  const fetchAISuggestion = useCallback(async () => {
    if (!selectedExerciseId || !isClient) {
      setAiNextSessionSuggestion(null);
      return;
    }
    
    setIsLoading(true); // Indicate loading for AI suggestion specifically
    setAiNextSessionSuggestion(null); // Clear previous suggestion

    const historicalData = getHistoricalDataForExercise(selectedExerciseId); // Check if we have history
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
          console.error('AI Recommendation Error:', e);
          toast({ variant: "destructive", title: "AI Error", description: "Could not fetch AI suggestion." });
          setAiNextSessionSuggestion(null);
        }
      } else {
        setAiNextSessionSuggestion(null); // No recent data for AI
      }
    } else {
      setAiNextSessionSuggestion(null); // No historical data at all
    }
    setIsLoading(false); // Finished loading AI suggestion
  }, [selectedExerciseId, isClient, selectedExerciseName, toast]);

  // Trigger AI fetch when selectedExerciseId changes
  useEffect(() => {
    fetchAISuggestion();
  }, [fetchAISuggestion]);

  // Refresh logged days and streaks
  const refreshLoggedDays = useCallback(() => {
      const days = getLoggedDays();
      setLoggedDays(days);
      setStreaks(calculateStreaks(days));
  }, []);


  // Handle selecting a date on the calendar
  const handleDateSelect = useCallback((date: Date | undefined) => {
    if (!date || typeof window === 'undefined') return;

    // Check if the selected date is actually a logged day
    const dateStr = formatDateLocal(date);
    const isLogged = loggedDays.some(d => formatDateLocal(d) === dateStr);

    if (!isLogged) {
        toast({ variant: "default", title: "No Log", description: "No workout logged on this day." });
        setSelectedDate(undefined); // Clear selection if not logged
        return;
    }

    setSelectedDate(date);

    const dayIndex = date.getDay(); // 0 for Sunday, 1 for Monday, etc.
    const daysOfWeek = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"];
    const dayId = daysOfWeek[dayIndex];
    const workoutForDay = getWorkoutByDay(dayId);
    setSelectedWorkoutDay(workoutForDay); // Store the workout structure for the selected day

    if (workoutForDay) {
        const key = getLocalStorageKey(workoutForDay.id, date);
        const storedLog = localStorage.getItem(key);
        if (storedLog) {
            try {
            setSelectedDateLog(JSON.parse(storedLog));
            setIsLogModalOpen(true);
            } catch (error) {
            console.error("Failed to parse stored log for selected date:", error);
            toast({ variant: "destructive", title: "Error", description: "Could not load the log for the selected date." });
            setSelectedDateLog(null);
            setIsLogModalOpen(false);
            }
        } else {
            // Should not happen if isLogged check passed, but handle defensively
            setSelectedDateLog(null);
            setIsLogModalOpen(false);
            toast({ variant: "default", title: "No Log Found", description: "Log data seems missing for this logged day." });
        }
    } else {
        // No planned workout for this day of the week
         toast({ variant: "default", title: "Rest Day", description: "No workout scheduled for this day of the week." });
         setSelectedDateLog(null); // Set log to null
         setIsLogModalOpen(false); // Don't open modal if no workout structure
    }

  }, [loggedDays, toast]);

  if (!isClient) {
    return <LoadingProgressiveOverloadDashboard />;
  }

  return (
    <div className="container mx-auto py-8 px-4 md:px-6 space-y-8">
        <div className="flex flex-col sm:flex-row justify-between items-center gap-4">
            <h1 className="text-3xl font-bold text-primary flex items-center">
              <History className="mr-3 h-8 w-8" />
              Progress & History
            </h1>
            {allExercises.length > 0 && (
                 <Select value={selectedExerciseId} onValueChange={setSelectedExerciseId}>
                    <SelectTrigger className="w-full sm:w-[280px] rounded-full bg-card border-primary/50 focus:ring-primary">
                        <SelectValue placeholder="Select exercise for AI insights" />
                    </SelectTrigger>
                    <SelectContent className="bg-card border-primary/50">
                        {allExercises.map(ex => (
                        <SelectItem key={ex.id} value={ex.id} className="focus:bg-primary/20">
                            {ex.name}
                        </SelectItem>
                        ))}
                    </SelectContent>
                </Select>
            )}
        </div>

        <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
          {/* Calendar and Streaks Section */}
          <div className="lg:col-span-2 space-y-8">
             <Card className="shadow-lg rounded-2xl">
              <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
                <CardTitle className="text-lg font-medium">Workout Streaks</CardTitle>
                <Flame className="h-5 w-5 text-primary" />
              </CardHeader>
              <CardContent className="flex justify-around pt-2">
                <div className="text-center">
                  <div className="text-3xl font-bold text-primary">{streaks.current}</div>
                  <p className="text-xs text-muted-foreground">Current Streak (days)</p>
                </div>
                <div className="text-center">
                  <div className="text-3xl font-bold">{streaks.longest}</div>
                  <p className="text-xs text-muted-foreground">Longest Streak (days)</p>
                </div>
              </CardContent>
            </Card>

             <Card className="shadow-lg rounded-2xl">
              <CardHeader>
                <CardTitle className="text-xl font-semibold flex items-center">
                  <CalendarDays className="mr-2 h-5 w-5 text-primary" />
                  Logged Workouts Calendar
                </CardTitle>
                <CardDescription>Click a highlighted day to view the logged workout.</CardDescription>
              </CardHeader>
              <CardContent className="flex justify-center">
                <Calendar
                  mode="single"
                  selected={selectedDate}
                  onSelect={handleDateSelect}
                  className="rounded-md border p-0" // Remove default padding
                   modifiers={{
                    logged: loggedDays,
                  }}
                  modifiersStyles={{
                    logged: { 
                      backgroundColor: 'hsl(var(--primary) / 0.3)',
                      color: 'hsl(var(--primary-foreground))',
                      fontWeight: 'bold',
                      borderRadius: 'var(--radius)'
                    },
                    selected: { // Style for the clicked day
                       backgroundColor: 'hsl(var(--primary))',
                       color: 'hsl(var(--primary-foreground))',
                       borderRadius: 'var(--radius)'
                    }
                  }}
                  disabled={{ after: new Date() }} 
                />
              </CardContent>
            </Card>
          </div>

          {/* AI Suggestion Section */}
          <div className="lg:col-span-1">
            {selectedExerciseId ? (
                 <NextUpWidget 
                    exerciseId={selectedExerciseId} 
                    exerciseName={selectedExerciseName}
                    aiSuggestion={aiNextSessionSuggestion}
                    onRefreshNeeded={fetchAISuggestion} // Allow widget to trigger a refresh
                    isLoading={isLoading} // Pass loading state
                />
            ) : (
                 <Card className="shadow-lg rounded-2xl h-full">
                    <CardHeader>
                        <CardTitle className="text-xl font-semibold">AI Insights</CardTitle>
                        <CardDescription>Select an exercise above to get AI-powered suggestions for your next session based on your progress.</CardDescription>
                    </CardHeader>
                    <CardContent className="flex items-center justify-center h-full pb-20">
                         <Activity className="h-16 w-16 text-muted-foreground/30" />
                    </CardContent>
                </Card>
            )}
           
            {!selectedExerciseId && allExercises.length === 0 && (
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
        </div>

      {/* Modal to display past workout log */}
        <Dialog open={isLogModalOpen} onOpenChange={setIsLogModalOpen}>
          <DialogContent className="max-w-3xl h-[80vh] flex flex-col">
            <DialogHeader>
              <DialogTitle>Workout Log: {selectedDate ? formatDateLocal(selectedDate) : ''}</DialogTitle>
              <DialogDescription>
                Showing workout logged on {selectedDate ? selectedDate.toLocaleDateString(undefined, { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric' }) : ''}.
              </DialogDescription>
            </DialogHeader>
            <div className="flex-grow overflow-y-auto pr-2 -mr-6 pl-6"> 
              {selectedWorkoutDay && selectedDateLog ? (
                 <PastWorkoutLogView workoutDay={selectedWorkoutDay} dailyLog={selectedDateLog} />
              ) : (
                <p className="text-muted-foreground text-center mt-8">Log details could not be loaded.</p>
              )}
            </div>
          </DialogContent>
        </Dialog>
    </div>
  );
}

```
  </change>

  <change>
    <file>src/components/dashboard/progress-chart.tsx</file>
    <description>Delete progress chart component as it's no longer used in the revamped Progressive Overload dashboard