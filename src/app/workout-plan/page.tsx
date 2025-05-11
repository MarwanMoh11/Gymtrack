
// src/app/workout-plan/page.tsx
import Link from 'next/link';
import { weeklyPlan, getDays } from '@/data/workout-data';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { ArrowRight, CalendarDays } from 'lucide-react';

export default function WorkoutPlanPage() {
  const days = getDays();

  return (
    <div className="container mx-auto py-8 px-4 md:px-6">
      <header className="mb-8">
        <h1 className="text-3xl font-bold text-primary flex items-center">
          <CalendarDays className="mr-3 h-8 w-8" />
          Full Workout Plan
        </h1>
        <p className="text-muted-foreground mt-1">
          Browse through all the workout days in your plan.
        </p>
      </header>

      {days.length === 0 ? (
        <Card className="shadow-lg rounded-2xl">
          <CardHeader>
            <CardTitle className="text-xl font-semibold">No Workout Plan Found</CardTitle>
          </CardHeader>
          <CardContent className="text-center py-12">
            <p className="text-muted-foreground">
              It seems there's no workout plan configured. Please check the application setup.
            </p>
          </CardContent>
        </Card>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          {weeklyPlan.map((day) => (
            <Link key={day.id} href={`/workout/${day.id}`} passHref legacyBehavior>
              <a className="block transform transition-all hover:scale-105 focus:scale-105 focus:outline-none focus:ring-2 focus:ring-primary focus:ring-offset-2 focus:ring-offset-background rounded-2xl">
                <Card className="h-full shadow-lg hover:shadow-xl transition-shadow duration-300 rounded-2xl flex flex-col">
                  <CardHeader>
                    <CardTitle className="text-xl font-semibold text-primary">{day.dayName}</CardTitle>
                    <CardDescription className="text-sm text-muted-foreground">{day.title}</CardDescription>
                  </CardHeader>
                  <CardContent className="flex-grow">
                    {day.notes && (
                       <p className="text-xs text-muted-foreground italic mb-2 p-2 bg-secondary/30 rounded-md">{day.notes}</p>
                    )}
                    <ul className="space-y-1 text-xs">
                      {day.exercises.slice(0, 3).map((ex) => (
                        <li key={ex.id} className="text-muted-foreground truncate">
                          - {ex.name}
                        </li>
                      ))}
                      {day.exercises.length > 3 && (
                        <li className="text-muted-foreground/70">...and more</li>
                      )}
                    </ul>
                  </CardContent>
                  <CardContent className="pt-0 pb-4">
                     <Button variant="ghost" className="w-full justify-start text-primary hover:bg-primary/10">
                        View {day.dayName}'s Workout <ArrowRight className="ml-auto h-4 w-4" />
                    </Button>
                  </CardContent>
                </Card>
              </a>
            </Link>
          ))}
        </div>
      )}
    </div>
  );
}
