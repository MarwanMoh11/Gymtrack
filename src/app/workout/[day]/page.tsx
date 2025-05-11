import { getWorkoutByDay } from '@/data/workout-data';
import WorkoutView from '@/components/workout/workout-view';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { AlertTriangle } from 'lucide-react';

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
            <p>The workout for {params.day} could not be found. Please select a valid day.</p>
          </CardContent>
        </Card>
      </div>
    );
  }

  return <WorkoutView workoutDay={workoutDay} />;
}

export async function generateStaticParams() {
  const { weeklyPlan } = await import('@/data/workout-data');
  return weeklyPlan.map((day) => ({
    day: day.id,
  }));
}
