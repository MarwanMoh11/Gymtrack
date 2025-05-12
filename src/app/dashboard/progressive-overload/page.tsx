
// src/app/dashboard/progressive-overload/page.tsx
'use client';
import { useState, useEffect, useCallback } from 'react';
// Removed Select imports as exercise selection is removed
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
// Removed NextUpWidget import
import { weeklyPlan, getWorkoutByDay } from '@/data/workout-data';
import type { DailyLog, WorkoutDay } from '@/types/workout';
import { History, Loader2, CalendarDays, Flame, Lightbulb } from 'lucide-react'; // Added Lightbulb
import LoadingProgressiveOverloadDashboard from './loading';
// Removed getAllExercises, parseWeightToNumber, transformHistoricalDataForAI, nextSessionRecommendation imports
import { calculateStreaks, summarizeRecentLogs } from '@/lib/workout-utils'; // Import new log summarizer
import { getCoachingTip, CoachingTipsInput, CoachingTipsOutput } from '@/ai/flows/coaching-tips-flow'; // Import new coaching tip flow
import { useToast } from '@/hooks/use-toast';
import { Calendar } from '@/components/ui/calendar';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from '@/components/ui/dialog';
import PastWorkoutLogView from '@/components/dashboard/past-workout-log-view';
import CoachingTipCard from '@/components/dashboard/coaching-tip-card'; // Import new component

// Removed getHistoricalDataForExercise function

const getLoggedDays = (): Date[] => {
  if (typeof window === 'undefined') return [];
  const loggedDates = new Set<string>();
  try {
    for (let i = 0; i < localStorage.length; i++) {
      const key = localStorage.key(i);
      if (!key || !key.startsWith('gymtrack_log_')) continue; // Skip irrelevant keys early

      const match = key.match(/^gymtrack_log_[a-zA-Z0-9-]+_(\d{4}-\d{2}-\d{2})$/);
      if (match && match[1]) { // Ensure match and capturing group exist
        const dateString = match[1];
        const logContent = localStorage.getItem(key);
        if (logContent && logContent !== '{}') {
           try {
             const parsedLog = JSON.parse(logContent);
             // Check if any exercise in the log has at least one completed set
             if (Object.values(parsedLog).some((exerciseLog: any) =>
                 typeof exerciseLog === 'object' && exerciseLog !== null && // Check if exerciseLog is an object
                 Object.values(exerciseLog).some((set: any) => typeof set === 'object' && set !== null && set.isCompleted)
             )) {
                 loggedDates.add(dateString); // Add the valid date string
             }
           } catch (e) {
               console.error("Error parsing log content for date check:", key, e);
               // Optionally remove the corrupted item: localStorage.removeItem(key);
           }
        }
      }
    }
  } catch (error) {
    console.error("Error accessing localStorage:", error);
    // Handle potential security errors or other localStorage issues
  }

  // Filter out invalid date strings before mapping
  return Array.from(loggedDates)
    .filter(dateStr => typeof dateStr === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(dateStr)) // Ensure it's the correct format
    .map(dateStr => {
      const [year, month, day] = dateStr.split('-').map(Number);
      // Add another check for parsing results
      if (isNaN(year) || isNaN(month) || isNaN(day) || month < 1 || month > 12 || day < 1 || day > 31) {
         console.error("Failed to parse valid date components from string:", dateStr);
         return null; // Indicate failure
      }
      // Create Date object using UTC to avoid timezone issues
      return new Date(Date.UTC(year, month - 1, day));
    })
    .filter((date): date is Date => date !== null); // Remove null entries from failed parsing
};


const formatDateLocal = (date: Date): string => {
  // Use UTC methods to format to avoid timezone shifts affecting the date string
  const year = date.getUTCFullYear();
  const month = (date.getUTCMonth() + 1).toString().padStart(2, '0');
  const day = date.getUTCDate().toString().padStart(2, '0');
  return `${year}-${month}-${day}`;
};

function getLocalStorageKey(dayId: string, date: Date): string {
  const dateStr = formatDateLocal(date);
  return `gymtrack_log_${dayId}_${dateStr}`;
}

