import { Skeleton } from "@/components/ui/skeleton";
import { Card, CardHeader, CardContent } from "@/components/ui/card";

export default function LoadingWorkoutPage() {
  return (
    <div className="container mx-auto max-w-3xl px-2 sm:px-4 py-8">
      <div className="mb-8">
        <Skeleton className="h-10 w-1/3 mb-2" />
        <Skeleton className="h-6 w-1/2 mb-4" />
        <Skeleton className="h-8 w-full" /> {/* For DayProgress */}
      </div>

      {[...Array(5)].map((_, i) => (
        <Card key={i} className="mb-6">
          <CardHeader className="pb-3">
            <Skeleton className="h-6 w-3/4 mb-1" />
            <Skeleton className="h-4 w-1/2" />
          </CardHeader>
          <CardContent className="p-0">
            {[...Array(3)].map((_, j) => (
              <div key={j} className="p-3 border-t">
                <div className="flex items-end gap-3">
                  <Skeleton className="h-6 w-12" />
                  <div className="flex-1 space-y-1">
                    <Skeleton className="h-4 w-1/3" />
                    <Skeleton className="h-9 w-full" />
                  </div>
                  <div className="flex-1 space-y-1">
                    <Skeleton className="h-4 w-1/3" />
                    <Skeleton className="h-9 w-full" />
                  </div>
                  <Skeleton className="h-9 w-12" />
                </div>
              </div>
            ))}
          </CardContent>
          <CardHeader className="pt-4 flex flex-row justify-end">
             <Skeleton className="h-8 w-32" />
          </CardHeader>
        </Card>
      ))}
    </div>
  );
}
