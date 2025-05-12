
// src/app/dashboard/progressive-overload/page.tsx
'use client';
import { useState, useEffect, useCallback } from 'react';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { getWorkoutByDay } from '@/data/workout-data';
import type { DailyLog, WorkoutDay } from '@/types/workout';
import { History, Loader2, CalendarDays, Flame, Lightbulb, RefreshCw } from 'lucide-react'; // Added RefreshCw for consistency if needed elsewhere
import LoadingProgressiveOverloadDashboard from './loading';
import { calculateStreaks, summarizeRecentLogs } from '@/lib/workout-utils'; // Added summarizeRecentLogs import
import { getCoachingTip, CoachingTipsOutput } from '@/ai/flows/coaching-tips-flow'; // Removed CoachingTipsInput
import { useToast } from '@/hooks/use-toast';
import { Calendar } from '@/components/ui/calendar';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from '@/components/ui/dialog';
import PastWorkoutLogView from '@/components/dashboard/past-workout-log-view';
import CoachingTipCard from '@/components/dashboard/coaching-tip-card';
import { cn } from "@/lib/utils"; // Import cn utility
import { buttonVariants } from "@/components/ui/button"; // Import buttonVariants

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
  const [coachingTip, setCoachingTip] = useState<CoachingTipsOutput | null>(null); // Initial state null
  const [isLoadingCoachingTip, setIsLoadingCoachingTip] = useState(false); // Start loading false
  const [isClient, setIsClient] = useState(false);
  const [loggedDays, setLoggedDays] = useState<Date[]>([]);
  const [streaks, setStreaks] = useState<{ current: number; longest: number }>({ current: 0, longest: 0 });
  const [selectedDate, setSelectedDate] = useState<Date | undefined>(undefined);
  const [displayMonth, setDisplayMonth] = useState<Date>(new Date()); // State for current calendar month
  const [selectedDateLog, setSelectedDateLog] = useState<DailyLog | null>(null);
  const [selectedWorkoutDay, setSelectedWorkoutDay] = useState<WorkoutDay | null>(null);
  const [isLogModalOpen, setIsLogModalOpen] = useState(false);
  const { toast } = useToast();

  // Fetch general coaching tip - now manually triggered
   const fetchCoachingTip = useCallback(async () => {
    if (!isClient || typeof window === 'undefined') return;

    setIsLoadingCoachingTip(true);
    // Don't clear previous tip immediately, let the loading state handle display
    // setCoachingTip(null); // Keep existing tip while loading if desired, or set to null for loader

    try {
      // Fetch current streaks just before fetching the tip
      const currentDays = getLoggedDays();
      const currentStreaks = calculateStreaks(currentDays);
      setStreaks(currentStreaks); // Update streaks state as well

      const tipResult = await getCoachingTip(currentStreaks); // getCoachingTip now handles internal fetch and fallbacks

      setCoachingTip(tipResult);

    } catch (e) {
      // This catch block is now less likely to be hit due to error handling inside getCoachingTip
      // but kept as a safeguard.
      console.error('Error occurred during fetchCoachingTip wrapper:', e);
      setCoachingTip({ tip: "Could not fetch coaching tip due to an unexpected error." }); // Set explicit error tip
      toast({ variant: "destructive", title: "AI Coach Error", description: "Could not fetch coaching tip." });
    } finally {
      setIsLoadingCoachingTip(false);
    }
   }, [isClient, toast]); // Removed streaks from dependency array as it's fetched inside


  // Initial setup: get logged days, calculate streaks (but don't fetch tip automatically)
  useEffect(() => {
    setIsClient(true);
    if (typeof window !== 'undefined') {
      const today = new Date();
      setDisplayMonth(new Date(Date.UTC(today.getUTCFullYear(), today.getUTCMonth(), 1))); // Initialize displayMonth
      const days = getLoggedDays();
      setLoggedDays(days);
      const calculatedStreaks = calculateStreaks(days);
      setStreaks(calculatedStreaks);
      // fetchCoachingTip(calculatedStreaks); // Removed automatic fetch
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []); // Run once on mount


  // Refresh dashboard data (re-calculate streaks) - can be triggered manually if needed elsewhere
  // Note: fetchCoachingTip now handles its own streak calculation
  const refreshDashboardData = useCallback(() => {
      if (typeof window !== 'undefined') {
          const days = getLoggedDays();
          setLoggedDays(days);
          const calculatedStreaks = calculateStreaks(days);
          setStreaks(calculatedStreaks);
          // fetchCoachingTip(); // Trigger fetch if needed after a general refresh
      }
  }, []);

  // Handle selecting a date on the calendar
  const handleDateSelect = useCallback((date: Date | undefined) => {
    if (!date || typeof window === 'undefined') return;

    // Normalize selected date to UTC start of day for comparison
    const selectedDateUTC = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()));
    // No need to update displayMonth on select, only on navigation
    // setDisplayMonth(new Date(Date.UTC(date.getFullYear(), date.getMonth(), 1)));

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
         // Attempt to find ANY log key ending with the date string
         let foundKey = null;
         try {
             for (let i = 0; i < localStorage.length; i++) {
                 const k = localStorage.key(i);
                 if (k && k.startsWith('gymtrack_log_') && k.endsWith(`_${dateStr}`)) {
                     foundKey = k;
                     break;
                 }
             }
         } catch (error) {
              console.error("Error accessing localStorage keys:", error);
              toast({ variant: "destructive", title: "Storage Error", description: "Could not access log data." });
              setSelectedDateLog(null);
              setIsLogModalOpen(false);
              return; // Exit if localStorage cannot be accessed
         }


         if (foundKey) {
             const storedLog = localStorage.getItem(foundKey);
             if (storedLog) {
                 try {
                    setSelectedDateLog(JSON.parse(storedLog));
                    setIsLogModalOpen(true);
                    toast({ variant: "default", title: "Log Found (No Plan)", description: "Showing raw log data as no current plan matches this day." });
                 } catch (error) {
                     console.error("Failed to parse stored log for selected date without plan:", error);
                     toast({ variant: "destructive", title: "Error", description: "Could not load the log data." });
                     setSelectedDateLog(null);
                     setIsLogModalOpen(false);
                 }
            } else {
                 // Key exists but value is missing/null
                toast({ variant: "default", title: "Log Data Missing", description: "Log data seems missing for this logged day." });
                setSelectedDateLog(null);
                setIsLogModalOpen(false);
            }
         } else {
             // No log key found for this date at all (shouldn't happen if isLogged was true, but safeguard)
             toast({ variant: "default", title: "Rest Day / No Log Found", description: "No workout log found for this day." });
             setSelectedDateLog(null);
             setIsLogModalOpen(false);
         }
    }

  }, [loggedDays, toast]);

  // Handle month change in the calendar navigation
   const handleMonthChange = (month: Date) => {
     // Ensure month is a valid Date object
     if (month instanceof Date && !isNaN(month.getTime())) {
        // Set display month to the first day of the selected month in UTC
        // Get UTC components to avoid timezone shifts during navigation
        const year = month.getUTCFullYear();
        const monthIndex = month.getUTCMonth();
        setDisplayMonth(new Date(Date.UTC(year, monthIndex, 1)));
     } else {
         console.error("Invalid date received for month change:", month);
         // Optionally reset to current month or show an error
         const today = new Date();
         setDisplayMonth(new Date(Date.UTC(today.getUTCFullYear(), today.getUTCMonth(), 1)));
     }
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
            {/* Ensure CardContent allows Calendar to grow */}
            <CardContent className="flex-grow flex items-center justify-center p-1 sm:p-2">
              <Calendar
                mode="single"
                selected={selectedDate}
                onSelect={handleDateSelect}
                month={displayMonth} // Control displayed month
                onMonthChange={handleMonthChange} // Handle navigation
                className="rounded-md border p-0 w-full max-w-full h-auto" // Adjusted for full width and auto height
                 modifiers={{
                  logged: loggedDays,
                 }}
                 modifiersStyles={{
                    logged: { // Use a less intense color for logged days
                        backgroundColor: 'hsl(var(--primary) / 0.2)', // More subtle highlight
                        color: 'hsl(var(--foreground))', // Ensure text remains readable
                        borderRadius: 'var(--radius)',
                        position: 'relative', // Needed for pseudo-element
                    },
                    selected: {
                         backgroundColor: 'hsl(var(--primary))',
                         color: 'hsl(var(--primary-foreground))',
                         borderRadius: 'var(--radius)',
                         fontWeight: 'bold',
                    }
                 }}
                 disabled={{ after: new Date() }} // Disable future dates
                 classNames={{
                    root: "w-full flex flex-col", // Full width, flex column
                    month: "flex flex-col space-y-2 flex-grow", // Allow month to grow
                    caption: "flex justify-center pt-1 relative items-center h-12 flex-shrink-0", // Standard caption
                    nav_button_previous: "absolute left-1",
                    nav_button_next: "absolute right-1",
                    table: "w-full border-collapse flex-grow flex flex-col", // Full width, flex column
                    head_row: "flex justify-around", // Distribute head cells
                    head_cell: "text-muted-foreground rounded-md w-[14.28%] font-normal text-[0.8rem] text-center", // Equal width
                    tbody: "flex-grow", // Allow body to take space
                    row: "flex w-full mt-1", // Rows take full width
                    cell: cn( // Cell styling from original, ensure takes space
                         "flex-1 p-0 relative text-center text-sm focus-within:relative focus-within:z-20",
                        "[&:has([aria-selected])]:bg-accent first:[&:has([aria-selected])]:rounded-l-md last:[&:has([aria-selected])]:rounded-r-md", // shadcn styles
                        "h-12 md:h-16 lg:h-20", // Make cells taller
                         "flex items-center justify-center", // Center content
                    ),
                    day: cn( // Day button styling from original
                         buttonVariants({ variant: "ghost" }),
                         "h-full w-full p-0 font-normal aria-selected:opacity-100 rounded-md", // Full size, rounded
                         "hover:bg-accent focus:outline-none focus:ring-1 focus:ring-ring", // Hover/focus
                    ),
                    day_selected: "bg-primary text-primary-foreground hover:bg-primary focus:bg-primary",
                    day_today: "bg-accent text-accent-foreground",
                    day_outside: "day-outside text-muted-foreground opacity-50",
                    day_disabled: "text-muted-foreground opacity-50",
                    day_range_middle: "aria-selected:bg-accent aria-selected:text-accent-foreground",
                    day_hidden: "invisible",
                 }}
                numberOfMonths={1}
                fixedWeeks // Keep fixed weeks for consistent height
                showOutsideDays={true} // Show outside days
              />
            </CardContent>
          </Card>

          {/* AI Coaching Tip Section - Placed Below Calendar */}
          <CoachingTipCard
              tip={coachingTip?.tip}
              isLoading={isLoadingCoachingTip}
              onRefresh={fetchCoachingTip} // Pass the fetch function
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
                   <PastWorkoutLogView workoutDay={null} dailyLog={selectedDateLog} />
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

