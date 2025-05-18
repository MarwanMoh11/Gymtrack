
// src/app/exercises/[exerciseId]/page.tsx
import { getExerciseById, getAllExercisesFromPlan } from '@/data/workout-data';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { ArrowLeft, Dumbbell } from 'lucide-react';
import Link from 'next/link';
import { Button } from '@/components/ui/button';
import { Separator } from '@/components/ui/separator';

type ExercisePageProps = {
  params: {
    exerciseId: string;
  };
};

export default function ExerciseDetailPage({ params }: ExercisePageProps) {
  const exercise = getExerciseById(params.exerciseId);

  if (!exercise) {
    return (
      <div className="container mx-auto px-4 py-8 flex flex-col items-center text-center">
        <Dumbbell className="h-16 w-16 text-destructive mb-4" />
        <h1 className="text-2xl font-bold text-destructive mb-2">Exercise Not Found</h1>
        <p className="text-muted-foreground mb-6">
          The exercise with ID "{params.exerciseId}" could not be found.
        </p>
        <Button asChild variant="outline">
          <Link href="/workout-plan">
            <ArrowLeft className="mr-2 h-4 w-4" /> Back to Workout Plan
          </Link>
        </Button>
      </div>
    );
  }

  const hasVideo = exercise.videoUrl && exercise.videoUrl.includes('youtube.com/embed');

  return (
    <div className="container mx-auto max-w-3xl px-4 py-8 space-y-8">
      <div className="flex items-center">
        <Button asChild variant="ghost" size="sm" className="mr-4">
          <Link href="/dashboard/today">
            <ArrowLeft className="mr-2 h-4 w-4" /> Back
          </Link>
        </Button>
        <h1 className="text-3xl font-bold text-primary flex items-center">
          <Dumbbell className="mr-3 h-8 w-8" />
          {exercise.name}
        </h1>
      </div>

      <Card className="shadow-lg rounded-2xl">
        <CardHeader>
          <CardTitle className="text-2xl">{exercise.name}</CardTitle>
          {exercise.notes && (
            <CardDescription className="text-sm text-muted-foreground italic pt-1">{exercise.notes}</CardDescription>
          )}
        </CardHeader>
        <CardContent className="space-y-6">
          {exercise.description && (
            <div>
              <h3 className="text-lg font-semibold mb-2 text-foreground">Description</h3>
              <p className="text-muted-foreground whitespace-pre-line">{exercise.description}</p>
            </div>
          )}

          {exercise.muscleGroups && exercise.muscleGroups.length > 0 && (
            <div>
              <h3 className="text-lg font-semibold mb-2 text-foreground">Primary Muscle Groups</h3>
              <div className="flex flex-wrap gap-2">
                {exercise.muscleGroups.map((group) => (
                  <Badge key={group} variant="secondary" className="text-sm">{group}</Badge>
                ))}
              </div>
            </div>
          )}
          
          <Separator />

          {exercise.targetWeight && (
             <div>
                <h3 className="text-lg font-semibold mb-1 text-foreground">Base Plan Target Weight</h3>
                <p className="text-muted-foreground">{exercise.targetWeight}</p>
            </div>
          )}
           <div>
                <h3 className="text-lg font-semibold mb-1 text-foreground">Base Plan Sets & Reps</h3>
                <ul className="list-disc list-inside text-muted-foreground space-y-1">
                    {exercise.sets.map((set, index) => (
                        <li key={set.id}>Set {index + 1}: {set.targetReps} {set.unit || exercise.unit || 'reps'}</li>
                    ))}
                </ul>
            </div>


          {exercise.videoUrl && (
            <div>
              <h3 className="text-lg font-semibold mb-2 text-foreground">Instructional Video</h3>
              {hasVideo ? (
                <div className="aspect-video rounded-lg overflow-hidden border border-border">
                  <iframe
                    width="100%"
                    height="100%"
                    src={exercise.videoUrl}
                    title={`Video for ${exercise.name}`}
                    frameBorder="0"
                    allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share"
                    allowFullScreen
                    className="bg-muted"
                  ></iframe>
                </div>
              ) : (
                <p className="text-muted-foreground">
                  Video link: <a href={exercise.videoUrl} target="_blank" rel="noopener noreferrer" className="text-primary hover:underline">{exercise.videoUrl}</a>
                </p>
              )}
            </div>
          )}

        </CardContent>
      </Card>
    </div>
  );
}

export async function generateStaticParams() {
  const exercises = getAllExercisesFromPlan(); // Use the new helper
  return exercises.map((exercise) => ({
    exerciseId: exercise.id,
  }));
}
