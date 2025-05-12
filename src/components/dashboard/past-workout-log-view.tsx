
// src/components/dashboard/past-workout-log-view.tsx
import type { DailyLog, WorkoutDay, LoggedSetData, Exercise } from '@/types/workout';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { CheckCircle } from 'lucide-react';
import { weeklyPlan } from '@/data/workout-data'; // Import plan to lookup exercise names

interface PastWorkoutLogViewProps {
  workoutDay: WorkoutDay | null; // Allow workoutDay to be null
  dailyLog: DailyLog;
}

// Helper to find exercise definition even without workoutDay object
const findExerciseById = (exerciseId: string): Exercise | undefined => {
    for (const day of weeklyPlan) {
        const exercise = day.exercises.find(ex => ex.id === exerciseId);
        if (exercise) {
            return exercise;
        }
    }
    return undefined;
};

export default function PastWorkoutLogView({ workoutDay, dailyLog }: PastWorkoutLogViewProps) {
  if (!dailyLog || Object.keys(dailyLog).length === 0) {
    return <p className="text-muted-foreground text-center mt-8">No log data available for this day.</p>;
  }

  // Determine the list of exercise IDs to render
  // If workoutDay exists, use its exercise order. Otherwise, use the keys from the log.
  const exerciseIdsToRender = workoutDay
    ? workoutDay.exercises.map(ex => ex.id)
    : Object.keys(dailyLog);

  return (
    <div className="space-y-4 pt-2 pb-6">
      {exerciseIdsToRender.map((exerciseId) => {
        const exerciseLog = dailyLog[exerciseId];
        // Find the exercise definition using the helper function
        const exerciseDefinition = workoutDay?.exercises.find(ex => ex.id === exerciseId) || findExerciseById(exerciseId);

        if (!exerciseLog || typeof exerciseLog !== 'object') return null; // Skip if no log or invalid log format

        // Check if any set for this exercise was completed
        const wasExercisedLogged = Object.values(exerciseLog).some(set => set && typeof set === 'object' && set.isCompleted);
        if (!wasExercisedLogged) return null; // Don't show if no sets were completed

        // Get exercise name and notes, handling cases where definition might be missing
        const exerciseName = exerciseDefinition?.name || `Exercise ID: ${exerciseId}`;
        const exerciseNotes = exerciseDefinition?.notes;
        const exerciseUnit = exerciseDefinition?.unit;

        // Determine set IDs to render: from definition if available, else from log keys
        const setIdsToRender = exerciseDefinition
          ? exerciseDefinition.sets.map(set => set.id)
          : Object.keys(exerciseLog).sort(); // Sort log keys for consistent order

        return (
          <Card key={exerciseId} className="bg-card border border-border/50 shadow-sm">
            <CardHeader className="pb-2 pt-3 px-4">
              <CardTitle className="text-base font-semibold">{exerciseName}</CardTitle>
              {exerciseNotes && <CardDescription className="text-xs">{exerciseNotes}</CardDescription>}
            </CardHeader>
            <CardContent className="px-4 pb-3 text-xs space-y-1">
              {setIdsToRender.map((setId, index) => {
                const loggedSet = exerciseLog[setId];
                // Only display sets that were marked as completed
                if (!loggedSet || !loggedSet.isCompleted) return null;

                const setNumber = index + 1; // Calculate set number based on order
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