export default function ProgressiveOverloadDashboardPage() {
  // Removed state related to selectedExerciseId and specific AI suggestions
  const [coachingTip, setCoachingTip] = useState<CoachingTipsOutput | null>(null);
  const [isLoadingCoachingTip, setIsLoadingCoachingTip] = useState(false);
  const [isClient, setIsClient] = useState(false);
  const [loggedDays, setLoggedDays] = useState<Date[]>([]);
  const [streaks, setStreaks] = useState<{ current: number; longest: number }>({ current: 0, longest: 0 });
  const [selectedDate, setSelectedDate] = useState<Date | undefined>(undefined);
  const [selectedDateLog, setSelectedDateLog] = useState<DailyLog | null>(null);
  const [selectedWorkoutDay, setSelectedWorkoutDay] = useState<WorkoutDay | null>(null);
  const [isLogModalOpen, setIsLogModalOpen] = useState(false);
  const { toast } = useToast();

  // Initial setup: get logged days, calculate streaks, fetch initial coaching tip
  useEffect(() => {
    setIsClient(true);
    const days = getLoggedDays();
    setLoggedDays(days);
    const calculatedStreaks = calculateStreaks(days);
    setStreaks(calculatedStreaks);
    fetchCoachingTip(calculatedStreaks); // Fetch tip after streaks are calculated
  }, []); // Run once on mount

  // Fetch general coaching tip
  const fetchCoachingTip = useCallback(async (currentStreaks?: { current: number; longest: number }) => {
    if (!isClient || typeof window === 'undefined') return;

    setIsLoadingCoachingTip(true);
    setCoachingTip(null);

    try {
      const recentLogs = summarizeRecentLogs(); // Get summarized logs
      const streaksToUse = currentStreaks || streaks; // Use provided streaks or current state

      const input: CoachingTipsInput = {
        recentLogs: recentLogs,
        streakData: streaksToUse,
        // userGoal: "Optional user goal here", // Can be added later if needed
      };
      const tipResult = await getCoachingTip(input);
      setCoachingTip(tipResult);
    } catch (e) {
      console.error('Coaching Tip Error:', e);
      toast({ variant: "destructive", title: "AI Coach Error", description: "Could not fetch coaching tip." });
      setCoachingTip({ tip: "Could not fetch tip. Keep logging consistently!" }); // Set a fallback tip on error
    } finally {
      setIsLoadingCoachingTip(false);
    }
  }, [isClient, streaks, toast]); // Depends on streaks state if not provided

  // Refresh logged days, streaks, and fetch a new tip
  const refreshDashboardData = useCallback(() => {
      const days = getLoggedDays();
      setLoggedDays(days);
      const calculatedStreaks = calculateStreaks(days);
      setStreaks(calculatedStreaks);
      fetchCoachingTip(calculatedStreaks); // Fetch tip with updated streaks
  }, [fetchCoachingTip]);

  // Handle selecting a date on the calendar
  const handleDateSelect = useCallback((date: Date | undefined) => {
    if (!date || typeof window === 'undefined') return;
    
    // Normalize selected date to UTC start of day for comparison
    const selectedDateUTC = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()));

    const dateStr = formatDateLocal(selectedDateUTC); // Use the UTC date for formatting
    const isLogged = loggedDays.some(d => formatDateLocal(d) === dateStr);

    if (!isLogged) {
        toast({ variant: "default", title: "No Log", description: "No workout logged on this day." });
        setSelectedDate(undefined);
        return;
    }
    
    setSelectedDate(selectedDateUTC); // Store the UTC normalized date

    // Use getUTCDay() for consistency as we are working with UTC dates
    const dayIndex = selectedDateUTC.getUTCDay(); 
    const daysOfWeek = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"];
    const dayId = daysOfWeek[dayIndex];
    const workoutForDay = getWorkoutByDay(dayId);
    setSelectedWorkoutDay(workoutForDay);

    if (workoutForDay) {
        // Use the selected UTC date to generate the key
        const key = getLocalStorageKey(workoutForDay.id, selectedDateUTC); 
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
            setSelectedDateLog(null);
            setIsLogModalOpen(false);
            toast({ variant: "default", title: "No Log Found", description: "Log data seems missing for this logged day." });
        }
    } else {
         toast({ variant: "default", title: "Rest Day / No Plan", description: "No specific workout plan found for this day." });
         setSelectedDateLog(null);
         setIsLogModalOpen(false);
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
            {/* Exercise Select Removed */}
        </div>

        <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
          {/* Calendar Section (Larger) */}
          <div className="lg:col-span-2 space-y-8">
             {/* Streak Card Removed */}

             <Card className="shadow-lg rounded-2xl">
              <CardHeader>
                <div className="flex justify-between items-center flex-wrap gap-2">
                    <CardTitle className="text-xl font-semibold flex items-center">
                      <CalendarDays className="mr-2 h-5 w-5 text-primary" />
                      Logged Workouts Calendar
                    </CardTitle>
                    {/* Integrated Streak Display */}
                    <div className="flex items-center gap-3 text-sm">
                         <div className="flex items-center text-primary">
                            <Flame className="h-4 w-4 mr-1"/>
                            <span>{streaks.current} Day Streak</span>
                         </div>
                         <span className="text-muted-foreground">|</span>
                         <span className="text-muted-foreground">Longest: {streaks.longest} days</span>
                    </div>
                </div>
                <CardDescription>Click a highlighted day to view the logged workout.</CardDescription>
              </CardHeader>
              <CardContent className="flex justify-center p-2 sm:p-4"> {/* Adjusted padding */}
                <Calendar
                  mode="single"
                  selected={selectedDate}
                  onSelect={handleDateSelect}
                  className="rounded-md border p-0 w-full" // Make calendar fill container width
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
                    selected: {
                       backgroundColor: 'hsl(var(--primary))',
                       color: 'hsl(var(--primary-foreground))',
                       borderRadius: 'var(--radius)'
                    }
                  }}
                  disabled={{ after: new Date() }} // Disable future dates
                  // Attempt to make calendar cells larger 
                  classNames={{
                      day: "h-10 w-10 sm:h-12 sm:w-12 text-base", // Increase day cell size & font
                      head_cell: "w-10 sm:w-12", // Adjust header cell width
                      // Customize month navigation buttons if needed
                      // nav_button: "h-8 w-8", 
                  }}
                  // Ensure it displays the current month by default, or the month of the selected date
                  month={selectedDate ? new Date(selectedDate.getFullYear(), selectedDate.getMonth(), 1) : new Date()} 
                />
              </CardContent>
            </Card>
          </div>

          {/* AI Coaching Tip Section */}
          <div className="lg:col-span-1">
             <CoachingTipCard
                tip={coachingTip?.tip}
                isLoading={isLoadingCoachingTip}
                onRefresh={refreshDashboardData}
             />
          </div>
        </div>

      {/* Modal to display past workout log */}
        <Dialog open={isLogModalOpen} onOpenChange={setIsLogModalOpen}>
          <DialogContent className="max-w-3xl h-[80vh] flex flex-col">
            <DialogHeader>
              <DialogTitle>Workout Log: {selectedDate ? formatDateLocal(selectedDate) : ''}</DialogTitle>
              <DialogDescription>
                Showing workout logged on {selectedDate ? selectedDate.toLocaleDateString(undefined, { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric', timeZone: 'UTC' }) : ''}.
              </DialogDescription>
            </DialogHeader>
            <div className="flex-grow overflow-y-auto pr-2 -mr-6 pl-6">
              {selectedWorkoutDay && selectedDateLog ? (
                 <PastWorkoutLogView workoutDay={selectedWorkoutDay} dailyLog={selectedDateLog} />
              ) : (
                 // Provide specific feedback if no workout structure found
                 !selectedWorkoutDay && selectedDateLog ? (
                    <p className="text-muted-foreground text-center mt-8">No workout plan structure found for this day, but a log exists.</p>
                 ) : (
                    <p className="text-muted-foreground text-center mt-8">Log details could not be loaded.</p>
                 )
              )}
            </div>
          </DialogContent>
        </Dialog>
    </div>
  );
}
