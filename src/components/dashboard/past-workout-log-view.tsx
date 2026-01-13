// src/components/dashboard/past-workout-log-view.tsx
import { useMemo } from 'react';
import type { DailyLog, WorkoutDay, Exercise, ExerciseLogData, LoggedSetData, SetData } from '../../types/workout';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { CheckCircle } from 'lucide-react';
import { useUser } from '@/context/user-context';

interface PastWorkoutLogViewProps {
  workoutDay: WorkoutDay | null;
  dailyLog: DailyLog;
}

export default function PastWorkoutLogView({ workoutDay, dailyLog }: PastWorkoutLogViewProps) {
  const { isLoading } = useUser();
  // Helper to find exercise definition if available in the passed workout day
  function getExerciseById(exerciseId: string) {
    return workoutDay?.exercises.find((ex: Exercise) => ex.id === exerciseId);
  }

  if (isLoading) {
    return <p>Loading exercise definitions...</p>
  }

  if (!dailyLog || Object.keys(dailyLog).length === 0) {
    return <p className="text-muted-foreground text-center mt-8">No log data available for this day.</p>;
  }

  const exerciseIdsToRender = workoutDay
    ? workoutDay.exercises.map((ex: Exercise) => ex.id).filter((id: string) => dailyLog[id])
    : Object.keys(dailyLog);

  if (exerciseIdsToRender.length === 0) {
    return <p className="text-muted-foreground text-center mt-8">No exercises logged for this day.</p>;
  }

  return (
    <div className="space-y-4 pt-2 pb-6">
      {exerciseIdsToRender.map((exerciseId) => {
        const exerciseLog = dailyLog[exerciseId] as ExerciseLogData;
        const exerciseDefinition = getExerciseById(exerciseId);

        if (!exerciseLog || typeof exerciseLog !== 'object') return null;

        // Use type narrowing or casting
        const wasExercisedLogged = Object.values(exerciseLog).some((set: any) => set && typeof set === 'object' && (set as LoggedSetData).isCompleted);
        if (!wasExercisedLogged) return null;

        const exerciseName = exerciseDefinition?.name || exerciseLog.name || `Exercise ID: ${exerciseId}`;
        const exerciseNotes = exerciseDefinition?.notes;
        const exerciseUnit = exerciseDefinition?.unit;

        const setIdsToRender = exerciseDefinition
          ? exerciseDefinition.sets.map((set: SetData) => set.id)
          : Object.keys(exerciseLog).sort();

        return (
          <Card key={exerciseId} className="bg-card border border-border/50 shadow-sm">
            <CardHeader className="pb-2 pt-3 px-4">
              <CardTitle className="text-base font-semibold">{exerciseName}</CardTitle>
              {exerciseNotes && <CardDescription className="text-xs">{exerciseNotes}</CardDescription>}
            </CardHeader>
            <CardContent className="px-4 pb-3 text-xs space-y-1">
              {setIdsToRender.map((setId: string, index: number) => {
                const loggedSet = exerciseLog[setId] as LoggedSetData;
                if (!loggedSet || !loggedSet.isCompleted) return null;

                const setNumber = index + 1;
                const setDef = exerciseDefinition?.sets.find((s: SetData) => s.id === setId);
                const unitDisplay = setDef?.unit || exerciseUnit || 'reps';

                return (
                  <div key={setId} className="flex justify-between items-center text-muted-foreground border-t border-border/30 pt-1 mt-1 first:mt-0 first:border-t-0">
                    <span>Set {setNumber}:</span>
                    <span className="text-foreground font-medium flex items-center">
                      <CheckCircle className="h-3 w-3 mr-1.5 text-primary" />
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
    </div>
  );
}
