import { Skeleton } from "@/components/ui/skeleton";
import { Card, CardHeader, CardContent } from "@/components/ui/card";
import { CalendarDays } from "lucide-react";

export default function LoadingProgressiveOverloadDashboard() {
  return (
    <div className="container mx-auto py-8 px-4 md:px-6 space-y-8">
      <div className="flex flex-col sm:flex-row justify-between items-center gap-4">
        <Skeleton className="h-10 w-1/2 sm:w-1/3" /> {/* Title */}
        <Skeleton className="h-10 w-full sm:w-1/4" /> {/* Exercise Selector */}
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
        {/* Calendar and Streaks Section */}
        <div className="lg:col-span-2 space-y-8">
           <Card className="shadow-lg rounded-2xl">
              <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
                 <Skeleton className="h-6 w-1/3" /> {/* Streaks Title */}
                <CalendarDays className="h-5 w-5 text-muted-foreground" />
              </CardHeader>
              <CardContent className="flex justify-around">
                <div className="text-center">
                  <Skeleton className="h-8 w-16 mx-auto mb-1"/>
                  <Skeleton className="h-4 w-24 mx-auto" />
                </div>
                <div className="text-center">
                   <Skeleton className="h-8 w-16 mx-auto mb-1"/>
                   <Skeleton className="h-4 w-28 mx-auto"/>
                </div>
              </CardContent>
            </Card>
             <Card className="shadow-lg rounded-2xl">
              <CardHeader>
                 <Skeleton className="h-7 w-1/2" /> {/* Calendar Title */}
                 <Skeleton className="h-4 w-3/4" /> {/* Calendar Desc */}
              </CardHeader>
              <CardContent className="flex justify-center">
                 <Skeleton className="h-72 w-full max-w-md" /> {/* Calendar Area */}
              </CardContent>
            </Card>
        </div>

         {/* AI Suggestion Section */}
        <div className="lg:col-span-1">
          <Card className="shadow-lg rounded-2xl">
            <CardHeader>
               <Skeleton className="h-8 w-3/4" /> {/* Next-Up Widget Title */}
               <Skeleton className="h-4 w-1/2" /> {/* Next-Up Desc */}
            </CardHeader>
            <CardContent className="space-y-4">
              <Skeleton className="h-6 w-full mb-2" />
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
