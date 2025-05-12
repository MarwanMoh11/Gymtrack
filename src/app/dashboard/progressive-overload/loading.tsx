
import { Skeleton } from "@/components/ui/skeleton";
import { Card, CardHeader, CardContent } from "@/components/ui/card";
import { CalendarDays, Lightbulb, History } from "lucide-react"; // Added History

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

         {/* AI Coaching Tip Section (Below Calendar) */}
        <Card className="shadow-lg rounded-2xl">
          <CardHeader>
             <div className="flex justify-between items-center"> {/* Align title and add button skeleton */}
               <div className="flex items-center">
                   <Lightbulb className="mr-2 h-6 w-6 text-primary/50 animate-pulse" />
                   <Skeleton className="h-8 w-3/4" /> {/* Coaching Tip Title */}
               </div>
               {/* Refresh Button Skeleton */}
               <Skeleton className="h-8 w-8 rounded-full" /> 
             </div>
             <Skeleton className="h-4 w-1/2 mt-1" /> {/* Coaching Tip Desc */}
          </CardHeader>
          <CardContent className="min-h-[150px] flex items-center justify-center"> {/* Match min-height */}
            {/* Keep loading content skeleton */}
            <div className="space-y-3 w-full">
              <Skeleton className="h-4 w-full" />
              <Skeleton className="h-4 w-5/6" />
              <Skeleton className="h-4 w-full" />
              <Skeleton className="h-4 w-4/5" />
            </div>
          </CardContent>
        </Card>
      </div>
    </div>
  );
}

