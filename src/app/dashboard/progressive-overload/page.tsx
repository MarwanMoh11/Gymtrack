// src/app/dashboard/progressive-overload/page.tsx
'use client';
import { useState, useEffect, useMemo } from 'react';
import { useQuery } from '@tanstack/react-query';
import { useAuth } from '@/context/auth-context';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import type { DailyLog, WorkoutDay, NamedWorkoutPlan, UserData } from '@/types/workout';
import { History, CalendarDays, Flame, BarChart } from 'lucide-react';
import LoadingProgressiveOverloadDashboard from './loading';
import { calculateStreaks, calculateProgressDataForChart, ChartData } from '@/lib/workout-utils';
import { getUserData } from '@/lib/firestore-workout-plan-service';
import { getAllUserLogs } from '@/lib/firestore-log-service';
import { useToast } from '@/hooks/use-toast';
import { Calendar } from '@/components/ui/calendar';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from '@/components/ui/dialog';
import PastWorkoutLogView from '@/components/dashboard/past-workout-log-view';
import { cn } from "@/lib/utils";
import { buttonVariants } from "@/components/ui/button";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue, SelectGroup, SelectLabel } from '@/components/ui/select';
import { ChartContainer, ChartTooltip, ChartTooltipContent } from '@/components/ui/chart';
import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip } from 'recharts';

type TrackableExercise = { id: string; name: string; dayId: string; dayName: string; hasEnoughData: boolean; };

const formatDateLocal = (date: Date): string => {
  const year = date.getUTCFullYear();
  const month = (date.getUTCMonth() + 1).toString().padStart(2, '0');
  const day = date.getUTCDate().toString().padStart(2, '0');
  return `${year}-${month}-${day}`;
};

