
// src/app/exercises/[exerciseId]/loading.tsx
import { Skeleton } from "@/components/ui/skeleton";
import { Card, CardHeader, CardContent } from "@/components/ui/card";
import { ArrowLeft, Dumbbell } from "lucide-react";

export default function LoadingExercisePage() {
  return (
    <div className="container mx-auto max-w-3xl px-4 py-8 space-y-8">
      <div className="flex items-center">
        <Skeleton className="h-9 w-24 mr-4" /> {/* Back Button */}
        <Dumbbell className="mr-3 h-8 w-8 text-primary/50 animate-pulse" />
        <Skeleton className="h-10 w-1/2" /> {/* Title */}
      </div>

      <Card className="shadow-lg rounded-2xl">
        <CardHeader>
          <Skeleton className="h-8 w-3/4 mb-2" /> {/* Exercise Name */}
          <Skeleton className="h-4 w-1/2" /> {/* Notes if any */}
        </CardHeader>
        <CardContent className="space-y-6">
          <div>
            <Skeleton className="h-6 w-1/4 mb-2" /> {/* Description Title */}
            <Skeleton className="h-4 w-full mb-1" />
            <Skeleton className="h-4 w-full mb-1" />
            <Skeleton className="h-4 w-3/4" />
          </div>

          <div>
            <Skeleton className="h-6 w-1/3 mb-2" /> {/* Muscle Groups Title */}
            <div className="flex flex-wrap gap-2">
              <Skeleton className="h-7 w-20 rounded-full" />
              <Skeleton className="h-7 w-24 rounded-full" />
              <Skeleton className="h-7 w-16 rounded-full" />
            </div>
          </div>

          <Skeleton className="h-px w-full" /> {/* Separator */}

          <div>
             <Skeleton className="h-6 w-1/3 mb-1" /> {/* Target Weight Title */}
             <Skeleton className="h-4 w-1/4" />
          </div>
           <div>
                <Skeleton className="h-6 w-1/3 mb-1" /> {/* Sets & Reps Title */}
                <Skeleton className="h-4 w-1/2 mb-1" />
                <Skeleton className="h-4 w-1/2 mb-1" />
            </div>


          <div>
            <Skeleton className="h-6 w-1/4 mb-2" /> {/* Video Title */}
            <Skeleton className="aspect-video w-full rounded-lg" /> {/* Video Placeholder */}
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
