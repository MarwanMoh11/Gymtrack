
// src/app/dashboard/progressive-overload/page.tsx
'use client';
import { useState, useEffect, useCallback } from 'react';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { getWorkoutByDay } from '@/data/workout-data';
import type { DailyLog, WorkoutDay } from '@/types/workout';
import { History, CalendarDays, Flame } from 'lucide-react'; // Removed Lightbulb, RefreshCw
import LoadingProgressiveOverloadDashboard from './loading';
import { calculateStreaks } from '@/lib/workout-utils';
import { useToast } from '@/hooks/use-toast';
import { Calendar } from '@/components/ui/calendar';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from '@/components/ui/dialog';
import PastWorkoutLogView from '@/components/dashboard/past-workout-log-view';
import { cn } from "@/lib/utils";
import { buttonVariants } from "@/components/ui/button";

const getLoggedDays = (): Date[] => {
  if (typeof window === 'undefined') return [];
  const loggedDates = new Set<string>();
  try {
    for (let i = 0; i < localStorage.length; i++) {
      const key = localStorage.key(i);
      if (!key || !key.startsWith('gymtrack_log_')) continue;

      const match = key.match(/^gymtrack_log_[a-zA-Z0-9-]+_(\d{4}-\d{2}-\d{2})$/);
      if (match && match[1]) {
        const dateString = match[1];
        const logContent = localStorage.getItem(key);
        if (logContent && logContent !== '{}') {
           try {
             const parsedLog = JSON.parse(logContent);
             if (Object.values(parsedLog).some((exerciseLog: any) =>
                 typeof exerciseLog === 'object' && exerciseLog !== null &&
                 Object.values(exerciseLog).some((set: any) => typeof set === 'object' && set !== null && set.isCompleted)
             )) {
                 loggedDates.add(dateString);
             }
           } catch (e) {
               console.error("Error parsing log content for date check:", key, e);
           }
        }
      }
    }
  } catch (error) {
    console.error("Error accessing localStorage:", error);
  }

  return Array.from(loggedDates)
    .filter(dateStr => typeof dateStr === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(dateStr))
    .map(dateStr => {
       if (!dateStr) return null;
      const [year, month, day] = dateStr.split('-').map(Number);
      if (isNaN(year) || isNaN(month) || isNaN(day) || month < 1 || month > 12 || day < 1 || day > 31) {
         console.error("Failed to parse valid date components from string:", dateStr);
         return null;
      }
      return new Date(Date.UTC(year, month - 1, day));
    })
    .filter((date): date is Date => date !== null);
};


