import { Skeleton } from "@/components/ui/skeleton";
import { Card, CardHeader, CardContent } from "@/components/ui/card";
import { CalendarDays, Lightbulb } from "lucide-react"; // Changed icon for coaching tip

export default function LoadingProgressiveOverloadDashboard() {
  return (
    <div className="container mx-auto py-8 px-4 md:px-6 space-y-8">
      <div className="flex flex-col sm:flex-row justify-between items-center gap-4">
        <Skeleton className="h-10 w-1/2 sm:w-1/3" /> {/* Title */}
        {/* Removed Exercise Selector Skeleton */}
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
        {/* Calendar Section */}
        <div className="lg:col-span-2 space-y-8">
           {/* Streaks Card Removed */}
           <Card className="shadow-lg rounded-2xl">
              <CardHeader>
                 <div className="flex items-center mb-2">
                    <CalendarDays className="mr-2 h-5 w-5 text-primary/50 animate-pulse" />
                    <Skeleton className="h-7 w-1/2" /> {/* Calendar Title */}
                 </div>
                 <Skeleton className="h-4 w-3/4" /> {/* Calendar Desc */}
                 {/* Skeleton for integrated streak text */}
                 <div className="flex gap-4 mt-3">
                    <Skeleton className="h-4 w-1/4" />
                    <Skeleton className="h-4 w-1/4" />
                 </div>
              </CardHeader>
              <CardContent className="flex justify-center p-4">
                 {/* Increased size for calendar area */}
                 <Skeleton className="h-80 w-full max-w-2xl" /> 
              </CardContent>
            </Card>
        </div>

         {/* AI Coaching Tip Section */}
        <div className="lg:col-span-1">
          <Card className="shadow-lg rounded-2xl">
            <CardHeader>
               <div className="flex items-center">
                 <Lightbulb className="mr-2 h-6 w-6 text-primary/50 animate-pulse" />
                 <Skeleton className="h-8 w-3/4" /> {/* Coaching Tip Title */}
               </div>
               <Skeleton className="h-4 w-1/2 mt-1" /> {/* Coaching Tip Desc */}
            </CardHeader>
            <CardContent className="space-y-3 py-6">
              <Skeleton className="h-4 w-full" />
              <Skeleton className="h-4 w-5/6" />
              <Skeleton className="h-4 w-full mt-1" />
               <Skeleton className="h-4 w-4/5 mt-1" />
            </CardContent>
          </Card>
        </div>
      </div>
    </div>
  );
}
