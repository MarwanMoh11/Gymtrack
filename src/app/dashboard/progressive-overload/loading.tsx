// src/app/dashboard/progressive-overload/loading.tsx
import { Skeleton } from "@/components/ui/skeleton";
import { Card, CardHeader, CardContent } from "@/components/ui/card";
import { History, BarChart, CalendarDays, User } from "lucide-react";

export default function LoadingProgressiveOverloadDashboard() {
  return (
    <div className="container mx-auto py-8 px-4 md:px-6 space-y-8">
      <div className="flex flex-col sm:flex-row justify-between items-center gap-4">
        <h1 className="text-3xl font-bold text-primary flex items-center">
          <History className="mr-3 h-8 w-8" />
          Progress Dashboard
        </h1>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-8 items-start">
        {/* Muscle Heatmap Skeleton (Left/Top) */}
        <div className="lg:col-span-2 space-y-8">
          <Card className="shadow-lg rounded-2xl">
            <CardHeader>
              <div className="flex items-center gap-3">
                <User className="h-6 w-6 text-primary/80" />
                <h2 className="text-xl font-semibold">Weekly Muscle Heatmap</h2>
              </div>
              <Skeleton className="h-4 w-3/4" />
            </CardHeader>
            <CardContent>
              <Skeleton className="w-full aspect-square max-w-lg mx-auto" />
            </CardContent>
          </Card>
        </div>

        {/* Calendar Widget and Details Skeleton (Right/Bottom) */}
        <div className="space-y-8">
          <Card className="shadow-lg rounded-2xl">
            <CardHeader>
              <div className="flex items-center gap-3">
                <CalendarDays className="h-6 w-6 text-primary/80" />
                <h2 className="text-xl font-semibold">Workout Calendar</h2>
              </div>
            </CardHeader>
            <CardContent>
              <Skeleton className="h-64 w-full" />
              <div className="flex justify-between mt-4">
                <Skeleton className="h-8 w-1/3" />
                <Skeleton className="h-8 w-1/3" />
              </div>
            </CardContent>
          </Card>
          
          <Card className="shadow-lg rounded-2xl">
            <CardHeader>
                <div className="flex items-center gap-3">
                    <BarChart className="h-6 w-6 text-primary/80" />
                    <h2 className="text-xl font-semibold">Muscle Details</h2>
                </div>
            </CardHeader>
            <CardContent>
                <Skeleton className="h-6 w-1/2 mb-4" />
                <div className="space-y-2">
                    <Skeleton className="h-4 w-full" />
                    <Skeleton className="h-4 w-5/6" />
                </div>
            </CardContent>
          </Card>
        </div>
      </div>
    </div>
  );
}
