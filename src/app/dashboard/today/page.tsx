// src/app/dashboard/today/page.tsx
'use client';

import { useState, useEffect } from 'react';
import WorkoutView from '@/components/workout/workout-view';
import { getWorkoutByDay } from '@/data/workout-data';
import type { WorkoutDay } from '@/types/workout';
import LoadingWorkoutPage from '@/app/workout/[day]/loading';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { AlertTriangle } from 'lucide-react';

const days = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"];

export default function TodaysWorkoutDashboardPage() {
  const [workoutDay, setWorkoutDay] = useState<WorkoutDay | null | undefined>(undefined); // undefined for initial loading state
  const [currentDayId, setCurrentDayId] = useState<string | null>(null);
  const [isClient, setIsClient] = useState(false);

  useEffect(() => {
    setIsClient(true);
    const date = new Date();
    const dayId = days[date.getDay()];
    setCurrentDayId(dayId);
    const fetchedWorkoutDay = getWorkoutByDay(dayId);
    setWorkoutDay(fetchedWorkoutDay);
  }, []);

  if (!isClient || workoutDay === undefined) {
    return <LoadingWorkoutPage />;
  }

  if (!workoutDay) {
    return (
      <div className="container mx-auto px-4 py-8">
        <Card className="border-destructive">
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-destructive">
              <AlertTriangle /> Workout Not Found for Today
            </CardTitle>
          </CardHeader>
          <CardContent>
            <p>No workout plan found for {currentDayId || 'today'}. Enjoy your rest day or check your plan!</p>
          </CardContent>
        </Card>
      </div>
    );
  }

  return <WorkoutView workoutDay={workoutDay} />;
}
