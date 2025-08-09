// src/app/onboarding/create-plan/add-exercises/loading.tsx
import { Skeleton } from "@/components/ui/skeleton";
import { Card, CardHeader, CardContent, CardFooter } from "@/components/ui/card";
import { Accordion } from "@/components/ui/accordion";

export default function LoadingAddExercisesPage() {
  return (
    <div className="flex flex-col items-center justify-center min-h-screen bg-background p-4">
      <Card className="w-full max-w-4xl">
        <CardHeader>
          <Skeleton className="h-8 w-1/2" />
          <Skeleton className="h-4 w-3/4 mt-2" />
        </CardHeader>
        <CardContent>
          <Accordion type="single" collapsible className="w-full space-y-4">
            {[...Array(3)].map((_, i) => (
                <div key={i} className="p-4 border rounded-lg">
                    <div className="flex justify-between items-center">
                        <Skeleton className="h-6 w-1/3" />
                        <Skeleton className="h-4 w-1/4" />
                    </div>
                </div>
            ))}
          </Accordion>
        </CardContent>
        <CardFooter className="flex justify-end pt-6">
          <Skeleton className="h-10 w-48" />
        </CardFooter>
      </Card>
    </div>
  );
}
