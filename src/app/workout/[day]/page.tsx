
import { getWorkoutByDay as getWorkoutByDayFromActivePlan, getActiveWorkoutPlan } from '@/lib/workout-plan-service'; // Updated import
import WorkoutView from '@/components/workout/workout-view';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { AlertTriangle } from 'lucide-react';
import Link from 'next/link';
import { defaultNamedPlans } from '@/data/workout-data'; // For generateStaticParams

type WorkoutPageProps = {
  params: {
    day: string; // This 'day' is the dayId (e.g., 'monday', 'cal-tue')
  };
};

export default function WorkoutPage({ params }: WorkoutPageProps) {
  // Fetch workout day from the *active* plan
  const workoutDay = getWorkoutByDayFromActivePlan(params.day);

  if (!workoutDay) {
    return (
      <div className="container mx-auto px-4 py-8">
        <Card className="border-destructive">
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-destructive">
              <AlertTriangle /> Workout Not Found
            </CardTitle>
          </CardHeader>
          <CardContent>
            <p>The workout for "{params.day}" could not be found in the active plan.</p>
            <p className="mt-2">
              Please check the URL or return to <Link href="/dashboard/today" className="underline hover:text-primary">Today's Session</Link>.
              Or <Link href="/workout-plan" className="underline hover:text-primary">manage your active plan</Link>.
            </p>
          </CardContent>
        </Card>
      </div>
    );
  }

  return <WorkoutView workoutDay={workoutDay} />;
}

export async function generateStaticParams() {
  // Generate params for all days in all default plans to ensure they can be prerendered
  // If users can create fully custom day IDs, this might need adjustment or be dynamic.
  const params: { day: string }[] = [];
  defaultNamedPlans.forEach(namedPlan => {
    namedPlan.plan.forEach(day => {
      if (day.id !== 'exercise-library') { // Exclude library pseudo-day
        params.push({ day: day.id });
      }
    });
  });
  return params;
}