const formatDateLocal = (date: Date): string => {
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
  const [isClient, setIsClient] = useState(false);
  const [loggedDays, setLoggedDays] = useState<Date[]>([]);
  const [streaks, setStreaks] = useState<{ current: number; longest: number }>({ current: 0, longest: 0 });
  const [selectedDate, setSelectedDate] = useState<Date | undefined>(undefined);
  const [displayMonth, setDisplayMonth] = useState<Date>(new Date());
  const [selectedDateLog, setSelectedDateLog] = useState<DailyLog | null>(null);
  const [selectedWorkoutDay, setSelectedWorkoutDay] = useState<WorkoutDay | null>(null);
  const [isLogModalOpen, setIsLogModalOpen] = useState(false);
  const { toast } = useToast();

  useEffect(() => {
    setIsClient(true);
    if (typeof window !== 'undefined') {
      const today = new Date();
      setDisplayMonth(new Date(Date.UTC(today.getUTCFullYear(), today.getUTCMonth(), 1)));
      const days = getLoggedDays();
      setLoggedDays(days);
      const calculatedStreaks = calculateStreaks(days);
      setStreaks(calculatedStreaks);
    }
  }, []);


  const handleDateSelect = useCallback((date: Date | undefined) => {
    if (!date || typeof window === 'undefined') return;

    const selectedDateUTC = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()));
    const dateStr = formatDateLocal(selectedDateUTC);
    const isLogged = loggedDays.some(d => formatDateLocal(d) === dateStr);

    if (!isLogged) {
        toast({ variant: "default", title: "No Log", description: "No workout logged on this day." });
        setSelectedDate(undefined);
        setIsLogModalOpen(false);
        setSelectedDateLog(null);
        setSelectedWorkoutDay(null);
        return;
    }

    setSelectedDate(selectedDateUTC);

    const dayIndex = selectedDateUTC.getUTCDay();
    const daysOfWeek = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"];
    const dayId = daysOfWeek[dayIndex];
    const workoutForDay = getWorkoutByDay(dayId);
    setSelectedWorkoutDay(workoutForDay);

    if (workoutForDay) {
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
            toast({ variant: "default", title: "Log Data Missing", description: "Log data seems missing for this logged day." });
        }
    } else {
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
              return;
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
                toast({ variant: "default", title: "Log Data Missing", description: "Log data seems missing for this logged day." });
                setSelectedDateLog(null);
                setIsLogModalOpen(false);
            }
         } else {
             toast({ variant: "default", title: "Rest Day / No Log Found", description: "No workout log found for this day." });
             setSelectedDateLog(null);
             setIsLogModalOpen(false);
         }
    }
  }, [loggedDays, toast]);

   const handleMonthChange = (month: Date) => {
     if (month instanceof Date && !isNaN(month.getTime())) {
        const year = month.getUTCFullYear();
        const monthIndex = month.getUTCMonth();
        setDisplayMonth(new Date(Date.UTC(year, monthIndex, 1)));
     } else {
         console.error("Invalid date received for month change:", month);
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

        <div className="space-y-8">
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
            <CardContent className="flex-grow flex items-center justify-center p-1 sm:p-2">
              <Calendar
                mode="single"
                selected={selectedDate}
                onSelect={handleDateSelect}
                month={displayMonth}
                onMonthChange={handleMonthChange}
                className="rounded-md border p-0 w-full max-w-full h-auto"
                 modifiers={{
                  logged: loggedDays,
                 }}
                 modifiersStyles={{
                    logged: {
                        backgroundColor: 'hsl(var(--primary) / 0.2)',
                        color: 'hsl(var(--foreground))',
                        borderRadius: 'var(--radius)',
                        position: 'relative',
                    },
                    selected: {
                         backgroundColor: 'hsl(var(--primary))',
                         color: 'hsl(var(--primary-foreground))',
                         borderRadius: 'var(--radius)',
                         fontWeight: 'bold',
                    }
                 }}
                 disabled={{ after: new Date() }}
                 classNames={{
                    root: "w-full flex flex-col",
                    month: "flex flex-col space-y-2 flex-grow",
                    caption: "flex justify-center pt-1 relative items-center h-12 flex-shrink-0",
                    nav_button_previous: "absolute left-1",
                    nav_button_next: "absolute right-1",
                    table: "w-full border-collapse flex-grow flex flex-col",
                    head_row: "flex justify-around",
                    head_cell: "text-muted-foreground rounded-md w-[14.28%] font-normal text-[0.8rem] text-center",
                    tbody: "flex-grow",
                    row: "flex w-full mt-1",
                    cell: cn(
                         "flex-1 p-0 relative text-center text-sm focus-within:relative focus-within:z-20",
                        "[&:has([aria-selected])]:bg-accent first:[&:has([aria-selected])]:rounded-l-md last:[&:has([aria-selected])]:rounded-r-md",
                        "h-12 md:h-16 lg:h-20",
                         "flex items-center justify-center",
                    ),
                    day: cn(
                         buttonVariants({ variant: "ghost" }),
                         "h-full w-full p-0 font-normal aria-selected:opacity-100 rounded-md",
                         "hover:bg-accent focus:outline-none focus:ring-1 focus:ring-ring",
                    ),
                    day_selected: "bg-primary text-primary-foreground hover:bg-primary focus:bg-primary",
                    day_today: "bg-accent text-accent-foreground",
                    day_outside: "day-outside text-muted-foreground opacity-50",
                    day_disabled: "text-muted-foreground opacity-50",
                    day_range_middle: "aria-selected:bg-accent aria-selected:text-accent-foreground",
                    day_hidden: "invisible",
                 }}
                numberOfMonths={1}
                fixedWeeks
                showOutsideDays={true}
              />
            </CardContent>
          </Card>

          {/* AI Coaching Tip Section Removed */}
        </div>

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
                 !selectedWorkoutDay && selectedDateLog ? (
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

    