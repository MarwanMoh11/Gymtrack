import { Skeleton } from "@/components/ui/skeleton";
import { Card, CardHeader, CardContent } from "@/components/ui/card";
import { History, BarChart } from "lucide-react";

export default function LoadingProgressiveOverloadDashboard() {
  return (
    <div className="container mx-auto py-8 px-4 md:px-6 space-y-8">
      <div className="flex flex-col sm:flex-row justify-between items-center gap-4">
        <h1 className="text-3xl font-bold text-primary flex items-center">
          <History className="mr-3 h-8 w-8" />
          Progress & History
        </h1>
      </div>

      {/* Calendar Section Skeleton */}
      <Card className="shadow-lg rounded-2xl">
         <CardHeader>
            <Skeleton className="h-7 w-1/2" />
            <Skeleton className="h-4 w-3/4 mb-2" />
            <div className="flex gap-4 mt-1">
               <Skeleton className="h-4 w-1/4" />
               <Skeleton className="h-4 w-1/4" />
            </div>
         </CardHeader>
         <CardContent className="flex-grow flex items-center justify-center p-2 sm:p-4">
            <Skeleton className="h-[500px] w-full" />
         </CardContent>
       </Card>

      {/* Progress Chart Skeleton */}
      <Card className="shadow-lg rounded-2xl">
        <CardHeader>
          <div className="flex flex-col sm:flex-row justify-between items-start gap-3">
             <div>
                <CardHeader className="flex flex-row items-center gap-2 p-0 mb-1">
                   <BarChart className="h-6 w-6 text-primary/80" />
                   <Skeleton className="h-7 w-48" />
                </CardHeader>
                <Skeleton className="h-4 w-64" />
             </div>
             <div className="w-full sm:w-64">
                <Skeleton className="h-10 w-full" />
             </div>
          </div>
        </CardHeader>
        <CardContent>
           <Skeleton className="w-full aspect-video" />
        </CardContent>
      </Card>
    </div>
  );
}
