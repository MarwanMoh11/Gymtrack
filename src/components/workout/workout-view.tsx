'use client';

import { useState, useEffect } from 'react';
import type { WorkoutDay, DailyLog, LoggedSetData, Exercise } from '@/types/workout';
import ExerciseCard from './exercise-card';
import DayProgress from './day-progress';
import { Button } from '@/components/ui/button';
import { useToast } from '@/hooks/use-toast';
import { Card, CardDescription, CardHeader, CardTitle } from '../ui/card';

const getCurrentDateString = (): string => {
  // Ensures that a date is used, avoids issues with server/client mismatch for default date.
  // This component is client-side, so new Date() is safe here.
  return new Date().toISOString().split('T')[0];
};

function getLocalStorageKey(dayId: string, date: string): string {
  return `gymtrack_log_${dayId}_${date}`;
}

export default function WorkoutView({ workoutDay }: WorkoutViewProps) {
  const [dailyLog, setDailyLog] = useState<DailyLog>({});
  const [isInitialized, setIsInitialized] = useState(false);
  const [currentDate, setCurrentDate] = useState('');
  const { toast } = useToast();

  useEffect(() => {
    // Set current date only on the client side after mount
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
        // If no log for the current date, ensure dailyLog is empty
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
        // If dailyLog is empty, remove the item from localStorage
        // This prevents storing empty {} objects if a day is visited but no logs are made,
        // or if logs are cleared.
        localStorage.removeItem(key);
      }
    }
  }, [dailyLog, workoutDay.id, isInitialized, currentDate]);

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
    // localStorage update will be handled by the useEffect watching dailyLog
    toast({
      title: "Log Cleared",
      description: `Log for ${workoutDay.dayName} (${currentDate}) has been cleared.`,
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

      {workoutDay.exercises.map((exercise: Exercise) => (
        <ExerciseCard
          key={exercise.id}
          exercise={exercise}
          onLogSet={handleLogSet}
          loggedData={dailyLog[exercise.id]}
        />
      ))}
    </div>
  );
}
