
// src/components/dashboard/coaching-tip-card.tsx
'use client';

import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Loader2, Lightbulb } from 'lucide-react';

interface CoachingTipCardProps {
  tip: string | undefined | null;
  isLoading: boolean;
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
        {!isLoading && ( // Always try to display the tip when not loading
          <blockquote className="text-center text-sm italic text-foreground/90 border-l-4 border-primary pl-4 py-2">
             "{tip || 'Log your workouts to get personalized tips!'}" {/* Provide a default inline fallback just in case */}
          </blockquote>
        )}
        {/* Removed the explicit placeholder section for !isLoading && !tip */}
      </CardContent>
    </Card>
  );
}
