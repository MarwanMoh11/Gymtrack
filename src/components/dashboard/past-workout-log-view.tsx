// src/components/dashboard/past-workout-log-view.tsx
import type { DailyLog, WorkoutDay, LoggedSetData } from '@/types/workout';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { CheckCircle } from 'lucide-react';

interface PastWorkoutLogViewProps {
  workoutDay: WorkoutDay;
  dailyLog: DailyLog;
}

export default function PastWorkoutLogView({ workoutDay, dailyLog }: PastWorkoutLogViewProps) {
  if (!workoutDay || !dailyLog || Object.keys(dailyLog).length === 0) {
    return <p className="text-muted-foreground text-center mt-8">No log data available for this day.</p>;
  }

  return (
    <div className="space-y-4 pt-2 pb-6">
      {workoutDay.exercises.map((exercise) => {
        const exerciseLog = dailyLog[exercise.id];
        if (!exerciseLog) return null; // Don't show exercise if no sets were logged

        // Check if any set for this exercise was completed
        const wasExercisedLogged = Object.values(exerciseLog).some(set => set.isCompleted);
        if (!wasExercisedLogged) return null; // Don't show if no sets were completed

        return (
          <Card key={exercise.id} className="bg-card border border-border/50 shadow-sm">
            <CardHeader className="pb-2 pt-3 px-4">
              <CardTitle className="text-base font-semibold">{exercise.name}</CardTitle>
              {exercise.notes && <CardDescription className="text-xs">{exercise.notes}</CardDescription>}
            </CardHeader>
            <CardContent className="px-4 pb-3 text-xs space-y-1">
              {exercise.sets.map((set, index) => {
                const loggedSet = exerciseLog[set.id];
                // Only display sets that were marked as completed
                if (!loggedSet || !loggedSet.isCompleted) return null; 

                return (
                  <div key={set.id} className="flex justify-between items-center text-muted-foreground border-t border-border/30 pt-1 mt-1 first:mt-0 first:border-t-0">
                    <span>Set {index + 1}:</span>
                    <span className="text-foreground font-medium flex items-center">
                       <CheckCircle className="h-3 w-3 mr-1.5 text-primary"/>
                       {loggedSet.reps ?? 'N/A'} {exercise.unit || 'reps'}
                       {loggedSet.weight && ` @ ${loggedSet.weight}`} 
                    </span>
                  </div>
                );
              })}
            </CardContent>
          </Card>
        );
      })}
       {Object.keys(dailyLog).length === 0 && (
            <p className="text-muted-foreground text-center mt-8">No exercises logged for this day.</p>
       )}
    </div>
  );
}
