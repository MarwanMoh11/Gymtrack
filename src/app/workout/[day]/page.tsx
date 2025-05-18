
import { getWorkoutByDay, weeklyPlan as allWorkoutDays } from '@/data/workout-data'; // Import weeklyPlan directly
import WorkoutView from '@/components/workout/workout-view';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { AlertTriangle } from 'lucide-react';
import Link from 'next/link';

type WorkoutPageProps = {
  params: {
    day: string;
  };
};

export default function WorkoutPage({ params }: WorkoutPageProps) {
  const workoutDay = getWorkoutByDay(params.day);

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
            <p>The workout for "{params.day}" could not be found.</p>
            <p className="mt-2">
              Please check the URL or return to <Link href="/dashboard/today" className="underline hover:text-primary">Today's Session</Link>.
            </p>
          </CardContent>
        </Card>
      </div>
    );
  }

  // WorkoutView is now simplified. It will display a list of exercises
  // that link to their detail pages for logging.
  return <WorkoutView workoutDay={workoutDay} />;
}

export async function generateStaticParams() {
  return allWorkoutDays.map((day) => ({
    day: day.id,
  }));
}
    