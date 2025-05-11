'use client';

import { Progress } from '@/components/ui/progress';
import type { DailyLog, WorkoutDay } from '@/types/workout';

interface DayProgressProps {
  workoutDay: WorkoutDay;
  dailyLog: DailyLog;
}

export default function DayProgress({ workoutDay, dailyLog }: DayProgressProps) {
  const totalSets = workoutDay.exercises.reduce((sum, exercise) => sum + exercise.sets.length, 0);
  
  let completedSets = 0;
  workoutDay.exercises.forEach(exercise => {
    const exerciseLog = dailyLog[exercise.id] || {};
    exercise.sets.forEach(set => {
      if (exerciseLog[set.id]?.isCompleted) {
        completedSets++;
      }
    });
  });

  const progressPercentage = totalSets > 0 ? (completedSets / totalSets) * 100 : 0;

  if (totalSets === 0) {
    return null; // No sets to track
  }

  return (
    <div className="mb-6">
      <div className="mb-2 flex justify-between text-sm font-medium">
        <span>Daily Progress</span>
        <span>{completedSets} / {totalSets} sets completed</span>
      </div>
      <Progress value={progressPercentage} aria-label={`Workout progress: ${progressPercentage.toFixed(0)}%`} />
    </div>
  );
}
