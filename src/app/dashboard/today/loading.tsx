import { Skeleton } from "@/components/ui/skeleton";
import { Card, CardHeader, CardContent, CardFooter } from "@/components/ui/card";

export default function LoadingWorkoutPage() {
  return (
    <div className="container mx-auto max-w-3xl px-2 sm:px-4 py-8">
      <Card className="mb-8 bg-card shadow-lg border-none">
        <CardHeader>
            <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-2">
                <div>
                    <Skeleton className="h-10 w-48 mb-2" />
                    <Skeleton className="h-6 w-64" />
                </div>
                <Skeleton className="h-8 w-40 rounded-full" />
            </div>
             <Skeleton className="h-12 w-full mt-3" />
        </CardHeader>
        <CardFooter className="flex flex-col sm:flex-row justify-between items-center pt-3 pb-4 px-6 gap-4">
            <div className="w-full sm:w-auto">
                 <Skeleton className="h-4 w-24 mb-1" />
                 <Skeleton className="h-8 w-16" />
                 <Skeleton className="h-3 w-32 mt-1" />
            </div>
            <div className="w-full sm:w-auto flex-grow max-w-xs">
                <Skeleton className="h-5 w-full" />
            </div>
        </CardFooter>
      </Card>


      {[...Array(5)].map((_, i) => (
        <Card key={i} className="mb-4 shadow-md">
          <CardHeader className="flex flex-row justify-between items-center pb-3">
             <div>
                <Skeleton className="h-6 w-48" />
                <Skeleton className="h-4 w-32 mt-1" />
             </div>
             <Skeleton className="h-9 w-32" />
          </CardHeader>
        </Card>
      ))}
    </div>
  );
}
