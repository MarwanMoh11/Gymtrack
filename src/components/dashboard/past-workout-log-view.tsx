
// src/components/dashboard/past-workout-log-view.tsx
import type { DailyLog, WorkoutDay, LoggedSetData, Exercise } from '@/types/workout';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { CheckCircle } from 'lucide-react';
import { getExerciseById } from '@/lib/workout-plan-service'; // Corrected import

interface PastWorkoutLogViewProps {
  workoutDay: WorkoutDay | null; // Allow workoutDay to be null
  dailyLog: DailyLog;
}

export default function PastWorkoutLogView({ workoutDay, dailyLog }: PastWorkoutLogViewProps) {
  if (!dailyLog || Object.keys(dailyLog).length === 0) {
    return <p className="text-muted-foreground text-center mt-8">No log data available for this day.</p>;
  }

  const exerciseIdsToRender = workoutDay
    ? workoutDay.exercises.map(ex => ex.id)
    : Object.keys(dailyLog);

  return (
    <div className="space-y-4 pt-2 pb-6">
      {exerciseIdsToRender.map((exerciseId) => {
        const exerciseLog = dailyLog[exerciseId];
        // Find the exercise definition using the global service
        const exerciseDefinition = workoutDay?.exercises.find(ex => ex.id === exerciseId) || getExerciseById(exerciseId);

        if (!exerciseLog || typeof exerciseLog !== 'object') return null;

        const wasExercisedLogged = Object.values(exerciseLog).some(set => set && typeof set === 'object' && set.isCompleted);
        if (!wasExercisedLogged) return null;

        const exerciseName = exerciseDefinition?.name || `Exercise ID: ${exerciseId}`;
        const exerciseNotes = exerciseDefinition?.notes;
        const exerciseUnit = exerciseDefinition?.unit;

        const setIdsToRender = exerciseDefinition
          ? exerciseDefinition.sets.map(set => set.id)
          : Object.keys(exerciseLog).sort();

        return (
          <Card key={exerciseId} className="bg-card border border-border/50 shadow-sm">
            <CardHeader className="pb-2 pt-3 px-4">
              <CardTitle className="text-base font-semibold">{exerciseName}</CardTitle>
              {exerciseNotes && <CardDescription className="text-xs">{exerciseNotes}</CardDescription>}
            </CardHeader>
            <CardContent className="px-4 pb-3 text-xs space-y-1">
              {setIdsToRender.map((setId, index) => {
                const loggedSet = exerciseLog[setId];
                if (!loggedSet || !loggedSet.isCompleted) return null;

                const setNumber = index + 1;
                const unitDisplay = exerciseDefinition?.sets.find(s => s.id === setId)?.unit || exerciseUnit || 'reps';

                return (
                  <div key={setId} className="flex justify-between items-center text-muted-foreground border-t border-border/30 pt-1 mt-1 first:mt-0 first:border-t-0">
                    <span>Set {setNumber}:</span>
                    <span className="text-foreground font-medium flex items-center">
                       <CheckCircle className="h-3 w-3 mr-1.5 text-primary"/>
                       {loggedSet.reps ?? 'N/A'} {unitDisplay}
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
