
// src/app/workout-plan/loading.tsx
import { Skeleton } from "@/components/ui/skeleton";
import { Card, CardHeader, CardContent, CardFooter } from "@/components/ui/card";
import { CalendarDays } from "lucide-react";

export default function LoadingWorkoutPlanPage() {
  return (
    <div className="container mx-auto py-8 px-4 md:px-6">
      <header className="mb-8">
        <div className="flex items-center">
            <CalendarDays className="mr-3 h-8 w-8 text-primary/50 animate-pulse" />
            <Skeleton className="h-10 w-1/2 sm:w-1/3" /> {/* Title */}
        </div>
        <Skeleton className="h-4 w-3/4 sm:w-1/2 mt-2" /> {/* Description */}
      </header>
       <div className="mb-12">
            <Skeleton className="h-7 w-1/4 mb-4" /> {/* Available Plans Title */}
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {[...Array(3)].map((_, i) => (
                <Card key={i}>
                    <CardHeader>
                        <Skeleton className="h-6 w-3/4 mb-1" />
                        <Skeleton className="h-4 w-full" />
                    </CardHeader>
                    <CardFooter>
                        <Skeleton className="h-9 w-full" />
                    </CardFooter>
                </Card>
            ))}
            </div>
       </div>

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
        {[...Array(3)].map((_, i) => (
          <Card key={i} className="shadow-lg rounded-2xl">
            <CardHeader>
              <Skeleton className="h-7 w-3/4 mb-1" /> {/* Day Name */}
              <Skeleton className="h-4 w-1/2" /> {/* Day Title */}
            </CardHeader>
            <CardContent className="flex-grow">
                <Skeleton className="h-4 w-full mb-1" />
                <Skeleton className="h-4 w-5/6 mb-1" />
                <Skeleton className="h-4 w-4/5 mb-1" />
            </CardContent>
            <CardContent className="pt-0 pb-4">
                 <Skeleton className="h-9 w-full" /> {/* Button */}
            </CardContent>
          </Card>
        ))}
      </div>
    </div>
  );
}