export default function ProgressiveOverloadDashboardPage() {
  const { user } = useAuth();
  const { toast } = useToast();

  // State
  const [isClient, setIsClient] = useState(false);
  const [loggedDays, setLoggedDays] = useState<Date[]>([]);
  const [streaks, setStreaks] = useState<{ current: number; longest: number }>({ current: 0, longest: 0 });
  const [selectedDate, setSelectedDate] = useState<Date | undefined>(undefined);
  const [displayMonth, setDisplayMonth] = useState<Date>(new Date());
  const [selectedDateLog, setSelectedDateLog] = useState<DailyLog | null>(null);
  const [selectedWorkoutDay, setSelectedWorkoutDay] = useState<WorkoutDay | null>(null);
  const [isLogModalOpen, setIsLogModalOpen] = useState(false);
  const [trackableExercises, setTrackableExercises] = useState<TrackableExercise[]>([]);
  const [selectedExerciseId, setSelectedExerciseId] = useState<string | null>(null);
  const [chartData, setChartData] = useState<ChartData[]>([]);
  const [exerciseName, setExerciseName] = useState<string>('');

  const { data: userData, isLoading: isLoadingUserData } = useQuery({
    queryKey: ['userData', user?.uid],
    queryFn: () => getUserData(user!.uid),
    enabled: !!user,
  });

  const { data: allLogs, isLoading: isLoadingLogs } = useQuery({
    queryKey: ['allUserLogs', user?.uid],
    queryFn: () => getAllUserLogs(user!.uid),
    enabled: !!user,
  });

  const activePlan = useMemo(() => userData?.plans.find(p => p.isActive), [userData]);

  // Effects
  useEffect(() => {
    setIsClient(true);
    const today = new Date();
    setDisplayMonth(new Date(Date.UTC(today.getUTCFullYear(), today.getUTCMonth(), 1)));
  }, []);

  useEffect(() => {
    if (allLogs) {
      const dates = Array.from(allLogs.keys()).map(dateStr => {
        const [year, month, day] = dateStr.split('-').map(Number);
        return new Date(Date.UTC(year, month - 1, day));
      });
      setLoggedDays(dates);
      setStreaks(calculateStreaks(dates));
    }
  }, [allLogs]);

  useEffect(() => {
    if (activePlan && allLogs) {
      const exercisesWithDataCheck: TrackableExercise[] = [];
      activePlan.plan.forEach(day => {
        day.exercises.forEach(ex => {
          if (!ex.isActivity && !ex.isCore && ex.unit === 'reps') {
            const data = calculateProgressDataForChart(ex.id, allLogs);
            exercisesWithDataCheck.push({
              id: ex.id,
              name: ex.name,
              dayId: day.id,
              dayName: day.title,
              hasEnoughData: data.length > 1
            });
          }
        });
      });
      setTrackableExercises(exercisesWithDataCheck);

      const firstTrackableExercise = exercisesWithDataCheck.find(ex => ex.hasEnoughData);
      if (firstTrackableExercise) {
        setSelectedExerciseId(firstTrackableExercise.id);
      }
    }
  }, [activePlan, allLogs]);

  useEffect(() => {
    if (selectedExerciseId && allLogs) {
      const data = calculateProgressDataForChart(selectedExerciseId, allLogs);
      setChartData(data);
      const exercise = trackableExercises.find(ex => ex.id === selectedExerciseId);
      if (exercise) setExerciseName(exercise.name);
    }
  }, [selectedExerciseId, allLogs, trackableExercises]);

  const handleDayClick = (date: Date) => {
    if (!activePlan || !allLogs) return;
    const dateStr = formatDateLocal(date);
    const logForDay = allLogs.get(dateStr);
    
    if (logForDay) {
        setSelectedDate(date);
        setSelectedDateLog(logForDay);
        // Find which workout day corresponds to this log
        const workoutDayForLog = activePlan.plan.find(day => day.exercises.some(ex => logForDay[ex.id]));
        setSelectedWorkoutDay(workoutDayForLog || null);
        setIsLogModalOpen(true);
    }
  };
  
  const handleExerciseSelectForChart = (exerciseId: string) => {
    setSelectedExerciseId(exerciseId);
  };

  const groupedExercises = useMemo(() => {
    const groups: { [key: string]: TrackableExercise[] } = {};
    trackableExercises.forEach(ex => {
      if (!groups[ex.dayName]) {
        groups[ex.dayName] = [];
      }
      groups[ex.dayName].push(ex);
    });
    return Object.entries(groups);
  }, [trackableExercises]);

  const chartConfig = {
    weight: { label: 'Weight (kg)', color: 'hsl(var(--primary))' },
  };

  if (!isClient || isLoadingUserData || isLoadingLogs) {
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
                  position: 'relative',
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
        
        <Card className="shadow-lg rounded-2xl">
          <CardHeader>
            <div className="flex flex-col sm:flex-row justify-between items-start gap-3">
              <div>
                <CardTitle className="text-xl font-semibold flex items-center mb-1">
                  <BarChart className="mr-2 h-5 w-5 text-primary" />
                  Strength Progression
                </CardTitle>
                <CardDescription>Visualize your gains over time. Select an exercise to see your history.</CardDescription>
              </div>
              <div className="w-full sm:w-64">
                <Select onValueChange={handleExerciseSelectForChart} value={selectedExerciseId ?? undefined}>
                  <SelectTrigger>
                    <SelectValue placeholder="Select an exercise..." />
                  </SelectTrigger>
                  <SelectContent>
                    {groupedExercises.map(([dayName, exercises]) => (
                      <SelectGroup key={dayName}>
                        <SelectLabel>{dayName}</SelectLabel>
                        {exercises.map(ex => (
                          <SelectItem key={ex.id} value={ex.id} disabled={!ex.hasEnoughData}>
                            {ex.name}
                          </SelectItem>
                        ))}
                      </SelectGroup>
                    ))}
                    {trackableExercises.length === 0 && <SelectItem value="none" disabled>No trackable exercises found.</SelectItem>}
                  </SelectContent>
                </Select>
              </div>
            </div>
          </CardHeader>
          <CardContent>
            {chartData.length > 1 ? (
              <ChartContainer config={chartConfig} className="min-h-[200px] w-full">
                <LineChart data={chartData} margin={{ top: 5, right: 20, left: 0, bottom: 5 }}>
                  <CartesianGrid vertical={false} strokeDasharray="3 3" stroke="hsl(var(--border) / 0.5)" />
                  <XAxis dataKey="date" tick={{ fill: 'hsl(var(--muted-foreground))', fontSize: 12 }} tickLine={false} axisLine={false} />
                  <YAxis domain={['dataMin - 5', 'dataMax + 5']} tick={{ fill: 'hsl(var(--muted-foreground))', fontSize: 12 }} tickLine={false} axisLine={false} label={{ value: "Weight (kg)", angle: -90, position: 'insideLeft', fill: 'hsl(var(--muted-foreground))', fontSize: 12 }} />
                  <ChartTooltip
                    cursor={{ stroke: 'hsl(var(--accent))', strokeWidth: 2, strokeDasharray: '3 3' }}
                    content={
                      <ChartTooltipContent
                        formatter={(value, name, props) => (
                          <div className="text-sm">
                            <div className="font-bold">{props.payload.date}</div>
                            <div>Weight: {value} kg</div>
                            <div>Reps: {props.payload.reps}</div>
                            {props.payload.isPR && <div className="text-primary font-bold">Personal Record!</div>}
                          </div>
                        )}
                      />
                    }
                  />
                  <Line type="monotone" dataKey="weight" stroke="hsl(var(--primary))" strokeWidth={2} dot={(props) => {
                    const { cx, cy, payload } = props;
                    if (payload.isPR) {
                      return <circle cx={cx} cy={cy} r={5} fill="hsl(var(--primary))" stroke="hsl(var(--background))" strokeWidth={2} className="pr-dot" />;
                    }
                    return <circle cx={cx} cy={cy} r={3} fill="hsl(var(--primary))" />;
                  }} />
                </LineChart>
              </ChartContainer>
            ) : (
              <div className="flex flex-col items-center justify-center text-center text-muted-foreground h-64">
                <BarChart className="h-12 w-12 mb-2" />
                <p className="font-semibold">{selectedExerciseId ? `Not enough data for ${exerciseName}.` : "Select an exercise."}</p>
                <p className="text-sm">Log at least two sessions for a trackable exercise to see its progression here.</p>
              </div>
            )}
          </CardContent>
        </Card>
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
            {selectedDateLog ? ( 
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
