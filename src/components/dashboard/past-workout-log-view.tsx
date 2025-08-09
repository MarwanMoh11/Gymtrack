// src/components/dashboard/past-workout-log-view.tsx
import type { DailyLog, WorkoutDay, NamedWorkoutPlan, Exercise } from '@/types/workout';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { CheckCircle } from 'lucide-react';
import { useQuery } from '@tanstack/react-query';
import { getAllUserWorkoutPlans } from '@/lib/firestore-workout-plan-service';
import { getExerciseById as getExerciseDefById } from '@/data/workout-data';


interface PastWorkoutLogViewProps {
  workoutDay: WorkoutDay | null; 
  dailyLog: DailyLog;
}

// Global cache for exercise definitions
const exerciseDefCache = new Map<string, Exercise>();

function populateCache(plans: NamedWorkoutPlan[]) {
    if (exerciseDefCache.size > 0) return; // Cache already populated
    plans.forEach(plan => {
        plan.plan.forEach(day => {
            day.exercises.forEach(ex => {
                if (!exerciseDefCache.has(ex.id)) {
                    exerciseDefCache.set(ex.id, ex);
                }
            });
        });
    });
}

function getExerciseById(exerciseId: string): Exercise | undefined {
    if (exerciseDefCache.size > 0) {
        return exerciseDefCache.get(exerciseId);
    }
    // Fallback if cache isn't populated for some reason, though less efficient.
    return getExerciseDefById(exerciseId);
}


export default function PastWorkoutLogView({ workoutDay, dailyLog }: PastWorkoutLogViewProps) {
  const { data: allPlans, isLoading } = useQuery({
      queryKey: ['workoutPlans'],
      queryFn: getAllUserWorkoutPlans,
  });

  if (isLoading) {
      return <p>Loading exercise definitions...</p>
  }

  if (allPlans) {
      populateCache(allPlans);
  }

  if (!dailyLog || Object.keys(dailyLog).length === 0) {
    return <p className="text-muted-foreground text-center mt-8">No log data available for this day.</p>;
  }

  const exerciseIdsToRender = workoutDay
    ? workoutDay.exercises.map(ex => ex.id).filter(id => dailyLog[id])
    : Object.keys(dailyLog);

  if (exerciseIdsToRender.length === 0) {
    return <p className="text-muted-foreground text-center mt-8">No exercises logged for this day.</p>;
  }

  return (
    <div className="space-y-4 pt-2 pb-6">
      {exerciseIdsToRender.map((exerciseId) => {
        const exerciseLog = dailyLog[exerciseId];
        const exerciseDefinition = getExerciseById(exerciseId);

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
    </div>
  );
}
