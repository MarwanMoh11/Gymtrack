
import { Skeleton } from "@/components/ui/skeleton";
import { Card, CardHeader, CardContent } from "@/components/ui/card";
import { CalendarDays, History } from "lucide-react"; // Removed Lightbulb

export default function LoadingProgressiveOverloadDashboard() {
  return (
    <div className="container mx-auto py-8 px-4 md:px-6 space-y-8">
      <div className="flex flex-col sm:flex-row justify-between items-center gap-4">
        <Skeleton className="h-10 w-1/2 sm:w-1/3" /> {/* Title */}
      </div>

      <div className="space-y-8"> {/* Main container for cards */}
        {/* Calendar Section (Full Width) */}
        <Card className="shadow-lg rounded-2xl">
           <CardHeader>
              <div className="flex items-center mb-2">
                 <CalendarDays className="mr-2 h-5 w-5 text-primary/50 animate-pulse" />
                 <Skeleton className="h-7 w-1/2" /> {/* Calendar Title */}
              </div>
              <Skeleton className="h-4 w-3/4 mb-2" /> {/* Calendar Desc */}
              {/* Skeleton for integrated streak text */}
              <div className="flex gap-4 mt-1">
                 <Skeleton className="h-4 w-1/4" />
                 <Skeleton className="h-4 w-1/4" />
              </div>
           </CardHeader>
           {/* Increased size for calendar area */}
           <CardContent className="flex-grow flex items-center justify-center p-2 sm:p-4">
              {/* Large skeleton to simulate calendar filling space */}
              <Skeleton className="h-[500px] w-full" />
           </CardContent>
         </Card>

         {/* AI Coaching Tip Section Removed */}
      </div>
    </div>
  );
}

    