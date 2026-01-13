// src/components/dashboard/calendar-widget.tsx
import { useState } from 'react';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { Calendar } from '@/components/ui/calendar';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from '@/components/ui/dialog';
import PastWorkoutLogView from '@/components/dashboard/past-workout-log-view';
import { CalendarDays, Flame } from 'lucide-react';
import type { DailyLog, NamedWorkoutPlan } from '../../types/workout';
import { cn } from "@/lib/utils";
import { buttonVariants } from "@/components/ui/button";

interface CalendarWidgetProps {
  loggedDays: Date[];
  streaks: { current: number; longest: number };
  allLogs: Map<string, DailyLog>;
  activePlan?: NamedWorkoutPlan;
}

const formatDateLocal = (date: Date): string => {
  const year = date.getUTCFullYear();
  const month = (date.getUTCMonth() + 1).toString().padStart(2, '0');
  const day = date.getUTCDate().toString().padStart(2, '0');
  return `${year}-${month}-${day}`;
};

export default function CalendarWidget({ loggedDays, streaks, allLogs, activePlan }: CalendarWidgetProps) {
  const [selectedDate, setSelectedDate] = useState<Date | undefined>(undefined);
  const [displayMonth, setDisplayMonth] = useState<Date>(new Date(new Date().getFullYear(), new Date().getMonth(), 1));
  const [isLogModalOpen, setIsLogModalOpen] = useState(false);

  const selectedDateLog = selectedDate ? allLogs.get(formatDateLocal(selectedDate)) : null;
  const workoutDayForLog = (selectedDateLog && activePlan)
    ? activePlan.plan.find(day => day.exercises.some(ex => selectedDateLog[ex.id]))
    : null;

  const handleDayClick = (date: Date) => {
    const logForDay = allLogs.get(formatDateLocal(date));
    if (logForDay) {
      setSelectedDate(date);
      setIsLogModalOpen(true);
    }
  };

  return (
    <>
      <Card className="shadow-lg rounded-2xl">
        <CardHeader>
          <div className="flex justify-between items-center flex-wrap gap-2 mb-2">
            <CardTitle className="text-xl font-semibold flex items-center">
              <CalendarDays className="mr-2 h-5 w-5 text-primary" />
              Calendar
            </CardTitle>
            <div className="flex items-center gap-3 text-sm">
              <div className="flex items-center text-primary">
                <Flame className="h-4 w-4 mr-1" />
                <span>{streaks.current} Day Streak</span>
              </div>
              <span className="text-muted-foreground">|</span>
              <span className="text-muted-foreground">Longest: {streaks.longest}</span>
            </div>
          </div>
          <CardDescription>Click a day to view your log.</CardDescription>
        </CardHeader>
        <CardContent className="p-1 sm:p-2">
          <Calendar
            mode="single"
            selected={selectedDate}
            onSelect={setSelectedDate}
            onDayClick={handleDayClick}
            month={displayMonth}
            onMonthChange={setDisplayMonth}
            className="rounded-md border p-0 w-full max-w-full h-auto"
            modifiers={{ logged: loggedDays }}
            modifiersStyles={{
              logged: {
                backgroundColor: 'hsl(var(--primary) / 0.2)',
                color: 'hsl(var(--foreground))',
                borderRadius: 'var(--radius)',
              }
            }}
            disabled={{ after: new Date() }}
            classNames={{
              cell: cn("text-center text-sm p-0 relative [&:has([aria-selected])]:bg-accent first:[&:has([aria-selected])]:rounded-l-md last:[&:has([aria-selected])]:rounded-r-md", "h-10 w-10"),
              day: cn(buttonVariants({ variant: "ghost" }), "h-10 w-10 p-0 font-normal"),
              day_selected: "bg-primary text-primary-foreground hover:bg-primary",
              day_today: "bg-accent text-accent-foreground",
              day_outside: "day-outside text-muted-foreground opacity-50",
              head_cell: "text-muted-foreground rounded-md w-10 font-normal text-[0.8rem]",
              row: "flex w-full mt-1",
            }}
            numberOfMonths={1}
            showOutsideDays={false}
          />
        </CardContent>
      </Card>

      <Dialog open={isLogModalOpen} onOpenChange={setIsLogModalOpen}>
        <DialogContent className="max-w-3xl h-[80vh] flex flex-col">
          <DialogHeader>
            <DialogTitle>Workout Log: {selectedDate ? selectedDate.toLocaleDateString(undefined, { timeZone: 'UTC', month: 'long', day: 'numeric', year: 'numeric' }) : ''}</DialogTitle>
            <DialogDescription>
              Showing workout logged on {selectedDate ? selectedDate.toLocaleDateString(undefined, { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric', timeZone: 'UTC' }) : ''}.
            </DialogDescription>
          </DialogHeader>
          <div className="flex-grow overflow-y-auto pr-2 -mr-6 pl-6">
            {selectedDateLog ? (
              <PastWorkoutLogView workoutDay={workoutDayForLog ?? null} dailyLog={selectedDateLog} />
            ) : (
              <p className="text-muted-foreground text-center mt-8">Log details could not be loaded.</p>
            )}
          </div>
        </DialogContent>
      </Dialog>
    </>
  );
}
