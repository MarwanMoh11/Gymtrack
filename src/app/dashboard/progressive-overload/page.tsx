
// src/app/dashboard/progressive-overload/page.tsx
'use client';
import { useState, useEffect, useCallback } from 'react';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { weeklyPlan, getWorkoutByDay } from '@/data/workout-data';
import type { DailyLog, WorkoutDay } from '@/types/workout';
import { History, Loader2, CalendarDays, Flame, Lightbulb } from 'lucide-react';
import LoadingProgressiveOverloadDashboard from './loading';
import { calculateStreaks, summarizeRecentLogs } from '@/lib/workout-utils';
import { getCoachingTip, CoachingTipsInput, CoachingTipsOutput } from '@/ai/flows/coaching-tips-flow';
import { useToast } from '@/hooks/use-toast';
import { Calendar } from '@/components/ui/calendar';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from '@/components/ui/dialog';
import PastWorkoutLogView from '@/components/dashboard/past-workout-log-view';
import CoachingTipCard from '@/components/dashboard/coaching-tip-card';

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
       if (!dateStr) return null; // Skip if dateStr is unexpectedly null or undefined
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
  const [coachingTip, setCoachingTip] = useState<CoachingTipsOutput | null>(null);
  const [isLoadingCoachingTip, setIsLoadingCoachingTip] = useState(false);
  const [isClient, setIsClient] = useState(false);
  const [loggedDays, setLoggedDays] = useState<Date[]>([]);
  const [streaks, setStreaks] = useState<{ current: number; longest: number }>({ current: 0, longest: 0 });
  const [selectedDate, setSelectedDate] = useState<Date | undefined>(undefined);
  const [displayMonth, setDisplayMonth] = useState<Date>(new Date()); // State for current calendar month
  const [selectedDateLog, setSelectedDateLog] = useState<DailyLog | null>(null);
  const [selectedWorkoutDay, setSelectedWorkoutDay] = useState<WorkoutDay | null>(null);
  const [isLogModalOpen, setIsLogModalOpen] = useState(false);
  const { toast } = useToast();

  // Fetch general coaching tip
   const fetchCoachingTip = useCallback(async (currentStreaks?: { current: number; longest: number }) => {
    if (!isClient || typeof window === 'undefined') return;

    setIsLoadingCoachingTip(true);
    setCoachingTip(null); // Clear previous tip

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


  // Initial setup: get logged days, calculate streaks, fetch initial coaching tip
  useEffect(() => {
    setIsClient(true);
    const today = new Date();
    setDisplayMonth(new Date(today.getFullYear(), today.getMonth(), 1)); // Initialize displayMonth
    const days = getLoggedDays();
    setLoggedDays(days);
    const calculatedStreaks = calculateStreaks(days);
    setStreaks(calculatedStreaks);
    fetchCoachingTip(calculatedStreaks); // Fetch tip after streaks are calculated
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []); // Run once on mount

  // Refresh dashboard data (e.g., after logging a workout - though logging happens elsewhere)
  // This can be called if needed, but isn't directly triggered by this page now
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
    setDisplayMonth(new Date(Date.UTC(date.getFullYear(), date.getMonth(), 1))); // Update display month

    const dateStr = formatDateLocal(selectedDateUTC); // Use the UTC date for formatting
    const isLogged = loggedDays.some(d => formatDateLocal(d) === dateStr);

    if (!isLogged) {
        toast({ variant: "default", title: "No Log", description: "No workout logged on this day." });
        setSelectedDate(undefined); // Clear selection if no log
        // Don't open modal if no log exists
        setIsLogModalOpen(false);
        setSelectedDateLog(null);
        setSelectedWorkoutDay(null);
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
            // This case might occur if a day is marked logged but the data is missing/corrupt
            setSelectedDateLog(null);
            setIsLogModalOpen(false);
            toast({ variant: "default", title: "Log Data Missing", description: "Log data seems missing for this logged day." });
        }
    } else {
         // This path handles days that have logs but no matching workout plan (e.g., plan changed)
         // Still try to load the log if it exists, even without a plan structure
         const key = `gymtrack_log_unknown_${dateStr}`; // Attempt a generic key or find based on date
         const storedLog = localStorage.getItem(key) // This part needs refinement - how are logs stored without workoutDay.id?
            || Object.keys(localStorage).find(k => k.endsWith(`_${dateStr}`)); // Brute-force find by date if needed

         if (storedLog && localStorage.getItem(storedLog)) {
             try {
                setSelectedDateLog(JSON.parse(localStorage.getItem(storedLog)!));
                setIsLogModalOpen(true);
                 toast({ variant: "default", title: "Log Found (No Plan)", description: "Showing raw log data as no current plan matches this day." });
             } catch (error) {
                 console.error("Failed to parse stored log for selected date without plan:", error);
                 toast({ variant: "destructive", title: "Error", description: "Could not load the log data." });
                 setSelectedDateLog(null);
                 setIsLogModalOpen(false);
             }
         } else {
             toast({ variant: "default", title: "Rest Day / No Plan", description: "No workout plan found for this day." });
             setSelectedDateLog(null);
             setIsLogModalOpen(false);
         }
    }

  }, [loggedDays, toast]);

  // Handle month change in the calendar navigation
   const handleMonthChange = (month: Date) => {
    setDisplayMonth(month);
   };


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
        </div>

        {/* Main Content Area - Calendar First */}
        <div className="space-y-8">
          {/* Calendar Section */}
          <Card className="shadow-lg rounded-2xl flex flex-col overflow-hidden">
            <CardHeader className="flex-shrink-0">
              <div className="flex justify-between items-center flex-wrap gap-2 mb-2">
                  <CardTitle className="text-xl font-semibold flex items-center">
                    <CalendarDays className="mr-2 h-5 w-5 text-primary" />
                    Workout Log Calendar
                  </CardTitle>
                  <div className="flex items-center gap-3 text-sm">
                       <div className="flex items-center text-primary">
                          <Flame className="h-4 w-4 mr-1"/>
                          <span>{streaks.current} Day Streak</span>
                       </div>
                       <span className="text-muted-foreground">|</span>
                       <span className="text-muted-foreground">Longest: {streaks.longest} days</span>
                  </div>
              </div>
              <CardDescription>Click a highlighted day to view the logged workout. Use arrows to navigate months.</CardDescription>
            </CardHeader>
            <CardContent className="flex-grow flex items-center justify-center p-2 sm:p-4">
              <Calendar
                mode="single"
                selected={selectedDate}
                onSelect={handleDateSelect}
                month={displayMonth} // Control displayed month
                onMonthChange={handleMonthChange} // Handle navigation
                // Removed dropdown related props: captionLayout, fromYear, toYear
                className="rounded-md border p-0 w-full h-auto aspect-[4/3] max-h-[600px]"
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
                classNames={{
                    root: "w-full h-full flex flex-col",
                    months: "flex-grow flex flex-col",
                    month: "flex-grow flex flex-col",
                    table: "flex-grow",
                    caption: "flex justify-center pt-1 relative items-center h-12 flex-shrink-0 gap-1", // Adjusted caption height and gap
                    caption_label: "text-sm font-medium", // Ensure label is visible
                    nav: "space-x-1 flex items-center",
                    nav_button: "h-7 w-7 bg-transparent p-0 opacity-50 hover:opacity-100",
                    nav_button_previous: "absolute left-1",
                    nav_button_next: "absolute right-1",
                    head_row: "flex justify-around",
                    head_cell: "w-full text-muted-foreground rounded-md font-normal text-[0.8rem] flex-1 text-center",
                    row: "flex w-full mt-2 justify-around",
                    cell: "h-auto aspect-square p-0 relative flex items-center justify-center flex-1",
                    day: "h-full w-full aspect-square text-sm font-normal aria-selected:opacity-100 rounded-md hover:bg-accent focus:outline-none focus:ring-1 focus:ring-ring",
                    day_selected: "bg-primary text-primary-foreground hover:bg-primary focus:bg-primary",
                    day_today: "bg-accent text-accent-foreground",
                    day_outside: "day-outside text-muted-foreground opacity-50",
                    day_disabled: "text-muted-foreground opacity-50",
                    day_range_middle: "aria-selected:bg-accent aria-selected:text-accent-foreground",
                    day_hidden: "invisible",
                    // Removed dropdown styles
                }}
                numberOfMonths={1}
                fixedWeeks
              />
            </CardContent>
          </Card>

          {/* AI Coaching Tip Section - Placed Below Calendar */}
          <CoachingTipCard
              tip={coachingTip?.tip}
              isLoading={isLoadingCoachingTip}
              // Removed onRefresh as button is removed
           />
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
                 // Improved feedback: Check if log exists but plan doesn't
                 !selectedWorkoutDay && selectedDateLog ? (
                   // Render log data even without a plan structure if possible
                   // This requires PastWorkoutLogView to handle missing workoutDay gracefully
                   <PastWorkoutLogView workoutDay={null} dailyLog={selectedDateLog} />
                   // <p className="text-muted-foreground text-center mt-8">No current workout plan matches this day, but a log was found.</p>
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
