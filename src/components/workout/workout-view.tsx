'use client';

import { useState, useEffect } from 'react';
import type { WorkoutDay, DailyLog, LoggedSetData, Exercise } from '@/types/workout';
import ExerciseCard from './exercise-card';
import DayProgress from './day-progress';
import { Button } from '@/components/ui/button';
import { useToast } from '@/hooks/use-toast';
import { Card, CardDescription, CardHeader, CardTitle } from '../ui/card';

interface WorkoutViewProps {
  workoutDay: WorkoutDay;
}

function getLocalStorageKey(dayId: string): string {
  // For simplicity, not including date. Data will persist for the day across sessions.
  return `gymtrack_log_${dayId}`;
}

export default function WorkoutView({ workoutDay }: WorkoutViewProps) {
  const [dailyLog, setDailyLog] = useState<DailyLog>({});
  const [isInitialized, setIsInitialized] = useState(false);
  const { toast } = useToast();

  useEffect(() => {
    if (typeof window !== 'undefined') {
      const key = getLocalStorageKey(workoutDay.id);
      const storedLog = localStorage.getItem(key);
      if (storedLog) {
        try {
          setDailyLog(JSON.parse(storedLog));
        } catch (error) {
          console.error("Failed to parse stored log:", error);
          localStorage.removeItem(key); // Clear corrupted data
        }
      }
      setIsInitialized(true);
    }
  }, [workoutDay.id]);

  useEffect(() => {
    if (isInitialized && typeof window !== 'undefined') {
      const key = getLocalStorageKey(workoutDay.id);
      localStorage.setItem(key, JSON.stringify(dailyLog));
    }
  }, [dailyLog, workoutDay.id, isInitialized]);

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
    if (typeof window !== 'undefined') {
      const key = getLocalStorageKey(workoutDay.id);
      localStorage.removeItem(key);
    }
    toast({
      title: "Log Cleared",
      description: `Log for ${workoutDay.dayName} has been cleared.`,
    });
  };
  
  if (!isInitialized && typeof window !== 'undefined') {
     // Basic loading state to avoid flash of unstyled/empty content before localStorage is read
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
      <Card className="mb-8 bg-card shadow-sm border-none">
        <CardHeader>
          <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center">
            <div>
              <CardTitle className="text-3xl font-bold text-primary mb-1">{workoutDay.dayName}</CardTitle>
              <CardDescription className="text-lg text-muted-foreground">{workoutDay.title}</CardDescription>
            </div>
             <Button variant="outline" onClick={handleClearDayLog} size="sm" className="mt-2 sm:mt-0">
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
