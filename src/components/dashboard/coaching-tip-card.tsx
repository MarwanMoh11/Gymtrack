
// src/components/dashboard/coaching-tip-card.tsx
'use client';

import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
// import { Button } from '@/components/ui/button'; // Button no longer needed
import { Loader2, Lightbulb } from 'lucide-react'; // RefreshCw no longer needed

interface CoachingTipCardProps {
  tip: string | undefined | null;
  isLoading: boolean;
  // onRefresh: () => void; // onRefresh prop is removed
}

export default function CoachingTipCard({ tip, isLoading }: CoachingTipCardProps) {
  return (
    <Card className="shadow-xl rounded-2xl">
      <CardHeader>
        <div className="flex justify-between items-center">
          <CardTitle className="text-xl font-bold text-primary flex items-center">
             <Lightbulb className="mr-2 h-5 w-5" />
             AI Coach Tip
          </CardTitle>
          {/* Refresh Button Removed */}
          {/* <Button variant="ghost" size="icon" onClick={onRefresh} disabled={isLoading} className="rounded-full text-primary hover:bg-primary/10">
            {isLoading ? <Loader2 className="h-5 w-5 animate-spin" /> : <RefreshCw className="h-5 w-5" />}
            <span className="sr-only">Refresh Tip</span>
          </Button> */}
        </div>
        <CardDescription>General advice based on your recent activity.</CardDescription>
      </CardHeader>
      <CardContent className="min-h-[150px] flex items-center justify-center">
        {isLoading && (
          <div className="flex flex-col items-center text-center py-8">
            <Loader2 className="h-8 w-8 animate-spin text-primary mb-3" />
            <span className="text-muted-foreground">Fetching coaching insights...</span>
          </div>
        )}
        {!isLoading && tip && (
          <blockquote className="text-center text-sm italic text-foreground/90 border-l-4 border-primary pl-4 py-2">
             "{tip}"
          </blockquote>
        )}
        {!isLoading && !tip && (
          <div className="text-center py-8">
             <Lightbulb className="mx-auto h-10 w-10 text-muted-foreground/50 mb-3" />
            <p className="text-muted-foreground">No coaching tip available right now.</p>
            <p className="text-xs text-muted-foreground/70 mt-1">Log some workouts to get started.</p>
          </div>
        )}
      </CardContent>
    </Card>
  );
}

