import { Skeleton } from "@/components/ui/skeleton";
import { Card, CardHeader, CardContent } from "@/components/ui/card";

export default function LoadingProgressiveOverloadDashboard() {
  return (
    <div className="container mx-auto py-8 px-4 md:px-6 space-y-8">
      <div className="flex flex-col sm:flex-row justify-between items-center gap-4">
        <Skeleton className="h-10 w-1/2 sm:w-1/3" /> {/* Title */}
        <Skeleton className="h-10 w-full sm:w-1/4" /> {/* Exercise Selector */}
      </div>

      <Card className="shadow-lg">
        <CardHeader>
          <Skeleton className="h-8 w-3/4 mb-2" /> {/* Chart Title */}
          <Skeleton className="h-4 w-1/2" /> {/* Chart Description */}
        </CardHeader>
        <CardContent>
          <Skeleton className="h-64 w-full" /> {/* Chart Area */}
        </CardContent>
      </Card>

      <Card className="shadow-lg">
        <CardHeader>
          <Skeleton className="h-8 w-1/2" /> {/* Next-Up Widget Title */}
        </CardHeader>
        <CardContent>
          <Skeleton className="h-6 w-3/4 mb-2" />
          <Skeleton className="h-4 w-full" />
          <Skeleton className="h-4 w-5/6 mt-1" />
        </CardContent>
      </Card>
    </div>
  );
}
